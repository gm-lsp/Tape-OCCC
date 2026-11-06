---
tap: TBD
title: Official Curated Circuit Collections
description: A registry and launch pattern that make "this circuit is an official work of this collection" a public, provenance-based fact on chain.
author: gm-lsp (@gm-lsp)
discussions-to: https://github.com/TapeOutProtocol/TAPs/issues/102
status: Draft
type: Standards
created: 2026-10-25
requires: TAP-02, ERC-165, ERC-721, ERC-1155, ERC-2981
license: CC0-1.0
---

# TAP-TBD: Official Curated Circuit Collections (OCCC)

## Summary

A way for an artist or project to launch a fixed list of circuits on TapeOut so that anyone — a buyer, a market, another contract — can check on chain which circuits in the collection are the real works and which were added by someone else.

## Abstract

On TapeOut a processor contract is an NFT collection, but anyone can add circuits to it: with transistors any netlist can be taped out, and without any transistors a netlist made only of REF records can be taped out at zero transistor cost. This TAP defines **curated collections** (the Official Curated Circuit Collections, OCCC, of the title): collections whose official works anyone can check. A curated collection is launched in a single transaction in which a vault contract creates the processor and mints its entire transistor supply to itself. Afterwards, the collection's transistors can be spent only through that vault, and the vault tapes out only works from a work list fixed at launch as a Merkle root. A circuit is **official** if and only if the vault taped it out and a registry certified its id in the same transaction; every official circuit also gets an official serial number, its order among the collection's official tape-outs. A curator can mark works in the list as **reserved** for a treasury fixed at launch, from which they can be given away or airdropped like any circuit, and can declare a royalty that markets may read and honour. How a vault sells its works (prices, order, assignment, payment) is left to the vault, within the rules every vault follows; officialness does not depend on it. The TAP specifies the registry interface (`isOfficial`, `editionOf`, `tokenOf`, `serialOf`, `tokenOfSerial`, `isReserved`, `isCurated`, `collectionOf`, the royalty functions and their events), the conditions the registry checks at launch (including that the curator launches personally), the rules every vault follows, a work-list leaf encoding bound to the chain, the registry and the curator, the requirement to publish every leaf, a commitment to the collection's name, symbol, story and titles, an optional metadata directory fixed at launch from which the registry's `tokenURI` gives every official circuit ERC-721 metadata (name, image, attributes), and how front-ends, markets and contracts are to use the record. It ends with two recommendations to TapeOut: let each processor's creator decide its circuits' metadata, and let a creator restrict tape-outs to itself.

**For TapeOut:** the two upgrades this TAP recommends to TapeOut (circuit metadata decided by each processor's creator, for every project; and an opt-in restriction of tape-outs to a processor's creator) are collected at the end, under *Recommendations to TapeOut (key points)*. Nothing else depends on them.

## Motivation

A collection of circuit NFTs is, on TapeOut, the set of circuits of one processor contract. The protocol does not let the processor's creator decide what enters that set:

1. **Anyone holding transistors can tape out any netlist** into the processor. If the processor's transistors are sold publicly, buyers can tape out small "toy" circuits, or tape out a netlist **byte-for-byte identical** to an official work.
2. **Anyone can tape out a pure-REF netlist with no transistors at all.** `tapeout` burns only the netlist's own NAND and LATCH records (TAP-02 §6); REF records burn nothing. A 31-byte netlist that is a single REF to an official circuit costs only the tape-out fee, and its `circuitInfo`, `eval` and `step` are identical to the official circuit's (TAP-02 §4, §6).

Mainnet collections already contain toy circuits and pure-REF wrappers. In two collections examined on 2026-10-25, between a few dozen and about 1,400 circuits were small toy circuits, and tens to hundreds were pure-REF wrappers whose `circuitInfo` matched the official design exactly. Their projects did not recognise them, but markets listed them in the collection, and some marked them as matching the standard. Users also reported official-identical netlists taped out by holders of the processor's transistors, which no content check can distinguish.

What the projects actually used to decide "official" was off-chain knowledge of **who taped the circuit out**. Buyers could not check it, markets could not display it, and contracts that grant rights to circuit holders could not enforce it. This TAP turns that knowledge into a public, immutable record with a fixed meaning.

Content checks cannot replace it:

| Kind | Netlist vs. official | Detectable by content? |
|---|---|---|
| Toy circuit | different | yes, by netlist hash |
| Pure-REF wrapper | different bytes, identical `circuitInfo` / evaluation | only by netlist bytes |
| Same netlist taped out by someone else | identical | **no** |

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174 when, and only when, they appear in all capitals.

### 1. Terms

| Term | Meaning |
|---|---|
| Processor contract | As in TAP-02: an ERC-721 contract created by the TapeOut processor factory. Called `circuits` below |
| Transistor contract | The processor's ERC-1155 contract; id 0 = NAND, id 1 = LATCH; one supply cap shared by both ids |
| Chain | A chain on which TapeOut is deployed: BNB Smart Chain (chain id 56), X Layer (196) and Base (8453) at the time of writing. "Native coin" is the chain's own coin (BNB, OKB, ETH) |
| Registry | A contract implementing §3, deployed on one chain and bound at deployment to that chain's TapeOut processor factory. It has no owner and cannot be upgraded |
| Vault | The contract that launched a curated collection and is bound to it in the registry |
| Curated collection | A processor contract bound to a vault in a registry |
| Work list | An ordered list of `count` works, indexed from 0, committed to by a Merkle root |
| Official circuit | A circuit `(circuits, tokenId)` certified by the registry under §2 |
| Curator | The address that launches the collection, is the only one that may claim reserved works, and may change the royalty receiver or lower its rate |
| Sale rules | How a vault sells its works (prices, order, assignment of works to buyers, payment); fixed at launch and not part of this standard beyond §6 |
| Run | In a sequential work list, a design listed once with a number of identical copies, which occupy consecutive indexes (§5) |
| Payment asset | The native coin, or one ERC-20 token fixed at launch, in which a vault prices its works (§6 rule 8) |
| Serial | An official circuit's position, from 1, among the official circuits of its collection in tape-out order (§3) |
| Reserved work | A work the work list marks as kept for the treasury: it cannot be bought, only claimed to the treasury |
| Treasury | The address, fixed at launch, that receives every reserved work |

### 2. Definition of an official circuit

A circuit `(circuits, tokenId)` is **official** in a registry if and only if:

1. `circuits` is a curated collection in that registry (§4), and
2. the collection's vault taped out circuit `tokenId` by calling `circuits.tapeout`, and
3. in the same transaction, the vault called the registry's `certify(circuits, tokenId, index, netlistHash, reserved)` for a work `index` with `index < count` that had not been certified before.

Officialness belongs to the circuit, not to its holder: it does not change when the circuit is transferred, sold, given away or airdropped.

When a work list sells one design in many copies (§5), each copy is official by the same rule, because the vault taped it out. A circuit with the same netlist taped out by anyone else, on this processor (only possible as a pure-REF wrapper, §4) or on another, is not official.

Officialness MUST NOT be inferred from a circuit's netlist bytes, netlist hash, `circuitInfo`, evaluation results, owner, or token URI.

Officialness is relative to one processor contract. A curator may launch more than one collection, so consumers MUST identify a collection by the chain id and processor address the curator announced, not by its name or symbol, which are not unique.

### 3. Registry interface

A registry MUST implement the following functions and events. All functions in the table except `certify` are `view`.

| Function | Selector | Returns |
|---|---|---|
| `isOfficial(address circuits, uint256 tokenId)` | `0x9a516edc` | `bool`: whether the circuit is official (§2) |
| `editionOf(address circuits, uint256 tokenId)` | `0xe80e01aa` | `(bool official, uint256 index)`: `index` is the work-list position; `(false, 0)` if not official |
| `tokenOf(address circuits, uint256 index)` | `0xa3dabb02` | `(bool taped, uint256 tokenId)`: whether work `index` has been taped out, and its circuit id |
| `isReserved(address circuits, uint256 tokenId)` | `0x9e9cf5c3` | `bool`: whether the circuit is an official work that the list reserved for the treasury; unchanged by later transfers |
| `isCurated(address circuits)` | `0x774d70e4` | `bool`: whether `circuits` is a curated collection in this registry |
| `collectionOf(address circuits)` | `0x3e94c904` | `(address vault, address curator, address transistors, address treasury, bytes32 root, uint32 count, uint32 reserved, uint32 certified, bytes32 metadata, uint8 saleMode)`; `saleMode` identifies the vault's sale rules (implementation-defined; 0 = works sold as listed); all zero if not curated |
| `serialOf(address circuits, uint256 tokenId)` | `0x7be75877` | `uint256`: the circuit's official serial (1 for the collection's first official circuit, 2 for the next, …); 0 if not official |
| `tokenOfSerial(address circuits, uint256 serial)` | `0x065b9385` | `(bool taped, uint256 tokenId)`: the circuit with that serial |
| `certify(address circuits, uint256 tokenId, uint256 index, bytes32 netlistHash, bool reserved)` | `0xaa92a7c0` | not `view`: records an official circuit; callable only by the collection's vault (§3 rule 4) |

| Event | Topic 0 |
|---|---|
| `CollectionLaunched(address indexed circuits, address indexed vault, address indexed curator, address transistors, bytes32 root, uint32 count, address treasury, uint32 reserved, bytes32 metadata)` | `0xfafcf03610954fd778b52f9044d3c3fcbade024c53f03257b287645a997bb10d` |
| `Certified(address indexed circuits, uint256 indexed tokenId, uint256 indexed index, bytes32 netlistHash, bool reserved)` | `0x8d7d8f5d2406ca80fb5e26889f1d3c94eaa0bc9e610a469ca59e18cab4ff1340` |
| `Serial(address indexed circuits, uint256 indexed tokenId, uint256 serial)` | `0x8299a793f3c0fd9c6e44cf13aa3d647c724f27561931bed2f30f320848a31a19` |

Rules:

1. For each `circuits`, `CollectionLaunched` MUST be emitted exactly once, and before any `Certified` for it.
2. `Certified` MUST be emitted in the same transaction as the tape-out of `tokenId`, exactly once per `tokenId` and exactly once per `index`.
3. Once `isOfficial(circuits, tokenId)` is true it MUST stay true; `editionOf` and `tokenOf` MUST NOT change once set. `collectionOf(circuits).root`, `.count`, `.vault`, `.curator`, `.transistors`, `.treasury`, `.reserved` and `.metadata` MUST NOT change once set.
4. The registry MUST NOT have an owner, administrator, pause switch or upgrade mechanism, and MUST NOT accept certifications from any address other than the collection's vault.
5. The registry MUST NOT certify more reserved works for a collection than the `reserved` count fixed at launch.
6. Each certification MUST assign the next serial: the first circuit certified for a collection gets serial 1, and each later one the previous serial plus 1. `Serial` MUST be emitted right after `Certified`, and `serialOf` and `tokenOfSerial` MUST NOT change once set.

The index (`editionOf`) is a work's position in the work list; the serial (`serialOf`) is its place in the order of official tape-outs, which is the number a collection's holders usually mean by "#N". The registry requires a fresh processor (§4.6) and TapeOut numbers circuits from 1 in tape-out order, so as long as nobody else tapes out a circuit on the processor, the serial equals the TapeOut circuit id. Anyone can still tape out a pure-REF wrapper into any processor (§4); each one takes a TapeOut id, and from then on the two numbers differ. A protocol cannot prevent that today; Recommendation 2 (at the end) recommends the TapeOut change that would. Front-ends SHOULD show the serial as the work's number and the TapeOut id beside it when they differ. In a sequential collection (§5) the serial is the index plus one; where it assigns works to buyers at random, the serial is the delivery order and is unrelated to the work's index or title.

### 4. Launch

A registry MUST bind a collection to a vault only if all of the following hold **at the moment of binding**, checked on chain by the registry itself rather than taken from the vault:

1. The vault was created for this launch by this registry, in a call whose sender is the curator, from vault code the registry fixed at its own deployment (the reference registry creates an EIP-1167 clone of a vault implementation whose address is immutable in the registry). A registry MUST NOT launch a collection whose curator is not the caller, so nobody can launch in an artist's name.
2. `factory.isCPU(circuits)` (selector `0x5f5a364f`) is true for the TapeOut processor factory of the registry's chain, which the registry MUST fix at deployment.
3. `circuits.transistors() == transistors` and `transistors.circuits() == circuits`.
4. `transistors.creator() == vault`.
5. `transistors.minted() == transistors.supplyCap()`, and `transistors.balanceOf(vault, 0) + transistors.balanceOf(vault, 1) == transistors.supplyCap()`.
6. No circuit has been taped out on `circuits` yet. (On the deployed contracts `circuits.nextId()` returns 0 for a fresh processor; see Backwards Compatibility.)
7. `circuits` is not already bound.

Creating the processor, minting its whole supply to the vault and binding MUST happen in one transaction. Because the processor does not exist before that transaction, nobody else can hold any of its transistors.

Right after creating the processor, the reference vault calls `restrictTapeoutToCreator()` (`0x9051fb27`) on it with a gas limit of 100,000 and ignores the result. Today's processors have no such function and the call changes nothing; if TapeOut adopts Recommendation 2 (at the end), collections launched afterwards are restricted to their vault from their first block, and no wrapper can ever be taped out into them.

The launch MUST fix a sale end time, which MUST be later than the launch. The launcher SHOULD state the most it will pay in factory and protocol fees, and the launch MUST revert if the fees read at launch time exceed it, so a fee change between preparing and sending the launch cannot drain the launcher's float.

A launch MAY use a non-zero processor mint price (for example to meet a front-end display threshold). In that case the vault pays itself and recovers the payment with `withdraw()` between mint batches; the vault is the creator, so the net cost is the factory deploy fee and the protocol fees. This "mint revenue" is not real demand, and tools SHOULD say so.

### 5. Work list

Each work is `(index, netlist, nIn, nOut, price, reserved)`, where `netlist` is a well-formed TAP-02 netlist, `price` is its price in the smallest unit of the collection's payment asset (wei for the native coin; §6 rule 8), and `reserved` says whether the work is kept for the treasury. A reserved work MUST have `price = 0`. The leaf of a work is (pseudo-code; `abi.encode` and `keccak256` as in Solidity)

```
leaf = keccak256(bytes.concat(keccak256(abi.encode(
    uint256 chainId, address registry, address curator,
    uint256 index, bytes32 keccak256(netlist), uint32 nIn, uint32 nOut, uint256 price, bool reserved))))
```

and the root is computed with sorted-pair hashing, as verified by OpenZeppelin `MerkleProof` (`hash(a, b) = keccak256(a < b ? a ‖ b : b ‖ a)`). Binding the leaf to the chain, the registry and the curator means a work list cannot be reused by anyone else, on another chain, or in another registry.

Which works are public and which are reserved is therefore fixed at launch, together with the number of reserved works and the treasury address. A curator cannot later move a popular public work into the treasury, and buyers can see every reserved work before the sale opens. Indexes MUST be `0 … count − 1`, each used once.

**Copies.** Many collections sell one design many times: thousands of circuits with the same netlist, each an official work (§2). A work list MAY therefore contain the same netlist at several indexes. Tools SHOULD reject a work list that contains the same netlist twice unless the curator declares it as one design sold in `copies` identical copies, which the tool expands to `copies` consecutive indexes; an undeclared repetition is refused as a likely mistake. Tools and publication formats SHOULD store such a design once, with its copy count, not once per copy. The transistors a design needs are counted once per copy.

**Sequential collections.** A collection MAY be launched as **sequential**: works are then sold strictly in list order, the vault tapes out index `sold` (the number of works taped out so far) on each purchase, and the work list is a list of **runs**, each a design with `copies` identical copies at indexes `first … first + copies − 1` (a single work is a run of one), with one leaf per run:

```
runLeaf = keccak256(bytes.concat(keccak256(abi.encode(
    uint256 chainId, address registry, address curator, bytes32 keccak256("TAP-curated-run"),
    uint256 first, uint32 copies, bytes32 keccak256(netlist), uint32 nIn, uint32 nOut, uint256 price, bool reserved))))
```

The tag and the length (eleven words) keep run leaves apart from work leaves. Because nobody can skip ahead, a work's index fixed in the list is also its tape-out order, so its serial (§3) is `index + 1`, and while nobody else tapes out on the processor it is also its TapeOut id: a curator can number works in advance (#1 is this design, #2 that one). Reserved runs MUST come first in a sequential list and are claimed in order before the public sale (tools enforce this); a reserved run placed later would stop the sale until it is claimed, and one placed last could not be claimed once the sale ended unsold. Works not sold by the end are the last ones in the list, so no serial is ever skipped.

**Other leaf formats.** A vault MAY commit to its works with another leaf format, for example leaves for works that stay unpublished until they are taped out. Such a format MUST bind the chain id, the registry, the curator, each work's index and the hash of its netlist, MUST carry a tag that keeps its leaves apart from those above, and, where the leaves are not published before the sale, MUST allow exactly one leaf per index to be proven (a positional tree does this), so that no hidden second leaf can be used. The reference implementation documents its formats.

A Merkle root commits to a set of leaves, not to "exactly `count` works": a dishonest curator could add a hidden second leaf for an index (for example, at price 0) and buy it first. The curator MUST therefore publish every leaf — every work's index, netlist, pins, price and reserved flag — before the sale opens, or, for a vault whose works stay unpublished until they are taped out (so that nobody can pick the rare ones), as soon as the sale is over, and verifiers SHOULD rebuild the root from the published list and compare it with `collectionOf(circuits).root`. A collection whose published list does not rebuild the on-chain root MUST NOT be presented as verified.

A REF record in a listed netlist MUST point to a circuit that already exists when the list is built, with matching pin counts. A REF to an id that does not exist yet would let anyone tape out a circuit at that id first and so decide part of the official work's behaviour; a REF with wrong pins can never be taped out.

The netlist does not need to equal what any particular editor would produce for the same design; it needs to be well-formed and to be exactly the bytes the vault will tape out.

### 6. Vault

A vault bound to a collection:

1. MUST tape out only netlists whose leaf is proven against the root, at most once per `index`.
2. MUST call `certify` in the same transaction as each tape-out, with the id returned by `tapeout`.
3. MUST NOT sell a reserved work. It MUST tape out a reserved work only to the treasury fixed at launch (which MUST NOT be the vault or the registry), at most `reserved` times in total, and only until the leftover transistors are burned (item 4). Once in the treasury, a reserved work is an ordinary circuit that the treasury MAY transfer, give away or airdrop; the vault and registry place no restriction on it.
4. MUST NOT transfer, approve or burn transistors except by tape-out, or by sending the remainder to a burn address once all `count` works are taped out, or once the sale has ended and either every reserved work has been claimed or a grace period fixed in the vault has passed. Public works not sold by the sale end can never be taped out, and the grace period is bounded, so one unsellable work cannot keep the supply unburned forever; a reserved work that the curator forgot to claim is not lost when the sale ends.
5. MUST NOT have an owner or functions that change the root, the count, the curator, the treasury, the reserved count, or the prices and sale rules it was launched with. It MAY let the curator pause and resume buying, and move the sale end later (never earlier) while the sale has not ended and the vault is not finalized; it MUST NOT let anyone move the sale end earlier or reopen an ended sale.
6. MUST NOT let the launcher, or anyone else, buy works during the launch transaction (for example from a refund callback).
7. SHOULD transfer each new circuit to its buyer in the same transaction as the tape-out, or, where the tape-out happens later, MUST send it to whoever holds the buyer's claim at that moment.
8. MAY price works in one ERC-20 token fixed at launch instead of the native coin (the payment asset); TapeOut's tape-out and launch fees are still paid in the native coin. A vault that does MUST make the token readable on chain, and MUST complete a purchase only if it received exactly the price in that token, so that nobody is ever credited with tokens that did not arrive.
9. In a sequential collection (§5), MUST tape out exactly index `sold` on every purchase and every reserved claim, so that no work can be bought, or claimed, out of order.

Beyond these rules, how a vault sells is up to it, for example fixed prices per work, a presale, or works assigned to buyers at random. None of this affects officialness, which §2 alone decides.

### 7. Front-ends and markets

1. A front-end that labels a circuit as an official or verified work of a curated collection MUST base that label on `isOfficial` (or `editionOf`) of a registry, named by the front-end, that is deployed on the same chain as the circuit. It MUST identify a collection by chain id and address together: officialness on one chain says nothing about another, and the same address can be a different processor on another chain (X Layer and Base share TapeOut's contract addresses).
2. It MUST NOT label a circuit as official, verified or "matching" a curated collection based on `circuitInfo`, evaluation results, netlist hash, owner or token URI.
3. For a curated collection, it SHOULD visibly mark circuits that are not official, and SHOULD let users filter them out.
4. It SHOULD show the official serial (`serialOf`) as the work's number, the work index (`editionOf`), and the TapeOut circuit id where it differs from the serial, and link to the certifying transaction (`Certified` log).
5. It SHOULD show which works of a collection are reserved for the treasury, before and after they are claimed (`isReserved`), and MUST still show a reserved work as official after the treasury transfers it.
6. It SHOULD show a collection as verified only if the curator's published work list rebuilds the on-chain root (§5).
7. It MUST NOT present a token that is not a certified circuit (for example a voucher or pass a vault issues before a work is taped out) as a circuit or as an official work.
8. It SHOULD show prices in the collection's payment asset (§6 rule 8) read from the vault, using the token's own `decimals()`, and SHOULD show the native tape-out fee separately when prices are in a token.

### 8. Contracts that grant rights to holders

A contract that grants rights, rewards, access or voting power to holders of circuits from a curated collection MUST check `isOfficial(circuits, tokenId)` of the collection's registry, and MUST NOT rely on netlist content or `circuitInfo`.

### 9. Royalty declaration (optional)

TapeOut's processor contracts do not implement ERC-2981, and a curator cannot add it to them. A registry MUST therefore offer an advisory royalty declaration in the shape of ERC-2981, with the processor as an extra argument; declaring a royalty is optional for the curator:

| Function / event | Selector / topic 0 | Meaning |
|---|---|---|
| `royaltyInfo(address circuits, uint256 tokenId, uint256 salePrice)` | `0x538bd5ea` | `(address receiver, uint256 royaltyAmount)`; `(address(0), 0)` for a circuit that is not official, or when the collection declared no royalty |
| `royaltyOf(address circuits)` | `0xbb30d4ce` | `(address receiver, uint16 bps)` of the collection |
| `setRoyalty(address circuits, address receiver, uint16 bps)` | `0x4adc6e44` | curator only: change the receiver or lower the rate |
| `RoyaltySet(address indexed circuits, address receiver, uint16 bps)` | `0x42467d290c72e182ef85378ad110bba52b9442ac5509a2fd4c2754a38dac93c9` | emitted at launch and on every change |

1. A curator MAY declare a royalty at launch, as a receiver and a rate in basis points, or none. A receiver MUST be given if and only if the rate is not zero, and the rate MUST be at most 500 (5 %).
2. `royaltyInfo` MUST return `(address(0), 0)` for circuits that are not official, so REF wrappers and copies never carry the collection's royalty.
3. After launch, the curator MAY change the receiver and MAY lower the rate. The rate MUST NOT rise, so a collection that declared none can never add one. Nobody else can change it.
4. The declaration is advisory. This TAP does not require anyone to pay it and does not restrict transfers. Markets SHOULD read it for official circuits and MAY honour it; a market MAY enforce it on trades made through it.

### 10. Metadata commitment

The netlists, prices and reserved flags are committed by the root (§5), but the collection's name, symbol, story and work titles are not part of any leaf. Without a commitment, any site could show official circuits under other titles or another story. A registry therefore records one `metadata` value per collection at launch, returned by `collectionOf` (pseudo-code):

```
titlesHash = keccak256(abi.encodePacked(keccak256(bytes(title_0)), …, keccak256(bytes(title_{count−1}))))
metadata   = keccak256(abi.encode(keccak256("TAP-curated-metadata"),
                                  keccak256(bytes(name)), keccak256(bytes(symbol)), keccak256(bytes(story)),
                                  titlesHash))
```

with every string UTF-8 encoded and titles in index order (one title per index; every copy of a design repeats its title). `name`, `symbol` and `story` are the strings the processor was created with; the reference registry computes their hashes on chain from the launch parameters (`metadataOf(name, symbol, story, titlesHash)`, `0xe2e2bef0`), so the commitment cannot disagree with the processor, and the launcher supplies only `titlesHash`, which MUST NOT be zero.

1. `metadata` MUST be fixed at launch and MUST NOT change.
2. A curator MUST publish the name, symbol, story and every title together with the work list.
3. A front-end SHOULD show a collection's name, symbol, story and titles only after rebuilding `metadata` from them and comparing it with `collectionOf(circuits).metadata`, and MUST NOT present them as the curator's if they do not match.

### 11. Token metadata and images (optional)

TapeOut's processor contracts return an empty `tokenURI` for every circuit and give a processor's creator no way to set one, so a circuit NFT has no name, image or attributes in any wallet or market (Recommendation 1 at the end asks TapeOut to let each processor's creator decide that). A registry MUST therefore implement the functions below; a curator MAY record one **content-addressed** metadata directory per collection at launch, and the registry answers `tokenURI` for official circuits:

| Function / event | Selector / topic 0 | Meaning |
|---|---|---|
| `tokenURI(address circuits, uint256 tokenId)` | `0xe9dc6375` | for an official circuit, its own file if the vault declared one at its tape-out, else `"<metadataURI>/<index>.json"`, where `index` is its work-list position (`editionOf`); `""` for a circuit that is not official, or when there is neither |
| `metadataURIOf(address circuits)` | `0x9eac0ca2` | the collection's directory: `"ipfs://<CID>"`, `"ar://<transaction id>"` or `""` |
| `MetadataURISet(address indexed circuits, string uri)` | `0xf4ea916416710952791c00e6c397903c99c416633fd82eeb8f5786572a9d899c` | emitted once: at launch, or when a vault whose works stayed unpublished publishes them |
| `TokenURISet(address indexed circuits, uint256 indexed tokenId, string uri)` | `0x7e2a04aa388921ad0859b09b5255b044773bb1782dd70ac3b1db0031e7fd054d` | emitted when a vault declares a circuit's own metadata file at its tape-out |

1. The directory MUST be declared at most once and MUST NOT change: at launch, or, by a vault whose works stay unpublished until they are taped out, when it publishes them; a collection that never declares one never gets one. A vault MAY instead declare one content-addressed file per circuit, once, in the transaction that tapes the circuit out (`declareTokenURI`, callable only by the vault). Nobody, including the curator, can change either later.
2. The directory MUST be content-addressed, so that its content cannot change either: `"ipfs://"` followed by a CID of immutable content (CIDv0, `Qm` + 44 base58 characters, or CIDv1 in lower-case base32 beginning `bafy` or `bafk`, which covers dag-pb, dag-cbor and raw data with any hash, 50 to 100 characters; no path, no other encoding, never a libp2p-key CID, which names an IPNS record), or `"ar://"` followed by a 43-character Arweave transaction id (base64url) that contains at least one upper-case letter (typically the id of an Arweave path manifest). ArNS names and undernames are lower case, so the upper-case rule keeps a 43-character name from ever passing as an id; a random id lacks an upper-case letter with probability about 2 × 10⁻¹⁰, and an uploader that draws one can re-sign the file. Mutable names (IPNS, DNSLink, ENS, ArNS) and `http(s)` URLs MUST be refused. The reference registry checks this on chain (`isContentAddressed(bytes)`, `0x9bdfd89c`) and reverts the launch otherwise.
3. `tokenURI` MUST return `""` for circuits that are not official, so REF wrappers and copies never show a work's image.
4. The file `<index>.json` SHOULD follow the ERC-721 metadata JSON schema (`name`, `description`, `image`, optionally `animation_url` and `attributes`). Its `name` SHOULD equal the committed title of work `index` (§10), and its `image` and `animation_url` SHOULD themselves be content-addressed (`ipfs://…` or `ar://…`, optionally with a path of plain segments: letters, digits and `. _ ~ -`, no `.` or `..` segment and no percent-encoding, so a link cannot climb out of its content-addressed root). The reference tool also writes `properties` with the work's `index` and `netlistHash`, which ties the image to the circuit design.
5. A front-end SHOULD read a circuit's metadata only through the registry's `tokenURI`, SHOULD show only content-addressed images, and MUST NOT treat the presence of metadata as evidence that a circuit is official (§7.2); `isOfficial` decides that.

Because the directory is fixed before the first sale, the curator uploads it before launch: first the images (each gets its own content address), then one `<index>.json` per work that links to them, then the directory. A launch that stores the directory costs about 90,000 gas (an `ar://` id) to 105,000 gas (a CIDv1) more than one without, measured on a mainnet fork. Storage of the files themselves is outside the chain: Arweave stores them permanently for a one-off fee; IPFS needs at least one party, the curator, a platform or a holder, to keep the files pinned, and anyone holding a copy of the files can re-publish them under the same CID. Collections whose images are computed from the netlist itself MAY instead point `animation_url` at a renderer stored on chain or on Arweave.

## Rationale

**Provenance, not content.** Two of the three kinds of foreign circuit cannot be told apart from official ones by anything the processor contract exposes except raw netlist bytes, and one of them has identical bytes. The only property that separates official from foreign circuits in every case is who taped the circuit out. Recording it at tape-out time makes it a fact anyone can read without trusting the curator's later word or an indexer.

**Why the curator must launch personally.** An internal review of the reference implementation found that, without this rule, anyone could launch a collection naming a real artist as curator, reuse the artist's root, and have its circuits certified as official; or reuse the artist's root under its own name. Requiring `curator == msg.sender` closes the first path, and binding leaves to the curator closes the second. A platform that runs launches for artists can still do so by having the artist sign the launch transaction.

**Why reserved works are fixed at launch.** Projects often keep part of a collection for a treasury, to give away, airdrop or reward contributors later. If the curator could decide afterwards which works to keep, it could take the most sought-after pieces once demand is visible. Marking reserved works in the leaves, and fixing the treasury and the reserved count at launch, makes the split public and binding before anyone buys. Sending every reserved work to one fixed treasury, rather than straight to arbitrary recipients, keeps the reserve easy to audit: every later gift or airdrop is an ordinary, visible transfer out of that address.

**Why the royalty is only a declaration.** Royalties cannot be enforced on circuits: the NFT contract belongs to TapeOut, so a curator can neither add ERC-2981 to it nor restrict transfers in the way ERC-721C does, and anyone can trade around a market. Across NFTs, ERC-2981 itself is advisory for the same reason. What a shared protocol can usefully add is one public place, next to the officialness record that markets already read, where the curator's terms are stated and cannot be raised after people have bought. Collecting the royalty is left to markets.

**Why reserved works survive the sale end.** A first version closed reserved claims with the sale, which made a forgotten claim a permanent loss. Keeping claims open until the leftover supply is burned, and delaying the burn only while reserved works are unclaimed and only for a fixed period, removes that loss without letting anyone keep the supply unburned forever. The grace period gives the curator no new power: it can only tape out the works the list already marks as reserved, to the treasury fixed at launch.

**Why titles are committed as a hash.** Storing every title on chain would cost gas per byte for text that only front-ends read. A single hash, fixed at launch, makes any change detectable at the cost of one storage slot. Name, symbol and story are hashed by the vault from the launch parameters, so the commitment always describes the processor that was actually created.

**Why metadata is a directory fixed at launch, not images on chain.** An NFT without an image is of little use to most collections, but storing images on chain costs about 216 gas per byte (measured on BNB Smart Chain): a 700 KB animation costs about 150 M gas, and a collection of thousands of works would need hundreds of blocks' worth of gas. A content-addressed directory costs one short string on chain, and its address is itself the hash of every file in it, so committing the address commits every file in it, and every image the files link to by content address (§11.4), as firmly as the root commits the netlists. Fixing it at launch keeps the guarantee buyers get from the rest of this TAP: what they see before buying cannot be swapped afterwards, not even by the curator. Mutable names are refused because a name is a pointer whose owner can repoint it. Returning `""` for circuits that are not official keeps images, like royalties, attached to provenance rather than to netlist content.

**Why the vault answers for its processor.** The processor's creator is the only party TapeOut already associates with each processor, and a curated vault is that creator by construction (§4.4). Asking the creator lets TapeOut support every curated collection, and any future scheme, without choosing which registries to trust.

**Why the curator can pause and extend a sale, but not shorten or reopen it.** Projects sometimes find a problem during a sale, a broken page, a wrong announcement or a market event, and need to stop buying for a while or give buyers more time. Pausing and extending change only when the listed works can be bought: they add no work, change no price and touch no circuit already sold, so buyers keep exactly what they were promised. Shortening a sale or reopening an ended one would break what buyers could rely on, namely that the works stay buyable until the announced end and never again after it, so neither is possible.

**Why one registry per chain, and no cross-chain officialness.** TapeOut runs a separate factory on each chain, and a processor, its transistors and its circuits exist on one chain only (BEM and miners can be bridged; processors and circuits cannot). A registry is therefore deployed per chain and bound to that chain's factory, so the launch checks of §4 are made against the chain the collection lives on. Work-list leaves include the chain id (§5), so a work list built for one chain cannot be used on another, even by the same curator with a registry at the same address. A curator who wants the same works on several chains launches one collection per chain; each is official only on its own chain. A single registry that accepted certifications from other chains would need a bridge or an oracle and would no longer be checkable with a read-only call.

**Why the curator cannot be changed.** No one, including the curator, can change the curator address after launch, and there is no recovery path for a lost key. Any such path would be a privilege that could be stolen or abused, and buyers would have to trust whoever holds it. A curator that wants protection against losing a single key can launch from a multi-signature wallet.

**Why the vault tapes out, not the buyer.** If buyers taped out with transistors they were given, the registry could not tell their circuits from copies taped out with the same transistors. Keeping every transistor in the vault means that nobody else can tape out anything into the processor except pure-REF netlists, which cost no transistors. These include byte-identical copies of any listed work that is itself pure-REF (see Security Considerations), and none of them is ever certified.

**Why the registry re-checks everything at bind.** A registry that trusted the vault's word would make the guarantee only as strong as the least careful vault. The checks in §4 are cheap view calls and make the launch guarantee hold regardless of vault code, given that the vault came from this registry.

**Why not a wrapper collection.** A second ERC-721 that wraps official circuits would give markets a collection that looks clean without integration, but it must hold every work indefinitely, which concentrates risk; and a wrapped circuit is owned by the wrapper, so the buyer loses control of the circuit's container account (ERC-6551) and is not shown as the owner on TapeOut. A registry holds nothing. A wrapper can be built on top of this registry later, as an option for holders.

**Why a Merkle root fixed at launch.** It makes the full work list, and every price, binding before the first sale. A curator cannot add works later or quietly replace a design with another version.

**Why byte-equality with the tapeout.net editor is not required.** Officialness comes from the certified tape-out, not from re-deriving the netlist. The leaf commits to exactly the bytes the vault tapes out.

**Why serials, and why sequential sales.** Holders call a work "#N", and in most collections they expect #N on the project's site, in markets and on TapeOut to be the same circuit. A work-list index cannot be that number when buyers pick works in any order, because TapeOut numbers circuits in tape-out order. The registry therefore records the order of official tape-outs as the serial, which equals the TapeOut id until someone injects a wrapper, and a sequential sale makes the index, fixed in advance, equal to that order. Runs of copies keep the most common kind of project, one design sold thousands of times, to one leaf per design, and let the tools store the design once. Reserved runs come first because a later reserved run would either stop the sale or, once the sale ended unsold, be unreachable.

**Why prices may be in a token, while tape-out fees stay native.** Communities on TapeOut often want to sell in their own token (for example BEM) rather than in the chain's coin. TapeOut's `tapeout` and `createCPU` charge their fees in the native coin and cannot be changed by this TAP, so a token sale still needs a small native payment; the vault keeps the two apart (`msg.value` is exactly the tape-out fee) so neither can be mistaken for the other. The token is a launch parameter rather than a list in the registry, so no one has to approve tokens and a token that appears on a chain later can be used without deploying anything; the price of this freedom is that a curator can pick a token that misbehaves, which affects only that collection (see Security Considerations). Exact-amount receipt is required because a fee-on-transfer token would otherwise let the vault count tokens it never received.

## Backwards Compatibility

This TAP changes no TapeOut contract. Existing processors cannot become curated collections under §4, because their transistors already circulate; their projects may publish signed lists of official ids in another TAP, but such lists are attestations by the project, not provenance guarantees, and are out of scope here.

During this work it was observed on mainnet that `circuits.nextId()` returns the number of circuits taped out so far (0 for a fresh processor, 1 after the first tape-out, whose id is 1), not "the id the next taped-out circuit will get" as TAP-02 §6 states. The reference registry uses `nextId() == 0` for condition §4.6. TAP-02 may want to correct its description.

## Test Cases

The reference implementation ships 50 Foundry tests (48 in `test/Curated.t.sol`, 2 in `test/Copies.t.sol`) that run against a fork of BNB Smart Chain, X Layer or Base mainnet (`forge test --fork-url https://bsc-dataseed.bnbchain.org`, `https://rpc.xlayer.tech` or `https://mainnet.base.org`); the tests pick that chain's factory and a work list built for it. The work list has seven throw-away test circuits produced by the reference tool: a toggle, a 4-bit counter, a 7-bit LFSR, an XOR, a REF work (on BNB Smart Chain, genesis circuit #13 with a parity output; on X Layer and Base, circuit #1 of processor `0x0565EA48CA41Ae559d8d491dbb0a9ec945DB551b` with an inverse output), and two works the list reserves for the treasury (the TAP-02 vector `popcount8_3151` and an AND gate with a non-ASCII title). `test/Copies.t.sol` uses a sequential collection of the same circuits: two reserved AND gates, five toggles and three XORs (`copies`). All pass on all three chains (2026-11-01; the BEM test runs on BNB Smart Chain only and is skipped elsewhere); the contracts are the same on every chain. Gas figures and fees below are from BNB Smart Chain. Because free public nodes keep only recent state, the tests fork the latest block rather than a pinned one. The tests are:

| Test | What it shows |
|---|---|
| `test_Launch_AtomicAndVerified` | one transaction creates the processor, mints the full supply to the vault (non-zero mint price, 5 mint batches), binds, fixes the metadata directory, refunds the float; 1.83 M gas (the vault is a clone); the launcher pays exactly the 0.0015 BNB (on BNB Smart Chain) of factory and protocol fees (0.001 deploy fee + 5 × 0.0001) the tool predicted |
| `test_Launch_ZeroMintPrice` | the same with mint price 0 |
| `test_Launch_RejectsBadParams` | invalid sale settings (for example a sale end not after the sale start) and insufficient launch funds |
| `test_L2_LaunchFeeCap` | launch reverts when fees exceed the launcher's cap |
| `test_H1_CopycatLaunchRejected` | nobody can launch in another curator's name; a copycat that reuses the root as its own curator cannot sell any listed work |
| `test_L3_RefundReentryBlocked` | a curator account that tries to buy from the launch refund callback hits the re-entry guard (`ReentrancyGuardReentrantCall`), and nothing is sold |
| `test_L4_TokenOfAndEditionOfDefaults` | before a work is taped out `tokenOf` reports it as not taped out (never as id 0), circuits that are not official report `(false, 0)`, and after tape-out the work maps to its circuit id |
| `test_TreasuryCannotBeVaultOrRegistry` | the treasury can be neither the vault being created nor the registry |
| `test_BuyAll_CertifyPayFinalize` | all seven works: `Certified` emitted with the netlist hash, certified with the right index, owned by the buyer (the two reserved works by the treasury), netlist bytes as listed, transistors consumed exactly as predicted by the tool; leftover 9,814 NAND and 3 LATCH burned |
| `test_M1_FinalizeAfterSaleEnd` | after the sale end, buying stops; with reserved works unclaimed the burn waits for the grace period, then the leftover supply is burned although works remain unsold |
| `test_R1_NoWayToExtractTransistors` | nobody can move, burn or mint the vault's transistors; finalize before sell-out and before the sale end fails |
| `test_R2_SameNetlistElsewhereIsNotOfficial` | the identical netlist taped out on another processor is not official; on the curated processor it cannot be taped out by others (`ERC1155InsufficientBalance`) |
| `test_R3_RefWrapperIsNotOfficial` | a stranger tapes out a 0-transistor REF wrapper into the curated collection; its `circuitInfo` equals the official circuit's; it is not official |
| `test_R4_EachWorkOnceAndStrictInputs` | second purchase of a work, tampered netlist, lower price, wrong proof, wrong pins, a valid work under another index, wrong payment, bad index, zero recipient |
| `test_R5_OnlyBoundVaultCanCertify` | strangers and vaults not deployed by the registry cannot bind or certify (a rogue vault tries both); no double certification; no index out of range |
| `test_R7_WorkListIsFixed` | the root is immutable; an unlisted netlist cannot be sold even with a real proof, index and price |
| `test_SaleStartIsEnforced` | no sale before `saleStart` |
| `test_Sale_CuratorCanPauseAndResume` | only the curator can pause; while paused nobody can buy, reserved claims still work; after resuming, buying works again |
| `test_Sale_ExtendOnlyLaterWhileOpen` | only the curator can extend; the new end must be later; buying works past the old end and finalize waits for the new one; once the new end has passed the sale cannot be extended or reopened |
| `test_Sale_NoControlsAfterFinalize` | after finalize the sale can be neither paused nor extended |
| `test_Royalty_OfficialOnly` | an official work reports the declared 3 % royalty; a REF wrapper in the same collection reports none |
| `test_Royalty_None` | a collection may declare no royalty, and then can never add one |
| `test_Royalty_CuratorCanOnlyLower` | the curator changes the receiver and lowers the rate; raising it, strangers and a second declaration are refused |
| `test_Royalty_ParamsChecked` | a rate above 5 %, a receiver without a rate, or a rate without a receiver is refused at launch; exactly 5 % is accepted |
| `test_Reserved_PublicCannotBuy` | a reserved work cannot be bought, at price 0 or any other price |
| `test_Reserved_CuratorClaimsToTreasury` | only the curator can claim, before the public sale opens; the circuit goes to the treasury, is official and reserved, earns nothing, and cannot be claimed twice |
| `test_Reserved_TreasuryCanTransferAndItStaysOfficial` | the treasury gives the work away and the recipient passes it on; it stays official and reserved |
| `test_Reserved_CannotClaimPublicWork` | the curator cannot pull a public work into the treasury |
| `test_Reserved_DeclaredCountIsACap` | claims beyond the reserved count declared at launch fail, even if the tree held more reserved leaves |
| `test_Reserved_Params` | reserved works need a treasury, which cannot be the registry; the reserved count cannot exceed the work count |
| `test_Reserved_ClaimAfterSaleEndWithinGrace` | after the sale ends the curator can still claim a reserved work; finalize waits while one is unclaimed, until exactly the end of the grace period; then anyone can finalize and nothing more can be claimed |
| `test_Reserved_AllClaimedFinalizeAtSaleEnd` | once every reserved work is claimed, finalize works at the sale end without waiting |
| `test_Reserved_BatchClaim` | two reserved works claimed in one transaction to the treasury; strangers, a wrong total fee, a batch containing a public work (nothing is claimed) and a second claim are refused |
| `test_Metadata_Committed` | the registry records the metadata commitment computed by the tool (including a non-ASCII title); a different story gives a different value; a launch without a titles hash is refused |
| `test_Metadata_TokenURIOfficialOnly` | official works (bought and reserved) get `<directory>/<index>.json`; a REF wrapper of an official work, a missing circuit and another processor get `""`; the vault, which is the processor's creator, gives the same answer through `circuitURI` and declares `ICircuitURIProvider` via ERC-165 |
| `test_Metadata_FixedAtLaunch` | the directory cannot be declared again, by the vault or the curator |
| `test_Metadata_None` | a collection launched without a directory returns `""` for every circuit |
| `test_Metadata_OnlyContentAddressed` | `https` URLs, IPNS names (including an IPNS key written as a CID, in base36 and base32), ENS-style names, an ArNS name, a 43-character lower-case name, a CID with a trailing slash, ids of the wrong length, upper-case base32, a non-base58 character and an upper-case scheme are refused at launch; CIDv0, CIDv1 of dag-pb and raw data, and an Arweave id are accepted |
| `test_L5_RejectsStrayFundsAndTokens` | the vault refuses plain native coin, and refuses a real circuit of its own processor sent by a third party |
| `test_ReentrancyFromRecipientFails` | a recipient that re-enters `buy` makes the purchase revert with `ReentrancyGuardReentrantCall` |
| `test_Token_BuyAndWithdraw` | in a collection priced in an ERC-20, a buyer pays the price in the token and only the tape-out fee in native coin (paying the price in native coin is refused, and so is a purchase without approval); the circuit is official; the proceeds are paid in the token and nothing is left in the vault |
| `test_Token_RefusesFeeOnTransfer` | a token that takes 1 % of every transfer is refused with `TokenAmountMismatch`, and the work stays unsold |
| `test_Token_FreeWorkAndParams` | a free work needs no approval; a payment token without code is refused at launch |
| `test_Token_BEMOnBSC` | on BNB Smart Chain, BEM (`0x5ce033B2bFCa3Af30b3e8C8457DeaF776A8b695a`, 8 decimals) works as the payment token: it has no transfer tax, and the proceeds are paid in BEM (skipped on other chains) |
| `test_Token_NoReturnToken` | a token whose `transfer` and `transferFrom` return nothing (USDT style) works; the registry is refused as payment token |
| `test_Token_FailedPayoutIsKept` | a token that blocks the curator does not block the purchase; the proceeds are kept in `owed` and withdrawn to another address, by the curator only |
| `test_Clones_FixedImplementation` | the registry names its vault implementation; it cannot be initialised, a launched vault cannot be initialised again, and its code is the EIP-1167 proxy of the implementation |
| `test_Token_ReentrantTokenIsBlocked` | a token that calls back into the vault during a purchase is stopped by the reentrancy guard; nothing else is bought |
| `test_Copies_SoldInOrder_SerialEqualsTapeOutId` | a sequential collection: nothing sells before the reserved run is claimed, unordered `buy` is refused, every copy is official with serial = TapeOut id = index + 1, a used-up run sells nothing more |
| `test_Copies_InjectedWrapperShiftsTapeOutIds` | a stranger's REF wrapper takes a TapeOut id; the next work's serial is one less than its TapeOut id, and the wrapper has no serial |

Test vectors from the fixtures `test/fixtures/manifest.json` and `copies.json` (chain id 56, registry `0x00000000000000000000000000000000c0dec0de`, curator `0x00000000000000000000000000000000000c0ffe`), which any implementation of §5, §10 and §11 must reproduce:

| Input | Expected output |
|---|---|
| work leaf (§5): index 0, netlistHash `0x7ca496e2d18c48a09aea26fc7df653df9c3fa5a10cb1a2bb7ec311c8220130b2`, nIn 1, nOut 1, price 10¹⁶ wei, reserved false | `0x14358d2386912617595812f5484d92d4899a96129a8904f771b29454b0524156` |
| root of the seven works (§5) | `0x131d82b25cc3283cc417942e38b63e6d665024c75cc40c645602d13437af1949` |
| `titlesHash` of the seven titles (§10) | `0x1ecdc691abff41d0c4b6f032dd9b4845349526520462790a1fcffac33215ba9a` |
| `metadata` (§10) for name `P05 Test Collection`, symbol `P5TEST`, the fixture's story and that `titlesHash` | `0x131a0d4c42d02f4d670b1f463011bea1aa93a04665aaadcb1fe32dd663cd218c` |
| `isContentAddressed` (§11) of `ipfs://QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG`, `ipfs://bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi`, `ar://bNbA3TEQVL60xlgCcqdz4ZPHFZ711cZ3hmkpGttDt_U`, `""` | true |
| `isContentAddressed` (§11) of `ipfs://k51qzi5uqu5dlvj2baxnqndepeb86cbk3ng7n3i46uzyxzyqj2xjonzllnv0v8`, `ar://myundername_mycollectionname-permaweb123456`, `https://example.com/meta` | false |
| run leaf (§5), fixture `copies.json`: first 2, copies 5, the toggle's netlistHash above, nIn 1, nOut 1, price 10¹⁶ wei, reserved false | `0xf1ff4a2cd09c75999fb8275cc2685de0a3783c77a1ffeccf4b2dcc1cdb3b7569` |
| root of `copies.json` (three runs) | `0xbb2baad141cb47fc7d721f13b9d12728c769b088c543bc49affcba97c7d5095a` |

The tool's `selftest` checks all 13 TAP-02 vectors (5 valid, 8 ill-formed), and 200 random canvas designs; an additional run checked 6,000 random designs (inputs, constants, LATCH feedback, shuffled file order, multiple outputs) and found every encoded netlist to evaluate identically to the canvas graph over 8–24 beats. An end-to-end run on a local fork followed the real workflow: deploy the registry, build the manifest for it (with REF targets checked on chain), launch as the curator (`script/Demo.s.sol`), buy two works, claim both reserved works in one batch, and have a second account tape out a REF wrapper. `curate verify` reported the two works as official with matching netlists, the reserved works as official and reserved, owned by the treasury, and the wrapper as not official, although its `circuitInfo` was identical; `curate checkroot` rebuilt the root from the published works and it matched the chain, as did the treasury and the reserved count.

The tool also refuses work lists with a REF to a circuit that does not exist yet or with wrong pin counts, and warns about pure-REF works, whose byte-identical copies anyone can tape out.

## Reference Implementation

Repository: <https://github.com/gm-lsp/Tape-OCCC/tree/6d87cbc6c29acec5d39aae84ec9d05d6c006496f> (MIT).

- `src/CuratedRegistry.sol` — registry and launcher (§3, §4): checks the launch parameters, creates each vault as a clone of the vault implementation fixed in its constructor, records official circuits, serials and metadata.
- `src/CuratedTypes.sol` — the launch parameters.
- `src/CuratedVault.sol` — the reference vault (§6): fixed prices per work, in any order or in list order from runs of copies, prices in the native coin or one ERC-20 token, proceeds to the curator, reserved works, sale controls, finalize.
- `src/interfaces/ICuratedRegistry.sol` — the interface of §3, §9 and §11.
- `src/interfaces/ICircuitURIProvider.sol` — the interface of Recommendation 1 to TapeOut.
- `tool/curate.py` — dependency-free Python, knowing the TapeOut factory of each chain: TapeOut canvas → TAP-02 netlist encoder (validated with the TAP-02 reference implementation), on-chain checks of REF targets, transistor counts, work lists and proofs, metadata commitment and the metadata files of §11 (`metadata`), launch manifest and fee cap, root and metadata rebuilding (`checkroot`), on-chain verification (`verify`).
- `test/Curated.t.sol`, `test/Copies.t.sol`, `script/Demo.s.sol` — the tests and demo above; `script/Deploy.s.sol` deploys the vault implementation and the registry; `script/Launch.s.sol` launches a collection from a manifest (`script/ManifestParams.sol` reads it).

## Deployments

Deployed on 2026-11-07 from the commit linked in Reference Implementation. The addresses are the same on all three chains (same deployer and nonce); each deployment was checked with `tool/check_deploy.py`.

| Chain (chainId) | Contract | Address | Implementation it must point to | How to verify read-only | Sealed? |
|---|---|---|---|---|---|
| BNB Smart Chain (56) | CuratedRegistry | `0x0a3e2191A21ab3c1bFe9F7E52Bf6a7DBB08788e7` | not a proxy | `FACTORY()` returns `0x68224F668083c29e9800Be2a646d42d18cedF7e2`; the runtime bytecode (immutables masked) matches the reference implementation at the linked commit | yes (no owner, no proxy) |
| BNB Smart Chain (56) | CuratedVault | `VAULT_IMPL()` of the registry above: `0x7eE2C66988D77043A31A8AbFcF8167Cad636bAeD` | not a proxy; vaults are EIP-1167 clones of it | the runtime bytecode matches the reference implementation; it cannot be initialised | yes (no owner) |
| X Layer (196) | CuratedRegistry | `0x0a3e2191A21ab3c1bFe9F7E52Bf6a7DBB08788e7` | not a proxy | `FACTORY()` returns `0x1f09DAeFA827f02CBb40967cc91b259763760761`; the runtime bytecode (immutables masked) matches the reference implementation at the linked commit | yes (no owner, no proxy) |
| X Layer (196) | CuratedVault | `VAULT_IMPL()` of the registry above: `0x7eE2C66988D77043A31A8AbFcF8167Cad636bAeD` | not a proxy; vaults are EIP-1167 clones of it | the runtime bytecode matches the reference implementation; it cannot be initialised | yes (no owner) |
| Base (8453) | CuratedRegistry | `0x0a3e2191A21ab3c1bFe9F7E52Bf6a7DBB08788e7` | not a proxy | `FACTORY()` returns `0x1f09DAeFA827f02CBb40967cc91b259763760761`; the runtime bytecode (immutables masked) matches the reference implementation at the linked commit | yes (no owner, no proxy) |
| Base (8453) | CuratedVault | `VAULT_IMPL()` of the registry above: `0x7eE2C66988D77043A31A8AbFcF8167Cad636bAeD` | not a proxy; vaults are EIP-1167 clones of it | the runtime bytecode matches the reference implementation; it cannot be initialised | yes (no owner) |

The TapeOut factory addresses are those listed in TAP-10's Deployments. A registry's address may differ from chain to chain; front-ends name the registry per chain (§7.1). `python3 tool/check_deploy.py --rpc <RPC> --registry <address>` in the reference implementation runs the checks of this table (after `forge build` at the linked commit) and prints both fingerprints: registry `0x5ba3de9e9d56421bba8212612416ef0bf7181a03c3bc1edd0fe0565b1dbc01a2`, vault implementation `0x44b3b1d049a8cda1899cf42aa2354061def8331bb48989534229f851bbf64dd9` (keccak256 of the runtime code without its CBOR metadata, with the registry's immutables set to zero).

## Security Considerations

- **Trust in TapeOut.** The factory, processor and transistor contracts are upgradeable by TapeOut's multisig, on each chain separately; X Layer and Base have their own factory deployment, separate from BNB Smart Chain's (TAP-10). The fork tests exercise the behaviour below on all three chains. This TAP relies on: `isCPU` being correct; `tapeout` burning only the caller's transistors (the transistor contract has a `burnFrom` callable by the processor contract, so an upgraded processor could burn the vault's stock); the supply cap staying fixed; and transfers to the burn address staying allowed. The registry's launch checks hold at launch time only. Certifications already made are unaffected, because they record provenance at the time of tape-out.
- **Internal review.** The reference implementation went through five rounds of internal review, each by reviewers who did not write the code. The first round found no critical issue, one high (launch in another curator's name; fixed by §4.1 and the curator-bound leaf), two medium (an unsellable work blocking finalize forever; hidden leaves for an index — fixed by the sale end and by §5's publication rule) and five low issues (fixed: `withdrawTo`, the launch-fee cap, reentrancy from the launch refund, `tokenOf` not relying on id 0, and refusing stray circuits). The second round covered the reserve, royalty and tool code and found no critical issue; its contract and tool findings were fixed (among them, a treasury that is the vault or the registry is refused; `checkroot` now rebuilds every work and compares every launch setting with the chain). A third round re-checked the final code and found no critical, high or medium issue; its low findings were fixed or are listed below (Reserved works, Treasury contract, Work lists, Sale end). A fourth round reviewed the metadata additions (§11, Recommendation 1 and the tool code for them) and found no critical issue; its findings were fixed: a percent-encoded `..` in an image path could leave a content-addressed root, an IPNS key written as an `ipfs://` CID passed the check, a 43-character ArNS undername could in principle pass as an Arweave id (now refused by the upper-case rule), tools did not read the directory back before launch, and metadata files were not written as UTF-8 on every platform. A fifth round reviewed copies sold in list order, direct payment of proceeds and clones and found no critical issue; its findings were fixed. Every on-chain fix has a regression test; the hidden-leaf finding of the first round is addressed by the publication rule of §5, which `checkroot` enforces.
- **Metadata availability.** The registry fixes the address of the metadata, not its availability. Files on IPFS disappear if no one keeps them pinned; curators should pin them with more than one provider or use Arweave. A front-end that fetches files through an HTTP gateway trusts that gateway to serve the content the address names; it may check the content against the address. A collection launched with an unreachable or wrong directory cannot correct it (§11.1), so tools should read the directory back before launch.
- **What "official" does not promise.** The registry certifies where a circuit came from, not what it does. A curator can list any well-formed netlist, including one that REFs circuits on other processors, whose behaviour then depends on those circuits (TAP-02, Security Considerations).
- **Foreign circuits still appear in the collection.** Pure-REF wrappers can always be taped out into any processor. This TAP makes them distinguishable; it does not and cannot prevent them. Front-ends that ignore §7 will keep showing them.
- **Vault assets.** The vault holds transistors that are only usable on its own processor, and whatever its sale rules keep for later (for example fees not yet spent, or payouts that could not be delivered). It has no owner. Every sale and claim updates the vault's state before its external calls, and every state-changing entry point that makes external calls shares one re-entry guard.
- **Contract and EIP-7702 buyers.** A circuit sent with `safeTransferFrom` to a recipient with code that does not implement `onERC721Received` makes the purchase revert, so no funds are lost; buyers can name a different recipient. A vault that delivers circuits in a later transaction should send them with a plain `transferFrom`, so that a holder cannot block other deliveries; a holder contract that cannot handle ERC-721 tokens then holds a circuit it cannot move, which is the buyer's choice of recipient. Note that some well-known EOAs on BNB Smart Chain and Base carry EIP-7702 delegations.
- **First come, first served.** When netlists and proofs are public before the sale, bots can take price-0 or underpriced works as soon as the sale opens, and two buyers can race for the same work (the loser's transaction reverts). A vault can prevent this by keeping its works unpublished until they are taped out (§5).
- **Reserved works.** The treasury holds reserved works like any other circuits, so its key is what protects them; a multisig is recommended. A reserved work can be claimed until the leftover transistors are burned, which anyone can do once the sale has ended and every reserved work is claimed, or otherwise once `RESERVE_GRACE` has passed after the sale end; a reserved work not claimed by then is lost.
- **Treasury contract.** Reserved works are sent to the treasury with `safeTransferFrom`. A treasury contract that does not accept ERC-721 transfers makes every claim revert, and the reserved works are lost when the vault is finalized. Multi-signature wallets such as Safe accept them; curators should claim one reserved work right after launch to confirm.
- **Work lists.** Work leaves are bound to the chain, the registry and the curator, not to one collection. A curator who reuses a work list in a second collection makes every proof valid in both; tools should build a fresh list per collection, and front-ends identify a collection by its chain id and processor address, never by its name.
- **Sale end.** Until the sale ends, unsold works stay buyable and the leftover transistors stay in the vault. A very distant sale end (the test fixture uses the year 2100) means the supply is effectively never burned; curators should choose a realistic one.
- **Payment tokens.** The curator chooses the token and the registry does not vet it. A token can be paused, can blacklist the vault or a buyer, can be upgraded to behave differently, or can call back into the buyer; then purchases of that collection can fail. Officialness, already sold works, the work list and other collections are not affected. Tokens sent to a vault directly, outside a purchase, cannot be refused or recovered (unlike the native coin, which `receive` refuses), and stay locked. Every purchase is guarded against reentrancy and updates state before external calls, and the exact-amount check refuses tokens that deliver less than the price. An approval larger than needed lets only this vault, which has no owner, pull tokens, and only as part of a purchase the approver sends. Front-ends should show which token a collection uses and warn before a purchase in an unknown token.
- **Sale controls.** The curator can pause buying for as long as it likes and can keep moving the sale end later, which also postpones `finalize` and the burn of leftover transistors. Buyers cannot force a purchase while a sale is paused, and an attacker who obtains the curator key can pause or extend the sale (but cannot take proceeds, change prices or add works). Holders and the officialness of sold works are never affected. Front-ends should read `paused()` and the current `SALE_END()` rather than the launch values.
- **Curator key.** The curator address can never be changed. If its key is lost, unclaimed reserved works can no longer be claimed, the royalty can no longer be changed, and nothing else the vault leaves to the curator can be done any more. This is deliberate (see Rationale); a multisig curator is recommended.
- **Pure-REF works.** A listed work made only of REF records burns no transistors, so anyone can tape out a byte-identical copy of it into the curated processor. The copy is not official, but it looks the same; tools warn about such works.
- **Fee changes.** The vault reads `TAPEOUT_FEE()` when it tapes out, so a fee change is passed on rather than breaking sales.
- **Netlist size.** Tape-outs above about 34,000 bytes fail on BNB Smart Chain mainnet (other chains' block gas limits may differ); the tool rejects them. Large works should be split into sub-circuits joined by REF.
- **Merkle leaves** are double-hashed, so an inner node cannot be presented as a leaf.
- **No audit yet.** The reference implementation has had internal reviews only. It should not hold significant value before an independent audit.

## Recommendations to TapeOut (key points)

**These are the two upgrades this TAP asks TapeOut to consider.** They are recommendations, not requirements: nothing else in this TAP depends on them, and every part of it works on today's contracts. Both are one change each to the shared processor implementation behind TapeOut's beacon, both are opt-in for creators, and both change nothing for processors whose creators do nothing. The reference vault is already prepared for both, so collections launched today benefit as soon as TapeOut adopts them.

### ★ Recommendation 1 (key): let each processor's creator decide its circuits' metadata

**What we ask.** Today a processor returns an empty `tokenURI` for every circuit and gives its creator no way to set one, so no circuit has a name or an image in any wallet or market. One change to the shared processor implementation behind TapeOut's beacon would let **every project, whether or not it uses this TAP**, show its circuits' metadata everywhere. The rule is a single one: **a processor's creator decides what its circuits show.** `tokenURI(id)` answers, in this order:

1. **A directory the creator set.** The creator calls `setCircuitBaseURI(uri)` once; circuit `id` then shows `"<uri><id>.json"`. This serves every project whose processor was created by an ordinary wallet, including processors created before the upgrade (their creator sets it once afterwards). Optionally, the processor-creation call could take the directory as a parameter, so a project sets it when it creates the processor.
2. **A creator contract that answers for itself.** If no directory is set and the creator is a contract that declares `ICircuitURIProvider` through ERC-165, the processor asks it with `circuitURI(circuits, tokenId)`. Curated collections use this path: their creator is the vault, which has no owner and could never call a setter, and it answers with the registry's `tokenURI` (official works only, fixed at launch).
3. **Neither:** `""`, which is today's behaviour; projects that do nothing see no change.

**Must-have detail.** Path 2 MUST use exactly this interface: `circuitURI(address,uint256)`, interface id `0xcd51078c`. A vault's code is fixed when its collection is launched; the reference vault already implements this interface and ERC-165, so every curated collection already launched would show its metadata the moment the upgrade lands, without any action, only if the names match.

Example (informative):

```solidity
interface ICircuitURIProvider {
    function circuitURI(address circuits, uint256 tokenId) external view returns (string memory); // 0xcd51078c
}

string public circuitBaseURI;                               // 0x3e3f2de4
event CircuitBaseURISet(string uri);

/// Only the processor's creator (an ordinary wallet or a contract) may set it.
function setCircuitBaseURI(string calldata uri) external {  // 0x8651a9c5
    require(msg.sender == transistors.creator());
    circuitBaseURI = uri;
    emit CircuitBaseURISet(uri);
}

function tokenURI(uint256 id) public view returns (string memory) {
    _requireOwned(id);
    // 1. a directory set by the creator
    if (bytes(circuitBaseURI).length != 0) return string.concat(circuitBaseURI, Strings.toString(id), ".json");
    // 2. a creator contract that answers itself (low-level calls: try/catch would not catch bad return data)
    address creator = transistors.creator();
    if (creator.code.length == 0) return "";
    (bool ok, bytes memory r) = creator.staticcall{gas: 30_000}(
        abi.encodeCall(IERC165.supportsInterface, (type(ICircuitURIProvider).interfaceId)));
    if (!ok || r.length < 32 || abi.decode(r, (uint256)) != 1) return "";
    (ok, r) = creator.staticcall{gas: 200_000}(abi.encodeCall(ICircuitURIProvider.circuitURI, (address(this), id)));
    if (!ok || r.length < 64) return "";
    (uint256 offset, uint256 length) = abi.decode(r, (uint256, uint256));
    if (offset != 32 || length > r.length - 64) return "";
    return abi.decode(r, (string));
    // 3. neither: "" (today's behaviour)
}
```

Why it is safe for TapeOut: the processor only ever asks its own creator, which is fixed when the processor is created, so TapeOut never has to whitelist registries or judge collections. The gas limits keep a faulty creator contract from making `tokenURI` expensive, and every failure (a call that reverts, runs out of gas, or returns data that is too short or malformed) returns `""`. A production implementation would also copy at most a few kilobytes of return data (in assembly, since a plain `staticcall` copies all of it). A directory set by the creator applies to every circuit of the processor; a curated vault answers only for official works, so REF wrappers and copies taped out into a curated processor never show a work's image (§11).

### ★ Recommendation 2 (key): let a processor's creator restrict tape-outs to itself

Anyone can tape out a pure-REF wrapper into any processor without transistors (§4, Motivation). Such wrappers are never official, but they appear in the collection's contract, look like its works, and take TapeOut circuit ids, so after the first one the official serial (§3) and the TapeOut id of later works differ. No protocol built on today's processors can prevent this. TapeOut could let a creator opt in to a processor that only its creator can tape out on:

```solidity
bool public tapeoutRestricted;                          // 0x… view, false by default
event TapeoutRestricted();

/// One-way: once set, it can never be cleared.
function restrictTapeoutToCreator() external {           // 0x9051fb27
    require(msg.sender == transistors.creator());
    tapeoutRestricted = true;
    emit TapeoutRestricted();
}

// at the start of tapeout(...):
//     if (tapeoutRestricted && msg.sender != transistors.creator()) revert NotCreator();
```

For a curated collection the creator is its vault, so after the change nothing but official works could ever enter the processor, and the serial would always equal the TapeOut id. Assessment: the change touches only who may create circuits in one processor. It changes nothing for processors that do not opt in (the default), nothing about existing circuits, and nothing about REF: circuits of a restricted processor can still be used as REF targets from other processors, and nothing that reads circuits (evaluation, mining, REF resolution, ERC-6551 accounts) needs to know about it. It must be one-way, or a creator could lift the restriction once buyers rely on it. A creator that is an ordinary wallet could restrict its own processor too; that is its choice and affects only its own collection. The reference vault already calls `restrictTapeoutToCreator()` right after creating its processor (§4), with a gas limit and ignoring failure, so every collection launched after TapeOut adopted the change, with this exact selector and meaning, would be restricted from its first block, without a new registry.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE).
