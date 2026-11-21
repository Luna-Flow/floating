"""Tests of `itl_oracle_checks.py`: which checks exist, how a missing corpus is reported, and
that a hand-edited refinement is caught.

Oracle of the last test: the exact hull of `itl_pow2_reverse_oracle.py` (Python `decimal` and
`fractions`; no code of this library; level A). The other tests are plumbing (no numeric oracle).
"""

import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import itl_oracle_checks as checks
import itl_pow2_reverse_oracle as pow2_oracle


class RegistryTest(unittest.TestCase):
    def test_every_oracle_program_has_a_check(self) -> None:
        self.assertEqual(
            [check.name for check in checks.CHECKS],
            ["trig-reverse", "pow-reverse-1", "pow-reverse-2", "refinements", "atan2-reverse"],
        )
        self.assertEqual(
            [check.name for check in checks.CHECKS if not check.needs_corpus], ["atan2-reverse"]
        )


class MissingCorpusTest(unittest.TestCase):
    def run_without_corpus(self, require: bool) -> tuple[tuple[int, int, int], str]:
        stream = io.StringIO()
        with tempfile.TemporaryDirectory() as directory:
            calls: list[str] = []
            fake = tuple(
                checks.Check(check.name, lambda name=check.name: calls.append(name) or 0, check.needs_corpus)
                for check in checks.CHECKS
            )
            counts = checks.run_checks(fake, require, corpus=Path(directory), stream=stream)
        return counts, stream.getvalue()

    def test_a_missing_corpus_is_reported_as_skipped_with_a_count(self) -> None:
        (passed, failed, skipped), text = self.run_without_corpus(False)
        self.assertEqual((passed, failed, skipped), (1, 0, 4))
        self.assertEqual(text.count("SKIP  "), 4)
        self.assertIn("PASS  atan2-reverse", text)

    def test_a_missing_corpus_fails_when_it_is_required(self) -> None:
        (passed, failed, skipped), text = self.run_without_corpus(True)
        self.assertEqual((passed, failed, skipped), (1, 4, 0))
        self.assertIn("FAIL  trig-reverse: the ITF1788 corpus is missing", text)

    def test_a_failing_check_is_a_failure_with_its_output(self) -> None:
        def broken() -> int:
            print("DISAGREEMENT somewhere")
            return 1

        stream = io.StringIO()
        counts = checks.run_checks((checks.Check("broken", broken, False),), True, stream=stream)
        self.assertEqual(counts, (0, 1, 0))
        self.assertIn("DISAGREEMENT somewhere", stream.getvalue())

    def test_main_fails_without_a_passing_check(self) -> None:
        with mock.patch.object(checks, "CHECKS", ()):
            self.assertEqual(checks.main([]), 1)


class HandEditedRefinementTest(unittest.TestCase):
    def test_an_edited_powrev2_refinement_is_caught(self) -> None:
        if not (pow2_oracle.CORPUS / pow2_oracle.FILE).exists():
            self.skipTest("the ITF1788 corpus is not installed")
        document = json.loads(pow2_oracle.REFINEMENTS.read_text(encoding="utf-8"))
        entries = [entry for entry in document["refinements"] if entry["operation"] == "powRev2"]
        self.assertEqual(len(entries), 2)
        entries[0]["refined"] = entries[0]["corpus"]  # a refinement that no longer refines
        with tempfile.TemporaryDirectory() as directory:
            edited = Path(directory) / "interpreter_refinements.json"
            edited.write_text(json.dumps(document), encoding="utf-8")
            with mock.patch.object(pow2_oracle, "REFINEMENTS", edited):
                with mock.patch("sys.stdout", new_callable=io.StringIO):
                    self.assertEqual(pow2_oracle.main([]), 1)


if __name__ == "__main__":
    unittest.main()
