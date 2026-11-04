// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

struct LaunchParams {
    string name;
    string symbol;
    string story;
    uint256 nandSupply; // NAND to mint: sum of NAND records over all works (plus spare)
    uint256 latchSupply; // LATCH to mint: sum of LATCH records over all works (plus spare)
    uint256 mintPrice; // processor mint price; 0, or >0 to meet front-end display thresholds
    uint256 mintBatch; // batch size for the mint/withdraw loop when mintPrice > 0
    bytes32 root; // Merkle root of the work list
    uint32 count; // number of works (every copy counts)
    address curator; // launches the collection, runs it and receives its proceeds
    uint64 saleStart; // unix time when the sale opens
    uint64 saleEnd; // unix time after which buying closes
    uint256 maxLaunchFees; // cap on deploy fee + protocol fees paid at launch (guards against fee changes)
    address treasury; // receives every reserved work; fixed at launch (address(0) if none are reserved)
    uint32 reservedCount; // number of works marked reserved in the work list; fixed at launch
    address royaltyReceiver; // optional royalty declaration for resales (ERC-2981 style); address(0) = none
    uint16 royaltyBps; // royalty rate in basis points, at most the registry's MAX_ROYALTY_BPS; 0 when none
    bytes32 titlesHash; // keccak256 of the keccak256 of every work title (UTF-8), in index order
    string metadataURI; // content-addressed directory of <index>.json files, or ""
    address paymentToken; // ERC-20 that prices are paid in; address(0) = the chain's native coin
    bool sequential; // works are sold strictly in list order from runs of copies (see runLeafOf)
}

interface ICuratedVaultInit {
    function initialize(LaunchParams calldata p, address refundTo) external payable returns (address t, address c);
}
