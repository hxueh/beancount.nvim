"""Expose Beancount's loaded ledger to the editor without rewriting accounting data."""

import argparse
import contextlib
import json
import os
import sys
from collections import defaultdict

from beancount import loader
from beancount.core import flags
from beancount.core.data import Close, Commodity, Open, Price, Transaction
from beancount.core.realization import get, realize
from beancount.parser import parser


def canonical(filename):
    return os.path.realpath(os.path.abspath(filename))


def load_ledger(filename, overlays):
    """Parse editor snapshots with original filenames and include resolution.

    Only the parser input is substituted. Booking, plugins, validation and include
    expansion remain Beancount's responsibility. Disable disk caching so editor
    snapshots cannot read or populate a cache for different on-disk contents.
    """
    original = parser.parse_file
    original_loader = loader._load_file

    def parse_file(path, **kwargs):
        text = overlays.get(canonical(path)) if isinstance(path, (str, os.PathLike)) else None
        if text is not None:
            return parser.parse_string(text, report_filename=path)
        return original(path, **kwargs)

    # Beancount 3.2.3's initialize(False) deletes existing disk caches. Keep
    # this private-API adapter scoped to one load instead, bypassing both cache
    # reads and writes while preserving load_file's normal include handling.
    loader._load_file = loader._uncached_load_file
    parser.parse_file = parse_file
    try:
        return loader.load_file(filename)
    finally:
        parser.parse_file = original
        loader._load_file = original_loader


def analyze(filename, overlays, *, include_postings=False, payee_narration=True, selected_flags=None, hints_only=False):
    entries, errors, options = load_ledger(filename, overlays)
    accounts, commodities = {}, set(options.get("operating_currency", []))
    payees, narrations, tags, links = set(), set(), set(), set()
    automatics, booked = defaultdict(dict), defaultdict(dict)
    flagged = []
    names = {v: k[5:] for k, v in vars(flags).items() if k.startswith("FLAG_")}

    def location(meta):
        meta = meta or {}
        source = meta.get("filename") or filename
        return {"file": canonical(source) if not source.startswith("<") else filename,
                "line": max(1, meta.get("lineno") or 1)}

    def flag_record(entry):
        flag = getattr(entry, "flag", None)
        if flag and not hints_only and (selected_flags is None or flag in selected_flags):
            flagged.append(dict(location(entry.meta), flag=flag,
                                message=f'{type(entry).__name__} has flag {names.get(flag, flag)}'))

    for entry in entries:
        flag_record(entry)
        if isinstance(entry, Open):
            commodities.update(entry.currencies or [])
            accounts[entry.account] = dict(location(entry.meta), open=str(entry.date),
                                          close="", currencies=entry.currencies or [], balance=[])
        elif isinstance(entry, Close):
            if entry.account in accounts:
                accounts[entry.account]["close"] = str(entry.date)
        elif isinstance(entry, Commodity):
            commodities.add(entry.currency)
        elif isinstance(entry, Price):
            commodities.update((entry.currency, entry.amount.currency))
        elif isinstance(entry, Transaction):
            if payee_narration and not hints_only and entry.payee:
                payees.add(entry.payee)
            if entry.flag != flags.FLAG_PADDING:
                if payee_narration and not hints_only:
                    narrations.add(entry.narration)
                tags.update(entry.tags or ())
                links.update(entry.links or ())
            for posting in entry.postings:
                flag_record(posting)
                loc = location(posting.meta)
                file, line = loc["file"], str(loc["line"])
                if posting.units is None:
                    continue
                commodities.add(posting.units.currency)
                if posting.cost:
                    commodities.add(posting.cost.currency)
                if posting.price:
                    commodities.add(posting.price.currency)
                # One source posting can book against multiple lots. Retain every
                # result as structured data; never turn cost into a market price.
                if include_postings:
                    booked[file].setdefault(line, []).append({
                        "account": posting.account, "units": str(posting.units),
                        "cost": str(posting.cost) if posting.cost else None,
                        "price": str(posting.price) if posting.price else None,
                    })
                if posting.meta and posting.meta.get("__automatic__"):
                    automatics[file].setdefault(line, []).append(str(posting.units))

    # Autofill only needs interpolation and errors; avoid building account
    # inventories and serializing completion history twice during a save.
    if hints_only:
        accounts, commodities, tags, links = {}, set(), set(), set()
    tree = realize(entries) if not hints_only else None
    for account, details in accounts.items():
        node = get(tree, account)
        if node is not None:
            details["balance"] = sorted(str(position) for position in node.balance)
    return {
        "version": 1, "root": canonical(filename),
        "files": sorted({canonical(p) for p in options.get("include", [])} | {canonical(filename)}),
        "errors": [dict(location(e.source), message=e.message) for e in errors],
        "flags": flagged,
        "completion": {
            "accounts": accounts, "commodities": sorted(commodities),
            "payees": sorted(payees), "narrations": sorted(narrations - {""}),
            "tags": sorted(tags), "links": sorted(links),
            "options": [{"key": "operating_currency", "value": value}
                        for value in options.get("operating_currency", [])],
        },
        "hints": {"automatics": automatics, "cost_basis": {}},
        "postings": booked,
    }


def main():
    args = argparse.ArgumentParser(description=__doc__)
    args.add_argument("filename")
    args.add_argument("--payeeNarration", action="store_true")
    args.add_argument("--json", action="store_true", help="Return the versioned editor response")
    args.add_argument("--stdin", action="store_true", help="Read {filename: text} snapshots from stdin")
    args.add_argument("--postings", action="store_true", help="Include detailed booked postings")
    args.add_argument("--flags", default=None, help="Only return these flag characters (default: all)")
    args.add_argument("--hints-only", action="store_true", help="Omit completion inventories for autofill")
    opts = args.parse_args()
    overlays = json.load(sys.stdin) if opts.stdin else {}
    overlays = {canonical(path): text for path, text in overlays.items()}
    # Ledger plugins may print progress; keep stdout exclusively for the protocol.
    with contextlib.redirect_stdout(sys.stderr):
        result = analyze(canonical(opts.filename), overlays, include_postings=opts.postings,
                         payee_narration=opts.payeeNarration, selected_flags=opts.flags,
                         hints_only=opts.hints_only)
    if not opts.payeeNarration:
        result["completion"]["payees"] = []
        result["completion"]["narrations"] = []
    if opts.json:
        print(json.dumps(result, separators=(",", ":")))
    else:
        # Retain the old CLI format for external consumers during migration.
        for value in (result["errors"], result["completion"], result["flags"], result["hints"]):
            print(json.dumps(value, separators=(",", ":")))


if __name__ == "__main__":
    main()
