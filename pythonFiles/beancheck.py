"""load beancount file and print errors"""

import json
from collections import defaultdict
from sys import argv
from typing import Any, Dict, List, Optional, Set, Tuple, Union

from beancount import loader  # type: ignore
from beancount.core import flags  # type: ignore
from beancount.core.data import Close, Open, Transaction  # type: ignore
from beancount.core.display_context import Align  # type: ignore
from beancount.core.realization import dump_balances, realize  # type: ignore

# Lazy initialization of reverse_flag_map
_reverse_flag_map: Optional[Dict[str, str]] = None


def get_reverse_flag_map() -> Dict[str, str]:
    global _reverse_flag_map
    if _reverse_flag_map is None:
        _reverse_flag_map = {
            flag_value: flag_name[5:]
            for flag_name, flag_value in flags.__dict__.items()
            if flag_name.startswith("FLAG_")
        }
    return _reverse_flag_map


def get_flag_metadata(thing: Any) -> Dict[str, Union[str, int]]:
    reverse_flag_map = get_reverse_flag_map()
    # Cache frequently accessed attributes
    meta: Dict[str, Any] = thing.meta
    flag: str = thing.flag
    thing_class: str = thing.__class__.__name__

    # More efficient attribute lookup with explicit type handling
    help_text: str
    if hasattr(thing, "narration") and getattr(thing, "narration", None) is not None:
        help_text = str(getattr(thing, "narration"))
    elif hasattr(thing, "payee") and getattr(thing, "payee", None) is not None:
        help_text = str(getattr(thing, "payee"))
    elif hasattr(thing, "account") and getattr(thing, "account", None) is not None:
        help_text = str(getattr(thing, "account"))
    else:
        help_text = r"¯\_(ツ)_/¯"

    return {
        "file": meta["filename"],
        "line": meta["lineno"],
        "message": f"{thing_class} has flag {reverse_flag_map.get(flag, flag)} ({help_text})",
        "flag": flag,
    }


entries, errors, options = loader.load_file(argv[1])  # type: ignore
complete_payee_narration: bool = "--payeeNarration" in argv

error_list: List[Dict[str, Union[str, int]]] = [
    {"file": e.source["filename"], "line": e.source["lineno"], "message": e.message}  # type: ignore
    for e in errors  # type: ignore
]

# Pre-allocate data structures with better initial capacity
accounts: Dict[str, Dict[str, Union[str, List[str]]]] = {}
automatics: Dict[str, Dict[int, List[str]]] = defaultdict(dict)
commodities: Set[str] = set()
flagged_entries: List[Dict[str, Union[str, int]]] = []

# Initialize collection sets
payees: Set[str] = set()
narrations: Set[str] = set()
tags: Set[str] = set()
links: Set[str] = set()

for entry in entries:
    # Check for flagged entries first (most common case)
    if hasattr(entry, "flag") and entry.flag == "!":  # type: ignore
        flagged_entries.append(get_flag_metadata(entry))

    if isinstance(entry, Transaction):
        # Cache entry attributes with safe access
        entry_payee: Optional[str] = getattr(entry, "payee", None)
        entry_narration: str = str(getattr(entry, "narration", ""))
        entry_postings: List[Any] = getattr(entry, "postings", [])

        # Handle payee collection
        if complete_payee_narration and entry_payee:
            payees.add(entry_payee)

        # Skip padding transactions for narration/tags/links
        if not entry_narration.startswith("(Padding inserted"):
            if complete_payee_narration and entry_narration:
                narrations.add(entry_narration)
            tags.update(getattr(entry, "tags", set()))
            links.update(getattr(entry, "links", set()))

        # Process postings more efficiently
        txn_commodities: Set[str] = set()
        postings_count: int = len(entry_postings)

        for posting in entry_postings:
            units = getattr(posting, "units", None)
            if units is not None:
                currency: str = str(getattr(units, "currency", ""))
                if currency:
                    txn_commodities.add(currency)

            # Check for flagged postings
            if hasattr(posting, "flag") and str(getattr(posting, "flag", "")) == "!":
                flagged_entries.append(get_flag_metadata(posting))

            # Handle automatic postings more efficiently
            posting_meta: Dict[str, Any] = getattr(posting, "meta", {})
            if posting_meta and posting_meta.get("__automatic__", False):
                # Process all automatic postings for autofill feature
                # Previously filtered by: postings_count > 2 or len(txn_commodities) > 1
                filename: str = str(posting_meta.get("filename", ""))
                lineno: int = int(posting_meta.get("lineno", 0))
                if units is not None:
                    amount_str: str = str(getattr(units, "to_string", lambda: "")())
                    if lineno not in automatics[filename]:
                        automatics[filename][lineno] = []
                    automatics[filename][lineno].append(amount_str)

        commodities.update(txn_commodities)

    elif isinstance(entry, Open):
        account_name: str = str(getattr(entry, "account", ""))  # type: ignore
        if account_name:
            accounts[account_name] = {
                "open": str(getattr(entry, "date", "")),
                "currencies": getattr(entry, "currencies", None) or [],
                "close": "",
                "balance": [],
            }
    elif isinstance(entry, Close):
        # Use get() method instead of try/except
        account_name: str = str(getattr(entry, "account", ""))
        if account_name:
            account_data: Optional[Dict[str, Union[str, List[str]]]] = accounts.get(  # type: ignore
                account_name
            )
            if account_data is not None:
                account_data["close"] = str(getattr(entry, "date", ""))


# More efficient balance processing using list instead of StringIO
class BalanceCapture:
    def __init__(self) -> None:
        self.lines: List[str] = []

    def write(self, text: str) -> None:
        self.lines.append(text)

    def get_lines(self) -> List[str]:
        return "".join(self.lines).split("\n")


balance_capture: BalanceCapture = BalanceCapture()
dump_balances(
    realize(entries),
    options["dcontext"].build(alignment=Align.DOT, reserved=2),
    at_cost=False,
    fullnames=True,
    file=balance_capture,
)

# Process balance lines more efficiently
for line in balance_capture.get_lines():
    if line:
        # Use partition for more efficient string splitting
        account_part: str
        sep: str
        remainder: str
        account_part, sep, remainder = line.partition(" ")
        if sep and remainder:
            # Find the balance part more efficiently
            balance_part: str
            balance_part, _, _ = remainder.strip().partition(" ")
            if balance_part:
                account_data: Optional[Dict[str, Union[str, List[str]]]] = accounts.get(
                    account_part
                )
                if account_data is not None:
                    balance_list: List[str] = account_data["balance"]  # type: ignore
                    balance_list.append(balance_part)

# Clean up empty/None values more efficiently using set subtraction
if complete_payee_narration:
    payees -= {"", "None"}
    narrations -= {"", "None"}
else:
    # Remove empty values for consistency even if not collecting
    payees -= {"", "None"}

# Build output dictionary more efficiently
output: Dict[str, Any] = {
    "accounts": accounts,
    "commodities": list(commodities),
    "payees": list(payees),
    "narrations": list(narrations),
    "tags": list(tags),
    "links": list(links),
}

# Use separators to reduce JSON output size
json_separators: Tuple[str, str] = (",", ":")
print(json.dumps(error_list, separators=json_separators))
print(json.dumps(output, separators=json_separators))
print(json.dumps(flagged_entries, separators=json_separators))
print(json.dumps(automatics, separators=json_separators))
