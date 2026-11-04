// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {CuratedRegistry} from "../src/CuratedRegistry.sol";
import {CuratedVault} from "../src/CuratedVault.sol";
import {ITapeOutFactory} from "../src/interfaces/ITapeOut.sol";

/// Deploy the vault implementation and the registry that clones it (two transactions, no owner).
///
///   FACTORY=<TapeOut factory of the chain> forge script script/Deploy.s.sol --rpc-url <RPC> --broadcast \
///       --private-key <any key>
contract Deploy is Script {
    function run() external {
        ITapeOutFactory factory = ITapeOutFactory(vm.envAddress("FACTORY"));
        vm.startBroadcast();
        address impl = address(new CuratedVault());
        CuratedRegistry reg = new CuratedRegistry(factory, impl);
        vm.stopBroadcast();
        console.log("REGISTRY", address(reg));
        console.log("VAULT_IMPL", impl);
    }
}
