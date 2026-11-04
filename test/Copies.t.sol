// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {CuratedRegistry} from "../src/CuratedRegistry.sol";
import {CuratedVault} from "../src/CuratedVault.sol";
import {LaunchParams} from "../src/CuratedTypes.sol";
import {ICuratedRegistry} from "../src/interfaces/ICuratedRegistry.sol";
import {ITapeOutFactory, ITapeOutTransistors, ITapeOutCircuits} from "../src/interfaces/ITapeOut.sol";
import {ManifestParams} from "../script/ManifestParams.sol";

/// Fork tests of a sequential collection (one design in many copies, sold in list order), on BNB Smart Chain, X Layer
/// or Base (as test/Curated.t.sol). Fixture: test/fixtures/copies[.<chainId>].json, built by `tool/curate.py build`
/// from tool/examples.
abstract contract CopiesBase is Test {
    address constant REG = 0x00000000000000000000000000000000c0dEc0DE;
    ITapeOutFactory FACTORY;
    CuratedRegistry reg;
    string manifest;
    LaunchParams P;
    address curator;
    address buyer = makeAddr("modes-buyer");
    address buyer2 = makeAddr("modes-buyer2");
    address attacker = makeAddr("modes-attacker");
    ITapeOutTransistors T;
    ITapeOutCircuits C;
    address vaultAddr;
    uint256 fee;

    struct Item {
        uint256 index;
        bytes netlist;
        uint32 nIn;
        uint32 nOut;
        bool reserved;
        uint256 price;
        uint256 first;
        uint32 copies;
    }

    Item[] items;

    function _fixture() internal pure virtual returns (string memory);

    function setUp() public {
        string memory sfx;
        if (block.chainid == 56) {
            FACTORY = ITapeOutFactory(0x68224F668083c29e9800Be2a646d42d18cedF7e2);
        } else if (block.chainid == 196 || block.chainid == 8453) {
            FACTORY = ITapeOutFactory(0x1f09DAeFA827f02CBb40967cc91b259763760761);
            sfx = string.concat(".", vm.toString(block.chainid));
        } else {
            revert("fork BNB Smart Chain (56), X Layer (196) or Base (8453)");
        }
        address i0 = address(new CuratedVault());
        deployCodeTo("CuratedRegistry.sol:CuratedRegistry", abi.encode(FACTORY, i0), REG);
        reg = CuratedRegistry(REG);
        manifest = vm.readFile(string.concat("test/fixtures/", _fixture(), sfx, ".json"));
        assertEq(vm.parseJsonAddress(manifest, ".registry"), REG);
        P = ManifestParams.read(manifest);
        curator = P.curator;
        address[4] memory eoas = [buyer, buyer2, attacker, curator];
        for (uint256 i; i < eoas.length; i++) {
            vm.etch(eoas[i], "");
            vm.deal(eoas[i], 100 ether);
        }
        // every work, one per index (runs of copies expanded)
        for (uint256 r; vm.keyExistsJson(manifest, string.concat(".works[", vm.toString(r), "]")); r++) {
            string memory k = string.concat(".works[", vm.toString(r), "]");
            string memory d =
                string.concat(".designs[", vm.toString(vm.parseJsonUint(manifest, string.concat(k, ".design"))), "]");
            Item memory it;
            it.first = vm.parseJsonUint(manifest, string.concat(k, ".first"));
            it.copies = uint32(vm.parseJsonUint(manifest, string.concat(k, ".copies")));
            it.netlist = vm.parseJsonBytes(manifest, string.concat(d, ".netlist"));
            it.nIn = uint32(vm.parseJsonUint(manifest, string.concat(d, ".nIn")));
            it.nOut = uint32(vm.parseJsonUint(manifest, string.concat(d, ".nOut")));
            it.reserved = vm.parseJsonBool(manifest, string.concat(k, ".reserved"));
            if (vm.keyExistsJson(manifest, string.concat(k, ".priceWei"))) {
                it.price = vm.parseJsonUint(manifest, string.concat(k, ".priceWei"));
            }
            for (uint256 c; c < it.copies; c++) {
                it.index = it.first + c;
                items.push(it);
            }
        }
        assertEq(items.length, P.count);
    }

    function _launch() internal {
        vm.prank(curator);
        (address v, address t, address c) = reg.launch{value: vm.parseJsonUint(manifest, ".launch.launchValueWei")}(P);
        vaultAddr = v;
        T = ITapeOutTransistors(t);
        C = ITapeOutCircuits(c);
        fee = C.TAPEOUT_FEE();
    }
}

// ====================================================================== same design, many copies, sold in list order

contract CopiesForkTest is CopiesBase {
    function _fixture() internal pure override returns (string memory) {
        return "copies";
    }

    function vault() internal view returns (CuratedVault) {
        return CuratedVault(payable(vaultAddr));
    }

    // runs of the fixture: [0, 2) AND reserved, [2, 7) Toggle, [7, 10) XOR (free)
    function _run(uint256 r) internal view returns (Item memory it, bytes32[] memory proof) {
        string memory k = string.concat(".works[", vm.toString(r), "]");
        it = items[vm.parseJsonUint(manifest, string.concat(k, ".first"))];
        proof = vm.parseJsonBytes32Array(manifest, string.concat(k, ".proof"));
    }

    function _buyNext(uint256 r, address who) internal returns (uint256 id) {
        (Item memory it, bytes32[] memory proof) = _run(r);
        vm.prank(who);
        id = vault().buyNext{value: it.price + fee}(it.first, it.copies, it.netlist, it.nIn, it.nOut, it.price, proof, who);
    }

    /// The design is stored once in the manifest; one run leaf covers all its copies; every copy is official, in list
    /// order, and its official serial equals its TapeOut circuit id and its position in the list plus one.
    function test_Copies_SoldInOrder_SerialEqualsTapeOutId() public {
        _launch();
        assertTrue(vault().SEQUENTIAL());
        // nothing can be bought before the reserved run (first in the list) is claimed
        (Item memory t0, bytes32[] memory tp) = _run(1);
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(CuratedVault.NotNext.selector, 0));
        vault().buyNext{value: t0.price + fee}(t0.first, t0.copies, t0.netlist, t0.nIn, t0.nOut, t0.price, tp, buyer);
        // the per-index buy and claim of an unordered collection are refused
        vm.prank(buyer);
        vm.expectRevert(CuratedVault.WrongMode.selector);
        vault().buy{value: t0.price + fee}(2, t0.netlist, t0.nIn, t0.nOut, t0.price, tp, buyer);

        (Item memory r0, bytes32[] memory rp) = _run(0);
        vm.prank(attacker);
        vm.expectRevert(CuratedVault.OnlyCurator.selector);
        vault().claimReservedRun{value: 2 * fee}(r0.first, r0.copies, r0.netlist, r0.nIn, r0.nOut, rp, 2);
        vm.prank(curator);
        uint256[] memory res = vault().claimReservedRun{value: 2 * fee}(r0.first, r0.copies, r0.netlist, r0.nIn, r0.nOut, rp, 2);
        assertEq(res[0], 1);
        assertEq(res[1], 2);

        uint256 curator0 = curator.balance;
        uint256 gross;
        for (uint256 r = 1; r <= 2; r++) {
            (Item memory it,) = _run(r);
            for (uint256 c; c < it.copies; c++) {
                uint256 expected = C.nextId() + 1;
                vm.expectEmit(true, true, false, true, address(reg));
                emit ICuratedRegistry.Serial(address(C), expected, expected);
                uint256 id = _buyNext(r, c % 2 == 0 ? buyer : buyer2);
                assertEq(id, expected);
                assertEq(id, it.first + c + 1, "TapeOut id = list position + 1");
                assertEq(reg.serialOf(address(C), id), id, "official serial = TapeOut id");
                (bool taped, uint256 tid) = reg.tokenOfSerial(address(C), id);
                assertTrue(taped);
                assertEq(tid, id);
                (bool off, uint256 idx) = reg.editionOf(address(C), id);
                assertTrue(off);
                assertEq(idx, it.first + c);
                assertEq(keccak256(C.netlist(id)), keccak256(it.netlist));
                gross += it.price;
            }
            // the run is used up: its leaf sells nothing more
            if (r == 1) {
                (Item memory it1, bytes32[] memory p1) = _run(1);
                vm.prank(buyer);
                vm.expectRevert(abi.encodeWithSelector(CuratedVault.NotNext.selector, 7));
                vault().buyNext{value: it1.price + fee}(it1.first, it1.copies, it1.netlist, it1.nIn, it1.nOut, it1.price, p1, buyer);
            }
        }
        (Item memory x, bytes32[] memory xp) = _run(2);
        vm.prank(buyer);
        vm.expectRevert(CuratedVault.IndexOutOfRange.selector);
        vault().buyNext{value: fee}(x.first, x.copies, x.netlist, x.nIn, x.nOut, 0, xp, buyer);
        // every sale is paid to the curator at once
        assertEq(curator.balance - curator0, gross);
        assertEq(vaultAddr.balance, 0);
        assertEq(reg.collectionOf(address(C)).certified, P.count);
        assertEq(uint256(reg.collectionOf(address(C)).saleMode), 0);
        vault().finalize();
    }

    /// A wrapper injected by an outsider takes a TapeOut id: from then on serial and TapeOut id differ by one (the
    /// registry records both; TAP Recommendation 2 asks TapeOut to let a creator restrict tape-outs to itself).
    function test_Copies_InjectedWrapperShiftsTapeOutIds() public {
        _launch();
        (Item memory r0, bytes32[] memory rp) = _run(0);
        vm.prank(curator);
        vault().claimReservedRun{value: 2 * fee}(r0.first, r0.copies, r0.netlist, r0.nIn, r0.nOut, rp, 2);
        // a zero-cost REF wrapper of circuit 1, taped out by a stranger
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes memory wrapper = abi.encodePacked(uint8(2), address(C), uint64(1), uint8(2), uint8(1), uint24(2), uint24(3));
        vm.prank(attacker);
        uint256 fake = C.tapeout{value: fee}(wrapper, r0.nIn, r0.nOut);
        assertEq(fake, 3);
        assertEq(reg.serialOf(address(C), fake), 0);
        uint256 id = _buyNext(1, buyer);
        assertEq(id, 4);
        assertEq(reg.serialOf(address(C), id), 3);
        (, uint256 idx) = reg.editionOf(address(C), id);
        assertEq(idx, 2);
    }
}
