import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import run_python_tests as runner


class ProtectedWriteTests(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name).resolve()
        (self.root / "library/src").mkdir(parents=True)
        (self.root / "tools").mkdir()

    def test_a_write_below_a_protected_directory_is_recorded_even_if_the_file_is_removed(self) -> None:
        target = self.root / "library/src/generated_wbtest.mbt"
        with runner.record_protected_writes(self.root) as hits:
            target.write_text("x", encoding="utf-8")
            target.unlink()
        self.assertFalse(target.exists())
        self.assertIn("Path.write_text library/src/generated_wbtest.mbt", hits)
        self.assertIn("Path.unlink library/src/generated_wbtest.mbt", hits)

    def test_open_os_and_shutil_writes_are_recorded(self) -> None:
        with runner.record_protected_writes(self.root) as hits:
            with open(self.root / "library/a.txt", "w", encoding="utf-8") as stream:
                stream.write("a")
            os.makedirs(self.root / "doc/new")
            shutil.copy(self.root / "library/a.txt", self.root / "library/b.txt")
            shutil.rmtree(self.root / "doc/new")
        # `makedirs` and `copy` call `mkdir` and `open` themselves: assert inclusion.
        for expected in ("open library/a.txt", "os.makedirs doc/new", "shutil.copy library/b.txt", "shutil.rmtree doc/new"):
            self.assertIn(expected, hits)

    def test_reads_and_writes_elsewhere_are_not_recorded(self) -> None:
        (self.root / "library/read.txt").write_text("r", encoding="utf-8")
        with runner.record_protected_writes(self.root) as hits:
            (self.root / "library/read.txt").read_text(encoding="utf-8")
            with open(self.root / "library/read.txt", encoding="utf-8") as stream:
                stream.read()
            (self.root / "tools/scratch.txt").write_text("w", encoding="utf-8")
            with tempfile.TemporaryDirectory() as other:
                (Path(other) / "x").write_text("w", encoding="utf-8")
        self.assertEqual(hits, [])

    def test_the_patches_are_removed_afterwards(self) -> None:
        original = Path.write_text
        with runner.record_protected_writes(self.root):
            pass
        self.assertIs(Path.write_text, original)

    def test_protected_relative(self) -> None:
        self.assertEqual(runner.protected_relative(self.root / "testdata/a", self.root), "testdata/a")
        self.assertIsNone(runner.protected_relative(self.root / "tools/a", self.root))
        self.assertIsNone(runner.protected_relative("/definitely/elsewhere", self.root))


class SkipSummaryTests(unittest.TestCase):
    def test_skips_are_counted_by_reason(self) -> None:
        skipped = [(None, "the ITF1788 corpus is not installed")] * 3 + [(None, "no MPFR")]
        self.assertEqual(
            runner.skip_summary(skipped),
            [
                "run_python_tests: 4 tests skipped:",
                "  1 x no MPFR",
                "  3 x the ITF1788 corpus is not installed",
            ],
        )

    def test_no_skip_is_still_one_line(self) -> None:
        self.assertEqual(runner.skip_summary([]), ["run_python_tests: 0 tests skipped"])


class StatusComparisonTests(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name).resolve()
        for command in (["git", "init", "-q", "-b", "main"], ["git", "config", "user.email", "t@example.invalid"], ["git", "config", "user.name", "t"]):
            subprocess.run(command, cwd=self.root, check=True)
        (self.root / "library/src").mkdir(parents=True)
        (self.root / "tooling/src").mkdir(parents=True)
        (self.root / "library/src/kept.mbt").write_text("kept", encoding="utf-8")
        (self.root / ".gitignore").write_text("library/src/decimal/ieee_corpus_generated_*_wbtest.mbt\n", encoding="utf-8")
        subprocess.run(["git", "add", "-A"], cwd=self.root, check=True)
        subprocess.run(["git", "commit", "-q", "-m", "init"], cwd=self.root, check=True)

    def status(self) -> str:
        return runner.git_status(self.root)

    def test_a_concurrent_stage_writing_generated_sources_is_not_a_difference(self) -> None:
        before = self.status()
        for relative in (
            "library/src/_generated_doc_examples/tutorial_a/README.mbt.md",
            "tooling/src/_generated_doc_examples/api_b/README.mbt.md",
            "library/src/decimal/ieee_corpus_generated_00_wbtest.mbt",
        ):
            path = self.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("generated", encoding="utf-8")
        during = self.status()
        self.assertNotEqual(before, during)  # git sees them ...
        self.assertEqual(runner.status_difference(before, during), [])  # ... the guard does not care
        shutil.rmtree(self.root / "library/src/_generated_doc_examples")
        self.assertEqual(runner.status_difference(during, self.status()), [])

    def test_a_stray_write_of_a_test_subprocess_is_still_a_difference(self) -> None:
        before = self.status()
        # A test's subprocess writes a source file the in-process recorder cannot see.
        subprocess.run(
            [sys.executable, "-c", "import sys, pathlib; pathlib.Path(sys.argv[1], 'library/src/stray_wbtest.mbt').write_text('x')", str(self.root)],
            check=True,
        )
        difference = runner.status_difference(before, self.status())
        self.assertEqual(difference, ["+ ?? library/src/stray_wbtest.mbt"])
        # An edit of a tracked file is a difference too.
        (self.root / "library/src/kept.mbt").write_text("edited", encoding="utf-8")
        self.assertIn("+  M library/src/kept.mbt", runner.status_difference(before, self.status()))

    def test_a_stray_write_next_to_generated_files_is_still_reported(self) -> None:
        before = self.status()
        generated = self.root / "library/src/_generated_doc_examples/p/README.mbt.md"
        generated.parent.mkdir(parents=True)
        generated.write_text("g", encoding="utf-8")
        (self.root / "tooling/src/stray.mbt").write_text("x", encoding="utf-8")
        self.assertEqual(runner.status_difference(before, self.status()), ["+ ?? tooling/src/stray.mbt"])

    def test_the_marker_list_is_the_one_of_the_package_check(self) -> None:
        import check_package_contents
        import generated_paths

        self.assertIs(check_package_contents.GENERATED_MARKERS, generated_paths.GENERATED_MARKERS)
        self.assertTrue(generated_paths.is_generated_path("library/src/decimal/ieee_corpus_generated_03_wbtest.mbt"))
        self.assertFalse(generated_paths.is_generated_path("library/src/decimal/ordinary_wbtest.mbt"))


if __name__ == "__main__":
    unittest.main()
