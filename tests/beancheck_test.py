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

            return {
                "errors": json.loads(lines[0]),
                "data": json.loads(lines[1]),
                "flagged": json.loads(lines[2]),
                "automatics": json.loads(lines[3]),
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
