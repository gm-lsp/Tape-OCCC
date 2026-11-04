#!/usr/bin/env python3
"""Check a deployed CuratedRegistry and its vault implementation against this repository.

    forge build
    python3 tool/check_deploy.py --rpc https://bsc-dataseed.bnbchain.org --registry 0x...

Compares the code on chain with out/ (built from this commit): the registry with its immutables masked,
the vault implementation as is. Checks that FACTORY() is TapeOut's factory for the chain. Prints the
fingerprint (keccak256 of the runtime code without its CBOR metadata) of each contract. Exit code 0 = ok.
"""
from __future__ import annotations

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from curate import CHAINS, keccak256, rpc_call, rpc_raw, sel  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def artifact(name: str) -> dict:
    path = os.path.join(ROOT, "out", f"{name}.sol", f"{name}.json")
    if not os.path.exists(path):
        sys.exit(f"{path} not found: run `forge build` first")
    return json.load(open(path))["deployedBytecode"]


def mask(code: bytes, refs: dict | None) -> bytes:
    b = bytearray(code)
    for spans in (refs or {}).values():
        for s in spans:
            b[s["start"]:s["start"] + s["length"]] = bytes(s["length"])
    return bytes(b)


def strip_cbor(code: bytes) -> bytes:
    n = int.from_bytes(code[-2:], "big")
    return code[:-(n + 2)] if n + 2 <= len(code) else code


def read_addr(url: str, to: str, sig: str) -> str:
    try:
        word = rpc_call(url, to, "0x" + sel(sig))
    except RuntimeError:
        word = ""
    if len(word) != 66:
        sys.exit("not a CuratedRegistry (no contract at this address, or no such function)")
    return "0x" + word[-40:]


def check(url: str, name: str, address: str) -> bool:
    art = artifact(name)
    want = bytes.fromhex(art["object"][2:])
    got = bytes.fromhex(rpc_raw(url, "eth_getCode", [address, "latest"])[2:])
    refs = art.get("immutableReferences")
    same = len(got) == len(want) and mask(got, refs) == mask(want, refs)
    fp = "0x" + keccak256(strip_cbor(mask(got, refs))).hex() if got else "-"
    print(f"{name:16} {address}  {len(got):,} bytes  fingerprint {fp}  {'ok' if same else 'MISMATCH'}")
    return same


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--rpc", required=True)
    ap.add_argument("--registry", required=True)
    a = ap.parse_args()
    chain_id = int(rpc_raw(a.rpc, "eth_chainId", []), 16)
    chain = CHAINS.get(chain_id)
    ok = True
    factory = read_addr(a.rpc, a.registry, "FACTORY()")
    want_factory = chain["factory"] if chain else None
    f_ok = want_factory is not None and factory.lower() == want_factory.lower()
    print(f"chain {chain_id} ({chain['name'] if chain else 'unknown'})  FACTORY() {factory}  "
          f"{'ok' if f_ok else 'not the TapeOut factory of this chain'}")
    ok &= f_ok
    impl = read_addr(a.rpc, a.registry, "VAULT_IMPL()")
    ok &= check(a.rpc, "CuratedRegistry", a.registry)
    ok &= check(a.rpc, "CuratedVault", impl)
    print("ok" if ok else "FAILED")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
