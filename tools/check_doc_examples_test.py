import unittest
from pathlib import Path

import check_doc_examples as tool


def page(slug: str) -> tool.Page:
    return tool.Page(
        path=tool.MANUAL_ROOT / f"{slug}.md",
        slug=slug,
        blocks=("test \"x\" { assert_eq(1, 1) }",),
        aliases=(),
        unknown_aliases=(),
    )


class DocExamplesTests(unittest.TestCase):
    def test_one_moon_call_covers_every_page(self) -> None:
        directories = [tool.GENERATED_ROOT / "a", tool.GENERATED_ROOT / "b"]
        command = tool.moon_test_command(directories, "native")
        self.assertEqual(command.count("test"), 1)
        self.assertEqual(
            command[3:5],
            ("src/_generated_doc_examples/a", "src/_generated_doc_examples/b"),
        )
        self.assertEqual(command[-2:], ("--target", "native"))

    def test_totals_come_from_the_last_summary_line(self) -> None:
        output = "Total tests: 1, passed: 1, failed: 0.\nTotal tests: 271, passed: 270, failed: 1.\n"
        self.assertEqual(tool.parse_totals(output), (271, 270, 1))
        self.assertIsNone(tool.parse_totals("no summary"))

    def test_failures_are_attributed_to_pages_by_package_directory(self) -> None:
        pages = [page("getting_started"), page("verification")]
        output = "[Luna-Flow/floating/_generated_doc_examples/verification] test ... src/_generated_doc_examples/verification/README.mbt.md:12 failed"
        self.assertEqual([p.slug for p in tool.failing_pages(output, pages)], ["verification"])
        self.assertEqual(tool.failing_pages("other output", pages), [])

    def test_checkable_blocks_skip_nocheck(self) -> None:
        text = "```moonbit\nlet a = 1\n```\n```moonbit nocheck\nlet b = 2\n```\n"
        self.assertEqual(tool.checkable_blocks(text), ["let a = 1"])


if __name__ == "__main__":
    unittest.main()
