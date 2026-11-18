import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import check_imports

MODULE = check_imports.MODULE


def write_pkg(src: Path, directory: str, text: str) -> None:
    path = src / directory / "moon.pkg"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


CLEAN_DECIMAL = f'import {{\n  "{MODULE}/def",\n  "moonbitlang/core/bigint",\n}}\n'


class ImportsOfTests(unittest.TestCase):
    def test_reads_aliases_comments_and_test_blocks(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "moon.pkg"
            path.write_text(
                'import {\n  "a/b" @x,\n  // "c/d",\n  "e/f",\n}\n\nimport {\n  "g/h",\n} for "test"\n',
                encoding="utf-8",
            )
            self.assertEqual(check_imports.imports_of(path), ["a/b", "e/f", "g/h"])


class ViolationsTests(unittest.TestCase):
    def setUp(self) -> None:
        # The restricted packages of the real repository do not exist in the
        # temporary trees below; the tests that need one register their own.
        patcher = patch.dict(check_imports.ALLOWED_MODULE_IMPORTS, {}, clear=True)
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_clean_tree_passes(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            src = Path(tmp)
            write_pkg(src, "decimal", CLEAN_DECIMAL)
            write_pkg(src, "decimal_gda", CLEAN_DECIMAL)
            self.assertEqual(check_imports.violations(src), [])

    def test_decimal_importing_gda_fails(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            src = Path(tmp)
            write_pkg(src, "decimal", f'import {{\n  "{MODULE}/decimal_gda" @gda,\n}}\n')
            write_pkg(src, "decimal_gda", CLEAN_DECIMAL)
            self.assertEqual(
                check_imports.violations(src),
                [f"src/decimal must not import {MODULE}/decimal_gda"],
            )

    def test_gda_importing_decimal_in_test_block_fails(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            src = Path(tmp)
            write_pkg(src, "decimal", CLEAN_DECIMAL)
            write_pkg(
                src,
                "decimal_gda",
                CLEAN_DECIMAL + f'import {{\n  "{MODULE}/decimal",\n}} for "wbtest"\n',
            )
            self.assertEqual(
                check_imports.violations(src),
                [f"src/decimal_gda must not import {MODULE}/decimal"],
            )

    def test_similar_package_names_are_not_confused(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            src = Path(tmp)
            write_pkg(src, "decimal", CLEAN_DECIMAL + f'import {{\n  "{MODULE}/decimal_checked",\n}}\n')
            write_pkg(src, "decimal_gda", CLEAN_DECIMAL)
            self.assertEqual(check_imports.violations(src), [])

    def test_missing_package_is_reported(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(len(check_imports.violations(Path(tmp))), 2)

    def test_restricted_package_may_only_import_the_allowed_paths(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            src = Path(tmp)
            write_pkg(src, "decimal", CLEAN_DECIMAL)
            write_pkg(src, "decimal_gda", CLEAN_DECIMAL)
            write_pkg(src, "kernel", f'import {{\n  "moonbitlang/core/bigint",\n  "{MODULE}/def",\n}}\n')
            with patch.dict(check_imports.ALLOWED_MODULE_IMPORTS, {"kernel": ()}, clear=True):
                self.assertEqual(
                    check_imports.violations(src),
                    [f"src/kernel must not import {MODULE}/def"],
                )


class RepositoryTests(unittest.TestCase):
    def test_the_shared_kernel_is_restricted(self) -> None:
        self.assertIn("internal/decimal_kernel", check_imports.ALLOWED_MODULE_IMPORTS)

    def test_this_repository_satisfies_the_rules(self) -> None:
        self.assertEqual(check_imports.violations(check_imports.REPO_ROOT / "src"), [])


if __name__ == "__main__":
    unittest.main()
