# Official Curated Circuit Collections (OCCC) for TapeOut

Reference implementation of the TAP draft **Official Curated Circuit Collections (OCCC)** (`TAP-draft-occc.md`, 中文：`TAP-draft-occc.zh.md`).

On TapeOut, anyone can add circuits to any processor's NFT collection — with transistors any netlist, and without transistors a pure-REF netlist whose `circuitInfo` copies an official work. This project makes "which circuits are the real works" a public on-chain fact based on **who taped the circuit out**.

The reference vault in this repository sells each listed work at a fixed price, in any order or strictly in list order, in the chain's coin or in an ERC-20 token. Other ways of selling are allowed by the standard; they are not part of this repository.

## Chains

TapeOut runs on BNB Smart Chain, X Layer and Base, and so does this protocol, unchanged: deploy the vault implementation and one `CuratedRegistry` per chain with that chain's TapeOut factory (`FACTORY=<factory> forge script script/Deploy.s.sol --rpc-url <RPC> --broadcast --private-key <key>`, then `python3 tool/check_deploy.py --rpc <RPC> --registry <REGISTRY>`). A collection, its work list and its officialness belong to one chain (leaves include the chain id).

| Chain | chainId | Native coin | TapeOut factory (registry constructor argument) | Public RPC |
|---|---|---|---|---|
| BNB Smart Chain | 56 | BNB | `0x68224F668083c29e9800Be2a646d42d18cedF7e2` | `https://bsc-dataseed.bnbchain.org` |
| X Layer | 196 | OKB | `0x1f09DAeFA827f02CBb40967cc91b259763760761` | `https://rpc.xlayer.tech` |
| Base | 8453 | ETH | `0x1f09DAeFA827f02CBb40967cc91b259763760761` | `https://mainnet.base.org` |

`curate.py` knows these factories: `build` checks that `--rpc` is on the spec's `chainId` and, unless the spec gives `deployFeeWei` and `protocolFeeWei`, reads the current fees from that chain's factory; `checkroot` checks the registry's `FACTORY()`. For any other chain (a testnet, a devnet) the spec must give `deployFeeWei` and `protocolFeeWei`, and `factory` when REF targets are checked with `--rpc`. `tool/examples/make_examples.py <chainId>` writes the example collections for a chain; `test/fixtures/manifest[.<chainId>].json` and `copies[.<chainId>].json` are their manifests.

## How it works

1. **Launch (one transaction, sent by the curator).** `CuratedRegistry.launch` checks the parameters and creates the vault as a clone of `VAULT_IMPL`. The vault creates the processor, mints the whole transistor supply to itself, and binds itself to the registry, which re-checks all of that on chain.
2. **Sell.** A buyer calls `vault.buy(index, netlist, nIn, nOut, price, proof, recipient)` with `price + TAPEOUT_FEE` (in a collection priced in a token, only `TAPEOUT_FEE`; see 9). The vault checks the Merkle proof, tapes out with its own transistors, the registry certifies the new circuit id in the same transaction (and gives it the next official serial, `registry.serialOf`), the circuit goes to the recipient, and the price is paid to the curator at once. A payout that fails is kept in `vault.owed(curator)` and withdrawn with `withdraw` / `withdrawTo`; it never blocks the purchase.
   - **Copies, in order.** A work with `"copies": N` is one design sold N times (the manifest stores it once). With `"sequential": true` works are sold strictly in list order with `vault.buyNext(first, copies, …)`, so the official serial of every work is its list position + 1 and, while nobody injects a wrapper into the processor, its TapeOut id. Reserved runs come first and are claimed with `claimReservedRun` before the sale.
3. **Reserve (optional).** Works marked `"reserved": true` cannot be bought. The curator claims them with `vault.claimReserved(...)`, or several at once with `vault.claimReservedBatch([...])` (tape-out fee per work; until `finalize`), and they go to the `treasury` fixed at launch. From there they can be given away like any circuit; they stay official.
4. **Check.** Anyone calls `registry.isOfficial(circuits, id)` / `editionOf(circuits, id)` / `isReserved(circuits, id)`.
5. **Royalty declaration (optional).** `"royalty": {"receiver": "0x…", "bps": 300}` (at most 500 bps). Markets read `registry.royaltyInfo(circuits, id, price)` (ERC-2981 shape); only official works report it. The curator can later change the receiver or lower the rate, never raise it.
6. **Pause or extend (curator).** `vault.setPaused(true/false)` stops and resumes buying (reserved claims are unaffected). `vault.extendSale(newEnd)` moves the sale end later, never earlier, while the sale is still open.
7. **Finish.** After every work is taped out, or after `saleEnd` once every reserved work is claimed (otherwise 30 days after `saleEnd`), anyone can call `vault.finalize()` to burn the leftover transistors; `vault.finalizable()` tells whether it is time.
8. **Images and metadata (optional).** Give works `"image"` (and optionally `"animation"`, `"description"`, `"attributes"`) as `ipfs://…` or `ar://…` links, run `curate.py metadata manifest.json out/` to write one `<index>.json` per work, upload that folder as one directory, set `"metadataURI"` in the spec and build again. `registry.tokenURI(circuits, id)` then returns `<metadataURI>/<index>.json` for official works and `""` for everything else (TAP §11).
9. **Price in a token (optional).** `"paymentToken": "0x…"` prices every work in that ERC-20 (`priceWei` is then in the token's smallest unit; BEM has 8 decimals). Buyers approve the vault for the price and call `buy` / `buyNext` with only `TAPEOUT_FEE` in native coin; the vault refuses tokens that do not deliver exactly the price. Launch fees and reserved claims stay native.
10. **Audit the list.** The curator publishes the manifest; anyone runs `curate.py checkroot` to rebuild the root from every published work and the metadata commitment from the name, symbol, story and titles, and compare them and every launch setting with the chain.

No contract has an owner, an admin function or an upgrade path.

## Layout

| Path | What |
|---|---|
| `src/CuratedRegistry.sol` | registry + launcher: checks parameters, clones the vault implementation, serials, per-circuit metadata, royalty declaration |
| `src/CuratedVault.sol` | the reference vault: fixed prices, any order or sequential runs of copies, native or token pricing, reserve, pause and extend, finalize |
| `src/CuratedTypes.sol` | launch parameters |
| `src/interfaces/ICuratedRegistry.sol` | the standard interface |
| `src/interfaces/ICircuitURIProvider.sol` | the `tokenURI` hook proposed to TapeOut (TAP Recommendation 1) |
| `src/interfaces/ITapeOut.sol` | the TapeOut functions used (selectors checked on mainnet) |
| `tool/curate.py` | encoder, Merkle builder, manifest, verifier (Python 3.11+, no dependencies) |
| `tool/check_deploy.py` | checks a deployed registry and its vault implementation against this commit (`forge build` first) |
| `tool/tap02_reference.py`, `tool/tap02_vectors.json` | official TAP-02 reference implementation and vectors (MIT) |
| `tool/examples/` | throw-away example collections of small test circuits |
| `test/Curated.t.sol`, `test/Copies.t.sol` | 50 fork tests (BNB Smart Chain, X Layer or Base), including token pricing with BEM on BNB Smart Chain and copies sold in order |
| `script/Deploy.s.sol` | deploy the vault implementation and the registry |
| `script/Launch.s.sol` | launch a collection from a manifest (run with the curator's key) |
| `script/Demo.s.sol` | end-to-end demo on a local fork |

## Setup

```bash
# Foundry (https://getfoundry.sh), then the two libraries (tested with forge-std v1.17.0):
forge install foundry-rs/forge-std@v1.17.0 OpenZeppelin/openzeppelin-contracts@v5.1.0
```

## Quick start

```bash
# 1. tool self-test (TAP-02 vectors + random encoder cross-checks)
python3 tool/curate.py selftest

# 2. encode one design (TapeOut canvas export, or {"netlist","nIn","nOut"})
python3 tool/curate.py encode tool/examples/lfsr7.json

# 3. build a launch manifest from a collection spec (--rpc checks REF targets on chain)
python3 tool/examples/make_examples.py          # 196 or 8453 for X Layer or Base
python3 tool/curate.py build tool/examples/collection.json test/fixtures/manifest.json \
    --rpc https://bsc-dataseed.bnbchain.org

# 4. run the fork tests on BNB Smart Chain, X Layer or Base
forge test --fork-url https://bsc-dataseed.bnbchain.org -vv
forge test --fork-url https://rpc.xlayer.tech
forge test --fork-url https://mainnet.base.org

# 5. after deployment: is circuit 7 of a collection official? (the manifest is optional; it adds the title)
python3 tool/curate.py verify my_manifest.json --rpc https://bsc-dataseed.bnbchain.org \
    --registry <REGISTRY> --circuits <PROCESSOR> --id 7

# 6. does the published manifest match the chain (works, titles and every launch setting)?
python3 tool/curate.py checkroot my_manifest.json --rpc https://bsc-dataseed.bnbchain.org \
    --registry <REGISTRY> --circuits <PROCESSOR>
```

### Collection spec (`collection.json`)

```json
{
  "name": "My Collection", "symbol": "MYC", "story": "…",
  "chainId": 56, "registry": "0x… (the deployed CuratedRegistry)",
  "curator": "0x… (the address that will send the launch and receive the proceeds)",
  "treasury": "0x… (receives reserved works; a multisig is recommended)",
  "mintPriceWei": "10000000000000", "mintBatch": 2500,
  "saleStart": 1798200000, "saleEnd": 1798761600, "spareNand": 0, "spareLatch": 0,
  "royalty": {"receiver": "0x…", "bps": 300},
  "paymentToken": "0x… (optional ERC-20 for prices; omit for the native coin)",
  "sequential": false,
  "metadataURI": "ar://<43-character id of the directory>",
  "works": [
    {"file": "design.json", "title": "Work 0", "priceWei": "10000000000000000",
     "image": "ar://<image id>", "description": "…", "attributes": [{"trait_type": "Gates", "value": 12}]},
    {"netlist": "0x…", "nIn": 8, "nOut": 4, "title": "Work 1", "priceWei": "0", "copies": 5},
    {"file": "gift.json", "title": "Kept for the treasury", "reserved": true}
  ]
}
```

`royalty`, `paymentToken`, `sequential`, `metadataURI` and the per-work `copies`, `image`, `animation`, `description` and `attributes` are optional; `build` refuses keys it does not know. `metadataURI` must be `ipfs://<CID>` or `ar://<id>` (an id with at least one upper-case letter) with no path; image links must be `ipfs://` or `ar://` too, and may have a path. Amounts in wei are integers or strings of digits. Other optional keys: `defaultPriceWei` (price of works without `priceWei`), `maxLaunchFeesWei` (the most you will pay in factory and protocol fees; default: the fees the tool predicts), `deployFeeWei` / `protocolFeeWei` and `factory`. Mixed-case addresses must have a correct EIP-55 checksum.

`build` encodes each design, checks it with the TAP-02 reference implementation, resolves every REF target on chain, cross-simulates canvas designs against the encoded netlist, counts NAND / LATCH exactly, pads the supply to the factory minimum of 10,000, computes the launch-fee cap and the value to send, and writes the root, proofs and launch parameters. Leaves are bound to the chain id, the registry and the curator, so the manifest is only valid for that registry and that curator.

### Canvas REF nodes

The TapeOut canvas export does not document a REF node's `data`. This tool expects `{"cpu": "0x…", "id": n, "nIn": i, "nOut": o, "nState": s}`.

## Launch

```bash
python3 tool/curate.py build my_collection.json my_manifest.json --rpc https://bsc-dataseed.bnbchain.org
MANIFEST=my_manifest.json forge script script/Launch.s.sol \
    --rpc-url https://bsc-dataseed.bnbchain.org --broadcast --private-key <curator key>
```

## Notes

- Launch must be sent by the curator, with `msg.value` = the manifest's `launchValueWei` (fees + one mint batch of float). The unused part is refunded in the same transaction. If TapeOut raises its fees above `maxLaunchFeesWei`, the launch reverts.
- Publish the whole manifest before the sale opens: buyers need it for proofs, and verifiers need it to rebuild the root.
- Free public BSC nodes keep recent state only, so long-lived `anvil` forks fail after about a minute; `forge test --fork-url` re-forks the latest block on every run.
- Internal reviews only, not audited. Do not use with significant value before an independent audit.

Licence: MIT (code), CC0 (TAP text).
