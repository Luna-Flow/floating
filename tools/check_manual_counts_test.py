from __future__ import annotations

import shutil
import tempfile
import unittest
from pathlib import Path

import check_manual_counts as check

REPO = check.REPO
FILES = (
    "testdata/bin_float/corpora.json",
    "testdata/bin_float/smoke/manifest.json",
    "testdata/bin_float/mpfr-4.2.2-elementary.txt",
    "testdata/bin_float/mpfr-4.2.2-strtofr.txt",
    "testdata/bin_float/mpfr-4.2.2-decimal-output.txt",
    "doc/manual/verification.md",
    "doc/manual/conformance/bin_float.md",
    "testdata/bin_float/README.md",
)


class ManualCountsTest(unittest.TestCase):
    def copy_repository(self) -> Path:
        root = Path(tempfile.mkdtemp(prefix="manual-counts-"))
        self.addCleanup(shutil.rmtree, root, True)
        for name in FILES:
            target = root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(REPO / name, target)
        return root

    def test_the_repository_pages_match_the_manifests(self) -> None:
        self.assertEqual(check.check(), [])

    def test_a_stale_count_is_reported(self) -> None:
        root = self.copy_repository()
        page = root / "doc/manual/verification.md"
        page.write_text(page.read_text().replace("1,434 `mpfr_strtofr`", "1,716 `mpfr_strtofr`"))
        problems = check.check(root)
        self.assertEqual(len(problems), 1)
        self.assertIn("1,716", problems[0])
        self.assertIn("1,434", problems[0])

    def test_a_page_that_changed_shape_is_reported(self) -> None:
        root = self.copy_repository()
        page = root / "testdata/bin_float/README.md"
        page.write_text(page.read_text().replace("MPFR-generated integer-power witnesses", "witnesses"))
        problems = check.check(root)
        self.assertEqual(len(problems), 1)
        self.assertIn("changed shape", problems[0])

    def test_a_manifest_that_disagrees_with_its_file_is_reported(self) -> None:
        root = self.copy_repository()
        manifest = root / "testdata/bin_float/corpora.json"
        manifest.write_text(manifest.read_text().replace('"expectedCases": 1740', '"expectedCases": 1741'))
        with self.assertRaises(ValueError):
            check.manifest_counts(root)


if __name__ == "__main__":
    unittest.main()
