"""Run on-demand ledger exploration against the same snapshots as validation."""
import contextlib
import json
import sys
from collections import defaultdict

from beancount.core import data, getters, inventory
from beancount.parser import parser
from beancheck import canonical, load_ledger


def location(entry):
    meta = entry.meta or {}
    filename = meta.get("filename", "")
    if not filename or filename.startswith("<"):
        return None
    return {"filename": canonical(filename), "lnum": max(1, meta.get("lineno", 1))}


def references(entries, token):
    """Match semantic fields, excluding lookalikes in comments and strings."""
    found = {}
    for entry in entries:
        matches = []
        if token.startswith(("#", "^")):
            field = "tags" if token[0] == "#" else "links"
            if token[1:] in (getattr(entry, field, None) or ()):
                matches = [entry]
        elif isinstance(entry, data.Transaction):
            matches = [p for p in entry.postings if p.account == token]
        elif token in getters.get_entry_accounts(entry):
            matches = [entry]
        for match in matches:
            loc = location(match) or location(entry)
            if loc:
                # Booking can split one source posting into several lots.
                key = (loc["filename"], loc["lnum"])
                description = " | ".join(filter(None, [getattr(entry, "payee", None),
                                                        getattr(entry, "narration", None)]))
                found[key] = dict(loc, col=1, text=f"{entry.date} {token} {description}".rstrip())
    return {"items": [found[key] for key in sorted(found)]}


def balances(entries, filename, line, account):
    """Accumulate booked inventories in loader order, including same-day entries."""
    target = [e for e in entries if isinstance(e, data.Transaction)
              and location(e) == {"filename": canonical(filename), "lnum": line}]
    if len(target) != 1:
        raise ValueError("Select a source transaction with a unique loaded entry")
    target = target[0]
    accounts = {p.account for p in target.postings}
    if account:
        if account not in accounts:
            raise ValueError("The selected account is not posted in this transaction")
        accounts = {account}
    totals = defaultdict(inventory.Inventory)
    before = {}
    for entry in entries:
        if not isinstance(entry, data.Transaction):
            continue
        if entry is target:
            before = {name: sorted(str(p) for p in totals[name]) for name in accounts}
        for posting in entry.postings:
            if posting.account in accounts:
                totals[posting.account].add_position(posting)
        if entry is target:
            return {"date": str(entry.date), "accounts": [
                {"account": name, "before": before[name],
                 "after": sorted(str(p) for p in totals[name])} for name in sorted(accounts)]}
    raise ValueError("Transaction unavailable")


def query(entries, errors, options, text):
    try:
        import beanquery
        from beanquery.parser import ast
    except ImportError as exc:
        raise ValueError("Query execution requires beanquery in the configured Python environment. "
                         "Install with: python -m pip install beanquery") from exc
    connection = beanquery.connect("beancount:", entries=entries, errors=errors, options=options)
    statement = connection.parse(text)
    # This editor command produces a result table; do not expose table mutation
    # or shell commands through the query UI.
    if not isinstance(statement, (ast.Select, ast.Balances, ast.Journal)):
        raise ValueError("Use a SELECT, BALANCES, or JOURNAL query")
    cursor = connection.execute(statement)
    return {"columns": [column[0] for column in cursor.description],
            "rows": [["" if cell is None else str(cell) for cell in row] for row in cursor.fetchall()]}


def run(request):
    overlays = {canonical(path): text for path, text in request.get("snapshots", {}).items()}
    entries, errors, options = load_ledger(request["root"], overlays)
    action = request["action"]
    if action == "references":
        result = references(entries, request["token"])
        result["warnings"] = [e.message for e in errors]
        return result
    # Invalid booking would make balances and aggregate query results misleading.
    if errors:
        raise ValueError("Fix ledger errors before running this command: " + errors[0].message)
    if action == "balances":
        return balances(entries, request["file"], request["line"], request.get("account"))
    if action == "query":
        text = request["query"]
        if request.get("directive"):
            parsed, parse_errors, _ = parser.parse_string(text)
            if parse_errors or len(parsed) != 1 or not isinstance(parsed[0], data.Query):
                raise ValueError("Place the cursor on a valid query directive, select BQL, or supply a query")
            text = parsed[0].query_string
        return query(entries, errors, options, text)
    raise ValueError("Unknown editor command")


def main():
    try:
        with contextlib.redirect_stdout(sys.stderr):
            result = run(json.load(sys.stdin))
        print(json.dumps(result))
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
