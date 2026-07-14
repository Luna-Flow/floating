import unittest
from unittest.mock import patch

import run_docs


class RunDocsTests(unittest.TestCase):
    def test_stops_when_quality_checks_fail(self) -> None:
        with patch.object(run_docs.doc_quality, "main", return_value=3):
            with patch.object(run_docs.subprocess, "run") as run:
                self.assertEqual(run_docs.main([]), 3)
        run.assert_not_called()

    def test_runs_examples_after_quality_checks(self) -> None:
        with patch.object(run_docs.doc_quality, "main", return_value=0):
            with patch.object(run_docs.subprocess, "run") as run:
                run.return_value.returncode = 5
                self.assertEqual(run_docs.main([]), 5)
        self.assertIn("src/doc_examples", run.call_args.args[0])
        self.assertIn("--frozen", run.call_args.args[0])


if __name__ == "__main__":
    unittest.main()
