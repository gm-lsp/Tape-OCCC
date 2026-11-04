// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Vm} from "forge-std/Vm.sol";
import {LaunchParams} from "../src/CuratedTypes.sol";

/// Reads the launch parameters of a manifest built by `tool/curate.py build` (curated-collection-manifest/8, core fields).
library ManifestParams {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function read(string memory m) internal pure returns (LaunchParams memory p) {
        p.name = vm.parseJsonString(m, ".launch.name");
        p.symbol = vm.parseJsonString(m, ".launch.symbol");
        p.story = vm.parseJsonString(m, ".launch.story");
        p.nandSupply = vm.parseJsonUint(m, ".launch.nandSupply");
        p.latchSupply = vm.parseJsonUint(m, ".launch.latchSupply");
        p.mintPrice = vm.parseJsonUint(m, ".launch.mintPrice");
        p.mintBatch = vm.parseJsonUint(m, ".launch.mintBatch");
        p.root = vm.parseJsonBytes32(m, ".launch.root");
        p.count = uint32(vm.parseJsonUint(m, ".launch.count"));
        p.curator = vm.parseJsonAddress(m, ".launch.curator");
        p.saleStart = uint64(vm.parseJsonUint(m, ".launch.saleStart"));
        p.saleEnd = uint64(vm.parseJsonUint(m, ".launch.saleEnd"));
        p.maxLaunchFees = vm.parseJsonUint(m, ".launch.maxLaunchFees");
        p.treasury = vm.parseJsonAddress(m, ".launch.treasury");
        p.reservedCount = uint32(vm.parseJsonUint(m, ".launch.reservedCount"));
        p.royaltyReceiver = vm.parseJsonAddress(m, ".launch.royaltyReceiver");
        p.royaltyBps = uint16(vm.parseJsonUint(m, ".launch.royaltyBps"));
        p.titlesHash = vm.parseJsonBytes32(m, ".launch.titlesHash");
        p.metadataURI = vm.parseJsonString(m, ".launch.metadataURI");
        p.paymentToken = vm.parseJsonAddress(m, ".launch.paymentToken");
        p.sequential = vm.parseJsonBool(m, ".launch.sequential");
    }
}
