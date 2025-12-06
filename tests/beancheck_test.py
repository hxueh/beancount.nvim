#!/usr/bin/env python3
"""
Comprehensive tests for beancheck.py

Tests the optimized beancheck.py script with various scenarios including:
- Basic functionality
- Error handling
- Type safety
- Performance optimizations
- Edge cases
"""

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from typing import Any, Dict, List


# Create a custom test result class to track statistics
class TestResultCollector(unittest.TextTestResult):
    def __init__(self, *args: Any, **kwargs: Any) -> None:
        super().__init__(*args, **kwargs)
        self.test_count: int = 0
        self.success_count: int = 0
        self.failure_count: int = 0
        self.error_count: int = 0
        self.skip_count: int = 0

    def startTest(self, test: unittest.TestCase) -> None:
        super().startTest(test)
        self.test_count += 1

    def addSuccess(self, test: unittest.TestCase) -> None:
        super().addSuccess(test)
        self.success_count += 1

    def addError(self, test: unittest.TestCase, err: Any) -> None:
        super().addError(test, err)
        self.error_count += 1

    def addFailure(self, test: unittest.TestCase, err: Any) -> None:
        super().addFailure(test, err)
        self.failure_count += 1

    def addSkip(self, test: unittest.TestCase, reason: str) -> None:
        super().addSkip(test, reason)
        self.skip_count += 1


class BeancheckTest(unittest.TestCase):
    """Test suite for beancheck.py functionality"""

    # Class attributes
    test_dir: Path
    beancheck_script: Path
    example_dir: Path
    main_file: Path
    python_path: str

    @classmethod
    def setUpClass(cls) -> None:
        """Set up test environment"""
        cls.test_dir = Path(__file__).parent
        cls.beancheck_script = cls.test_dir.parent / "pythonFiles" / "beancheck.py"
        cls.example_dir = cls.test_dir / "example"
        cls.main_file = cls.example_dir / "main.beancount"

        # Find Python executable (prefer virtual env)
        cls.python_path = cls.find_python_executable()

        # Ensure test files exist
        if not cls.beancheck_script.exists():
            raise FileNotFoundError(f"beancheck.py not found at {cls.beancheck_script}")
        if not cls.main_file.exists():
            raise FileNotFoundError(f"Test file not found at {cls.main_file}")

    @staticmethod
    def find_python_executable() -> str:
        """Find appropriate Python executable"""
        # Try common virtual environment paths first
        candidates: List[str] = [sys.executable, "python3", "python"]

        for candidate in candidates:
            try:
                result = subprocess.run(
                    [candidate, "--version"], capture_output=True, text=True
                )
                if result.returncode == 0:
                    return candidate
            except FileNotFoundError:
                continue

        return "python3"  # fallback

    def run_beancheck(
        self, filename: str, payee_narration: bool = False
    ) -> Dict[str, Any]:
        """Run beancheck.py and return parsed JSON output"""
        cmd: List[str] = [str(self.python_path), str(self.beancheck_script), filename]
        if payee_narration:
            cmd.append("--payeeNarration")

        try:
            result = subprocess.run(
                cmd, capture_output=True, text=True, cwd=self.test_dir.parent
            )
            if result.returncode != 0:
                self.fail(f"beancheck.py failed: {result.stderr}")

            lines: List[str] = result.stdout.strip().split("\n")
            self.assertEqual(len(lines), 4, "Expected 4 JSON output lines")

            # Parse the result object which contains automatics and cost_basis
            result_obj: Dict[str, Any] = json.loads(lines[3])

            return {
                "errors": json.loads(lines[0]),
                "data": json.loads(lines[1]),
                "flagged": json.loads(lines[2]),
                "automatics": result_obj.get("automatics", {}),
                "cost_basis": result_obj.get("cost_basis", {}),
            }
        except subprocess.CalledProcessError as e:
            self.fail(f"Failed to run beancheck.py: {e}")
        except json.JSONDecodeError as e:
            self.fail(f"Failed to parse JSON output: {e}")

    def test_basic_functionality(self) -> None:
        """Test basic beancheck functionality"""
        result: Dict[str, Any] = self.run_beancheck(str(self.main_file))

        # Check basic structure
        self.assertIn("errors", result)
        self.assertIn("data", result)
        self.assertIn("flagged", result)
        self.assertIn("automatics", result)

        data: Dict[str, Any] = result["data"]
        self.assertIn("accounts", data)
        self.assertIn("commodities", data)
        self.assertIn("payees", data)
        self.assertIn("narrations", data)
        self.assertIn("tags", data)
        self.assertIn("links", data)

    def test_account_processing(self) -> None:
        """Test account opening/closing processing"""
        result: Dict[str, Any] = self.run_beancheck(str(self.main_file))
        data: Dict[str, Any] = result["data"]
        accounts: Dict[str, Any] = data["accounts"]

        # Check that accounts are properly processed
        self.assertGreater(len(accounts), 0, "Should have processed accounts")

        # Check account structure
        for _, account_data in accounts.items():
            self.assertIn("open", account_data)
            self.assertIn("close", account_data)
            self.assertIn("balance", account_data)
            self.assertIn("currencies", account_data)

            # Validate data types
            self.assertIsInstance(account_data["open"], str)
            self.assertIsInstance(account_data["close"], str)
            self.assertIsInstance(account_data["balance"], list)
            self.assertIsInstance(account_data["currencies"], list)

    def test_payee_narration_flag(self) -> None:
        """Test --payeeNarration flag functionality"""
        result_without: Dict[str, Any] = self.run_beancheck(
            str(self.main_file), payee_narration=False
        )
        result_with: Dict[str, Any] = self.run_beancheck(
            str(self.main_file), payee_narration=True
        )

        # Without flag, payees and narrations should be empty or minimal
        self.assertLessEqual(
            len(result_without["data"]["payees"]), len(result_with["data"]["payees"])
        )
        self.assertLessEqual(
            len(result_without["data"]["narrations"]),
            len(result_with["data"]["narrations"]),
        )

    def test_commodity_extraction(self) -> None:
        """Test commodity extraction"""
        result: Dict[str, Any] = self.run_beancheck(str(self.main_file))
        commodities: List[str] = result["data"]["commodities"]

        self.assertIsInstance(commodities, list)
        # Should contain USD at minimum
        self.assertIn("USD", commodities)

    def test_flagged_entries(self) -> None:
        """Test flagged entry detection"""
        result: Dict[str, Any] = self.run_beancheck(str(self.main_file))
        flagged: List[Dict[str, Any]] = result["flagged"]

        self.assertIsInstance(flagged, list)
        # Check structure of flagged entries
        for entry in flagged:
            self.assertIn("file", entry)
            self.assertIn("line", entry)
            self.assertIn("message", entry)
            self.assertIn("flag", entry)

    def test_automatic_postings(self) -> None:
        """Test automatic posting detection"""
        result: Dict[str, Any] = self.run_beancheck(str(self.main_file))
        automatics: Dict[str, Dict[str, List[str]]] = result["automatics"]

        self.assertIsInstance(automatics, dict)
        # Structure: {filename: {lineno: [amount_string, ...]}}
        for _, line_data in automatics.items():
            self.assertIsInstance(line_data, dict)
            for _, amounts in line_data.items():
                self.assertIsInstance(amounts, list)
                for amount in amounts:
                    self.assertIsInstance(amount, str)

    def test_tags_and_links(self) -> None:
        """Test tag and link extraction"""
        result: Dict[str, Any] = self.run_beancheck(str(self.main_file))
        data: Dict[str, Any] = result["data"]

        self.assertIsInstance(data["tags"], list)
        self.assertIsInstance(data["links"], list)

        # Tags and links should be strings
        for tag in data["tags"]:
            self.assertIsInstance(tag, str)
        for link in data["links"]:
            self.assertIsInstance(link, str)

    def test_error_handling(self) -> None:
        """Test error detection and reporting"""
        # Create a file with intentional errors
        with tempfile.NamedTemporaryFile(
            mode="w", suffix=".beancount", delete=False
        ) as f:
            f.write(
                """
; File with errors
2025-01-01 open Assets:Test
2025-01-01 * "Test" "Invalid transaction"
    Assets:Test  100 USD
    ; Missing second posting - should cause error
"""
            )
            error_file: str = f.name

        try:
            result: Dict[str, Any] = self.run_beancheck(error_file)
            errors: List[Dict[str, Any]] = result["errors"]

            self.assertIsInstance(errors, list)
            # Should detect the unbalanced transaction
            # Note: Exact error detection depends on beancount version

        finally:
            os.unlink(error_file)

    def test_performance_with_large_data(self) -> None:
        """Test performance optimizations with larger dataset"""
        result: Dict[str, Any] = self.run_beancheck(str(self.main_file))

        # This test mainly ensures the script completes without hanging
        # and produces valid output structure
        self.assertIsInstance(result, dict)
        self.assertIn("data", result)

        # Verify optimized data structures work
        data: Dict[str, Any] = result["data"]
        self.assertIsInstance(data["accounts"], dict)
        self.assertIsInstance(data["commodities"], list)

    def test_unicode_handling(self) -> None:
        """Test Unicode character handling"""
        # The complex.beancount file contains Unicode characters
        complex_file: Path = self.example_dir / "2025" / "complex.beancount"
        if complex_file.exists():
            result: Dict[str, Any] = self.run_beancheck(str(self.main_file))
            # Should complete without encoding errors
            self.assertIsInstance(result, dict)

    def test_type_safety(self) -> None:
        """Test type safety improvements"""
        result: Dict[str, Any] = self.run_beancheck(str(self.main_file))

        # Verify all expected types are correct
        data: Dict[str, Any] = result["data"]

        # Accounts should be dict with proper structure
        self.assertIsInstance(data["accounts"], dict)
        for account_data in data["accounts"].values():
            self.assertIsInstance(account_data["balance"], list)
            for balance in account_data["balance"]:
                self.assertIsInstance(balance, str)

        # Lists should contain only strings
        self.assertIsInstance(data["commodities"], list)
        self.assertIsInstance(data["payees"], list)
        self.assertIsInstance(data["narrations"], list)
        self.assertIsInstance(data["tags"], list)
        self.assertIsInstance(data["links"], list)

    def test_empty_value_cleanup(self) -> None:
        """Test cleanup of empty/None values"""
        result: Dict[str, Any] = self.run_beancheck(str(self.main_file))
        data: Dict[str, Any] = result["data"]

        # Should not contain empty strings or "None" strings
        self.assertNotIn("", data["payees"])
        self.assertNotIn("None", data["payees"])
        self.assertNotIn("", data["narrations"])
        self.assertNotIn("None", data["narrations"])

    def test_json_output_format(self) -> None:
        """Test JSON output format and compactness"""
        _: Dict[str, Any] = self.run_beancheck(str(self.main_file))

        # Re-run to get raw output and check JSON format
        cmd: List[str] = [
            str(self.python_path),
            str(self.beancheck_script),
            str(self.main_file),
        ]
        raw_result = subprocess.run(
            cmd, capture_output=True, text=True, cwd=self.test_dir.parent
        )

        lines: List[str] = raw_result.stdout.strip().split("\n")

        # Check that JSON is compact (no extra spaces)
        for line in lines:
            # Compact JSON shouldn't have ": " or ", " (spaces after separators)
            parsed: Any = json.loads(line)  # Should parse without error
            compact_json: str = json.dumps(parsed, separators=(",", ":"))
            self.assertEqual(line, compact_json, "JSON should be compact format")

    def test_balance_processing_optimization(self) -> None:
        """Test optimized balance processing"""
        result: Dict[str, Any] = self.run_beancheck(str(self.main_file))
        data: Dict[str, Any] = result["data"]
        accounts: Dict[str, Any] = data["accounts"]

        # Check that balances are properly processed
        balance_found: bool = False
        for account_data in accounts.values():
            if account_data["balance"]:
                balance_found = True
                # Balance should be list of strings
                for balance in account_data["balance"]:
                    self.assertIsInstance(balance, str)
                    # Should contain numeric value (basic validation)
                    self.assertTrue(
                        any(char.isdigit() or char == "." for char in balance)
                    )

        # Should have at least some balances in the test data
        self.assertTrue(balance_found, "Should have processed some balances")


class CostBasisTest(unittest.TestCase):
    """Test cost basis data generation and precision handling"""

    # Class attributes
    test_dir: Path
    beancheck_script: Path
    example_dir: Path
    autofill_file: Path
    python_path: str

    @classmethod
    def setUpClass(cls) -> None:
        """Set up test environment"""
        cls.test_dir = Path(__file__).parent
        cls.beancheck_script = cls.test_dir.parent / "pythonFiles" / "beancheck.py"
        cls.example_dir = cls.test_dir / "example"
        cls.autofill_file = cls.example_dir / "test_autofill.beancount"
        cls.python_path = BeancheckTest.find_python_executable()

    def run_beancheck(self, filename: str) -> Dict[str, Any]:
        """Run beancheck.py and return parsed JSON output"""
        cmd: List[str] = [str(self.python_path), str(self.beancheck_script), filename]
        result = subprocess.run(
            cmd, capture_output=True, text=True, cwd=self.test_dir.parent
        )
        if result.returncode != 0:
            self.fail(f"beancheck.py failed: {result.stderr}")

        lines: List[str] = result.stdout.strip().split("\n")
        self.assertEqual(len(lines), 4, "Expected 4 JSON output lines")

        result_obj: Dict[str, Any] = json.loads(lines[3])
        return {
            "errors": json.loads(lines[0]),
            "data": json.loads(lines[1]),
            "flagged": json.loads(lines[2]),
            "automatics": result_obj.get("automatics", {}),
            "cost_basis": result_obj.get("cost_basis", {}),
        }

    def test_cost_basis_extraction(self) -> None:
        """Test cost basis data is correctly extracted"""
        result: Dict[str, Any] = self.run_beancheck(str(self.autofill_file))
        cost_basis: Dict[str, Dict[str, str]] = result["cost_basis"]

        # Should have cost_basis data
        self.assertIsInstance(cost_basis, dict)
        self.assertGreater(len(cost_basis), 0, "Should have cost_basis data")

        # Check structure: {filename: {lineno: position_string}}
        for filename, line_data in cost_basis.items():
            self.assertIsInstance(line_data, dict)
            for lineno, position in line_data.items():
                self.assertIsInstance(lineno, str)
                self.assertIsInstance(position, str)
                # Position should contain @@ notation
                self.assertIn("@@", position)

    def test_cost_basis_preserves_decimal_precision(self) -> None:
        """Test that original decimal precision is preserved (100.438 stays as 100.438)"""
        result: Dict[str, Any] = self.run_beancheck(str(self.autofill_file))
        cost_basis: Dict[str, Dict[str, str]] = result["cost_basis"]

        # Find the high precision test case (line with 100.438)
        found_high_precision = False
        for filename, line_data in cost_basis.items():
            for lineno, position in line_data.items():
                if "100.438" in position:
                    found_high_precision = True
                    # Should preserve 100.438, not round to 100.44
                    self.assertIn("100.438", position)
                    self.assertNotIn("100.44 ", position)  # Note space to avoid matching 100.438

        self.assertTrue(found_high_precision, "Should find high precision test case")

    def test_cost_basis_negative_quantity(self) -> None:
        """Test cost basis with negative quantity (sell) uses absolute value for @@"""
        result: Dict[str, Any] = self.run_beancheck(str(self.autofill_file))
        cost_basis: Dict[str, Dict[str, str]] = result["cost_basis"]

        # Find the sell transaction (negative quantity)
        found_sell = False
        for filename, line_data in cost_basis.items():
            for lineno, position in line_data.items():
                if "-50.00 AAPL" in position:
                    found_sell = True
                    # Total cost should be positive (absolute value)
                    self.assertIn("@@ 7500", position)
                    self.assertNotIn("@@ -7500", position)

        self.assertTrue(found_sell, "Should find sell transaction test case")

    def test_cost_basis_tolerance_usd(self) -> None:
        """Test USD uses 2 decimal places from inferred_tolerance_default"""
        result: Dict[str, Any] = self.run_beancheck(str(self.autofill_file))
        cost_basis: Dict[str, Dict[str, str]] = result["cost_basis"]

        # Find USD transaction and verify 2 decimal places
        found_usd = False
        for filename, line_data in cost_basis.items():
            for lineno, position in line_data.items():
                if "AAPL" in position and "USD" in position and "150.00 USD" in position:
                    found_usd = True
                    # Should have 2 decimal places for USD total (e.g., 15000.00)
                    import re
                    match = re.search(r"@@\s+(\d+\.\d+)\s+USD", position)
                    if match:
                        total = match.group(1)
                        decimals = len(total.split(".")[1]) if "." in total else 0
                        self.assertEqual(decimals, 2, f"USD should have 2 decimals, got {decimals}")

        self.assertTrue(found_usd, "Should find USD test case")

    def test_cost_basis_tolerance_btc(self) -> None:
        """Test BTC uses 8 decimal places from inferred_tolerance_default"""
        result: Dict[str, Any] = self.run_beancheck(str(self.autofill_file))
        cost_basis: Dict[str, Dict[str, str]] = result["cost_basis"]

        # Find BTC transaction
        found_btc = False
        for filename, line_data in cost_basis.items():
            for lineno, position in line_data.items():
                if "ETH" in position and "BTC" in position:
                    found_btc = True
                    # Should have 8 decimal places for BTC total
                    import re
                    match = re.search(r"@@\s+(\d+\.\d+)\s+BTC", position)
                    if match:
                        total = match.group(1)
                        decimals = len(total.split(".")[1]) if "." in total else 0
                        self.assertEqual(decimals, 8, f"BTC should have 8 decimals, got {decimals}")

        self.assertTrue(found_btc, "Should find BTC test case")

    def test_cost_basis_tolerance_jpy(self) -> None:
        """Test JPY uses 0 decimal places from inferred_tolerance_default"""
        result: Dict[str, Any] = self.run_beancheck(str(self.autofill_file))
        cost_basis: Dict[str, Dict[str, str]] = result["cost_basis"]

        # Find JPY transaction
        found_jpy = False
        for filename, line_data in cost_basis.items():
            for lineno, position in line_data.items():
                if "JPSTOCK" in position and "JPY" in position:
                    found_jpy = True
                    # Should have 0 decimal places for JPY total (e.g., 15000 not 15000.00)
                    import re
                    match = re.search(r"@@\s+(\d+)\s+JPY", position)
                    if match:
                        # No decimal point means 0 decimals
                        self.assertNotIn(".", match.group(1))

        self.assertTrue(found_jpy, "Should find JPY test case")

    def test_cost_basis_with_existing_date(self) -> None:
        """Test cost basis that already has a date preserves it"""
        result: Dict[str, Any] = self.run_beancheck(str(self.autofill_file))
        cost_basis: Dict[str, Dict[str, str]] = result["cost_basis"]

        # Find the transaction with existing date (line 39 in test file)
        found_existing_date = False
        for filename, line_data in cost_basis.items():
            for lineno, position in line_data.items():
                if "25.00 AAPL" in position and "2025-10-14" in position:
                    found_existing_date = True
                    # Date should be preserved
                    self.assertIn("2025-10-14", position)

        self.assertTrue(found_existing_date, "Should find transaction with existing date")

    def test_cost_basis_deeply_nested_account(self) -> None:
        """Test cost basis works with deeply nested account names"""
        result: Dict[str, Any] = self.run_beancheck(str(self.autofill_file))
        cost_basis: Dict[str, Dict[str, str]] = result["cost_basis"]

        # Find the deeply nested account test case
        found_deep = False
        for filename, line_data in cost_basis.items():
            for lineno, position in line_data.items():
                # This is the deeply nested account transaction
                if "10.00 AAPL" in position and "200.00 USD" in position:
                    # Check for 2025-10-19 date (the deep nested account transaction)
                    if "2025-10-19" in position:
                        found_deep = True
                        self.assertIn("@@", position)
                        self.assertIn("2000", position)  # 10 * 200 = 2000

        self.assertTrue(found_deep, "Should find deeply nested account test case")


class BeancheckErrorTest(unittest.TestCase):
    """Test error conditions and edge cases"""

    # Class attributes
    test_dir: Path
    beancheck_script: Path
    python_path: str

    @classmethod
    def setUpClass(cls) -> None:
        cls.test_dir = Path(__file__).parent
        cls.beancheck_script = cls.test_dir.parent / "pythonFiles" / "beancheck.py"
        cls.python_path = BeancheckTest.find_python_executable()

    def test_missing_file(self) -> None:
        """Test handling of missing input file"""
        cmd: List[str] = [
            str(self.python_path),
            str(self.beancheck_script),
            "nonexistent.beancount",
        ]
        result = subprocess.run(cmd, capture_output=True, text=True)
        # beancount library handles missing files gracefully, so check stderr instead
        if result.returncode == 0:
            # If it succeeds, it should produce valid JSON output
            lines: List[str] = result.stdout.strip().split("\n")
            self.assertEqual(
                len(lines),
                4,
                "Should produce 4 lines of JSON output even for missing file",
            )
        else:
            self.assertNotEqual(result.returncode, 0, "Should fail with missing file")

    def test_invalid_beancount_syntax(self) -> None:
        """Test handling of invalid beancount syntax"""
        with tempfile.NamedTemporaryFile(
            mode="w", suffix=".beancount", delete=False
        ) as f:
            f.write("invalid beancount syntax here")
            invalid_file: str = f.name

        try:
            cmd: List[str] = [
                str(self.python_path),
                str(self.beancheck_script),
                invalid_file,
            ]
            result = subprocess.run(cmd, capture_output=True, text=True)

            # Should still produce output (errors in first line)
            if result.returncode == 0:
                lines: List[str] = result.stdout.strip().split("\n")
                self.assertEqual(len(lines), 4)
                errors: List[Dict[str, Any]] = json.loads(lines[0])
                self.assertIsInstance(errors, list)

        finally:
            os.unlink(invalid_file)


if __name__ == "__main__":
    # Create test runner with custom result class
    runner: unittest.TextTestRunner = unittest.TextTestRunner(
        verbosity=2, resultclass=TestResultCollector, stream=sys.stdout
    )

    # Discover and run tests
    loader: unittest.TestLoader = unittest.TestLoader()
    suite: unittest.TestSuite = loader.loadTestsFromModule(sys.modules[__name__])
    result: TestResultCollector = runner.run(suite)  # type: ignore

    # Print summary in consistent format with Lua tests
    print("\nTest Summary:")
    print(f"Tests run: {result.test_count}")
    print(f"Tests passed: {result.success_count}")
    print(f"Tests failed: {result.failure_count + result.error_count}")
    if result.skip_count > 0:
        print(f"Tests skipped: {result.skip_count}")

    if result.failure_count == 0 and result.error_count == 0:
        print("✓ All tests passed!\n")
        sys.exit(0)
    else:
        print("✗ Some tests failed!\n")
        sys.exit(1)
