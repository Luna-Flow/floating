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
        self.assertIsNone(sig.line_key("type Private"))
        self.assertIsNone(sig.line_key("  // private fields"))


class BlockTest(unittest.TestCase):
    def test_only_mbti_fences(self) -> None:
        lines = sig.mbti_blocks(PAGE)
        self.assertEqual(lines[0], (4, "pub fn Foo::size(Self) -> Int"))
        self.assertEqual(len(lines), 6)


class CompareTest(unittest.TestCase):
    def test_differences(self) -> None:
        diffs = sig.compare("p.md", sig.mbti_blocks(PAGE), sig.interface_lines(INTERFACE))
        self.assertEqual([(d.line, d.new) for d in diffs], [
            (4, "pub fn Foo::size(Self) -> Int32"),
            (6, None),
            (9, "pub struct Foo(@k.Repr)"),
        ])

    def test_whitespace_is_normalised(self) -> None:
        page = [(1, "pub fn  Foo::keep(Self)   -> Bool")]
        self.assertEqual(sig.compare("p.md", page, sig.interface_lines(INTERFACE)), [])

    def test_apply_fixes_changes_only_paired_lines(self) -> None:
        diffs = sig.compare("p.md", sig.mbti_blocks(PAGE), sig.interface_lines(INTERFACE))
        fixed = sig.apply_fixes(PAGE, diffs).split("\n")
        original = PAGE.split("\n")
        changed = [i + 1 for i, (a, b) in enumerate(zip(original, fixed)) if a != b]
        self.assertEqual(changed, [4, 9])
        self.assertEqual(len(original), len(fixed))


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
