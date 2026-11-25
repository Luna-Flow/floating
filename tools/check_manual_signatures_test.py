from __future__ import annotations

import shutil
import tempfile
import unittest
from pathlib import Path

import check_manual_signatures as sig

PAGE = """# x

```mbti
pub fn Foo::size(Self) -> Int
pub fn Foo::keep(Self) -> Bool
pub fn Foo::gone(Self) -> Bool
#derive(Eq)
type Private
pub struct Foo(@k.Repr) derive(@debug.Debug)
```

```moonbit
pub fn Foo::size(Self) -> Int
```
"""

INTERFACE = """package "p/foo"

pub fn Foo::keep(Self) -> Bool
pub fn Foo::size(Self) -> Int32
#derive(@debug.Debug)
pub struct Foo(@k.Repr)
"""


class LineKeyTest(unittest.TestCase):
    def test_fn_key_stops_at_parameters(self) -> None:
        self.assertEqual(sig.line_key("pub fn  Foo::size(Self) -> Int"), "pub fn Foo::size")

    def test_generic_fn_and_impl(self) -> None:
        self.assertEqual(sig.line_key("pub fn[T : Eq] f(T) -> T"), "pub fn[T : Eq] f")
        self.assertEqual(sig.line_key("pub impl Show for Foo with output(Self, &Logger) -> Unit"), "pub impl Show for Foo with output")

    def test_let_struct_enum(self) -> None:
        self.assertEqual(sig.line_key("pub let max : Int"), "pub let max")
        self.assertEqual(sig.line_key("pub struct A {"), "pub struct A")
        self.assertEqual(sig.line_key("pub struct A(Int) derive(Eq)"), "pub struct A")
        self.assertEqual(sig.line_key("pub(all) enum E {"), "pub(all) enum E")

    def test_non_pub_has_no_key(self) -> None:
        self.assertEqual(sig.line_key("type Private"), "type Private")
        self.assertIsNone(sig.line_key("#derive(Eq)"))
        self.assertIsNone(sig.line_key("  fn indented(Self) -> Int"))
        self.assertIsNone(sig.line_key("  // private fields"))


def items_of(page: str) -> list[sig.Item]:
    return [item for block in sig.mbti_blocks(page) for item in sig.parse_items(block)]


def differences(page: str, interface: str) -> list[sig.Difference]:
    return sig.compare("p.md", items_of(page), sig.interface_items(interface))


class BlockTest(unittest.TestCase):
    def test_only_mbti_fences(self) -> None:
        blocks = sig.mbti_blocks(PAGE)
        self.assertEqual(len(blocks), 1)
        self.assertEqual(blocks[0][0], (4, "pub fn Foo::size(Self) -> Int"))
        self.assertEqual(len(blocks[0]), 6)

    def test_items_take_attributes_and_bodies(self) -> None:
        text = "```mbti\n#derive(Eq)\npub struct A {\n  f : Int\n}\npub fn g() -> Unit\n```\n"
        items = items_of(text)
        self.assertEqual([i.key for i in items], ["pub struct A", "pub fn g"])
        self.assertEqual(items[0].first, 2)
        self.assertEqual(len(items[0].lines), 4)


class CompareTest(unittest.TestCase):
    def test_line_differences(self) -> None:
        diffs = differences(PAGE, INTERFACE)
        self.assertEqual([(d.line, d.new) for d in diffs], [
            (4, ("pub fn Foo::size(Self) -> Int32",)),
            (6, None),
            (7, None),
            (9, ("#derive(@debug.Debug)", "pub struct Foo(@k.Repr)")),
        ])

    def test_whitespace_is_normalised(self) -> None:
        page = "```mbti\npub fn  Foo::keep(Self)   -> Bool\n```\n"
        self.assertEqual(differences(page, INTERFACE), [])

    def test_field_line_of_a_struct(self) -> None:
        iface = "pub struct S {\n  n : Int32\n}\n"
        page = "```mbti\npub struct S {\n  n : Int\n}\n```\n"
        diffs = differences(page, iface)
        self.assertEqual(len(diffs), 1)
        self.assertEqual(diffs[0].new, ("pub struct S {", "  n : Int32", "}"))
        self.assertEqual(differences(page.replace("Int\n", "Int32\n"), iface), [])

    def test_enum_variant_and_attribute(self) -> None:
        iface = "#derive(Eq)\npub(all) enum E {\n  A\n  B(Int32)\n}\n"
        self.assertEqual(len(differences("```mbti\n#derive(Eq)\npub(all) enum E {\n  A\n}\n```\n", iface)), 1)
        self.assertEqual(len(differences("```mbti\npub(all) enum E {\n  A\n  B(Int32)\n}\n```\n", iface)), 1)

    def test_derive_closing_differs_from_attribute_line(self) -> None:
        iface = "#derive(Eq)\npub struct S {\n  // private fields\n}\n"
        page = "```mbti\npub struct S {\n  // private fields\n} derive(Eq)\n```\n"
        diffs = differences(page, iface)
        self.assertEqual([d.new for d in diffs], [("#derive(Eq)", "pub struct S {", "  // private fields", "}")])
        fixed = sig.apply_fixes(page, diffs)
        self.assertEqual(differences(fixed, iface), [])

    def test_trait_method_alone_or_in_trait(self) -> None:
        iface = "pub(open) trait T {\n  fn size(Self) -> Int32\n}\n"
        alone = "```mbti\nfn size(Self) -> Int\n```\n"
        self.assertEqual([d.new for d in differences(alone, iface)], [("fn size(Self) -> Int32",)])
        inside = "```mbti\npub(open) trait T {\n  fn sign(Self) -> Int32\n}\n```\n"
        self.assertEqual([d.new for d in differences(inside, iface)], [("pub(open) trait T {", "  fn size(Self) -> Int32", "}")])
        self.assertEqual([d.new for d in differences("```mbti\nfn sign(Self) -> Int32\n```\n", iface)], [None])

    def test_item_without_counterpart_is_not_fixed(self) -> None:
        page = "```mbti\npub struct Gone {\n  n : Int\n}\n```\n"
        diffs = differences(page, INTERFACE)
        self.assertEqual([d.new for d in diffs], [None])
        self.assertEqual(sig.apply_fixes(page, diffs), page)

    def test_apply_fixes_changes_only_paired_items(self) -> None:
        diffs = differences(PAGE, INTERFACE)
        fixed = sig.apply_fixes(PAGE, diffs).split("\n")
        self.assertIn("pub fn Foo::size(Self) -> Int32", fixed)
        self.assertIn("pub fn Foo::gone(Self) -> Bool", fixed)
        self.assertEqual(fixed[0:3], PAGE.split("\n")[0:3])


class MainTest(unittest.TestCase):
    def test_check_and_fix_on_a_tree(self) -> None:
        root = Path(tempfile.mkdtemp())
        try:
            (root / "doc/manual/api").mkdir(parents=True)
            (root / "doc/manual/api/foo.md").write_text(PAGE)
            (root / "library/src/foo").mkdir(parents=True)
            (root / "library/src/foo/pkg.generated.mbti").write_text(INTERFACE)
            self.assertEqual(sig.main(["--check", "--root", str(root)]), 1)
            self.assertEqual(sig.main(["--fix", "--root", str(root)]), 0)
            self.assertIn("pub fn Foo::size(Self) -> Int32", (root / "doc/manual/api/foo.md").read_text())
            self.assertEqual(sig.main(["--check", "--root", str(root)]), 1)  # the unpaired line stays
        finally:
            shutil.rmtree(root)


if __name__ == "__main__":
    unittest.main()
