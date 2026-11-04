// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {CuratedRegistry} from "../src/CuratedRegistry.sol";
import {ICircuitURIProvider} from "../src/interfaces/ICircuitURIProvider.sol";
import {CuratedVault} from "../src/CuratedVault.sol";
import {LaunchParams} from "../src/CuratedTypes.sol";
import {ICuratedRegistry} from "../src/interfaces/ICuratedRegistry.sol";
import {ITapeOutFactory, ITapeOutTransistors, ITapeOutCircuits} from "../src/interfaces/ITapeOut.sol";

/// A plain ERC-20 for the payment-token tests (8 decimals, like BEM).
contract MockToken {
    string public constant symbol = "MOCK";
    uint8 public constant decimals = 8;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 public totalSupply;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _move(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        _move(from, to, amount);
        return true;
    }

    function _move(address from, address to, uint256 amount) internal virtual {
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
    }
}

/// Takes 1 % of every transfer: the vault must refuse it.
contract FeeToken is MockToken {
    function _move(address from, address to, uint256 amount) internal override {
        uint256 tax = amount / 100;
        balanceOf[from] -= amount;
        balanceOf[to] += amount - tax;
        totalSupply -= tax;
    }
}

/// Like USDT: transfer and transferFrom return nothing.
contract NoReturnToken {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external {
        allowance[msg.sender][spender] = amount;
    }

    function transfer(address to, uint256 amount) external {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
    }

    function transferFrom(address from, address to, uint256 amount) external {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
    }
}

/// Calls back into the vault on every transfer (like an ERC-777 hook) and records whether that call got in.
contract HookToken is MockToken {
    address public vault;
    bytes public hook;
    bool public reentered;

    function arm(address v, bytes calldata data) external {
        vault = v;
        hook = data;
    }

    function _move(address from, address to, uint256 amount) internal override {
        super._move(from, to, amount);
        if (vault != address(0) && hook.length > 0) {
            (bool ok,) = vault.call(hook);
            if (ok) reentered = true;
        }
    }
}

interface IERC20Meta {
    function decimals() external view returns (uint8);
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
}

interface IFactoryFees {
    function protocolFee() external view returns (uint256);
}

/// Fork tests against live TapeOut state on BNB Smart Chain, X Layer or Base. Run with one of:
///   forge test --fork-url https://bsc-dataseed.bnbchain.org   (chain 56)
///   forge test --fork-url https://rpc.xlayer.tech             (chain 196)
///   forge test --fork-url https://mainnet.base.org            (chain 8453)
/// Works come from test/fixtures/manifest.json (chain 56) or manifest.<chainId>.json, produced by
/// `tool/curate.py build`. The manifest's leaves are bound to the chain, the registry address REG and the curator,
/// so the registry is placed at REG.
contract CuratedForkTest is Test {
    ITapeOutFactory FACTORY;
    // a circuit of another processor on the same chain (its netlist is not in the work list)
    ITapeOutCircuits FOREIGN;
    uint256 FOREIGN_ID;
    address constant DEAD = 0x000000000000000000000000000000000000dEaD;
    address constant REG = 0x00000000000000000000000000000000c0dEc0DE;
    bytes4 constant ERC1155_INSUFFICIENT_BALANCE = 0x03dee4c5;

    CuratedRegistry reg;
    address IMPL0;
    string manifest;
    uint256 count;
    uint256 launchValue;

    address curator;
    address buyer = makeAddr("buyer");
    address attacker = makeAddr("attacker");

    CuratedVault vault;
    ITapeOutTransistors T;
    ITapeOutCircuits C;
    uint256 fee; // cached so that vm.prank / vm.expectRevert are not consumed by a fee lookup

    function setUp() public {
        string memory path;
        if (block.chainid == 56) {
            FACTORY = ITapeOutFactory(0x68224F668083c29e9800Be2a646d42d18cedF7e2);
            (FOREIGN, FOREIGN_ID) = (ITapeOutCircuits(0x50A994E71615474b55559fF4F500928fbc339DD9), 50);
            path = "test/fixtures/manifest.json";
        } else if (block.chainid == 196 || block.chainid == 8453) {
            // X Layer and Base: same deployer, same addresses. Base's circuit #1 is a XOR byte-identical to work 3,
            // so the foreign netlist there is circuit #2.
            FACTORY = ITapeOutFactory(0x1f09DAeFA827f02CBb40967cc91b259763760761);
            (FOREIGN, FOREIGN_ID) =
                (ITapeOutCircuits(0x0565EA48CA41Ae559d8d491dbb0a9ec945DB551b), block.chainid == 196 ? 1 : 2);
            path = string.concat("test/fixtures/manifest.", vm.toString(block.chainid), ".json");
        } else {
            revert("fork BNB Smart Chain (56), X Layer (196) or Base (8453)");
        }
        // the vault implementation, then the registry that clones it (at the address the leaves are bound to)
        IMPL0 = address(new CuratedVault());
        deployCodeTo("CuratedRegistry.sol:CuratedRegistry", abi.encode(FACTORY, IMPL0), REG);
        reg = CuratedRegistry(REG);
        manifest = vm.readFile(path);
        count = vm.parseJsonUint(manifest, ".launch.count");
        launchValue = vm.parseJsonUint(manifest, ".launch.launchValueWei");
        curator = vm.parseJsonAddress(manifest, ".launch.curator");
        assertEq(vm.parseJsonAddress(manifest, ".registry"), REG);
        assertEq(block.chainid, vm.parseJsonUint(manifest, ".chainId"));
        // the test actors are plain accounts (a labelled address can hold code on a live chain)
        vm.etch(buyer, "");
        vm.etch(attacker, "");
        vm.etch(curator, ""); // the curator receives the proceeds: a plain account, so balances are exact
        vm.deal(curator, 10 ether);
        vm.deal(buyer, 100 ether);
        vm.deal(attacker, 100 ether);
    }

    // ------------------------------------------------------------------ helpers

    /// The factory's protocol fee per mint call (not in ITapeOutFactory; src/ is unchanged).
    function _protocolFee() internal view returns (uint256) {
        return IFactoryFees(address(FACTORY)).protocolFee();
    }

    /// A labelled plain account: on a live chain the address makeAddr derives can hold code (e.g. EIP-7702).
    function _eoa(string memory name) internal returns (address a) {
        a = makeAddr(name);
        vm.etch(a, "");
    }


    function _params() internal view returns (LaunchParams memory p) {
        p.name = vm.parseJsonString(manifest, ".launch.name");
        p.symbol = vm.parseJsonString(manifest, ".launch.symbol");
        p.story = vm.parseJsonString(manifest, ".launch.story");
        p.nandSupply = vm.parseJsonUint(manifest, ".launch.nandSupply");
        p.latchSupply = vm.parseJsonUint(manifest, ".launch.latchSupply");
        p.mintPrice = vm.parseJsonUint(manifest, ".launch.mintPrice");
        p.mintBatch = vm.parseJsonUint(manifest, ".launch.mintBatch");
        p.root = vm.parseJsonBytes32(manifest, ".launch.root");
        p.count = uint32(vm.parseJsonUint(manifest, ".launch.count"));
        p.curator = vm.parseJsonAddress(manifest, ".launch.curator");
        p.saleStart = uint64(vm.parseJsonUint(manifest, ".launch.saleStart"));
        p.saleEnd = uint64(vm.parseJsonUint(manifest, ".launch.saleEnd"));
        p.maxLaunchFees = vm.parseJsonUint(manifest, ".launch.maxLaunchFees");
        p.treasury = vm.parseJsonAddress(manifest, ".launch.treasury");
        p.reservedCount = uint32(vm.parseJsonUint(manifest, ".launch.reservedCount"));
        p.royaltyReceiver = vm.parseJsonAddress(manifest, ".launch.royaltyReceiver");
        p.royaltyBps = uint16(vm.parseJsonUint(manifest, ".launch.royaltyBps"));
        p.titlesHash = vm.parseJsonBytes32(manifest, ".launch.titlesHash");
        p.metadataURI = vm.parseJsonString(manifest, ".launch.metadataURI");
        p.paymentToken = vm.parseJsonAddress(manifest, ".launch.paymentToken");
        p.sequential = vm.parseJsonBool(manifest, ".launch.sequential");
    }

    struct Work {
        uint256 index;
        bytes netlist;
        uint32 nIn;
        uint32 nOut;
        uint256 price;
        bytes32[] proof;
        uint256 nand;
        uint256 latch;
        bool reserved;
    }

    /// Work `i` of a fixture whose runs are single works (manifest /8: a run names its design, stored once).
    function _work(uint256 i) internal view returns (Work memory w) {
        string memory k = string.concat(".works[", vm.toString(i), "]");
        w.index = vm.parseJsonUint(manifest, string.concat(k, ".first"));
        require(vm.parseJsonUint(manifest, string.concat(k, ".copies")) == 1, "a run of copies");
        string memory d = string.concat(".designs[", vm.toString(vm.parseJsonUint(manifest, string.concat(k, ".design"))), "]");
        w.netlist = vm.parseJsonBytes(manifest, string.concat(d, ".netlist"));
        w.nIn = uint32(vm.parseJsonUint(manifest, string.concat(d, ".nIn")));
        w.nOut = uint32(vm.parseJsonUint(manifest, string.concat(d, ".nOut")));
        w.price = vm.parseJsonUint(manifest, string.concat(k, ".priceWei"));
        w.proof = vm.parseJsonBytes32Array(manifest, string.concat(k, ".proof"));
        w.nand = vm.parseJsonUint(manifest, string.concat(d, ".nand"));
        w.latch = vm.parseJsonUint(manifest, string.concat(d, ".latch"));
        w.reserved = vm.parseJsonBool(manifest, string.concat(k, ".reserved"));
    }

    uint256 constant RESERVED_WORK = 5; // the fixture reserves works 5 and 6 for the treasury
    uint256 constant RESERVED_WORK2 = 6;

    function _claim(uint256 i) internal returns (uint256 id) {
        Work memory w = _work(i);
        vm.prank(curator);
        id = vault.claimReserved{value: fee}(w.index, w.netlist, w.nIn, w.nOut, w.proof);
    }

    function _launchWith(LaunchParams memory p) internal returns (uint256 gasUsed, uint256 cost) {
        uint256 b0 = p.curator.balance;
        vm.prank(p.curator);
        uint256 g = gasleft();
        (address v, address t, address c) = reg.launch{value: launchValue}(p);
        gasUsed = g - gasleft();
        cost = b0 - p.curator.balance;
        vault = CuratedVault(payable(v));
        T = ITapeOutTransistors(t);
        C = ITapeOutCircuits(c);
        fee = C.TAPEOUT_FEE();
    }

    function _launch() internal returns (uint256, uint256) {
        return _launchWith(_params());
    }

    function _buy(uint256 i, address to) internal returns (uint256 id) {
        Work memory w = _work(i);
        vm.prank(buyer);
        id = vault.buy{value: w.price + fee}(w.index, w.netlist, w.nIn, w.nOut, w.price, w.proof, to);
    }

    // ------------------------------------------------------------------ launch

    function test_Launch_AtomicAndVerified() public {
        (uint256 gasUsed, uint256 cost) = _launch();
        emit log_named_uint("launch gas", gasUsed);
        emit log_named_decimal_uint("launch cost (native coin)", cost, 18);

        LaunchParams memory p = _params();
        assertTrue(reg.isCurated(address(C)));
        ICuratedRegistry.Collection memory col = reg.collectionOf(address(C));
        assertEq(col.vault, address(vault));
        assertEq(col.curator, p.curator);
        assertEq(col.transistors, address(T));
        assertEq(col.root, p.root);
        assertEq(col.count, p.count);
        assertEq(col.certified, 0);

        assertEq(T.creator(), address(vault));
        assertEq(T.minted(), T.supplyCap());
        assertEq(T.supplyCap(), p.nandSupply + p.latchSupply);
        assertEq(T.balanceOf(address(vault), 0), p.nandSupply);
        assertEq(T.balanceOf(address(vault), 1), p.latchSupply);
        assertEq(T.mintPrice(), p.mintPrice);
        assertEq(C.nextId(), 0);
        assertEq(address(vault).balance, 0);
        // the launcher paid exactly the protocol fees the tool predicted
        assertEq(cost, p.maxLaunchFees);
    }

    function test_Launch_ZeroMintPrice() public {
        LaunchParams memory p = _params();
        p.mintPrice = 0;
        p.mintBatch = 0;
        // deploy fee plus one protocol fee per id (no mint price, so one mint call each), with a margin
        uint256 value = 2 * (FACTORY.deployFee() + 2 * _protocolFee());
        vm.prank(curator);
        (address v,, address c) = reg.launch{value: value}(p);
        assertTrue(reg.isCurated(c));
        assertEq(reg.collectionOf(c).vault, v);
    }

    function test_Launch_RejectsBadParams() public {
        LaunchParams memory p = _params();
        p.saleEnd = p.saleStart;
        vm.prank(curator);
        vm.expectRevert(abi.encodeWithSelector(CuratedRegistry.BadParams.selector, bytes32("saleEnd")));
        reg.launch{value: launchValue}(p);

        p = _params();
        uint256 tooLittle = FACTORY.deployFee() + _protocolFee(); // deploy fee and one protocol fee only
        vm.prank(curator);
        vm.expectRevert(CuratedVault.InsufficientLaunchFunds.selector);
        reg.launch{value: tooLittle}(p);
    }

    /// L-2: the launcher caps what it is willing to pay in factory and protocol fees.
    function test_L2_LaunchFeeCap() public {
        LaunchParams memory p = _params();
        p.maxLaunchFees = p.maxLaunchFees - 1;
        vm.prank(curator);
        vm.expectPartialRevert(CuratedVault.LaunchFeesTooHigh.selector);
        reg.launch{value: launchValue}(p);
    }

    /// H-1: nobody can launch a collection in another curator's name, and a copied root is useless.
    function test_H1_CopycatLaunchRejected() public {
        LaunchParams memory p = _params();
        vm.prank(attacker);
        vm.expectRevert(CuratedRegistry.CuratorMustLaunch.selector);
        reg.launch{value: launchValue}(p);

        // same root and name, attacker as curator: it launches, but no listed work can be sold,
        // because every leaf is bound to the real curator
        p.curator = attacker;
        vm.prank(attacker);
        (address v,, address c) = reg.launch{value: launchValue}(p);
        uint256 f = ITapeOutCircuits(c).TAPEOUT_FEE();
        Work memory w = _work(3); // price 0
        vm.prank(attacker);
        vm.expectRevert(CuratedVault.InvalidProof.selector);
        CuratedVault(payable(v)).buy{value: f}(w.index, w.netlist, w.nIn, w.nOut, w.price, w.proof, attacker);
    }

    /// L-3: the launch refund cannot be used to buy works inside the launch transaction: the attempt hits the
    /// reentrancy guard (the hook records the exact error), and nothing is sold.
    function test_L3_RefundReentryBlocked() public {
        deployCodeTo("Curated.t.sol:RefundReenter", abi.encode(address(this)), curator);
        vm.deal(curator, 10 ether);
        _launch();
        assertEq(RefundReenter(payable(curator)).seen(), ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        assertEq(vault.sold(), 0);
    }

    /// L-4: tokenOf never reports a work as taped out by reading a default id 0; editionOf of a circuit that
    /// is not official is (false, 0), and a work keeps its circuit id after it is taped out.
    function test_L4_TokenOfAndEditionOfDefaults() public {
        _launch();
        (bool taped, uint256 tid) = reg.tokenOf(address(C), 0);
        assertFalse(taped);
        assertEq(tid, 0);
        (bool off, uint256 idx) = reg.editionOf(address(C), 0);
        assertFalse(off);
        assertEq(idx, 0);
        uint256 id = _buy(0, buyer);
        (taped, tid) = reg.tokenOf(address(C), 0);
        assertTrue(taped);
        assertEq(tid, id);
        (taped,) = reg.tokenOf(address(C), 1);
        assertFalse(taped);
        assertFalse(reg.isOfficial(address(C), 0));
        assertFalse(reg.isOfficial(address(0xbeef), id));
    }

    /// The treasury can be neither the vault being created nor the registry.
    function test_TreasuryCannotBeVaultOrRegistry() public {
        // vaults are clones the registry creates
        address nextVault = vm.computeCreateAddress(REG, vm.getNonce(REG));
        address[2] memory bad = [nextVault, REG];
        for (uint256 i; i < 2; i++) {
            LaunchParams memory p = _params();
            p.treasury = bad[i];
            vm.prank(curator);
            vm.expectRevert(abi.encodeWithSelector(CuratedRegistry.BadParams.selector, bytes32("treasury")));
            reg.launch{value: launchValue}(p);
        }
        // the address really is the next vault
        (address v,,) = _launch2();
        assertEq(v, nextVault);
    }

    function _launch2() internal returns (address v, address t, address c) {
        vm.prank(curator);
        (v, t, c) = reg.launch{value: launchValue}(_params());
    }

    // ------------------------------------------------------------------ sale, end to end

    function test_BuyAll_CertifyPayFinalize() public {
        _launch();
        LaunchParams memory p = _params();
        uint256 gross;
        uint256 claimFees;
        uint256 curator0 = curator.balance;
        for (uint256 i; i < count; i++) {
            Work memory w = _work(i);
            uint256 nand0 = T.balanceOf(address(vault), 0);
            uint256 latch0 = T.balanceOf(address(vault), 1);
            uint256 expectedId = C.nextId() + 1;
            uint256 g = gasleft();
            vm.expectEmit(true, true, true, true, address(reg));
            emit ICuratedRegistry.Certified(address(C), expectedId, i, keccak256(w.netlist), w.reserved);
            uint256 id = w.reserved ? _claim(i) : _buy(i, buyer);
            emit log_named_uint(
                string.concat(w.reserved ? "claim gas, work " : "buy gas, work ", vm.toString(i), ", bytes ",
                    vm.toString(w.netlist.length)),
                g - gasleft()
            );

            assertEq(id, expectedId);
            assertEq(C.ownerOf(id), w.reserved ? p.treasury : buyer);
            assertEq(reg.isReserved(address(C), id), w.reserved);
            assertTrue(reg.isOfficial(address(C), id));
            (bool off, uint256 idx) = reg.editionOf(address(C), id);
            assertTrue(off);
            assertEq(idx, i);
            (bool taped, uint256 tid) = reg.tokenOf(address(C), i);
            assertTrue(taped);
            assertEq(tid, id);
            assertEq(keccak256(C.netlist(id)), keccak256(w.netlist));
            (uint32 a, uint32 b,,) = C.circuitInfo(id);
            assertEq(a, w.nIn);
            assertEq(b, w.nOut);
            assertEq(nand0 - T.balanceOf(address(vault), 0), w.nand);
            assertEq(latch0 - T.balanceOf(address(vault), 1), w.latch);
            gross += w.price;
            if (w.reserved) claimFees += fee;

            if (i + 1 < count) {
                vm.expectRevert(CuratedVault.NotFinalizable.selector);
                vault.finalize();
            }
        }
        assertEq(vault.sold(), count);
        assertEq(vault.reservedClaimed(), p.reservedCount);
        assertEq(reg.collectionOf(address(C)).certified, count);

        // every sale was paid to the curator at once (the curator paid the tape-out fees of the reserved claims)
        assertEq(curator.balance + claimFees - curator0, gross);
        assertEq(address(vault).balance, 0);
        assertEq(vault.owed(curator), 0);
        vm.expectRevert(CuratedVault.NothingOwed.selector);
        vault.withdraw(curator);

        // finalize burns every leftover NAND and LATCH
        uint256 n = T.balanceOf(address(vault), 0);
        uint256 l = T.balanceOf(address(vault), 1);
        assertGt(l, 0, "fixture keeps spare LATCH so the LATCH burn path runs");
        uint256 dn = T.balanceOf(DEAD, 0);
        uint256 dl = T.balanceOf(DEAD, 1);
        vault.finalize();
        assertEq(T.balanceOf(address(vault), 0), 0);
        assertEq(T.balanceOf(address(vault), 1), 0);
        assertEq(T.balanceOf(DEAD, 0) - dn, n);
        assertEq(T.balanceOf(DEAD, 1) - dl, l);
        emit log_named_uint("leftover NAND burned", n);
        emit log_named_uint("leftover LATCH burned", l);
        vm.expectRevert(CuratedVault.AlreadyFinalized.selector);
        vault.finalize();
    }

    /// M-1: an unsold (or unbuyable) work cannot block finalize forever.
    function test_M1_FinalizeAfterSaleEnd() public {
        _launch();
        uint256 id = _buy(0, buyer);
        vm.expectRevert(CuratedVault.NotFinalizable.selector);
        vault.finalize();
        vm.warp(vault.SALE_END());
        Work memory w = _work(1);
        vm.prank(buyer);
        vm.expectRevert(CuratedVault.SaleEnded.selector);
        vault.buy{value: w.price + fee}(w.index, w.netlist, w.nIn, w.nOut, w.price, w.proof, buyer);
        // reserved works are still unclaimed, so finalize waits for the grace period
        vm.expectRevert(CuratedVault.NotFinalizable.selector);
        vault.finalize();
        vm.warp(uint256(vault.SALE_END()) + vault.RESERVE_GRACE());
        vault.finalize();
        assertEq(T.balanceOf(address(vault), 0) + T.balanceOf(address(vault), 1), 0);
        assertTrue(reg.isOfficial(address(C), id)); // the sold work stays official
    }

    // ------------------------------------------------------------------ R1: transistors never leave the vault

    function test_R1_NoWayToExtractTransistors() public {
        _launch();
        vm.startPrank(attacker);
        (bool ok1,) = address(T).call(
            abi.encodeWithSignature(
                "safeTransferFrom(address,address,uint256,uint256,bytes)", address(vault), attacker, 0, 1, ""
            )
        );
        (bool ok2,) = address(T).call(abi.encodeWithSignature("burnFrom(address,uint256,uint256)", address(vault), 0, 1));
        (bool ok3,) = address(T).call{value: 1 ether}(abi.encodeWithSignature("mint(uint256,uint256)", 0, 1));
        vm.stopPrank();
        assertFalse(ok1, "transfer from vault");
        assertFalse(ok2, "burnFrom vault");
        assertFalse(ok3, "mint after the supply is exhausted");
        vm.prank(curator);
        vm.expectRevert(CuratedVault.AlreadyInitialized.selector);
        vault.initialize(_params(), attacker);
        vm.expectRevert(CuratedVault.NotFinalizable.selector);
        vault.finalize();
        assertEq(T.balanceOf(attacker, 0) + T.balanceOf(attacker, 1), 0);
    }

    // ------------------------------------------------------------------ R2: same netlist taped out by someone else

    function test_R2_SameNetlistElsewhereIsNotOfficial() public {
        _launch();
        uint256 official = _buy(1, buyer);
        Work memory w = _work(1);

        vm.startPrank(attacker);
        (address t2, address c2) = FACTORY.createCPU{value: FACTORY.deployFee()}("Copy", "CPY", "", 10_000, 0);
        uint256 pf = ITapeOutTransistors(t2).protocolFee();
        ITapeOutTransistors(t2).mint{value: pf}(0, 9000);
        ITapeOutTransistors(t2).mint{value: pf}(1, 1000);
        uint256 copy = ITapeOutCircuits(c2).tapeout{value: fee}(w.netlist, w.nIn, w.nOut);
        vm.stopPrank();

        assertEq(keccak256(ITapeOutCircuits(c2).netlist(copy)), keccak256(C.netlist(official)));
        assertFalse(reg.isOfficial(c2, copy), "copy on another processor");
        assertFalse(reg.isCurated(c2));
        assertTrue(reg.isOfficial(address(C), official));

        // on the curated processor the attacker holds no transistors, so the burn fails
        vm.prank(attacker);
        vm.expectPartialRevert(ERC1155_INSUFFICIENT_BALANCE);
        C.tapeout{value: fee}(w.netlist, w.nIn, w.nOut);
    }

    // ------------------------------------------------------------------ R3: zero-cost REF wrappers

    function test_R3_RefWrapperIsNotOfficial() public {
        _launch();
        uint256 official = _buy(2, buyer); // the 7-bit LFSR
        Work memory w = _work(2);

        // circuit ids here are tiny, so the uint64 REF id field cannot truncate
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes memory wrapper = abi.encodePacked(uint8(2), address(C), uint64(official), uint8(0), uint8(w.nOut));
        vm.prank(attacker);
        uint256 fake = C.tapeout{value: fee}(wrapper, 0, w.nOut);

        assertEq(C.ownerOf(fake), attacker);
        (uint32 a1, uint32 b1, uint32 s1, uint32 g1) = C.circuitInfo(official);
        (uint32 a2, uint32 b2, uint32 s2, uint32 g2) = C.circuitInfo(fake);
        assertEq(abi.encode(a1, b1, s1, g1), abi.encode(a2, b2, s2, g2));
        assertFalse(reg.isOfficial(address(C), fake));
        (bool off,) = reg.editionOf(address(C), fake);
        assertFalse(off);
        (, uint256 tid) = reg.tokenOf(address(C), 2);
        assertEq(tid, official);
    }

    // ------------------------------------------------------------------ R4: one tape-out per work; strict inputs

    function test_R4_EachWorkOnceAndStrictInputs() public {
        _launch();
        _buy(0, buyer);
        Work memory w = _work(0);
        uint256 v = w.price + fee;

        vm.startPrank(buyer);
        vm.expectRevert(CuratedVault.AlreadyTaken.selector);
        vault.buy{value: v}(w.index, w.netlist, w.nIn, w.nOut, w.price, w.proof, buyer);

        Work memory x = _work(1);
        uint256 vx = x.price + fee;
        bytes memory bad = bytes.concat(x.netlist, hex"00");
        vm.expectRevert(CuratedVault.InvalidProof.selector);
        vault.buy{value: vx}(x.index, bad, x.nIn, x.nOut, x.price, x.proof, buyer);
        vm.expectRevert(CuratedVault.InvalidProof.selector);
        vault.buy{value: fee}(x.index, x.netlist, x.nIn, x.nOut, 0, x.proof, buyer);
        vm.expectRevert(CuratedVault.InvalidProof.selector);
        vault.buy{value: vx}(x.index, x.netlist, x.nIn, x.nOut, x.price, w.proof, buyer);
        vm.expectRevert(CuratedVault.InvalidProof.selector);
        vault.buy{value: vx}(x.index, x.netlist, x.nIn, x.nOut + 1, x.price, x.proof, buyer);
        // a valid work presented under another index
        vm.expectRevert(CuratedVault.InvalidProof.selector);
        vault.buy{value: vx}(4, x.netlist, x.nIn, x.nOut, x.price, x.proof, buyer);
        vm.expectRevert(abi.encodeWithSelector(CuratedVault.WrongPayment.selector, vx));
        vault.buy{value: vx + 1}(x.index, x.netlist, x.nIn, x.nOut, x.price, x.proof, buyer);
        vm.expectRevert(CuratedVault.IndexOutOfRange.selector);
        vault.buy{value: vx}(count, x.netlist, x.nIn, x.nOut, x.price, x.proof, buyer);
        vm.expectRevert(CuratedVault.ZeroRecipient.selector);
        vault.buy{value: vx}(x.index, x.netlist, x.nIn, x.nOut, x.price, x.proof, address(0));
        vm.stopPrank();
    }

    // ------------------------------------------------------------------ R5: only the bound vault writes the record

    function test_R5_OnlyBoundVaultCanCertify() public {
        _launch();
        vm.prank(attacker);
        vm.expectRevert(CuratedRegistry.NotBoundVault.selector);
        reg.certify(address(C), 1, 0, bytes32(0), false);

        vm.prank(attacker);
        vm.expectRevert(CuratedRegistry.NotVault.selector);
        reg.bind(address(C), address(T), attacker, bytes32(uint256(1)), 1, attacker, 0);

        CuratedVault rogue = new CuratedVault();
        vm.prank(address(rogue));
        vm.expectRevert(CuratedRegistry.NotBoundVault.selector);
        reg.certify(address(C), 1, 0, bytes32(0), false);
        vm.prank(address(rogue));
        vm.expectRevert(CuratedRegistry.NotVault.selector);
        reg.bind(address(C), address(T), attacker, bytes32(uint256(1)), 1, attacker, 0);

        vm.prank(address(vault));
        vm.expectRevert(CuratedRegistry.AlreadyBound.selector);
        reg.bind(address(C), address(T), attacker, bytes32(uint256(1)), 1, attacker, 0);
        uint256 id = _buy(3, buyer);
        vm.prank(address(vault));
        vm.expectRevert(CuratedRegistry.AlreadyCertified.selector);
        reg.certify(address(C), id, 4, bytes32(0), false);
        vm.prank(address(vault));
        vm.expectRevert(CuratedRegistry.AlreadyCertified.selector);
        reg.certify(address(C), id + 100, 3, bytes32(0), false);
        vm.prank(address(vault));
        vm.expectRevert(CuratedRegistry.IndexOutOfRange.selector);
        reg.certify(address(C), id + 100, count, bytes32(0), false);
    }

    // ------------------------------------------------------------------ R7: the work list cannot change

    function test_R7_WorkListIsFixed() public {
        _launch();
        assertEq(vault.ROOT(), _params().root);
        assertEq(reg.collectionOf(address(C)).root, _params().root);
        // an unlisted netlist cannot be sold even with a real proof, index and price from the list
        Work memory w = _work(3);
        bytes memory foreign = FOREIGN.netlist(FOREIGN_ID);
        vm.prank(buyer);
        vm.expectRevert(CuratedVault.InvalidProof.selector);
        vault.buy{value: w.price + fee}(w.index, foreign, w.nIn, w.nOut, w.price, w.proof, buyer);
    }

    // ------------------------------------------------------------------ misc safety

    function test_SaleStartIsEnforced() public {
        LaunchParams memory p = _params();
        p.saleStart = uint64(block.timestamp + 1 days);
        _launchWith(p);
        Work memory w = _work(0);
        vm.prank(buyer);
        vm.expectRevert(CuratedVault.SaleNotStarted.selector);
        vault.buy{value: w.price + fee}(w.index, w.netlist, w.nIn, w.nOut, w.price, w.proof, buyer);
    }

    /// L-5: only circuits freshly minted to the vault by its own tapeout are accepted.
    function test_L5_RejectsStrayFundsAndTokens() public {
        _launch();
        vm.prank(attacker);
        (bool ok,) = address(vault).call{value: 1 ether}("");
        assertFalse(ok, "plain native coin");

        // a real circuit of this processor, owned by the attacker, sent to the vault
        uint256 official = _buy(2, buyer);
        // circuit ids here are tiny, so the uint64 REF id field cannot truncate
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes memory wrapper = abi.encodePacked(uint8(2), address(C), uint64(official), uint8(0), uint8(7));
        vm.startPrank(attacker);
        uint256 fake = C.tapeout{value: fee}(wrapper, 0, 7);
        vm.expectRevert(CuratedVault.UnexpectedFunds.selector);
        C.safeTransferFrom(attacker, address(vault), fake);
        vm.stopPrank();
        assertEq(C.ownerOf(fake), attacker);
    }

    function test_ReentrancyFromRecipientFails() public {
        _launch();
        Reenter r = new Reenter(vault, this);
        Work memory w = _work(3);
        vm.deal(address(r), 1 ether);
        vm.prank(buyer);
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        vault.buy{value: w.price + fee}(w.index, w.netlist, w.nIn, w.nOut, w.price, w.proof, address(r));
        assertFalse(vault.taken(3));
    }

    // ------------------------------------------------------------------ reserved works for the treasury

    /// The public can never buy a work the list reserves for the treasury, at any price.
    function test_Reserved_PublicCannotBuy() public {
        _launch();
        Work memory w = _work(RESERVED_WORK);
        assertTrue(w.reserved);
        vm.startPrank(buyer);
        vm.expectRevert(CuratedVault.InvalidProof.selector);
        vault.buy{value: fee}(w.index, w.netlist, w.nIn, w.nOut, 0, w.proof, buyer);
        vm.expectRevert(CuratedVault.InvalidProof.selector);
        vault.buy{value: 1 ether + fee}(w.index, w.netlist, w.nIn, w.nOut, 1 ether, w.proof, buyer);
        vm.stopPrank();
    }

    /// Only the curator can claim, the work always goes to the fixed treasury, and it is official and marked
    /// reserved. Claiming works before the public sale opens.
    function test_Reserved_CuratorClaimsToTreasury() public {
        LaunchParams memory p = _params();
        p.saleStart = uint64(block.timestamp + 7 days);
        _launchWith(p);
        Work memory w = _work(RESERVED_WORK);

        vm.prank(attacker);
        vm.expectRevert(CuratedVault.OnlyCurator.selector);
        vault.claimReserved{value: fee}(w.index, w.netlist, w.nIn, w.nOut, w.proof);

        uint256 before = curator.balance;
        uint256 id = _claim(RESERVED_WORK);
        assertEq(C.ownerOf(id), p.treasury);
        assertTrue(reg.isOfficial(address(C), id));
        assertTrue(reg.isReserved(address(C), id));
        (bool off, uint256 idx) = reg.editionOf(address(C), id);
        assertTrue(off);
        assertEq(idx, RESERVED_WORK);
        assertEq(before - curator.balance, fee, "a reserved work earns nothing; the curator pays its tape-out fee");

        ICuratedRegistry.Collection memory col = reg.collectionOf(address(C));
        assertEq(col.treasury, p.treasury);
        assertEq(col.reserved, p.reservedCount);

        // cannot be claimed twice
        vm.prank(curator);
        vm.expectRevert(CuratedVault.AlreadyTaken.selector);
        vault.claimReserved{value: fee}(w.index, w.netlist, w.nIn, w.nOut, w.proof);
    }

    event Purchased(uint256 indexed index, uint256 indexed tokenId, address indexed recipient, uint256 price);

    // ------------------------------------------------------------------ royalty declaration (optional, advisory)

    /// Official works report the declared royalty; REF wrappers and other foreign circuits report none.
    function test_Royalty_OfficialOnly() public {
        _launch();
        LaunchParams memory p = _params();
        (address r0, uint16 b0) = reg.royaltyOf(address(C));
        assertEq(r0, p.royaltyReceiver);
        assertEq(b0, 300);
        uint256 official = _buy(2, buyer);
        (address r, uint256 amt) = reg.royaltyInfo(address(C), official, 1 ether);
        assertEq(r, p.royaltyReceiver);
        assertEq(amt, 0.03 ether);

        // circuit ids here are tiny, so the uint64 REF id field cannot truncate
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes memory wrapper = abi.encodePacked(uint8(2), address(C), uint64(official), uint8(0), uint8(7));
        vm.prank(attacker);
        uint256 fake = C.tapeout{value: fee}(wrapper, 0, 7);
        (address rf, uint256 af) = reg.royaltyInfo(address(C), fake, 1 ether);
        assertEq(rf, address(0));
        assertEq(af, 0);
    }

    /// A collection may declare no royalty at all.
    function test_Royalty_None() public {
        LaunchParams memory p = _params();
        p.royaltyReceiver = address(0);
        p.royaltyBps = 0;
        _launchWith(p);
        uint256 id = _buy(0, buyer);
        (address r, uint256 amt) = reg.royaltyInfo(address(C), id, 1 ether);
        assertEq(r, address(0));
        assertEq(amt, 0);
        // and none can be added later, because the rate can never rise
        vm.prank(curator);
        vm.expectRevert(CuratedRegistry.RoyaltyCannotRise.selector);
        reg.setRoyalty(address(C), curator, 100);
    }

    /// The curator can change the receiver or lower the rate, never raise it; nobody else can touch it.
    function test_Royalty_CuratorCanOnlyLower() public {
        _launch();
        address newReceiver = _eoa("p05-royalty-new");
        vm.prank(attacker);
        vm.expectRevert(CuratedRegistry.OnlyCurator.selector);
        reg.setRoyalty(address(C), attacker, 100);

        vm.prank(curator);
        vm.expectRevert(CuratedRegistry.RoyaltyCannotRise.selector);
        reg.setRoyalty(address(C), newReceiver, 301);

        vm.expectEmit(true, true, true, true, address(reg));
        emit ICuratedRegistry.RoyaltySet(address(C), newReceiver, 250);
        vm.prank(curator);
        reg.setRoyalty(address(C), newReceiver, 250);
        (address r, uint16 b) = reg.royaltyOf(address(C));
        assertEq(r, newReceiver);
        assertEq(b, 250);

        // the vault cannot re-declare, and a declared royalty cannot point at nobody
        vm.prank(address(vault));
        vm.expectRevert(CuratedRegistry.AlreadyBound.selector);
        reg.declareRoyalty(address(C), attacker, 1000);
        vm.prank(curator);
        vm.expectRevert(CuratedRegistry.BadRoyalty.selector);
        reg.setRoyalty(address(C), address(0), 100);
    }

    /// Launch refuses a rate above 5 % or a receiver without a rate (and the reverse); exactly 5 % is accepted.
    function test_Royalty_ParamsChecked() public {
        LaunchParams memory p = _params();
        p.royaltyBps = 501;
        vm.prank(curator);
        vm.expectRevert(CuratedRegistry.BadRoyalty.selector);
        reg.launch{value: launchValue}(p);
        assertEq(reg.MAX_ROYALTY_BPS(), 500);

        p = _params();
        p.royaltyBps = 0; // receiver set, no rate
        vm.prank(curator);
        vm.expectRevert(CuratedRegistry.BadRoyalty.selector);
        reg.launch{value: launchValue}(p);

        p = _params();
        p.royaltyReceiver = address(0); // rate set, no receiver
        vm.prank(curator);
        vm.expectRevert(CuratedRegistry.BadRoyalty.selector);
        reg.launch{value: launchValue}(p);

        p = _params();
        p.royaltyBps = 500; // the cap itself is allowed
        _launchWith(p);
        (, uint16 bps) = reg.royaltyOf(address(C));
        assertEq(bps, 500);
    }

    /// A reserved work is an ordinary circuit NFT once it is in the treasury: the treasury can give it away or
    /// airdrop it, and it stays official (and marked as reserved) whoever holds it.
    function test_Reserved_TreasuryCanTransferAndItStaysOfficial() public {
        _launch();
        uint256 id = _claim(RESERVED_WORK);
        address treasury = _params().treasury;
        address fan = _eoa("fan");
        address fan2 = _eoa("fan2");
        vm.prank(treasury);
        C.safeTransferFrom(treasury, fan, id); // gift / airdrop
        assertEq(C.ownerOf(id), fan);
        vm.prank(fan);
        C.safeTransferFrom(fan, fan2, id); // and it trades on like any other circuit
        assertEq(C.ownerOf(id), fan2);
        assertTrue(reg.isOfficial(address(C), id));
        assertTrue(reg.isReserved(address(C), id));
        (, uint256 idx) = reg.editionOf(address(C), id);
        assertEq(idx, RESERVED_WORK);
    }

    /// The curator cannot pull a public work into the treasury.
    function test_Reserved_CannotClaimPublicWork() public {
        _launch();
        Work memory w = _work(1);
        assertFalse(w.reserved);
        vm.prank(curator);
        vm.expectRevert(CuratedVault.InvalidProof.selector);
        vault.claimReserved{value: fee}(w.index, w.netlist, w.nIn, w.nOut, w.proof);
    }

    /// The reserved count declared at launch caps claims: here the list marks a reserved work but the launch declares
    /// none, so the work cannot be claimed. (A list hiding extra reserved leaves is caught off chain by checkroot.)
    function test_Reserved_DeclaredCountIsACap() public {
        LaunchParams memory p = _params();
        p.reservedCount = 0; // declares no reserved works although the list marks two
        _launchWith(p);
        Work memory w = _work(RESERVED_WORK);
        vm.prank(curator);
        vm.expectRevert(CuratedVault.ReservedQuotaUsed.selector);
        vault.claimReserved{value: fee}(w.index, w.netlist, w.nIn, w.nOut, w.proof);
        assertEq(reg.collectionOf(address(C)).reserved, 0);
    }

    /// Reserved works need a treasury, which can be neither the registry nor the vault.
    function test_Reserved_Params() public {
        LaunchParams memory p = _params();
        p.treasury = address(0);
        vm.prank(curator);
        vm.expectRevert(abi.encodeWithSelector(CuratedRegistry.BadParams.selector, bytes32("treasury")));
        reg.launch{value: launchValue}(p);

        p = _params();
        p.treasury = REG; // the registry (or the vault itself) can never receive reserved works
        vm.prank(curator);
        vm.expectRevert(abi.encodeWithSelector(CuratedRegistry.BadParams.selector, bytes32("treasury")));
        reg.launch{value: launchValue}(p);

        p = _params();
        p.reservedCount = p.count + 1;
        vm.prank(curator);
        vm.expectRevert(abi.encodeWithSelector(CuratedRegistry.BadParams.selector, bytes32("reservedCount")));
        reg.launch{value: launchValue}(p);
    }

    /// A forgotten reserved work is not lost when the sale ends: the curator can still claim it, and finalize
    /// waits until every reserved work is claimed or RESERVE_GRACE has passed. After finalize nothing can be claimed.
    function test_Reserved_ClaimAfterSaleEndWithinGrace() public {
        _launch();
        uint64 end = vault.SALE_END();
        vm.warp(end);
        assertFalse(vault.finalizable());
        vm.expectRevert(CuratedVault.NotFinalizable.selector);
        vault.finalize();

        uint256 id = _claim(RESERVED_WORK); // after the sale has ended
        assertEq(C.ownerOf(id), _params().treasury);
        assertTrue(reg.isOfficial(address(C), id));
        vm.expectRevert(CuratedVault.NotFinalizable.selector);
        vault.finalize(); // one reserved work is still unclaimed

        vm.warp(uint256(end) + vault.RESERVE_GRACE() - 1);
        vm.expectRevert(CuratedVault.NotFinalizable.selector);
        vault.finalize();
        vm.warp(uint256(end) + vault.RESERVE_GRACE());
        vm.prank(attacker); // anyone may finalize once the grace period is over
        vault.finalize();

        Work memory w = _work(RESERVED_WORK2);
        vm.prank(curator);
        vm.expectRevert(CuratedVault.AlreadyFinalized.selector);
        vault.claimReserved{value: fee}(w.index, w.netlist, w.nIn, w.nOut, w.proof);
    }

    /// Once every reserved work is claimed, finalize no longer waits for the grace period.
    function test_Reserved_AllClaimedFinalizeAtSaleEnd() public {
        _launch();
        _claim(RESERVED_WORK);
        _claim(RESERVED_WORK2);
        vm.warp(vault.SALE_END());
        assertTrue(vault.finalizable());
        vault.finalize();
    }

    function _batch(uint256[] memory idx) internal view returns (CuratedVault.ReservedWork[] memory b) {
        b = new CuratedVault.ReservedWork[](idx.length);
        for (uint256 i; i < idx.length; i++) {
            Work memory w = _work(idx[i]);
            b[i] = CuratedVault.ReservedWork(w.index, w.netlist, w.nIn, w.nOut, w.proof);
        }
    }

    /// Several reserved works in one transaction: curator only, exact fee per work, all or nothing.
    function test_Reserved_BatchClaim() public {
        _launch();
        uint256[] memory both = new uint256[](2);
        both[0] = RESERVED_WORK;
        both[1] = RESERVED_WORK2;
        CuratedVault.ReservedWork[] memory b = _batch(both);

        vm.prank(attacker);
        vm.expectRevert(CuratedVault.OnlyCurator.selector);
        vault.claimReservedBatch{value: 2 * fee}(b);
        vm.prank(curator);
        vm.expectRevert(abi.encodeWithSelector(CuratedVault.WrongPayment.selector, 2 * fee));
        vault.claimReservedBatch{value: fee}(b);

        // a public work in the batch makes the whole batch fail
        uint256[] memory mixed = new uint256[](2);
        mixed[0] = RESERVED_WORK;
        mixed[1] = 1;
        vm.prank(curator);
        vm.expectRevert(CuratedVault.InvalidProof.selector);
        vault.claimReservedBatch{value: 2 * fee}(_batch(mixed));
        assertEq(vault.reservedClaimed(), 0);

        vm.prank(curator); // an empty batch is a harmless no-op
        assertEq(vault.claimReservedBatch(new CuratedVault.ReservedWork[](0)).length, 0);
        assertEq(vault.reservedClaimed(), 0);

        vm.prank(curator);
        uint256[] memory ids = vault.claimReservedBatch{value: 2 * fee}(b);
        assertEq(ids.length, 2);
        for (uint256 i; i < 2; i++) {
            assertEq(C.ownerOf(ids[i]), _params().treasury);
            assertTrue(reg.isReserved(address(C), ids[i]));
            (bool off, uint256 idx) = reg.editionOf(address(C), ids[i]);
            assertTrue(off);
            assertEq(idx, both[i]);
        }
        assertEq(vault.reservedClaimed(), 2);
        vm.prank(curator);
        vm.expectRevert(CuratedVault.AlreadyTaken.selector);
        vault.claimReservedBatch{value: fee}(_batch(_one(RESERVED_WORK)));
    }

    function _one(uint256 i) internal pure returns (uint256[] memory a) {
        a = new uint256[](1);
        a[0] = i;
    }

    // ------------------------------------------------------------------ metadata commitment

    /// The registry records a commitment to the name, symbol, story and every title; the tool computes the same
    /// value (including a non-ASCII title), and the story the processor is created with is part of it.
    function test_Metadata_Committed() public {
        LaunchParams memory p = _params();
        _launch();
        bytes32 m = reg.collectionOf(address(C)).metadata;
        assertEq(m, vm.parseJsonBytes32(manifest, ".launch.metadataHash"));
        assertEq(m, reg.metadataOf(p.name, p.symbol, p.story, p.titlesHash));
        assertTrue(reg.metadataOf(p.name, p.symbol, "another story", p.titlesHash) != m);

        p.titlesHash = bytes32(0);
        vm.prank(curator);
        vm.expectRevert(abi.encodeWithSelector(CuratedRegistry.BadParams.selector, bytes32("titlesHash")));
        reg.launch{value: launchValue}(p);
    }

    // ------------------------------------------------------------------ sale controls

    function test_Sale_CuratorCanPauseAndResume() public {
        _launch();
        Work memory w = _work(0);
        vm.prank(attacker);
        vm.expectRevert(CuratedVault.OnlyCurator.selector);
        vault.setPaused(true);

        vm.prank(curator);
        vm.expectEmit(address(vault));
        emit CuratedVault.SalePaused(true);
        vault.setPaused(true);
        assertTrue(vault.paused());
        vm.prank(buyer);
        vm.expectRevert(CuratedVault.SaleIsPaused.selector);
        vault.buy{value: w.price + fee}(w.index, w.netlist, w.nIn, w.nOut, w.price, w.proof, buyer);

        // reserved claims are not affected by a pause
        uint256 r = _claim(6);
        assertTrue(reg.isReserved(address(C), r));

        vm.prank(curator);
        vault.setPaused(false);
        uint256 id = _buy(0, buyer);
        assertEq(C.ownerOf(id), buyer);
    }

    function test_Sale_ExtendOnlyLaterWhileOpen() public {
        _launch();
        uint64 end = vault.SALE_END();
        vm.prank(attacker);
        vm.expectRevert(CuratedVault.OnlyCurator.selector);
        vault.extendSale(end + 1 days);

        vm.startPrank(curator);
        vm.expectRevert(CuratedVault.CannotExtend.selector);
        vault.extendSale(end); // not later
        vm.expectRevert(CuratedVault.CannotExtend.selector);
        vault.extendSale(end - 1); // earlier
        vm.expectEmit(address(vault));
        emit CuratedVault.SaleEndExtended(end, end + 30 days);
        vault.extendSale(end + 30 days);
        vm.stopPrank();
        assertEq(vault.SALE_END(), end + 30 days);
        assertEq(vault.SALE_END(), end + 30 days);

        // buying works past the old end, finalize waits for the new one
        vm.warp(end + 1);
        uint256 id = _buy(0, buyer);
        assertEq(C.ownerOf(id), buyer);
        assertFalse(vault.finalizable());

        // once the (new) end has passed, the sale cannot be reopened
        vm.warp(uint256(end) + 30 days);
        vm.prank(curator);
        vm.expectRevert(CuratedVault.CannotExtend.selector);
        vault.extendSale(end + 60 days);
        Work memory w = _work(1);
        vm.prank(buyer);
        vm.expectRevert(CuratedVault.SaleEnded.selector);
        vault.buy{value: w.price + fee}(w.index, w.netlist, w.nIn, w.nOut, w.price, w.proof, buyer);
    }

    function test_Sale_NoControlsAfterFinalize() public {
        _launch();
        vm.warp(uint256(vault.SALE_END()) + vault.RESERVE_GRACE());
        vault.finalize();
        vm.startPrank(curator);
        vm.expectRevert(CuratedVault.AlreadyFinalized.selector);
        vault.setPaused(true);
        vm.expectRevert(CuratedVault.CannotExtend.selector);
        vault.extendSale(type(uint64).max);
        vm.stopPrank();
    }

    // ------------------------------------------------------------------ metadata (images)

    function test_Metadata_TokenURIOfficialOnly() public {
        string memory base = vm.parseJsonString(manifest, ".launch.metadataURI");
        _launch();
        assertEq(reg.metadataURIOf(address(C)), base);
        uint256 a = _buy(2, buyer);
        uint256 b = _buy(0, buyer);
        uint256 r = _claim(6);
        assertEq(reg.tokenURI(address(C), a), string.concat(base, "/2.json"));
        assertEq(reg.tokenURI(address(C), b), string.concat(base, "/0.json"));
        assertEq(reg.tokenURI(address(C), r), string.concat(base, "/6.json"));

        // a REF wrapper of an official work, and a circuit that does not exist, get nothing
        Work memory w = _work(2);
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes memory wrapper = abi.encodePacked(uint8(2), address(C), uint64(a), uint8(0), uint8(w.nOut));
        vm.prank(attacker);
        uint256 fake = C.tapeout{value: fee}(wrapper, 0, w.nOut);
        assertEq(reg.tokenURI(address(C), fake), "");
        assertEq(reg.tokenURI(address(C), 999), "");
        assertEq(reg.tokenURI(address(0xBEEF), a), "");

        // the vault answers for its processor (what TapeOut's tokenURI could ask the creator), and for nothing else
        assertEq(vault.circuitURI(address(C), a), string.concat(base, "/2.json"));
        assertEq(vault.circuitURI(address(C), fake), "");
        assertEq(vault.circuitURI(address(0xBEEF), a), "");
        assertTrue(vault.supportsInterface(type(ICircuitURIProvider).interfaceId));
        assertTrue(vault.supportsInterface(0x01ffc9a7));
        assertFalse(vault.supportsInterface(0xffffffff));
        assertEq(T.creator(), address(vault));
    }

    function test_Metadata_FixedAtLaunch() public {
        _launch();
        // nobody, not even the vault or the curator, can declare it again
        vm.prank(address(vault));
        vm.expectRevert(CuratedRegistry.AlreadyBound.selector);
        reg.declareMetadataURI(address(C), "ar://AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA");
        vm.prank(curator);
        vm.expectRevert(CuratedRegistry.NotBoundVault.selector);
        reg.declareMetadataURI(address(C), "ar://AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA");
    }

    function test_Metadata_None() public {
        LaunchParams memory p = _params();
        p.metadataURI = "";
        _launchWith(p);
        uint256 a = _buy(2, buyer);
        assertEq(reg.metadataURIOf(address(C)), "");
        assertEq(reg.tokenURI(address(C), a), "");
    }

    function test_Metadata_OnlyContentAddressed() public {
        string[14] memory bad = [
            "https://example.com/meta",
            "ipfs://QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG/", // trailing slash / path
            "ipfs://QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbd", // too short for a CID
            "ipns://k51qzi5uqu5dlvj2baxnqndepeb86cbk3ng7n3i46uzyxzyqj2xjonzllnv0v8", // mutable name
            "ipfs://my.domain.eth",
            "ar://AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", // 42 characters
            "ar://ardrive", // an ArNS name, which its owner can repoint
            "ar://AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA.",
            "IPFS://QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG",
            "ar://myundername_mycollectionname-permaweb123456", // 43 lower-case characters: could be an ArNS undername
            "ipfs://k51qzi5uqu5dlvj2baxnqndepeb86cbk3ng7n3i46uzyxzyqj2xjonzllnv0v8", // an IPNS key written as a CID
            "ipfs://bafzaajaiaejcaxykhmgsz2mhscluhm6bkliibattya2l2lld7xayj6owtdoyalvh", // libp2p-key CIDv1 (IPNS)
            "ipfs://BAFYBEIGDYRZT5SFP7UDM7HU76UH7Y26NF3EFUYLQABF3OCLGTQY55FBZDI", // upper-case base32
            "ipfs://QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbd0" // 0 is not base58
        ];
        for (uint256 i = 0; i < bad.length; i++) {
            assertFalse(reg.isContentAddressed(bytes(bad[i])), bad[i]);
            LaunchParams memory p = _params();
            p.metadataURI = bad[i];
            vm.prank(curator);
            vm.expectRevert(CuratedRegistry.BadMetadataURI.selector);
            reg.launch{value: launchValue}(p);
        }
        assertTrue(reg.isContentAddressed(bytes("")));
        assertTrue(reg.isContentAddressed(bytes("ipfs://QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG")));
        assertTrue(reg.isContentAddressed(bytes("ipfs://bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi")));
        assertTrue(reg.isContentAddressed(bytes("ipfs://bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u")));
        assertTrue(reg.isContentAddressed(bytes("ar://bNbA3TEQVL60xlgCcqdz4ZPHFZ711cZ3hmkpGttDt_U")));
    }

    function workFor(uint256 i) external view returns (Work memory) {
        return _work(i);
    }

    // ------------------------------------------------------------------ payment token (ERC-20 prices)

    function _launchToken(address token) internal {
        LaunchParams memory p = _params();
        p.paymentToken = token;
        _launchWith(p);
    }

    function _tokenBuy(MockToken tok, uint256 i, address payer) internal returns (uint256 id) {
        Work memory w = _work(i);
        tok.mint(payer, w.price);
        vm.prank(payer);
        tok.approve(address(vault), w.price);
        vm.prank(payer);
        id = vault.buy{value: fee}(w.index, w.netlist, w.nIn, w.nOut, w.price, w.proof, payer);
    }

    /// Prices are paid in the token and the tape-out fee in the native coin; payouts are in the token.
    function test_Token_BuyAndWithdraw() public {
        MockToken tok = new MockToken();
        _launchToken(address(tok));
        assertEq(vault.PAYMENT_TOKEN(), address(tok));
        Work memory w = _work(0);
        assertGt(w.price, 0);

        // the native-coin way of paying is refused: msg.value must be exactly the tape-out fee
        tok.mint(buyer, w.price);
        vm.prank(buyer);
        tok.approve(address(vault), w.price);
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(CuratedVault.WrongPayment.selector, fee));
        vault.buy{value: w.price + fee}(w.index, w.netlist, w.nIn, w.nOut, w.price, w.proof, buyer);
        // without an allowance the purchase reverts as a whole
        address poor = _eoa("p05-token-noallowance");
        vm.deal(poor, 1 ether);
        vm.prank(poor);
        vm.expectRevert();
        vault.buy{value: fee}(w.index, w.netlist, w.nIn, w.nOut, w.price, w.proof, poor);

        uint256 nativeBefore = buyer.balance;
        vm.prank(buyer);
        uint256 id = vault.buy{value: fee}(w.index, w.netlist, w.nIn, w.nOut, w.price, w.proof, buyer);
        assertEq(buyer.balance, nativeBefore - fee, "only the tape-out fee in native coin");
        assertEq(tok.balanceOf(buyer), 0);
        assertTrue(reg.isOfficial(address(C), id));
        assertEq(C.ownerOf(id), buyer);

        // paid to the curator in the token at once
        assertEq(vault.owed(curator), 0);
        assertEq(tok.balanceOf(curator), w.price);
        assertEq(tok.balanceOf(address(vault)), 0);
        assertEq(address(vault).balance, 0, "no native coin left behind");
    }

    /// A token that delivers less than the amount sent (transfer tax) is refused, and nothing changes.
    function test_Token_RefusesFeeOnTransfer() public {
        FeeToken tok = new FeeToken();
        _launchToken(address(tok));
        Work memory w = _work(0);
        tok.mint(buyer, w.price);
        vm.prank(buyer);
        tok.approve(address(vault), w.price);
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(CuratedVault.TokenAmountMismatch.selector, w.price, w.price - w.price / 100));
        vault.buy{value: fee}(w.index, w.netlist, w.nIn, w.nOut, w.price, w.proof, buyer);
        assertFalse(vault.taken(w.index));
        assertEq(tok.balanceOf(buyer), w.price);
    }

    /// A free work in a token collection needs no allowance; an address without code is refused as payment token.
    function test_Token_FreeWorkAndParams() public {
        LaunchParams memory p = _params();
        p.paymentToken = _eoa("p05-not-a-token");
        vm.prank(curator);
        vm.expectRevert(abi.encodeWithSelector(CuratedRegistry.BadParams.selector, bytes32("paymentToken")));
        reg.launch{value: launchValue}(p);

        MockToken tok = new MockToken();
        _launchToken(address(tok));
        Work memory w = _work(3); // the XOR is free
        assertEq(w.price, 0);
        vm.prank(buyer);
        uint256 id = vault.buy{value: fee}(w.index, w.netlist, w.nIn, w.nOut, 0, w.proof, buyer);
        assertTrue(reg.isOfficial(address(C), id));
    }

    /// A token that returns nothing (USDT style) works, also for direct payouts.
    function test_Token_NoReturnToken() public {
        NoReturnToken tok = new NoReturnToken();
        _launchToken(address(tok));
        Work memory w = _work(0);
        tok.mint(buyer, w.price);
        vm.prank(buyer);
        tok.approve(address(vault), w.price);
        vm.prank(buyer);
        vault.buy{value: fee}(w.index, w.netlist, w.nIn, w.nOut, w.price, w.proof, buyer);
        assertEq(tok.balanceOf(curator), w.price);
        assertEq(vault.owed(curator), 0);
        // the registry is refused as payment token
        LaunchParams memory p = _params();
        p.paymentToken = address(reg);
        vm.prank(curator);
        vm.expectRevert(abi.encodeWithSelector(CuratedRegistry.BadParams.selector, bytes32("paymentToken")));
        reg.launch{value: launchValue}(p);
    }

    /// A token payment of proceeds that fails (a blocked curator) is kept in `owed` and the purchase still goes through.
    function test_Token_FailedPayoutIsKept() public {
        BlockToken tok = new BlockToken();
        _launchToken(address(tok));
        tok.block_(curator);
        Work memory w = _work(0);
        tok.mint(buyer, w.price);
        vm.prank(buyer);
        tok.approve(address(vault), w.price);
        vm.prank(buyer);
        uint256 id = vault.buy{value: fee}(w.index, w.netlist, w.nIn, w.nOut, w.price, w.proof, buyer);
        assertEq(C.ownerOf(id), buyer);
        assertEq(vault.owed(curator), w.price);
        assertEq(tok.balanceOf(address(vault)), w.price);
        address cold = _eoa("p05-token-cold");
        vm.prank(attacker);
        vm.expectRevert(CuratedVault.NothingOwed.selector);
        vault.withdrawTo(attacker);
        vm.prank(curator);
        vault.withdrawTo(cold);
        assertEq(tok.balanceOf(cold), w.price);
        assertEq(vault.owed(curator), 0);
    }

    /// A token that calls back into the vault during a purchase or a withdrawal cannot get in.
    function test_Token_ReentrantTokenIsBlocked() public {
        HookToken tok = new HookToken();
        _launchToken(address(tok));
        Work memory w = _work(0);
        Work memory w1 = _work(1);
        tok.arm(address(vault), abi.encodeCall(
            CuratedVault.buy, (w1.index, w1.netlist, w1.nIn, w1.nOut, w1.price, w1.proof, attacker)
        ));
        tok.mint(buyer, w.price);
        vm.prank(buyer);
        tok.approve(address(vault), w.price);
        vm.prank(buyer);
        vault.buy{value: fee}(w.index, w.netlist, w.nIn, w.nOut, w.price, w.proof, buyer);
        assertFalse(tok.reentered(), "buy re-entered");
        assertFalse(vault.taken(w1.index));
        // the payout transfers inside the purchase cannot get in either
        tok.arm(address(vault), abi.encodeCall(CuratedVault.withdraw, (curator)));
        Work memory w2 = _work(2);
        tok.mint(buyer, w2.price);
        vm.prank(buyer);
        tok.approve(address(vault), w2.price);
        vm.prank(buyer);
        vault.buy{value: fee}(w2.index, w2.netlist, w2.nIn, w2.nOut, w2.price, w2.proof, buyer);
        assertFalse(tok.reentered(), "withdraw re-entered");
    }

    /// Vaults are clones of one fixed implementation; nobody can initialise the implementation or a launched vault
    /// again.
    function test_Clones_FixedImplementation() public {
        assertEq(reg.VAULT_IMPL(), IMPL0);
        LaunchParams memory p = _params();
        vm.prank(attacker);
        vm.expectRevert(CuratedVault.AlreadyInitialized.selector);
        CuratedVault(payable(IMPL0)).initialize(p, attacker);
        _launch();
        // the vault is a minimal proxy to the implementation
        assertEq(address(vault).code, abi.encodePacked(hex"363d3d373d3d3d363d73", IMPL0, hex"5af43d82803e903d91602b57fd5bf3"));
        vm.prank(address(reg));
        vm.expectRevert(CuratedVault.AlreadyInitialized.selector);
        vault.initialize(p, attacker);
    }

    /// On BNB Smart Chain, BEM itself works as a payment token (no transfer tax).
    function test_Token_BEMOnBSC() public {
        vm.skip(block.chainid != 56);
        address bem = 0x5ce033B2bFCa3Af30b3e8C8457DeaF776A8b695a;
        assertEq(IERC20Meta(bem).decimals(), 8);
        _launchToken(bem);
        Work memory w = _work(0);
        deal(bem, buyer, w.price);
        vm.prank(buyer);
        IERC20Meta(bem).approve(address(vault), w.price);
        vm.prank(buyer);
        uint256 id = vault.buy{value: fee}(w.index, w.netlist, w.nIn, w.nOut, w.price, w.proof, buyer);
        assertTrue(reg.isOfficial(address(C), id));
        assertEq(IERC20Meta(bem).balanceOf(address(vault)), 0);
        assertEq(IERC20Meta(bem).balanceOf(curator), w.price);
    }
}

/// A token that refuses transfers to blocked addresses (like USDC's blacklist).
contract BlockToken is MockToken {
    mapping(address => bool) public blocked;

    function block_(address a) external {
        blocked[a] = true;
    }

    function _move(address from, address to, uint256 amount) internal override {
        require(!blocked[to], "blocked");
        super._move(from, to, amount);
    }
}

/// Recipient that tries to buy again while receiving the circuit.
contract Reenter {
    CuratedVault immutable v;
    CuratedForkTest immutable t;

    constructor(CuratedVault v_, CuratedForkTest t_) {
        v = v_;
        t = t_;
    }

    function onERC721Received(address, address, uint256, bytes calldata) external returns (bytes4) {
        CuratedForkTest.Work memory w = t.workFor(0);
        uint256 f = v.circuits().TAPEOUT_FEE();
        v.buy{value: w.price + f}(w.index, w.netlist, w.nIn, w.nOut, w.price, w.proof, address(this));
        return this.onERC721Received.selector;
    }

    receive() external payable {}
}

/// Curator account whose refund hook tries to buy a work inside the launch transaction.
contract RefundReenter {
    CuratedForkTest immutable t;

    constructor(CuratedForkTest t_) {
        t = t_;
    }

    bytes4 public seen;

    receive() external payable {
        CuratedForkTest.Work memory w = t.workFor(3); // price 0
        // the vault sends the refund; buying now must hit the reentrancy guard
        CuratedVault v = CuratedVault(payable(msg.sender));
        uint256 f = v.circuits().TAPEOUT_FEE();
        try v.buy{value: f}(w.index, w.netlist, w.nIn, w.nOut, w.price, w.proof, address(this)) {
            seen = bytes4(0xffffffff); // must never happen
        } catch (bytes memory err) {
            // the first four bytes of the revert data are the error selector
            // forge-lint: disable-next-line(unsafe-typecast)
            seen = bytes4(err);
        }
    }
}
