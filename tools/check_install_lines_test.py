from __future__ import annotations

import shutil
import tempfile
import unittest
from pathlib import Path

import check_install_lines as cil

OK = "```bash\nmoon add Luna-Flow/floating@0.12.0\n```\n"


class StaleLinesTest(unittest.TestCase):
    def test_matching_line_passes(self) -> None:
        self.assertEqual(cil.stale_lines(OK, "0.12.0"), [])

    def test_old_version_fails(self) -> None:
        text = "x\nmoon add Luna-Flow/floating@0.11.0\n"
        self.assertEqual(cil.stale_lines(text, "0.12.0"), [(2, "0.11.0")])

    def test_pre_label_fails_against_release(self) -> None:
        self.assertEqual(cil.stale_lines("moon add Luna-Flow/floating@0.12.0-pre", "0.12.0"), [(1, "0.12.0-pre")])

    def test_release_fails_against_pre(self) -> None:
        self.assertEqual(cil.stale_lines(OK, "0.12.0-pre"), [(2, "0.12.0")])

    def test_inline_code_in_prose(self) -> None:
        text = "run `moon add Luna-Flow/floating@0.10.2` now"
        self.assertEqual(cil.stale_lines(text, "0.12.0"), [(1, "0.10.2")])

    def test_tools_module_is_not_checked(self) -> None:
        self.assertEqual(cil.stale_lines("moon add Luna-Flow/floating-tools@0.1.0", "0.12.0"), [])

    def test_history_block_is_skipped(self) -> None:
        text = "```bash history\nmoon add Luna-Flow/floating@0.10.2\n```\nmoon add Luna-Flow/floating@0.10.2\n"
        self.assertEqual(cil.stale_lines(text, "0.12.0"), [(4, "0.10.2")])

    def test_plain_block_is_not_skipped(self) -> None:
        text = "```bash\nmoon add Luna-Flow/floating@0.10.2\n```\n"
        self.assertEqual(cil.stale_lines(text, "0.12.0"), [(2, "0.10.2")])

    def test_library_version(self) -> None:
        self.assertEqual(cil.library_version('name = "a"\n\nversion = "0.12.0"\n'), "0.12.0")
        self.assertIsNone(cil.library_version("name = 1\n"))


class MainTest(unittest.TestCase):
    def make_root(self, page: str) -> Path:
        root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, root)
        (root / "library").mkdir()
        (root / "library/moon.mod").write_text('version = "0.12.0"\n')
        (root / "doc/manual/tutorial").mkdir(parents=True)
        (root / "doc/manual/tutorial/a.md").write_text(page)
        return root

    def test_clean_tree(self) -> None:
        self.assertEqual(cil.main(["--root", str(self.make_root(OK))]), 0)

    def test_stale_tree(self) -> None:
        self.assertEqual(cil.main(["--root", str(self.make_root(OK.replace("0.12.0", "0.11.0")))]), 1)

    def test_missing_version(self) -> None:
        root = self.make_root(OK)
        (root / "library/moon.mod").write_text("name = 1\n")
        self.assertEqual(cil.main(["--root", str(root)]), 1)


if __name__ == "__main__":
    unittest.main()
