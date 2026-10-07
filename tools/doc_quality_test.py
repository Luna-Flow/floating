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
                        "doc/manual/api/gone.md: no src/gone/moon.pkg package",
                        "doc/manual/drafts/x.md: drafts/ is not a chapter",
                        "doc/manual/notes.md: unlisted guide",
                    ],
                )

    def test_current_versions_follow_moon_mod_and_changelog(self) -> None:
        with tempfile.TemporaryDirectory() as directory, ExitStack() as stack:
            root = Path(directory)
            (root / "doc" / "manual").mkdir(parents=True)
            (root / "moon.mod").write_text('version = "0.6.1"\n', encoding="utf-8")
            (root / "CHANGELOG.md").write_text(
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

    def test_translations_may_not_add_stale_versions(self) -> None:
        with tempfile.TemporaryDirectory() as directory, ExitStack() as stack:
            root = Path(directory)
            catalog = root / "doc" / "locale" / "ja_JP" / "LC_MESSAGES" / "manual.po"
            catalog.parent.mkdir(parents=True)
            (root / "doc" / "conf.json").write_text('{"locales": ["ja_JP"]}', encoding="utf-8")
            (root / "moon.mod").write_text('version = "0.6.1"\n', encoding="utf-8")
            (root / "CHANGELOG.md").write_text("## 0.6.1\n\n## 0.6.0\n", encoding="utf-8")
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
