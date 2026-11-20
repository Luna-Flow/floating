import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

import check_package_contents as tool

GOOD_MOD = 'name = "Luna-Flow/floating"\n\nversion = "0.11.0"\n\nimport {\n  "Luna-Flow/arithmetic@0.5.2",\n  "Luna-Flow/luna-generic@0.4.0",\n}\n\nsource = "src"\n'
TOOLS_MOD = 'name = "Luna-Flow/floating-tools"\n\nversion = "0.11.0"\n\nimport {\n  "Luna-Flow/floating@0.11.0",\n  "moonbitlang/x@0.5.7",\n}\n\nsource = "src"\n'
LIBRARY_NAMES = ["moon.mod", "README.md", "LICENSE", "CHANGELOG.md", "src/def/a.mbt"]
TOOLS_NAMES = ["moon.mod", "LICENSE", "src/bench/a.mbt"]


class LibraryTests(unittest.TestCase):
    def test_the_expected_shape_passes(self) -> None:
        self.assertEqual(tool.violations("library", LIBRARY_NAMES, GOOD_MOD), [])

    def test_anything_outside_the_directory_files_is_rejected(self) -> None:
        names = [*LIBRARY_NAMES, "doc/x.md", "testdata/a", "tools/x.py", "justfile", "CONTRIBUTING.md", "moon.work", "tooling/moon.mod"]
        found = tool.violations("library", names, GOOD_MOD)
        self.assertEqual(len(found), 1)
        self.assertIn("7 packed paths", found[0])
        self.assertEqual(
            tool.unexpected_paths(names, tool.LIBRARY_TOP_LEVEL_FILES),
            ["doc/x.md", "testdata/a", "tools/x.py", "justfile", "CONTRIBUTING.md", "moon.work", "tooling/moon.mod"],
        )

    def test_generated_sources_are_rejected_in_every_module(self) -> None:
        generated = [
            "src/decimal/ieee_corpus_generated_00_wbtest.mbt",
            "src/_generated_doc_examples/getting_started/README.mbt.md",
            "src/.generated_dectest/a.mbt",
            "src/consistency/_generated_dectest_wbtest.mbt",
        ]
        self.assertEqual(tool.generated_paths([*LIBRARY_NAMES, *generated]), generated)
        for module, names, mod in (("library", LIBRARY_NAMES, GOOD_MOD), ("tools", TOOLS_NAMES, TOOLS_MOD)):
            found = tool.violations(module, [*names, *generated], mod, "0.11.0")
            self.assertEqual(len(found), 1, found)
            self.assertIn("4 packed paths are generated sources", found[0])

    def test_a_missing_required_file_is_reported(self) -> None:
        self.assertEqual(
            tool.violations("library", ["moon.mod", "README.md", "LICENSE", "src/a.mbt"], GOOD_MOD),
            ["the zip of the library module has no CHANGELOG.md"],
        )

    def test_a_tooling_dependency_in_the_packed_manifest_is_rejected(self) -> None:
        mod = GOOD_MOD.replace('}\n\nsource', '  "Luna-Flow/mare_mark@0.4.2",\n}\n\nsource')
        self.assertEqual(
            tool.violations("library", LIBRARY_NAMES, mod),
            ["packed moon.mod must not import Luna-Flow/mare_mark"],
        )

    def test_a_missing_dependency_is_reported(self) -> None:
        mod = 'name = "Luna-Flow/floating"\n\nimport {\n  "Luna-Flow/arithmetic@0.5.2",\n}\n'
        self.assertEqual(
            tool.violations("library", LIBRARY_NAMES, mod),
            ["packed moon.mod does not import Luna-Flow/luna-generic"],
        )

    def test_comments_in_the_import_block_are_ignored(self) -> None:
        mod = GOOD_MOD.replace('  "Luna-Flow/luna-generic', '  // "moonbitlang/x@0.5.7",\n  "Luna-Flow/luna-generic')
        self.assertEqual(tool.violations("library", LIBRARY_NAMES, mod), [])


class ToolsTests(unittest.TestCase):
    def test_the_expected_shape_passes(self) -> None:
        self.assertEqual(tool.violations("tools", TOOLS_NAMES, TOOLS_MOD, "0.11.0"), [])
        optional = [*TOOLS_NAMES, "README.md", "CHANGELOG.md"]
        self.assertEqual(tool.violations("tools", optional, TOOLS_MOD, "0.11.0"), [])

    def test_paths_of_the_library_or_the_repository_are_rejected(self) -> None:
        names = [*TOOLS_NAMES, "doc/x.md", "tools/x.py", "testdata/a", "moon.work", "justfile"]
        found = tool.violations("tools", names, TOOLS_MOD, "0.11.0")
        self.assertEqual(len(found), 1)
        self.assertIn("5 packed paths", found[0])

    def test_a_missing_licence_is_reported(self) -> None:
        self.assertEqual(
            tool.violations("tools", ["moon.mod", "src/a.mbt"], TOOLS_MOD, "0.11.0"),
            ["the zip of the tools module has no LICENSE"],
        )

    def test_the_version_and_the_pinned_library_version_must_match_the_library(self) -> None:
        stale_version = TOOLS_MOD.replace('version = "0.11.0"', 'version = "0.10.2"')
        self.assertEqual(
            tool.violations("tools", TOOLS_NAMES, stale_version, "0.11.0"),
            ["packed moon.mod has version 0.10.2, but the library version is 0.11.0"],
        )
        stale_pin = TOOLS_MOD.replace("floating@0.11.0", "floating@0.10.2")
        self.assertEqual(
            tool.violations("tools", TOOLS_NAMES, stale_pin, "0.11.0"),
            ["packed moon.mod imports Luna-Flow/floating@0.10.2, but the library version is 0.11.0"],
        )
        no_pin = 'name = "x"\n\nversion = "0.11.0"\n\nimport {\n  "moonbitlang/x@0.5.7",\n}\n'
        self.assertEqual(
            tool.violations("tools", TOOLS_NAMES, no_pin, "0.11.0"),
            ["packed moon.mod must import Luna-Flow/floating@0.11.0"],
        )

    def test_the_library_import_rule_does_not_apply_to_the_tools_module(self) -> None:
        self.assertEqual(tool.violations("tools", TOOLS_NAMES, TOOLS_MOD, "0.11.0"), [])


class CommandTests(unittest.TestCase):
    def test_each_module_is_packaged_from_its_own_directory(self) -> None:
        self.assertEqual(
            tool.package_command("library"),
            ["sh", "tools/run_moon_clean_exec.sh", "-C", "library", "package", "--frozen"],
        )
        self.assertEqual(
            tool.package_command("tools"),
            ["sh", "tools/run_moon_clean_exec.sh", "-C", "tooling", "package", "--frozen"],
        )
        self.assertFalse(any("publish" in word for word in tool.package_command("library")))

    def test_the_library_version_is_read_from_the_library_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            (Path(directory) / "library").mkdir()
            (Path(directory) / "library" / "moon.mod").write_text('name = "x"\n\nversion = "1.2.3"\n', encoding="utf-8")
            self.assertEqual(tool.library_version(Path(directory)), "1.2.3")


class ZipTests(unittest.TestCase):
    def make_zip(self, directory: str, entries: dict[str, str], name: str = "pkg.zip") -> Path:
        path = Path(directory) / name
        with zipfile.ZipFile(path, "w") as archive:
            for name, text in entries.items():
                archive.writestr(name, text)
        return path

    def entries(self, names: list[str], moon_mod: str) -> dict[str, str]:
        return {name: (moon_mod if name == "moon.mod" else "") for name in names}

    def test_inspect_zip_reads_names_and_the_packed_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            good = self.make_zip(directory, self.entries(LIBRARY_NAMES, GOOD_MOD))
            self.assertEqual(tool.inspect_zip(good), [])
            bad = self.make_zip(directory, self.entries([*LIBRARY_NAMES, "doc/x.md", "moon.work"], GOOD_MOD))
            self.assertIn("2 packed paths", tool.inspect_zip(bad)[0])
            tools = self.make_zip(directory, self.entries(TOOLS_NAMES, TOOLS_MOD))
            self.assertEqual(tool.inspect_zip(tools, "tools", "0.11.0"), [])

    def test_main_reports_violations_with_exit_status_one(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            (Path(directory) / "library").mkdir()
            (Path(directory) / "library" / "moon.mod").write_text('name = "x"\n\nversion = "0.11.0"\n', encoding="utf-8")
            bad = self.make_zip(directory, self.entries([*LIBRARY_NAMES, "moon.work"], GOOD_MOD))
            with patch.object(tool, "build_zip", return_value=bad):
                self.assertEqual(tool.main(["--root", directory]), 1)
            good = self.make_zip(directory, self.entries(LIBRARY_NAMES, GOOD_MOD), "good.zip")
            with patch.object(tool, "build_zip", return_value=good):
                self.assertEqual(tool.main(["--root", directory]), 0)
            tools = self.make_zip(directory, self.entries(TOOLS_NAMES, TOOLS_MOD), "tools.zip")
            with patch.object(tool, "build_zip", return_value=tools):
                self.assertEqual(tool.main(["--module", "tools", "--root", directory]), 0)
            zips = {"library": good, "tools": tools}
            with patch.object(tool, "build_zip", side_effect=lambda root, module: zips[module]):
                self.assertEqual(tool.main(["--module", "all", "--root", directory]), 0)
                zips["tools"] = self.make_zip(directory, self.entries([*TOOLS_NAMES, "doc/x.md"], TOOLS_MOD), "bad-tools.zip")
                self.assertEqual(tool.main(["--module", "all", "--root", directory]), 1)


if __name__ == "__main__":
    unittest.main()
