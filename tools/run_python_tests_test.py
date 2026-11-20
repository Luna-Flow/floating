import os
import shutil
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


if __name__ == "__main__":
    unittest.main()
