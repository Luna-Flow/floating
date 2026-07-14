import unittest
from contextlib import redirect_stderr, redirect_stdout
from io import StringIO
from unittest.mock import patch

import benchmark


class BenchmarkDispatcherTests(unittest.TestCase):
    def test_forwards_arguments_to_selected_suite(self) -> None:
        received: list[str] = []

        def run(arguments: list[str] | None) -> int:
            received.extend(arguments or [])
            return 9

        with patch.dict(benchmark.BENCHMARKS, {"binary": run}, clear=True):
            self.assertEqual(benchmark.main(["binary", "--target", "native"]), 9)
        self.assertEqual(received, ["--target", "native"])

    def test_missing_suite_is_rejected(self) -> None:
        with redirect_stderr(StringIO()):
            self.assertEqual(benchmark.main([]), 2)

    def test_unknown_suite_is_rejected(self) -> None:
        with redirect_stderr(StringIO()):
            self.assertEqual(benchmark.main(["unknown"]), 2)

    def test_help_prints_usage(self) -> None:
        output = StringIO()
        with redirect_stdout(output):
            self.assertEqual(benchmark.main(["--help"]), 0)
        self.assertIn("decimal-threshold", output.getvalue())


if __name__ == "__main__":
    unittest.main()
