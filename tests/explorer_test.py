"""Exercise exploration through the subprocess protocol and real ledger booking."""
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "pythonFiles/editor.py"
BOOK = '''2020-01-01 open Assets:Cash
2020-01-01 open Equity:Opening
2020-01-01 open Assets:CashExtra
2020-01-02 * "First" #trip ^receipt
  Assets:Cash 10 USD
  Equity:Opening -10 USD
2020-01-02 * "Second"
  Assets:Cash 2 EUR
  Equity:Opening -2 EUR
2020-01-03 * "Assets:Cash #trip ^receipt"
  Assets:CashExtra 1 USD
  Equity:Opening -1 USD
;; Assets:Cash #trip ^receipt
'''


class ExplorerTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "main.bean"
        self.book = Path(self.temp.name) / "book with spaces.bean"
        self.root.write_text('include "book with spaces.bean"\n')
        self.book.write_text(BOOK)

    def run_command(self, action, **kwargs):
        request = dict(root=str(self.root), action=action, **kwargs)
        result = subprocess.run([sys.executable, str(SCRIPT)], input=json.dumps(request),
                                capture_output=True, text=True)
        return result

    def result(self, action, **kwargs):
        process = self.run_command(action, **kwargs)
        self.assertEqual(process.returncode, 0, process.stderr)
        return json.loads(process.stdout)

    def test_exact_references_and_unsaved_includes(self):
        rows = self.result("references", token="Assets:Cash")["items"]
        self.assertEqual([r["lnum"] for r in rows], [1, 5, 8])
        self.assertTrue(all(r["filename"] == str(self.book.resolve()) for r in rows))
        for token in ("#trip", "^receipt"):
            self.assertEqual([r["lnum"] for r in self.result("references", token=token)["items"]], [4])
        changed = BOOK.replace('"Second"', '"Second" #trip')
        self.assertEqual(len(self.result("references", token="#trip",
                                        snapshots={str(self.book): changed})["items"]), 2)
        self.assertEqual(self.book.read_text(), BOOK)

    def test_same_day_balances_preserve_currencies(self):
        result = self.result("balances", file=str(self.book), line=7, account="Assets:Cash")
        self.assertEqual(result["accounts"], [{"account": "Assets:Cash", "before": ["10 USD"],
                                                "after": ["10 USD", "2 EUR"]}])
        first = self.result("balances", file=str(self.book), line=4)
        self.assertEqual(len(first["accounts"]), 2)
        self.assertEqual(first["accounts"][0]["before"], [])
        self.assertNotEqual(self.run_command("balances", file=str(self.book), line=1).returncode, 0)

    def test_balances_use_booked_lots(self):
        book = '''2020-01-01 open Assets:Stock HOOL "FIFO"
2020-01-01 open Assets:Cash USD
2020-01-02 * "Buy"
  Assets:Stock 2 HOOL {10 USD}
  Assets:Cash -20 USD
2020-01-03 * "Sell"
  Assets:Stock -1 HOOL {}
  Assets:Cash 10 USD
'''
        result = self.result("balances", file=str(self.book), line=6, account="Assets:Stock",
                             snapshots={str(self.book): book})["accounts"][0]
        self.assertEqual(result["before"], ["2 HOOL {10 USD, 2020-01-02}"])
        self.assertEqual(result["after"], ["1 HOOL {10 USD, 2020-01-02}"])

    def test_queries_and_directive_use_snapshot(self):
        query = "SELECT account, sum(position) WHERE account = 'Assets:Cash' GROUP BY account"
        result = self.result("query", query=query, snapshots={str(self.book): BOOK.replace('10 USD', '20 USD')})
        self.assertEqual(result["rows"][0][0], "Assets:Cash")
        self.assertIn("20 USD", result["rows"][0][1])
        self.assertIn("2 EUR", result["rows"][0][1])
        result = self.result("query", query='2020-01-01 query "cash" "SELECT account LIMIT 1"', directive=True)
        self.assertEqual(len(result["rows"]), 1)
        empty = self.result("query", query="SELECT account WHERE account = 'Missing'")
        self.assertEqual(empty["rows"], [])
        for text in ("SELECT broken(", "CREATE TABLE example (a integer)"):
            self.assertNotEqual(self.run_command("query", query=text).returncode, 0)

    def test_invalid_ledger_blocks_calculations_but_allows_references(self):
        overlay = {str(self.book): BOOK.replace('-10 USD', '-11 USD')}
        self.assertNotEqual(self.run_command("query", query="SELECT account", snapshots=overlay).returncode, 0)
        self.assertNotEqual(self.run_command("balances", file=str(self.book), line=4,
                                            snapshots=overlay).returncode, 0)
        self.assertTrue(self.result("references", token="Assets:Cash", snapshots=overlay)["warnings"])

    def test_missing_optional_dependency(self):
        # Import interception simulates a normal installation without beanquery.
        import importlib.util
        from unittest.mock import patch
        sys.path.insert(0, str(SCRIPT.parent))
        self.addCleanup(lambda: sys.path.remove(str(SCRIPT.parent)))
        spec = importlib.util.spec_from_file_location("editor", SCRIPT)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with patch.dict(sys.modules, {"beanquery": None}):
            with self.assertRaisesRegex(ValueError, "requires beanquery"):
                module.query([], [], {}, "SELECT account")
