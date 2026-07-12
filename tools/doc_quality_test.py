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

    def test_locale_only_research_is_excluded_from_parity(self) -> None:
        with patch.object(doc_quality, "markdown_files") as files:
            files.side_effect = lambda locale: {"README.md"} | (
                {"ball_float/ieee1788_research.md"} if locale == "zh_CN" else set()
            )
            self.assertEqual(doc_quality.check_locale_parity(), [])

    def test_heading_shape_counts_public_sections(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "api.md"
            path.write_text("# Package\n\n## API\n\n### Detail\n", encoding="utf-8")
            self.assertEqual(doc_quality.heading_shape(path), (1, 1))


if __name__ == "__main__":
    unittest.main()
