import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import run_elementary_performance_gate as gate


class ElementaryPerformanceGateTests(unittest.TestCase):
    def test_manifest_pins_real_baseline_and_maremark_policy(self) -> None:
        manifest = gate.load_manifest(gate.DEFAULT_MANIFEST)
        baseline = manifest["baseline"]

        def git_output(*arguments: str) -> str:
            revision = arguments[-1]
            if revision == baseline["commit"]:
                return baseline["commit"]
            if revision == f'{baseline["commit"]}^{{tree}}':
                return baseline["tree"]
            raise AssertionError(f"unexpected git revision: {revision}")

        with patch.object(gate, "git_output", side_effect=git_output):
            gate.verify_manifest(manifest)
        self.assertEqual(manifest["pairedSamples"], 10)
        self.assertEqual(manifest["practicalRegressionPct"], 3.0)
        self.assertEqual(manifest["confidencePct"], 95.0)

    def test_parser_requires_checksum_and_nine_runs(self) -> None:
        records = [{"name": "add/53bit", "runs": 9, "median": 1.0}]
        output = (
            "ELEMENTARY_BASELINE_CHECKSUM=elementary-baseline-v1\n"
            "ELEMENTARY_BASELINE_JSON=" + json.dumps(records)
        )
        self.assertEqual(
            gate.parse_records(output, "elementary-baseline-v1"), records
        )
        records[0]["runs"] = 8
        with self.assertRaisesRegex(ValueError, "fewer than nine"):
            gate.parse_records(
                "ELEMENTARY_BASELINE_CHECKSUM=elementary-baseline-v1\n"
                "ELEMENTARY_BASELINE_JSON=" + json.dumps(records),
                "elementary-baseline-v1",
            )

    def test_generated_gate_uses_maremark_significance(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "src/bench").mkdir(parents=True)
            path = gate.write_maremark_gate(
                root,
                {
                    "add/53bit": {
                        "baseline": [1.0] * 10,
                        "candidate": [1.1] * 10,
                    }
                },
            )
            source = path.read_text(encoding="utf-8")
            self.assertIn("confirmatory_regression", source)
            self.assertIn("is_significant_regression", source)


if __name__ == "__main__":
    unittest.main()
