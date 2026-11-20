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


def write_library(root: Path, manifest_imports: tuple[str, ...], package_imports: tuple[str, ...]) -> None:
    body = "".join(f'  "{name}",\n' for name in manifest_imports)
    (root / "library").mkdir(exist_ok=True)
    (root / "library" / "moon.mod").write_text(f'name = "{MODULE}"\n\nimport {{\n{body}}}\n', encoding="utf-8")
    body = "".join(f'  "{name}",\n' for name in package_imports)
    write_pkg(root / "library" / "src", "bin_float", f"import {{\n{body}}}\n")


class ModuleViolationsTests(unittest.TestCase):
    def test_library_with_its_two_dependencies_passes(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write_library(
                root,
                ("Luna-Flow/arithmetic@0.5.2", "Luna-Flow/luna-generic@0.4.0"),
                ("Luna-Flow/arithmetic", "moonbitlang/core/bigint", f"{MODULE}/def"),
            )
            self.assertEqual(check_imports.module_violations(root), [])

    def test_a_tooling_dependency_in_moon_mod_fails(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write_library(root, ("Luna-Flow/arithmetic@0.5.2", "Luna-Flow/mare_mark@0.4.2"), ())
            self.assertEqual(
                check_imports.module_violations(root),
                ["library/moon.mod must not depend on Luna-Flow/mare_mark"],
            )

    def test_a_package_importing_the_tools_module_or_a_foreign_module_fails(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write_library(
                root,
                ("Luna-Flow/arithmetic@0.5.2",),
                ("Luna-Flow/floating-tools/bench", "moonbitlang/async"),
            )
            self.assertEqual(
                check_imports.module_violations(root),
                [
                    "library/src/bin_float/moon.pkg must not import Luna-Flow/floating-tools/bench",
                    "library/src/bin_float/moon.pkg must not import moonbitlang/async",
                ],
            )


class LicenseTests(unittest.TestCase):
    def write(self, root: Path, texts: dict[str, str]) -> None:
        for name, text in texts.items():
            path = root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding="utf-8")

    def test_identical_licenses_pass(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.write(root, {name: "Apache\n" for name in check_imports.LICENSE_FILES})
            self.assertEqual(check_imports.license_violations(root), [])

    def test_a_differing_or_missing_license_fails(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.write(root, {"LICENSE": "Apache\n", "library/LICENSE": "Apache \n"})
            self.assertEqual(
                check_imports.license_violations(root),
                ["tooling/LICENSE is missing", "library/LICENSE differs from LICENSE"],
            )

    def test_the_repository_licenses_are_identical(self) -> None:
        self.assertEqual(check_imports.license_violations(check_imports.REPO_ROOT), [])


def write_versions(root: Path, library: str, tools: str | None, pinned: str | None) -> None:
    (root / "library").mkdir(exist_ok=True)
    (root / "tooling").mkdir(exist_ok=True)
    (root / "library" / "moon.mod").write_text(f'name = "{MODULE}"\n\nversion = "{library}"\n', encoding="utf-8")
    head = f'name = "{MODULE}-tools"\n\n' + ("" if tools is None else f'version = "{tools}"\n\n')
    body = "" if pinned is None else f'  "{MODULE}@{pinned}",\n'
    (root / "tooling" / "moon.mod").write_text(f"{head}import {{\n{body}}}\n", encoding="utf-8")


class VersionTests(unittest.TestCase):
    def violations(self, library: str, tools: str | None, pinned: str | None) -> list[str]:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write_versions(root, library, tools, pinned)
            return check_imports.version_violations(root)

    def test_three_equal_versions_pass(self) -> None:
        self.assertEqual(self.violations("0.11.0", "0.11.0", "0.11.0"), [])

    def test_a_different_tools_version_fails(self) -> None:
        self.assertEqual(
            self.violations("0.11.0", "0.10.2", "0.11.0"),
            ["tooling/moon.mod has version 0.10.2, but library/moon.mod has version 0.11.0"],
        )

    def test_a_different_pinned_library_version_fails(self) -> None:
        self.assertEqual(
            self.violations("0.11.0", "0.11.0", "0.10.2"),
            [f"tooling/moon.mod imports {MODULE}@0.10.2, but library/moon.mod has version 0.11.0"],
        )

    def test_a_missing_tools_version_or_library_import_fails(self) -> None:
        self.assertEqual(
            self.violations("0.11.0", None, "0.11.0"),
            ["tooling/moon.mod declares no version"],
        )
        self.assertEqual(
            self.violations("0.11.0", "0.11.0", None),
            [f"tooling/moon.mod must import {MODULE}@0.11.0"],
        )

    def test_the_repository_versions_agree(self) -> None:
        self.assertEqual(check_imports.version_violations(check_imports.REPO_ROOT), [])


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
                [f"library/src/decimal must not import {MODULE}/decimal_gda"],
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
                [f"library/src/decimal_gda must not import {MODULE}/decimal"],
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
                    [f"library/src/kernel must not import {MODULE}/def"],
                )


class RepositoryTests(unittest.TestCase):
    def test_the_shared_kernel_is_restricted(self) -> None:
        self.assertIn("internal/decimal_kernel", check_imports.ALLOWED_MODULE_IMPORTS)

    def test_this_repository_satisfies_the_rules(self) -> None:
        self.assertEqual(check_imports.violations(check_imports.REPO_ROOT / "library" / "src"), [])


if __name__ == "__main__":
    unittest.main()
