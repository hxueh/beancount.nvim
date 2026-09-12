"""Check the editor protocol against real booking, includes and buffer snapshots."""
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "pythonFiles/beancheck.py"


class EditorBackendTest(unittest.TestCase):
    def run_check(self, file, overlays=None, *extra):
        result = subprocess.run([sys.executable, str(SCRIPT), str(file), "--json", "--stdin", *extra],
                                input=json.dumps(overlays or {}), capture_output=True, text=True, check=True)
        return json.loads(result.stdout)

    def test_multilot_and_snapshot_validation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            main, book = root / "main.bean", root / "book.bean"
            main.write_text('include "book.bean"\n')
            text = '''2020-01-01 open Assets:Stock HOOL "FIFO"
2020-01-01 open Assets:Cash USD
2020-01-01 open Income:Gains USD
2020-01-02 * "Buy"
  Assets:Stock 1 HOOL {10 USD}
  Assets:Cash -10 USD
2020-01-03 * "Buy"
  Assets:Stock 1 HOOL {20 USD}
  Assets:Cash -20 USD
2020-01-04 * "Sell"
  Assets:Stock -2 HOOL {USD}
  Assets:Cash 40 USD
  Income:Gains
'''
            book.write_text(text)
            data = self.run_check(main, None, "--postings")
            self.assertEqual(data["errors"], [])
            self.assertEqual(len(data["postings"][str(book.resolve())]["11"]), 2)
            self.assertEqual(data["hints"]["cost_basis"], {})
            inferred = data["hints"]["automatics"][str(book.resolve())]["13"][0]
            valid = self.run_check(main, {str(book): text.replace('  Income:Gains\n', f'  Income:Gains {inferred}\n')})
            self.assertEqual(valid["errors"], [])
            invalid = self.run_check(main, {str(book): text.replace('{USD}', '{USD, 2020-01-03}')})
            self.assertTrue(invalid["errors"])
            self.assertEqual(book.read_text(), text, "snapshots never write to disk")

    def test_completion_sources_and_all_flags(self):
        with tempfile.TemporaryDirectory() as directory:
            main = Path(directory) / "main.bean"
            main.write_text('''option "operating_currency" "EUR"
2020-01-01 commodity NEW
2020-01-01 open Assets:Épargne CAD
2020-01-01 open Equity:Opening CAD
2020-01-01 price HOOL 10 CHF
2020-01-02 A "Entry"
  Assets:Épargne 10 CAD
  Equity:Opening -10 CAD
''')
            data = self.run_check(main)
            self.assertEqual(data["version"], 1)
            self.assertEqual(data["errors"], [])
            self.assertEqual(data["completion"]["commodities"], ['CAD', 'CHF', 'EUR', 'HOOL', 'NEW'])
            account = data["completion"]["accounts"]["Assets:Épargne"]
            self.assertEqual(account["line"], 3)
            self.assertEqual(account["balance"], ['10 CAD'])
            self.assertEqual(data["flags"][0]["flag"], 'A')
            self.assertEqual(data["completion"]["options"][0]["value"], 'EUR')

    def test_plugin_stdout_cannot_corrupt_protocol(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'chatty.py').write_text('__plugins__ = ("run",)\ndef run(entries, options):\n print("progress")\n return entries, []\n')
            main = root / 'main.bean'
            main.write_text('option "insert_pythonpath" "TRUE"\nplugin "chatty"\n')
            self.assertEqual(self.run_check(main)["errors"], [])

    def test_editor_load_preserves_disk_cache(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            main = root / "main.bean"
            main.write_text('2020-01-01 open Assets:Cash USD\n')
            cache = root / ".main.bean.picklecache"
            cache.write_bytes(b"not a pickle: snapshots must neither read nor delete it")
            stamp = cache.stat().st_mtime_ns
            overlay = '2020-01-01 open Assets:Updated EUR\n'
            data = self.run_check(main, {str(main): overlay})
            self.assertEqual(data["errors"], [])
            self.assertIn("Assets:Updated", data["completion"]["accounts"])
            self.assertEqual(cache.read_bytes(), b"not a pickle: snapshots must neither read nor delete it")
            self.assertEqual(cache.stat().st_mtime_ns, stamp)
            cache.unlink()
            self.run_check(main)
            self.assertFalse(cache.exists())

    def test_loader_adapter_restores_globals_on_failure(self):
        import importlib.util
        from unittest import mock
        from beancount import loader
        from beancount.parser import parser
        spec = importlib.util.spec_from_file_location("editor_backend", SCRIPT)
        backend = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(backend)
        original_load, original_parse = loader._load_file, parser.parse_file
        with mock.patch.object(loader, "load_file", side_effect=RuntimeError("load failed")):
            with self.assertRaisesRegex(RuntimeError, "load failed"):
                backend.load_ledger("unused.bean", {})
        self.assertIs(loader._load_file, original_load)
        self.assertIs(parser.parse_file, original_parse)

    def test_compact_response_and_hints_only(self):
        with tempfile.TemporaryDirectory() as directory:
            main = Path(directory) / "main.bean"
            main.write_text('2020-01-01 open Assets:Cash USD\n'
                            '2020-01-01 open Equity:Opening USD\n'
                            '2020-01-02 * "Payee" "Narration"\n'
                            '  Assets:Cash 1 USD\n  ! Equity:Opening\n')
            compact = self.run_check(main, None, "--flags", "!")
            detailed = self.run_check(main, None, "--postings", "--payeeNarration")
            hints = self.run_check(main, None, "--hints-only", "--flags", "")
            self.assertEqual(compact["postings"], {})
            self.assertTrue(detailed["postings"])
            self.assertEqual([f["flag"] for f in compact["flags"]], ["!"])
            self.assertEqual(hints["flags"], [])
            self.assertEqual(hints["completion"]["accounts"], {})
            self.assertEqual(hints["hints"], detailed["hints"])
            self.assertEqual(hints["errors"], detailed["errors"])

    def test_editor_syntax_fixtures_match_official_loader(self):
        from beancount import loader
        fixtures = json.loads((SCRIPT.parents[1] / "tests/example/editor_syntax.json").read_text())
        header = '2020-01-01 open Assets:Cash USD\n2020-01-01 open Equity:Opening USD\n'
        for marker in fixtures["transaction_markers"]:
            for expression in fixtures["expressions"]:
                with self.subTest(marker=marker, expression=expression):
                    _, errors, _ = loader.load_string(header + f'2020-01-02 {marker} "Payee" "Narration"\n'
                        f'  ! Assets:Cash {expression} USD\n  Equity:Opening\n')
                    self.assertEqual(errors, [])
        for flag in fixtures["posting_flags"]:
            with self.subTest(flag=flag):
                _, errors, _ = loader.load_string(header + '2020-01-02 * "Entry"\n'
                    f'  Assets:Cash 1 USD\n  {flag} Equity:Opening\n')
                self.assertEqual(errors, [])


if __name__ == '__main__':
    unittest.main()
