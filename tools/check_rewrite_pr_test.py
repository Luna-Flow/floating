from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

import check_rewrite_pr as check


def po(*messages: tuple[str, str, str], header: bool = True) -> str:
    """A PO text from (refs, msgid, msgstr); `flags` go in the refs field after a '|'."""
    out = ['msgid ""', 'msgstr ""', '"Language: x\\n"', ""] if header else []
    for refs, msgid, msgstr in messages:
        refs, _, extra = refs.partition("|")
        out += [f"#: {refs}"]
        if extra:
            out.append(extra)
        out += [f'msgid "{msgid}"', f'msgstr "{msgstr}"', ""]
    return "\n".join(out)


class QuantifierTest(unittest.TestCase):
    def drift(self, old: str, new: str) -> list[str]:
        return [word for _, word, _ in check.quantifier_drift(old, new)]

    def test_lost_always_is_reported(self) -> None:
        self.assertEqual(self.drift("A signaling NaN always has a payload.\n", "A signaling NaN has a payload.\n"), ["always"])

    def test_lost_never_and_only(self) -> None:
        old = "Conversions never abort.\nThe value is the same; only the flag differs.\n"
        new = "Conversions do not abort.\nThe value is the same, the flags differ.\n"
        self.assertEqual(self.drift(old, new), ["never", "only"])

    def test_lost_multiword(self) -> None:
        self.assertEqual(self.drift("It holds at most two limbs.\n", "It holds two limbs.\n"), ["at most"])

    def test_kept_word_is_not_reported(self) -> None:
        self.assertEqual(self.drift("It never aborts.\n", "The call never aborts, whatever the input.\n"), [])

    def test_unchanged_lines_are_not_reported(self) -> None:
        self.assertEqual(self.drift("It never aborts.\nOne.\n", "It never aborts.\nTwo.\n"), [])

    def test_word_inside_fenced_code_is_ignored(self) -> None:
        old = "Text.\n```moonbit\n// never\n```\n"
        new = "Text.\n```moonbit\n// seldom\n```\n"
        self.assertEqual(self.drift(old, new), [])

    def test_substring_is_not_a_word(self) -> None:
        self.assertEqual(self.drift("The mustard stays.\n", "The relish stays.\n"), [])

    def test_real_case_825_exactly_one(self) -> None:
        old = "`sinpi(0.5)` is exactly one, and the function knows it: exact results raise no flag.\n"
        new = "`sinpi(0.5)` is one, so exact results raise no flag.\n"
        self.assertEqual(self.drift(old, new), ["exactly"])

    def test_line_is_the_new_line(self) -> None:
        got = check.quantifier_drift("a\nb\nevery c\n", "a\nb\nc\n")
        self.assertEqual([line for line, _, _ in got], [3])


class SignatureTest(unittest.TestCase):
    BLOCK = "```mbti\npub fn f() -> Int\n```\n"

    def test_identical_blocks(self) -> None:
        self.assertEqual(check.signature_diffs("x\n" + self.BLOCK, "y\n" + self.BLOCK), [])

    def test_changed_block(self) -> None:
        new = self.BLOCK.replace("Int", "Bool")
        self.assertEqual(check.signature_diffs(self.BLOCK, new), [(1, "mbti block 1 differs from the base")])

    def test_removed_and_new_blocks(self) -> None:
        self.assertEqual(len(check.signature_diffs(self.BLOCK, "text\n")), 1)
        self.assertEqual(check.signature_diffs("text\n", self.BLOCK), [(1, "mbti block 1 is new")])

    def test_other_fences_are_not_signatures(self) -> None:
        text = "```moonbit\nfn f() {}\n```\n"
        self.assertEqual(check.mbti_blocks(text), [])


class ParseTest(unittest.TestCase):
    def test_messages_lines_and_continuation(self) -> None:
        text = (
            'msgid ""\nmsgstr ""\n\n#: a.md:1\n#, fuzzy\n#| msgid "old"\nmsgid "one "\n"two"\nmsgstr ""\n"x\\ny"\n'
        )
        (msg,) = check.parse_po(text)
        self.assertEqual((msg.line, msg.msgid, msg.msgstr), (7, "one two", "x\ny"))
        self.assertEqual((msg.flags, msg.has_previous, msg.refs), (["fuzzy"], True, ["a.md:1"]))

    def test_escapes(self) -> None:
        (msg,) = check.parse_po('msgid "a \\"b\\" \\\\nabla"\nmsgstr "c"\n')
        self.assertEqual(msg.msgid, 'a "b" \\nabla')

    def test_changed_messages(self) -> None:
        base = check.parse_po(po(("a:1", "x", "X"), ("a:2", "y", "Y")))
        head = check.parse_po(po(("a:1", "x", "X"), ("a:2", "y", "Z"), ("a:3", "w", "W")))
        self.assertEqual([m.msgid for m in check.changed_messages(base, head)], ["y", "w"])


class LanguageTest(unittest.TestCase):
    def problems(self, locale: str, msgstr: str, refs: str = "a:1") -> list[str]:
        (msg,) = check.parse_po(po((refs, "English", msgstr)))
        return check.language_problems(locale, msg)

    def test_kana_in_zh_cn(self) -> None:
        self.assertTrue(self.problems("zh_CN", "有限の值は 1 です"))

    def test_chinese_in_zh_cn_is_fine(self) -> None:
        self.assertEqual(self.problems("zh_CN", "有限值为 1"), [])

    def test_chinese_in_ja_jp(self) -> None:
        self.assertTrue(self.problems("ja_JP", "有限值为 1"))

    def test_japanese_and_english_only_in_ja_jp(self) -> None:
        self.assertEqual(self.problems("ja_JP", "有限の値は 1 です"), [])
        self.assertEqual(self.problems("ja_JP", "bench API"), [])

    def test_empty_fuzzy_and_previous(self) -> None:
        self.assertEqual(self.problems("zh_CN", ""), ["empty msgstr"])
        self.assertIn("fuzzy message", self.problems("zh_CN", "好|#, fuzzy"[:1], "a:1|#, fuzzy"))
        (msg,) = check.parse_po('#| msgid "o"\nmsgid "n"\nmsgstr "好"\n')
        self.assertEqual(check.language_problems("zh_CN", msg), ["`#|` previous-msgid line"])


class StaleTest(unittest.TestCase):
    def stale(self, base, head, locale: str = "zh_CN"):
        return check.stale_translations(locale, check.parse_po(po(*base)), check.parse_po(po(*head)))

    def test_copied_msgstr_with_changed_number(self) -> None:
        got = self.stale([("p.md:1", "It has 3 limbs.", "它有 3 个肢。")], [("p.md:1", "It has 4 limbs.", "它有 3 个肢。")])
        self.assertEqual(len(got), 1)
        self.assertIn("numbers differ", got[0][2][0])

    def test_copied_msgstr_with_new_quantifier(self) -> None:
        got = self.stale([("p.md:1", "It is exact.", "它是精确的。")], [("p.md:1", "It never rounds.", "它是精确的。")])
        self.assertTrue(any("'never'" in note for note in got[0][2]))

    def test_copied_msgstr_same_meaning_still_listed(self) -> None:
        got = self.stale([("p.md:1", "Return a value.", "返回值。")], [("p.md:1", "Returns a value.", "返回值。")])
        self.assertEqual((len(got), got[0][2]), (1, []))

    def test_fresh_translation_is_fine(self) -> None:
        self.assertEqual(self.stale([("p.md:1", "It has 3.", "三")], [("p.md:1", "It has 4.", "四")]), [])

    def test_other_page_does_not_match(self) -> None:
        self.assertEqual(self.stale([("p.md:1", "A.", "甲")], [("q.md:1", "B.", "甲")]), [])

    def test_unchanged_message_is_not_stale(self) -> None:
        same = [("p.md:1", "A.", "甲")]
        self.assertEqual(self.stale(same, same), [])


class SpanTest(unittest.TestCase):
    def test_equal(self) -> None:
        self.assertEqual(check.span_problems("Use `f` and $x^2$ [a](#b)", "用 `f` 和 $x^2$ [甲](#b)"), [])

    def test_code_span_changed(self) -> None:
        self.assertEqual(len(check.span_problems("Use `from_hex`", "用 `from_dec`")), 1)

    def test_formula_lost(self) -> None:
        (problem,) = check.span_problems("Take $2^{30}$", "取 2^30")
        self.assertTrue(problem.startswith("formula"))

    def test_link_target_changed(self) -> None:
        (problem,) = check.span_problems("[a](#build-exact-values)", "[甲](#build)")
        self.assertTrue(problem.startswith("link target"))

    def test_empty_msgstr_is_left_to_language(self) -> None:
        self.assertEqual(check.span_problems("`f`", ""), [])


class BackslashTest(unittest.TestCase):
    def test_real_case_810_nabla(self) -> None:
        self.assertIsNotNone(check.backslash_problem("The $\\nabla$ operator", "算子 $\\\nabla$"))
        self.assertIsNotNone(check.backslash_problem("The $\\ne$ sign", "符号 $\\\ne$"))

    def test_backslash_space(self) -> None:
        self.assertIsNotNone(check.backslash_problem("The $\\nabla$ operator", "算子 $\\ abla$"))

    def test_clean_formula(self) -> None:
        self.assertIsNone(check.backslash_problem("The $\\nabla$ operator", "算子 $\\nabla$"))

    def test_parsed_from_po_text(self) -> None:
        # `\\\nabla` in the PO file is backslash, line feed, "abla" after decoding
        (msg,) = check.parse_po('msgid "$\\\\nabla$"\nmsgstr "$\\\\\\nabla$"\n')
        self.assertIsNotNone(check.backslash_problem(msg.msgid, msg.msgstr))


class TrackedTest(unittest.TestCase):
    def test_classes(self) -> None:
        paths = [".tmp/plan/REPORT.md", ".claude/x.json", ".codex/a", ".cursor/b", "run.log", "a.pid", "doc/manual/a.md", "tools/x.py"]
        self.assertEqual(
            check.tracked_paths(paths), [".claude/x.json", ".codex/a", ".cursor/b", ".tmp/plan/REPORT.md", "a.pid", "run.log"]
        )

    def test_clean(self) -> None:
        self.assertEqual(check.tracked_paths(["doc/manual/a.md"]), [])


class CatalogTest(unittest.TestCase):
    def test_real_case_825_zh_in_japanese(self) -> None:
        old = po(("p.md:1", "A finite value is 1.", "有限值为 1。"))
        new = po(("p.md:1", "A finite value is 1.", "有限の値は 1 です。"))
        got = check.check_catalog("c.po", "zh_CN", old, new)
        self.assertEqual([f.code for f in got], ["LANGUAGE"])

    def test_clean_catalog_has_no_finding(self) -> None:
        old = po(("p.md:1", "Use `f`.", "用 `f`。"))
        new = po(("p.md:1", "Use `f`.", "用 `f`。"), ("p.md:2", "Take $x$.", "取 $x$。"))
        self.assertEqual(check.check_catalog("c.po", "zh_CN", old, new), [])

    def test_findings_are_sorted_and_deterministic(self) -> None:
        new = po(("p.md:1", "Use `f`.", "用 `g`。"), ("p.md:2", "Use `h`.", ""))
        a = check.check_catalog("c.po", "zh_CN", None, new)
        self.assertEqual(a, check.check_catalog("c.po", "zh_CN", None, new))
        self.assertEqual({f.code for f in a}, {"SPANS", "LANGUAGE"})


class RepositoryTest(unittest.TestCase):
    """The git side, on a throwaway repository."""

    def setUp(self) -> None:
        self.root = Path(tempfile.mkdtemp(prefix="rewrite-check-"))
        self.addCleanup(lambda: shutil.rmtree(self.root, True))
        self.git("init", "-q", "-b", "main")
        self.git("config", "user.email", "t@example.com")
        self.git("config", "user.name", "t")
        self.write("doc/manual/a.md", "It never aborts.\n")
        self.write("doc/locale/zh_CN/LC_MESSAGES/manual.po", po(("manual/a.md:1", "It never aborts.", "它从不中止。")))
        self.commit("base")
        self.git("checkout", "-q", "-b", "topic")

    def git(self, *args: str) -> str:
        proc = subprocess.run(("git", *args), cwd=self.root, capture_output=True, text=True, check=True)
        return proc.stdout

    def write(self, name: str, text: str) -> None:
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def commit(self, message: str) -> None:
        self.git("add", "-f", "-A")
        self.git("commit", "-q", "-m", message)

    def test_no_change_no_finding(self) -> None:
        self.assertEqual(check.check_range("main", "HEAD", self.root), [])

    def test_rewrite_with_all_classes(self) -> None:
        self.write("doc/manual/a.md", "It aborts.\n")
        self.write(
            "doc/locale/zh_CN/LC_MESSAGES/manual.po", po(("manual/a.md:1", "It aborts.", "它从不中止。"), ("manual/a.md:2", "Two.", "二の"))
        )
        self.write(".tmp/note.md", "x\n")
        self.commit("rewrite")
        codes = sorted({f.code for f in check.check_range("main", "HEAD", self.root)})
        self.assertEqual(codes, ["LANGUAGE", "QUANTIFIER", "STALE", "TRACKED"])

    def test_moved_base_is_not_a_change_of_the_pr(self) -> None:
        self.git("checkout", "-q", "main")
        self.write("doc/manual/a.md", "It always aborts.\n")
        self.commit("main moves")
        self.git("checkout", "-q", "topic")
        self.write("doc/manual/b.md", "New page.\n")
        self.commit("topic")
        self.assertEqual(check.check_range("main", "HEAD", self.root), [])

    def test_json_shape(self) -> None:
        self.write("doc/manual/a.md", "It aborts.\n")
        self.commit("rewrite")
        (finding,) = check.check_range("main", "HEAD", self.root)
        data = json.loads(json.dumps([check.asdict(finding)]))
        self.assertEqual(sorted(data[0]), ["code", "file", "line", "text"])
        self.assertEqual(finding.render().split(" ")[1], "QUANTIFIER")


if __name__ == "__main__":
    unittest.main()
