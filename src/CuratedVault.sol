// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {ITapeOutFactory, ITapeOutTransistors, ITapeOutCircuits} from "./interfaces/ITapeOut.sol";
import {ICircuitURIProvider} from "./interfaces/ICircuitURIProvider.sol";
import {LaunchParams, ICuratedVaultInit} from "./CuratedTypes.sol";

interface IRegistryForVault {
    function FACTORY() external view returns (ITapeOutFactory);
    function bind(
        address circuits,
        address transistors,
        address curator,
        bytes32 root,
        uint32 count,
        address treasury,
        uint32 reservedCount
    ) external;
    function declareRoyalty(address circuits, address receiver, uint16 bps) external;
    function declareMetadataURI(address circuits, string calldata uri) external;
    function certify(address circuits, uint256 tokenId, uint256 index, bytes32 netlistHash, bool reserved) external;
    function tokenURI(address circuits, uint256 tokenId) external view returns (string memory);
}

/// @title CuratedVault
/// @notice The reference vault of a curated collection. It launches the processor and holds its entire transistor
/// supply, sells the works of a public work list at fixed prices (in any order, or strictly in list order from runs of
/// copies), tapes each work out to its buyer and certifies it in the same transaction, sends reserved works to the
/// treasury, and burns the leftover supply at the end. Prices may be in the native coin or in one ERC-20 token.
/// Vaults are minimal clones created by the registry; `initialize` runs once, from the registry, in the launch
/// transaction.
/// @dev No owner. Transistors leave the vault only by tape-out, or to the burn address at finalize.
contract CuratedVault is ReentrancyGuard, ICircuitURIProvider, ICuratedVaultInit {
    using SafeERC20 for IERC20;

    address public constant BURN = 0x000000000000000000000000000000000000dEaD;
    uint256 internal constant NAND = 0;
    uint256 internal constant LATCH = 1;
    /// @dev gas forwarded with a native-coin payment of proceeds; a curator that needs more is paid through `owed`
    uint256 internal constant PAYOUT_GAS = 50_000;
    /// @dev gas forwarded with a token payment of proceeds (a plain transfer needs 30,000 to 60,000)
    uint256 internal constant TOKEN_PAYOUT_GAS = 150_000;
    /// @dev domain tag of run leaves (sequential collections)
    bytes32 public constant RUN_TAG = keccak256("TAP-curated-run");
    /// @notice after the sale ends, unclaimed reserved works can still be claimed for this long before anyone may
    /// finalize; finalize is allowed earlier once every reserved work is claimed
    uint64 public constant RESERVE_GRACE = 30 days;

    // launch parameters (clones have no immutables; set once in initialize)
    IRegistryForVault public REGISTRY;
    address public PAYMENT_TOKEN; // address(0) = native coin
    address public CURATOR;
    bool public SEQUENTIAL;
    bool public initialized;
    bool public finalized;
    bool public paused;
    bytes32 public ROOT;
    uint32 public COUNT;
    uint32 public RESERVED_COUNT;
    uint64 public SALE_START;
    /// @notice the end of the sale; the curator may move it later (never earlier) while the sale is still open
    uint64 internal saleEnd;
    address public TREASURY;

    ITapeOutCircuits public circuits;
    ITapeOutTransistors public transistors;
    uint32 public sold; // all works taped out, public and reserved
    uint32 public reservedClaimed;
    mapping(uint256 index => bool) public taken;

    /// @notice proceeds that could not be sent directly (a curator contract that rejected them)
    mapping(address => uint256) public owed;

    event Purchased(uint256 indexed index, uint256 indexed tokenId, address indexed recipient, uint256 price);
    event ReservedClaimed(uint256 indexed index, uint256 indexed tokenId, address indexed treasury);
    event Paid(address indexed to, uint256 amount, bool deferred);
    event Withdrawn(address indexed payee, address indexed to, uint256 amount);
    event Finalized(uint256 nandBurned, uint256 latchBurned);
    event SalePaused(bool paused);
    event SaleEndExtended(uint64 previousEnd, uint64 newEnd);

    error AlreadyInitialized();
    error InsufficientLaunchFunds();
    error RefundFailed();
    error SaleNotStarted();
    error SaleEnded();
    error LaunchFeesTooHigh(uint256 fees);
    error IndexOutOfRange();
    error AlreadyTaken();
    error InvalidProof();
    error WrongPayment(uint256 expected);
    error ZeroRecipient();
    error NotFinalizable();
    error AlreadyFinalized();
    error NothingOwed();
    error TransferFailed();
    error UnexpectedFunds();
    error OnlyCurator();
    error ReservedQuotaUsed();
    error SaleIsPaused();
    error CannotExtend();
    error TokenAmountMismatch(uint256 expected, uint256 received);
    error WrongMode();
    error NotNext(uint256 next);

    /// @dev the implementation itself can never be initialised; only its clones can
    constructor() {
        initialized = true;
    }

    // ------------------------------------------------------------------ launch

    /// @notice Create the processor, mint the whole supply to this vault, bind to the registry.
    /// Callable once, by the registry that created this clone, inside its launch transaction.
    function initialize(LaunchParams calldata p, address refundTo)
        external
        payable
        nonReentrant
        returns (address t, address c)
    {
        if (initialized) revert AlreadyInitialized();
        initialized = true;
        REGISTRY = IRegistryForVault(msg.sender);
        // the registry has checked p (CuratedRegistry._check) before calling initialize
        PAYMENT_TOKEN = p.paymentToken;
        CURATOR = p.curator;
        SEQUENTIAL = p.sequential;
        ROOT = p.root;
        COUNT = p.count;
        SALE_START = p.saleStart;
        saleEnd = p.saleEnd;
        TREASURY = p.treasury;
        RESERVED_COUNT = p.reservedCount;

        ITapeOutFactory factory = REGISTRY.FACTORY();
        uint256 deployFee = factory.deployFee();
        (t, c) = factory.createCPU{value: deployFee}(p.name, p.symbol, p.story, p.nandSupply + p.latchSupply, p.mintPrice);
        transistors = ITapeOutTransistors(t);
        circuits = ITapeOutCircuits(c);
        // TAP Recommendation 2 to TapeOut: if the processor lets its creator restrict tape-outs to itself, do so;
        // without that feature the call fails and changes nothing
        (bool restricted,) = c.call{gas: 100_000}(abi.encodeWithSignature("restrictTapeoutToCreator()"));
        restricted;

        uint256 fee = transistors.protocolFee();
        uint256 fees =
            deployFee + fee * (_calls(p.latchSupply, p.mintPrice, p.mintBatch) + _calls(p.nandSupply, p.mintPrice, p.mintBatch));
        if (fees > p.maxLaunchFees) revert LaunchFeesTooHigh(fees);
        _mintAll(LATCH, p.latchSupply, p.mintPrice, p.mintBatch, fee);
        _mintAll(NAND, p.nandSupply, p.mintPrice, p.mintBatch, fee);

        REGISTRY.bind(c, t, CURATOR, ROOT, COUNT, TREASURY, RESERVED_COUNT);
        REGISTRY.declareRoyalty(c, p.royaltyReceiver, p.royaltyBps);
        REGISTRY.declareMetadataURI(c, p.metadataURI);

        // everything left is the launcher's unused float
        uint256 rest = address(this).balance;
        if (rest > 0) {
            (bool ok,) = refundTo.call{value: rest}("");
            if (!ok) revert RefundFailed();
        }
    }

    function _calls(uint256 amount, uint256 price, uint256 batch) internal pure returns (uint256) {
        if (amount == 0) return 0;
        if (price == 0) return 1;
        return (amount + batch - 1) / batch;
    }

    function _mintAll(uint256 id, uint256 amount, uint256 price, uint256 batch, uint256 fee) internal {
        if (amount == 0) return;
        if (price == 0) {
            if (address(this).balance < fee) revert InsufficientLaunchFunds();
            transistors.mint{value: fee}(id, amount);
            return;
        }
        // pay ourselves the mint price and take it back after every batch
        while (amount > 0) {
            uint256 n = amount < batch ? amount : batch;
            uint256 cost = price * n + fee;
            if (address(this).balance < cost) revert InsufficientLaunchFunds();
            transistors.mint{value: cost}(id, n);
            transistors.withdraw();
            amount -= n;
        }
    }

    // ------------------------------------------------------------------ leaves

    /// @notice The Merkle leaf of one work (OpenZeppelin double-hashed leaf), bound to this chain, this registry and
    /// this curator. `reserved` marks a work kept for the treasury. Used when the collection is not sequential.
    function leafOf(uint256 index, bytes32 netlistHash, uint32 nIn, uint32 nOut, uint256 price, bool reserved)
        public
        view
        returns (bytes32)
    {
        return keccak256(
            bytes.concat(
                keccak256(abi.encode(block.chainid, address(REGISTRY), CURATOR, index, netlistHash, nIn, nOut, price, reserved))
            )
        );
    }

    /// @notice The Merkle leaf of a run in a sequential collection: `copies` identical works (same netlist, price and
    /// reserved flag) at indexes [first, first + copies). Each purchase tapes out the run's next copy.
    function runLeafOf(
        uint256 first,
        uint32 copies,
        bytes32 netlistHash,
        uint32 nIn,
        uint32 nOut,
        uint256 price,
        bool reserved
    ) public view returns (bytes32) {
        return keccak256(
            bytes.concat(
                keccak256(
                    abi.encode(
                        block.chainid, address(REGISTRY), CURATOR, RUN_TAG, first, copies, netlistHash, nIn, nOut, price, reserved
                    )
                )
            )
        );
    }

    // ------------------------------------------------------------------ buying in any order

    /// @notice Buy work `index`. Pay exactly `price + circuits.TAPEOUT_FEE()` (with a payment token: the tape-out fee
    /// in native coin and `price` in the token).
    function buy(
        uint256 index,
        bytes calldata netlist,
        uint32 nIn,
        uint32 nOut,
        uint256 price,
        bytes32[] calldata proof,
        address recipient
    ) external payable nonReentrant returns (uint256 tokenId) {
        if (SEQUENTIAL) revert WrongMode();
        _checkOpen();
        if (index >= COUNT) revert IndexOutOfRange();
        if (taken[index]) revert AlreadyTaken();
        if (!MerkleProof.verifyCalldata(proof, ROOT, leafOf(index, keccak256(netlist), nIn, nOut, price, false))) {
            revert InvalidProof();
        }
        tokenId = _deliver(index, netlist, nIn, nOut, price, recipient);
    }

    // ------------------------------------------------------------------ buying in list order

    /// @notice Buy the next work of a sequential collection, which must be the next copy of the run starting at
    /// `first` (index `sold`). Pay as in `buy`.
    function buyNext(
        uint256 first,
        uint32 copies,
        bytes calldata netlist,
        uint32 nIn,
        uint32 nOut,
        uint256 price,
        bytes32[] calldata proof,
        address recipient
    ) external payable nonReentrant returns (uint256 tokenId) {
        if (!SEQUENTIAL) revert WrongMode();
        _checkOpen();
        uint256 index = _nextOfRun(first, copies);
        if (!MerkleProof.verifyCalldata(proof, ROOT, runLeafOf(first, copies, keccak256(netlist), nIn, nOut, price, false))) {
            revert InvalidProof();
        }
        tokenId = _deliver(index, netlist, nIn, nOut, price, recipient);
    }

    /// @dev the next index in list order; it must lie in the run [first, first + copies)
    function _nextOfRun(uint256 first, uint32 copies) internal view returns (uint256 index) {
        index = sold;
        if (index >= COUNT) revert IndexOutOfRange();
        if (index < first || index >= first + copies) revert NotNext(index);
    }

    function _checkOpen() internal view {
        if (block.timestamp < SALE_START) revert SaleNotStarted();
        if (block.timestamp >= saleEnd) revert SaleEnded();
        if (paused) revert SaleIsPaused();
    }

    function _deliver(uint256 index, bytes calldata netlist, uint32 nIn, uint32 nOut, uint256 price, address recipient)
        internal
        returns (uint256 tokenId)
    {
        if (recipient == address(0)) revert ZeroRecipient();
        uint256 fee = circuits.TAPEOUT_FEE();
        // native coin: price + tape-out fee in msg.value; token: the tape-out fee in msg.value, the price pulled below
        uint256 due = PAYMENT_TOKEN == address(0) ? price + fee : fee;
        if (msg.value != due) revert WrongPayment(due);
        taken[index] = true;
        _pullToken(price);
        tokenId = _tapeOut(index, netlist, nIn, nOut, recipient, false, fee);
        emit Purchased(index, tokenId, recipient, price);
        if (price > 0) _send(CURATOR, price);
    }

    /// @dev Takes `amount` in the payment token from msg.sender, refusing tokens that deliver any other amount
    /// (fee-on-transfer, rebasing). Native-coin amounts arrive in msg.value and are checked by the caller.
    function _pullToken(uint256 amount) internal {
        if (PAYMENT_TOKEN == address(0) || amount == 0) return;
        IERC20 token = IERC20(PAYMENT_TOKEN);
        uint256 before = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), amount);
        uint256 afterwards = token.balanceOf(address(this));
        if (afterwards < before || afterwards - before != amount) {
            revert TokenAmountMismatch(amount, afterwards > before ? afterwards - before : 0);
        }
    }

    /// @dev Sends `amount` of the payment asset to `to`, or credits it to `owed[to]` if the transfer fails, so a
    /// recipient that rejects payments can never block a purchase.
    function _send(address to, uint256 amount) internal {
        bool ok;
        if (PAYMENT_TOKEN == address(0)) {
            assembly ("memory-safe") {
                ok := call(PAYOUT_GAS, to, amount, 0, 0, 0, 0)
            }
        } else {
            // a token transfer with a gas limit, reading at most one word of its answer: neither a token hook that
            // burns gas nor a malformed answer can make the purchase revert
            address t = PAYMENT_TOKEN;
            bytes memory data = abi.encodeCall(IERC20.transfer, (to, amount));
            uint256 r;
            uint256 n;
            assembly ("memory-safe") {
                ok := call(TOKEN_PAYOUT_GAS, t, 0, add(data, 32), mload(data), 0, 32)
                n := returndatasize()
                r := mload(0)
            }
            ok = ok && (n == 0 ? t.code.length > 0 : (n >= 32 && r == 1));
        }
        if (!ok) owed[to] += amount;
        emit Paid(to, amount, !ok);
    }

    /// @dev Tape out a work with the vault's transistors, certify it, and send it to `to`.
    function _tapeOut(uint256 index, bytes calldata netlist, uint32 nIn, uint32 nOut, address to, bool reserved, uint256 fee)
        internal
        returns (uint256 tokenId)
    {
        sold += 1;
        if (reserved) reservedClaimed += 1;
        tokenId = circuits.tapeout{value: fee}(netlist, nIn, nOut);
        REGISTRY.certify(address(circuits), tokenId, index, keccak256(netlist), reserved);
        circuits.safeTransferFrom(address(this), to, tokenId);
    }

    // ------------------------------------------------------------------ reserved works

    struct ReservedWork {
        uint256 index;
        bytes netlist;
        uint32 nIn;
        uint32 nOut;
        bytes32[] proof;
    }

    /// @notice Tape out a work that the work list marks as reserved, and send it to the treasury. Curator only, until
    /// the vault is finalized; pays exactly `circuits.TAPEOUT_FEE()`. Not in sequential collections (claimReservedRun).
    function claimReserved(uint256 index, bytes calldata netlist, uint32 nIn, uint32 nOut, bytes32[] calldata proof)
        external
        payable
        nonReentrant
        returns (uint256 tokenId)
    {
        _onlyCurator();
        uint256 fee = circuits.TAPEOUT_FEE();
        if (msg.value != fee) revert WrongPayment(fee);
        tokenId = _claim(index, netlist, nIn, nOut, proof, fee);
    }

    /// @notice Claim several reserved works in one transaction; pays `TAPEOUT_FEE()` once per work.
    function claimReservedBatch(ReservedWork[] calldata works)
        external
        payable
        nonReentrant
        returns (uint256[] memory tokenIds)
    {
        _onlyCurator();
        uint256 fee = circuits.TAPEOUT_FEE();
        if (msg.value != fee * works.length) revert WrongPayment(fee * works.length);
        tokenIds = new uint256[](works.length);
        for (uint256 i; i < works.length; i++) {
            ReservedWork calldata w = works[i];
            tokenIds[i] = _claim(w.index, w.netlist, w.nIn, w.nOut, w.proof, fee);
        }
    }

    function _claim(uint256 index, bytes calldata netlist, uint32 nIn, uint32 nOut, bytes32[] calldata proof, uint256 fee)
        internal
        returns (uint256 tokenId)
    {
        if (SEQUENTIAL) revert WrongMode();
        _reservedCheck(index, index < COUNT && taken[index]);
        if (!MerkleProof.verifyCalldata(proof, ROOT, leafOf(index, keccak256(netlist), nIn, nOut, 0, true))) {
            revert InvalidProof();
        }
        taken[index] = true;
        tokenId = _tapeOut(index, netlist, nIn, nOut, TREASURY, true, fee);
        emit ReservedClaimed(index, tokenId, TREASURY);
    }

    /// @notice Sequential collections: claim the next `n` copies of a reserved run (they must be next in list order,
    /// so reserved runs belong at the start of the list and are claimed before the sale). Curator only.
    function claimReservedRun(
        uint256 first,
        uint32 copies,
        bytes calldata netlist,
        uint32 nIn,
        uint32 nOut,
        bytes32[] calldata proof,
        uint32 n
    ) external payable nonReentrant returns (uint256[] memory tokenIds) {
        _onlyCurator();
        if (!SEQUENTIAL) revert WrongMode();
        uint256 fee = circuits.TAPEOUT_FEE();
        if (msg.value != fee * n) revert WrongPayment(fee * n);
        if (!MerkleProof.verifyCalldata(proof, ROOT, runLeafOf(first, copies, keccak256(netlist), nIn, nOut, 0, true))) {
            revert InvalidProof();
        }
        tokenIds = new uint256[](n);
        for (uint256 i; i < n; i++) {
            uint256 index = _nextOfRun(first, copies);
            _reservedCheck(index, false);
            taken[index] = true;
            tokenIds[i] = _tapeOut(index, netlist, nIn, nOut, TREASURY, true, fee);
            emit ReservedClaimed(index, tokenIds[i], TREASURY);
        }
    }

    function _reservedCheck(uint256 index, bool isTaken) internal view {
        if (finalized) revert AlreadyFinalized();
        if (index >= COUNT) revert IndexOutOfRange();
        if (isTaken) revert AlreadyTaken();
        if (reservedClaimed >= RESERVED_COUNT) revert ReservedQuotaUsed();
    }

    // ------------------------------------------------------------------ proceeds kept in the vault

    /// @notice Send `who` what the vault owes it (proceeds a direct payment could not deliver). Anyone may call; funds
    /// only go to `who`.
    function withdraw(address who) external nonReentrant {
        _pay(who, who);
    }

    /// @notice For a curator that cannot receive the payment itself: send what the caller is owed to `to`.
    function withdrawTo(address to) external nonReentrant {
        if (to == address(0)) revert ZeroRecipient();
        _pay(msg.sender, to);
    }

    function _pay(address who, address to) internal {
        uint256 amount = owed[who];
        if (amount == 0) revert NothingOwed();
        owed[who] = 0;
        emit Withdrawn(who, to, amount);
        if (PAYMENT_TOKEN == address(0)) {
            (bool ok,) = to.call{value: amount}("");
            if (!ok) revert TransferFailed();
        } else {
            IERC20(PAYMENT_TOKEN).safeTransfer(to, amount);
        }
    }

    // ------------------------------------------------------------------ finalize and sale controls

    /// @notice Send the leftover transistors to the burn address, once finalizable(). Anyone may call.
    function finalize() external nonReentrant {
        if (!finalizable()) revert NotFinalizable();
        if (finalized) revert AlreadyFinalized();
        finalized = true;
        uint256 n = transistors.balanceOf(address(this), NAND);
        uint256 l = transistors.balanceOf(address(this), LATCH);
        if (n > 0) transistors.safeTransferFrom(address(this), BURN, NAND, n, "");
        if (l > 0) transistors.safeTransferFrom(address(this), BURN, LATCH, l, "");
        emit Finalized(n, l);
    }

    /// @notice Whether finalize() may be called now (ignoring whether it already was): every work taped out, or the
    /// sale over and the reserved works claimed (or RESERVE_GRACE passed).
    function finalizable() public view returns (bool) {
        if (sold == COUNT) return true;
        if (block.timestamp < saleEnd) return false;
        return reservedClaimed == RESERVED_COUNT || block.timestamp >= uint256(saleEnd) + RESERVE_GRACE;
    }

    function _onlyCurator() internal view {
        if (msg.sender != CURATOR) revert OnlyCurator();
    }

    /// @notice The sale end as it stands now (the launch value, or a later one set by extendSale).
    function SALE_END() external view returns (uint64) {
        return saleEnd;
    }

    /// @notice Curator only: stop or resume buying.
    function setPaused(bool p) external {
        _onlyCurator();
        if (finalized) revert AlreadyFinalized();
        paused = p;
        emit SalePaused(p);
    }

    /// @notice Curator only: move the sale end later, while the sale has not ended and the vault is not finalized.
    /// It can never move earlier, and an ended sale cannot be reopened.
    function extendSale(uint64 newEnd) external {
        _onlyCurator();
        if (finalized || block.timestamp >= saleEnd || newEnd <= saleEnd) revert CannotExtend();
        emit SaleEndExtended(saleEnd, newEnd);
        saleEnd = newEnd;
    }

    // ------------------------------------------------------------------ receivers

    /// @dev Only the transistor contract (mint-price withdrawals during launch) may send plain native coin.
    receive() external payable {
        if (msg.sender != address(transistors)) revert UnexpectedFunds();
    }

    /// @dev Only circuits of this processor freshly minted to the vault by its own tapeout are accepted.
    function onERC721Received(address, address from, uint256, bytes calldata) external view returns (bytes4) {
        if (msg.sender != address(circuits) || from != address(0)) revert UnexpectedFunds();
        return this.onERC721Received.selector;
    }

    /// @dev Only this processor's own transistors are accepted.
    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external view returns (bytes4) {
        if (msg.sender != address(transistors)) revert UnexpectedFunds();
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        view
        returns (bytes4)
    {
        if (msg.sender != address(transistors)) revert UnexpectedFunds();
        return this.onERC1155BatchReceived.selector;
    }

    /// @notice This vault is its processor's creator. If TapeOut's processors ever ask their creator for token
    /// metadata (TAP Recommendation 1), they get the registry's answer: official works only.
    function circuitURI(address c, uint256 tokenId) external view returns (string memory) {
        if (c != address(circuits)) return "";
        return REGISTRY.tokenURI(c, tokenId);
    }

    /// @notice ERC-165
    function supportsInterface(bytes4 id) public pure returns (bool) {
        return id == 0x01ffc9a7 || id == type(ICircuitURIProvider).interfaceId;
    }
}
