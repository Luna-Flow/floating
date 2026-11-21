import tempfile
import unittest
from contextlib import ExitStack
from pathlib import Path
from unittest.mock import patch

import doc_quality


def use_repo(stack: ExitStack, root: Path) -> None:
    stack.enter_context(patch.object(doc_quality, "REPO_ROOT", root))
    stack.enter_context(patch.object(doc_quality, "DOC_ROOT", root / "doc"))
    stack.enter_context(patch.object(doc_quality, "MANUAL_ROOT", root / "doc" / "manual"))
    stack.enter_context(patch.object(doc_quality, "LOCALE_ROOT", root / "doc" / "locale"))
    stack.enter_context(
        patch.object(doc_quality, "ATTACHMENT_ROOT", root / "doc" / "attachments")
    )


class DocumentationQualityTests(unittest.TestCase):
    def test_retired_locale_trees_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory, ExitStack() as stack:
            root = Path(directory)
            (root / "doc" / "zh_CN").mkdir(parents=True)
            use_repo(stack, root)
            errors = doc_quality.check_retired_layout()
        self.assertEqual(len(errors), 1)
        self.assertTrue(errors[0].startswith("doc/zh_CN: retired per-locale tree"))

    def test_read_catalog_joins_continuations_and_references(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "manual.po"
            path.write_text(
                'msgid ""\nmsgstr ""\n"Language: ja_JP\\n"\n\n'
                "#: manual/index.md:3\n#: manual/api/decimal.md:4\n"
                'msgid "a \\"b\\""\nmsgstr ""\n"c"\n"d"\n',
                encoding="utf-8",
            )
            self.assertEqual(
                doc_quality.read_catalog(path),
                [(["manual/index.md:3", "manual/api/decimal.md:4"], 'a "b"', "cd")],
            )

    def test_github_anchor_normalizes_heading(self) -> None:
        self.assertEqual(doc_quality.github_anchor("API And Flags"), "api-and-flags")

    def test_api_snapshot_detects_stale_interface(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "api.md"
            path.write_text(
                "<!-- generated-api-start -->\n```moonbit\nold\n```\n"
                "<!-- generated-api-end -->\n",
                encoding="utf-8",
            )
            self.assertIsNotNone(doc_quality.API_BLOCK_RE.search(path.read_text()))

    def test_cited_evidence_paths_must_exist(self) -> None:
        with tempfile.TemporaryDirectory() as directory, ExitStack() as stack:
            root = Path(directory)
            page = root / "doc" / "manual" / "conformance" / "bin_float.md"
            page.parent.mkdir(parents=True)
            (root / "library" / "src").mkdir(parents=True)
            (root / "library" / "src" / "present_wbtest.mbt").write_text("", encoding="utf-8")
            page.write_text(
                "| `library/src/present_wbtest.mbt` | `library/src/missing_wbtest.mbt` |\n",
                encoding="utf-8",
            )
            use_repo(stack, root)
            errors = doc_quality.check_evidence_paths()
            self.assertEqual(len(errors), 1)
            self.assertIn("library/src/missing_wbtest.mbt", errors[0])

    def test_conformance_functions_must_exist_in_the_interface(self) -> None:
        with tempfile.TemporaryDirectory() as directory, ExitStack() as stack:
            root = Path(directory)
            page = root / "doc" / "manual" / "conformance" / "decimal.md"
            page.parent.mkdir(parents=True)
            package = root / "library" / "src" / "decimal"
            package.mkdir(parents=True)
            (package / "moon.pkg").write_text("", encoding="utf-8")
            (package / "pkg.generated.mbti").write_text(
                "pub fn Decimal::total_order(Self, Self) -> Bool\n", encoding="utf-8"
            )
            page.write_text(
                "| Clause | Level | API | Evidence |\n"
                "| --- | --- | --- | --- |\n"
                "| totalOrder | required | `Decimal::total_order`, `compare_total_ctx`, `_ctx`, `a b` | `x.mbt` |\n"
                "| not a function column | `missing_name` |\n",
                encoding="utf-8",
            )
            use_repo(stack, root)
            errors = doc_quality.check_conformance_functions()
            self.assertEqual(len(errors), 1)
            self.assertIn("`compare_total_ctx`", errors[0])
            self.assertIn("decimal.md:3", errors[0])

    def test_conformance_checklist_counts_follow_the_tables(self) -> None:
        import conformance_checklist

        self.assertEqual(conformance_checklist.classify("conforming; extension"), "conforming")
        self.assertEqual(conformance_checklist.classify("partial: no rSqrt"), "partial")
        self.assertEqual(conformance_checklist.classify("not implemented by design"), "not implemented")
        self.assertEqual(conformance_checklist.classify("not applicable"), "not applicable")
        with self.assertRaises(ValueError):
            conformance_checklist.classify("probably fine")
        self.assertEqual(doc_quality.check_conformance_checklist(), [])

    def test_package_coverage_uses_all_moon_packages(self) -> None:
        with patch.object(doc_quality, "package_paths", return_value={"nested/example"}):
            with tempfile.TemporaryDirectory() as directory, ExitStack() as stack:
                root = Path(directory)
                use_repo(stack, root)
                errors = doc_quality.check_package_doc_coverage()
        self.assertIn("doc/manual: missing api/nested/example.md", errors)
        self.assertIn("doc/manual: missing tutorial/nested/example.md", errors)
        self.assertIn("doc/manual: missing design/nested/example.md", errors)
        self.assertIn("doc/manual: missing conformance/decimal_gda.md", errors)
        self.assertIn("doc/manual: missing index.md", errors)

    def test_package_paths_ignore_only_underscored_source_directories(self) -> None:
        with tempfile.TemporaryDirectory() as directory, ExitStack() as stack:
            root = Path(directory) / "_checkout"
            for relative in ("core", "nested/leaf", "_generated_doc_examples/page"):
                (root / "library" / "src" / relative).mkdir(parents=True)
                (root / "library" / "src" / relative / "moon.pkg").write_text("", encoding="utf-8")
            use_repo(stack, root)
            self.assertEqual(doc_quality.package_paths(), {"core", "nested/leaf"})

    def test_package_paths_cover_the_library_and_the_tools_module(self) -> None:
        with tempfile.TemporaryDirectory() as directory, ExitStack() as stack:
            root = Path(directory)
            for relative in ("library/src/core", "tooling/src/bench/leaf"):
                (root / relative).mkdir(parents=True)
                (root / relative / "moon.pkg").write_text("", encoding="utf-8")
            use_repo(stack, root)
            self.assertEqual(doc_quality.package_paths(), {"core", "bench/leaf"})
            self.assertEqual(doc_quality.package_directory("bench/leaf"), root / "tooling/src/bench/leaf")

    def test_a_main_package_keeps_a_plain_readme_and_no_mbt_md(self) -> None:
        with tempfile.TemporaryDirectory() as directory, ExitStack() as stack:
            root = Path(directory)
            for relative, pkg in (
                ("library/src/lib", ""),
                ("tooling/src/main", 'pkgtype(kind: "executable")\n'),
            ):
                (root / relative).mkdir(parents=True)
                (root / relative / "moon.pkg").write_text(pkg, encoding="utf-8")
            (root / "library/src/lib/README.mbt.md").write_text("x", encoding="utf-8")
            use_repo(stack, root)
            self.assertEqual(
                doc_quality.check_package_readme_coverage(),
                ["tooling/src/main: missing README.md"],
            )
            (root / "tooling/src/main/README.md").write_text("x", encoding="utf-8")
            (root / "tooling/src/main/README.mbt.md").write_text("x", encoding="utf-8")
            self.assertEqual(
                doc_quality.check_package_readme_coverage(),
                ["tooling/src/main: a main package must not hold .mbt.md files"],
            )

    def test_the_tooling_standard_flags_missing_sections_items_and_examples(self) -> None:
        api = "# p API\n\n## Purpose\n\n## Importing\n\n### `run`\n\n## Complete public interface\n"
        tutorial = (
            "# p tutorial\n\n| I want to | Use |\n| --- | --- |\n\n## Quick start\n\n```moonbit\nlet a = 1\n```\n\n"
            "## Everyday tasks\n\n## Going further\n\n## Common pitfalls\n\n## Next steps\n"
        )
        design = "# p design\n\n" + "".join(f"## {t}\n\n" for t in doc_quality.TOOLING_DESIGN_HEADINGS)
        mbti = "pub fn run(Array[String]) -> Int32\npub fn Counter::total(Self) -> Int32\n"
        errors = doc_quality.tooling_standard_errors("p", api, tutorial, design, mbti)
        self.assertEqual(errors, ["doc/manual/api/p.md: public items without a heading: total"])
        thin_tutorial = "# p tutorial\n\n## Quick start\n\n```moonbit nocheck\nlet a = 1\n```\n"
        errors = doc_quality.tooling_standard_errors("p", api.replace("### `run`", "### `run`, `total`"), thin_tutorial, "# d\n", mbti)
        self.assertIn("doc/manual/tutorial/p.md: missing the | I want to | Use | table", errors)
        self.assertIn("doc/manual/tutorial/p.md: missing section Going further", errors)
        self.assertIn("doc/manual/tutorial/p.md: no example that compiles", errors)
        self.assertIn("doc/manual/design/p.md: missing section Alternatives rejected", errors)
        self.assertEqual(doc_quality.mbti_items(mbti), ["run", "total"])
        # An asynchronous package is exempt from the compiled example.
        self.assertNotIn(
            "doc/manual/tutorial/differential/harness.md: no example that compiles",
            doc_quality.tooling_standard_errors("differential/harness", api.replace("### `run`", "### `run`, `total`"), thin_tutorial, design, mbti),
        )

    def test_orphan_pages_need_a_moon_package(self) -> None:
        with patch.object(doc_quality, "package_paths", return_value={"example"}):
            with tempfile.TemporaryDirectory() as directory, ExitStack() as stack:
                root = Path(directory)
                manual = root / "doc" / "manual"
                for relative in ("index.md", "notes.md", "api/example.md", "api/gone.md", "drafts/x.md"):
                    (manual / relative).parent.mkdir(parents=True, exist_ok=True)
                    (manual / relative).write_text("# Page\n", encoding="utf-8")
                use_repo(stack, root)
                self.assertEqual(
                    doc_quality.check_orphan_pages(),
                    [
                        "doc/manual/api/gone.md: no gone/moon.pkg package below src or tooling/src",
                        "doc/manual/drafts/x.md: drafts/ is not a chapter",
                        "doc/manual/notes.md: unlisted guide",
                    ],
                )

    def test_current_versions_follow_moon_mod_and_changelog(self) -> None:
        with tempfile.TemporaryDirectory() as directory, ExitStack() as stack:
            root = Path(directory)
            (root / "doc" / "manual").mkdir(parents=True)
            (root / "library").mkdir()
            (root / "library" / "moon.mod").write_text('version = "0.6.1"\n', encoding="utf-8")
            (root / "library" / "CHANGELOG.md").write_text(
                "## 0.6.1 - 2026-07-14\n\n## 0.6.0 - 2026-07-14\n",
                encoding="utf-8",
            )
            (root / "README.md").write_text("Current 0.6.1\n", encoding="utf-8")
            (root / "CONTRIBUTING.md").write_text("Stale 0.6.0\n", encoding="utf-8")
            use_repo(stack, root)
            self.assertEqual(
                doc_quality.check_current_versions(),
                ["CONTRIBUTING.md: stale 0.6.0 baseline; current is 0.6.1"],
            )

    def test_the_latest_published_release_may_be_named_as_such(self) -> None:
        with tempfile.TemporaryDirectory() as directory, ExitStack() as stack:
            root = Path(directory)
            (root / "doc" / "manual").mkdir(parents=True)
            (root / "library").mkdir()
            (root / "library" / "moon.mod").write_text('version = "0.7.0"\n', encoding="utf-8")
            (root / "library" / "CHANGELOG.md").write_text("## Unreleased\n\n## 0.6.1\n", encoding="utf-8")
            (root / "README.md").write_text(
                "moon add Luna-Flow/floating@0.6.1\n"
                "The latest published release is 0.6.1.\n"
                "Baseline file summary-0.6.1.json.\n"
                "The toolchain 0.6.10 and moonc v0.6.11 are not the version.\n",
                encoding="utf-8",
            )
            (root / "CONTRIBUTING.md").write_text("The baseline is 0.6.1.\n", encoding="utf-8")
            use_repo(stack, root)
            self.assertEqual(
                doc_quality.check_current_versions(),
                ["CONTRIBUTING.md: stale 0.6.1 baseline; current is 0.7.0"],
            )

    def test_translations_may_not_add_stale_versions(self) -> None:
        with tempfile.TemporaryDirectory() as directory, ExitStack() as stack:
            root = Path(directory)
            catalog = root / "doc" / "locale" / "ja_JP" / "LC_MESSAGES" / "manual.po"
            catalog.parent.mkdir(parents=True)
            (root / "doc" / "conf.json").write_text('{"locales": ["ja_JP"]}', encoding="utf-8")
            (root / "library").mkdir()
            (root / "library" / "moon.mod").write_text('version = "0.6.1"\n', encoding="utf-8")
            (root / "library" / "CHANGELOG.md").write_text("## 0.6.1\n\n## 0.6.0\n", encoding="utf-8")
            catalog.write_text(
                '#: manual/index.md:1\nmsgid "Since 0.6.0"\nmsgstr "0.6.0 以降"\n\n'
                '#: manual/index.md:2\nmsgid "Current"\nmsgstr "0.6.0 現在"\n',
                encoding="utf-8",
            )
            use_repo(stack, root)
            self.assertEqual(
                doc_quality.check_translated_versions(),
                [
                    "doc/locale/ja_JP/LC_MESSAGES/manual.po: manual/index.md:2: "
                    "translation adds stale 0.6.0 baseline"
                ],
            )

    def test_explicit_historical_performance_baseline_is_allowed(self) -> None:
        text = "<!-- historical-performance-baseline: 0.6.1 -->\n0.6.1"
        self.assertEqual(
            set(doc_quality.HISTORICAL_BASELINE_RE.findall(text)), {"0.6.1"}
        )

if __name__ == "__main__":
    unittest.main()
