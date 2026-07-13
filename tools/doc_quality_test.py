import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import doc_quality


class DocumentationQualityTests(unittest.TestCase):
    def test_normalized_examples_ignore_trailing_space(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "tutorial.md"
            path.write_text("```moonbit check\ntest {  \n}\n```\n", encoding="utf-8")
            self.assertEqual(doc_quality.normalized_examples(path), ["test {\n}"])

    def test_example_shapes_use_test_names(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "tutorial.md"
            path.write_text('```moonbit check\ntest "workflow" {}\n```\n', encoding="utf-8")
            self.assertEqual(doc_quality.example_shapes(path), ["workflow"])

    def test_locale_parity_rejects_extra_files(self) -> None:
        with patch.object(doc_quality, "markdown_files") as files:
            files.side_effect = lambda locale: (
                {"README.md", "extra.md"} if locale == "zh_CN" else {"README.md"}
            )
            self.assertEqual(
                doc_quality.check_locale_parity(),
                ["zh_CN: extra files: extra.md"],
            )

    def test_heading_levels_preserve_order(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "api.md"
            path.write_text("# Package\n\n## API\n\n### Detail\n", encoding="utf-8")
            self.assertEqual(doc_quality.heading_levels(path), (1, 2, 3))
            self.assertEqual(doc_quality.heading_shape(path), (1, 1))

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
        with patch.object(doc_quality, "package_paths", return_value={"example"}):
            with tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                with patch.object(doc_quality, "DOC_ROOT", root / "doc"):
                    with patch.object(doc_quality, "REPO_ROOT", root):
                        self.assertTrue(doc_quality.check_package_doc_coverage())

if __name__ == "__main__":
    unittest.main()
