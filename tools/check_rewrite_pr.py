#!/usr/bin/env python3
"""Self-check for a pull request that rewrites manual pages and their catalogs.

Run it before pushing a rewrite (or a repair of one). It is not part of any gate: it
finds the classes of defect that review rounds of the 0.12 manual rewrite kept finding,
prints one finding per line and exits 1 if there is any. It reports, it never decides:
every finding is for the author to read and either fix or explain in the PR body.

    check_rewrite_pr.py [<base-ref> [<head-ref>]] [--json]

base defaults to origin/main and head to HEAD. The comparison is made from the merge
base of the two to the head (the three-dot diff a pull request shows), so a base that has
moved on does not show up as changes of the PR. Output is sorted and deterministic:

    <file>:<line> <CODE> <text>

Checks (each one comes from a real review finding):

    QUANTIFIER  a word of always, never, every, each, only, none, all, any, at most,
                at least, exactly, must in lines removed from a manual page and absent
                from the lines that replace them (fenced code is ignored).
    LANGUAGE    zh_CN msgstr with kana; ja_JP msgstr with Han characters and no kana
                (Chinese in the Japanese catalog); empty, fuzzy or `#|` message.
    STALE       a new msgid whose msgstr is the msgstr of a message the PR removed from
                the same page; the text says whether numbers or quantifier words of the
                English no longer match the translation.
    SPANS       code spans, formulas ($...$) or link targets differ between the msgid
                and msgstr of a changed message.
    BACKSLASH   a backslash followed by a line feed in a msgstr whose msgid has a backslash
                command, or a backslash followed by white space where the msgid has none
                (`\\nabla` written as `\\n` in the PO turns into a line feed).
    TRACKED     an added path under .tmp/, .claude/, .codex/, .cursor/ or a .log or .pid file.
    SIGNATURE   the fenced `mbti` blocks of a page differ between base and head.

A "changed message" is a message of a head catalog whose (msgid, msgstr) pair is not in
the base catalog. What the script cannot see: a translation that is wrong but spans-clean
and not stale, a quantifier drift inside a sentence that was reordered, terms (DECIDED
glossary), and any claim that the English made up.
"""

from __future__ import annotations

import argparse
import difflib
import json
import re
import subprocess
import sys
from collections import Counter
from dataclasses import asdict, dataclass
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

QUANTIFIERS = (
    "always", "never", "every", "each", "only", "none", "all", "any",
    "at most", "at least", "exactly", "must",
)

# CJK words that carry each quantifier. A message is compared by whether any word of the
# list is present; the lists are deliberately short and are for the stale check only.
QUANTIFIER_CJK: dict[str, dict[str, tuple[str, ...]]] = {
    "zh_CN": {
        "always": ("总是", "始终", "一律", "总会"),
        "never": ("从不", "绝不", "永不", "决不", "从未"),
        "every": ("每个", "每一", "每次", "每种", "每"),
        "each": ("每个", "每一", "每次", "每种", "每", "各"),
        "only": ("只", "仅", "唯一"),
        "none": ("都不", "没有任何", "无一", "均不"),
        "all": ("所有", "全部", "均", "一切"),
        "any": ("任何", "任意", "任一"),
        "at most": ("至多", "最多", "不超过"),
        "at least": ("至少", "最少", "不少于"),
        "exactly": ("恰好", "精确", "正好"),
        "must": ("必须", "须"),
    },
    "ja_JP": {
        "always": ("常に", "いつも", "必ず"),
        "never": ("決して", "一切"),
        "every": ("すべて", "全て", "各", "毎"),
        "each": ("すべて", "全て", "各", "毎", "それぞれ"),
        "only": ("のみ", "だけ"),
        "none": ("どれも", "いずれも", "一つも"),
        "all": ("すべて", "全て", "全部", "いずれも"),
        "any": ("任意", "いずれ"),
        "at most": ("高々", "多くとも", "を超えない"),
        "at least": ("少なくとも", "を下回らない"),
        "exactly": ("ちょうど", "正確"),
        "must": ("必ず", "なければ"),
    },
}

TRACKED_PREFIXES = (".tmp/", ".claude/", ".codex/", ".cursor/")
TRACKED_SUFFIXES = (".log", ".pid")

MANUAL_RE = re.compile(r"^doc/manual/.*\.md$")
CATALOG_RE = re.compile(r"^doc/locale/(zh_CN|ja_JP)/LC_MESSAGES/manual\.po$")

KANA_RE = re.compile("[぀-ゟ゠-ヺー-ヿ]")
HAN_RE = re.compile("[一-鿿]")


@dataclass(frozen=True, order=True)
class Finding:
    file: str
    line: int
    code: str
    text: str

    def render(self) -> str:
        return f"{self.file}:{self.line} {self.code} {self.text}"


# --------------------------------------------------------------------------- pure core


def mask_fences(text: str) -> list[str]:
    """Lines of `text` with the content of fenced blocks (and the fences) blanked."""
    out: list[str] = []
    fence: str | None = None
    for line in text.split("\n"):
        stripped = line.lstrip()
        marker = stripped[:3] if stripped[:3] in ("```", "~~~") else None
        if fence is None:
            if marker:
                fence = marker
                out.append("")
            else:
                out.append(line)
        else:
            if marker == fence:
                fence = None
            out.append("")
    return out


def quantifier_counts(text: str) -> Counter[str]:
    """Occurrences of each quantifier word outside code spans (`None` is a value, not a word)."""
    low = re.sub(r"`[^`\n]*`", " ", text).lower()
    counts: Counter[str] = Counter()
    for q in QUANTIFIERS:
        n = len(re.findall(r"(?<![\w-])" + q.replace(" ", r"\s+") + r"(?![\w-])", low))
        if n:
            counts[q] = n
    return counts


def quantifiers_in(text: str) -> set[str]:
    return set(quantifier_counts(text))


def quantifier_drift(old_text: str, new_text: str) -> list[tuple[int, str, str]]:
    """(new line, word, removed line) for each quantifier lost in a changed hunk."""
    old = mask_fences(old_text)
    new = mask_fences(new_text)
    result: list[tuple[int, str, str]] = []
    matcher = difflib.SequenceMatcher(None, old, new, autojunk=False)
    for tag, i1, i2, j1, j2 in matcher.get_opcodes():
        if tag not in ("replace", "delete"):
            continue
        removed = "\n".join(old[i1:i2])
        added = "\n".join(new[j1:j2])
        was, now = quantifier_counts(removed), quantifier_counts(added)
        lost = sorted(q for q in was if was[q] > now[q])
        if not lost:
            continue
        line = min(j1 + 1, max(len(new), 1))
        for word in lost:
            sample = next((s for s in old[i1:i2] if word in quantifiers_in(s)), "").strip()
            result.append((line, word, sample))
    return result


def mbti_blocks(text: str) -> list[tuple[int, str]]:
    """(line of the fence, body) of every fenced `mbti` block."""
    blocks: list[tuple[int, str]] = []
    lines = text.split("\n")
    i = 0
    while i < len(lines):
        stripped = lines[i].lstrip()
        if stripped.startswith("```") and stripped[3:].strip().split(" ")[0] == "mbti":
            start = i
            i += 1
            body: list[str] = []
            while i < len(lines) and not lines[i].lstrip().startswith("```"):
                body.append(lines[i])
                i += 1
            blocks.append((start + 1, "\n".join(body)))
        i += 1
    return blocks


def signature_diffs(old_text: str, new_text: str) -> list[tuple[int, str]]:
    old = mbti_blocks(old_text)
    new = mbti_blocks(new_text)
    out: list[tuple[int, str]] = []
    for index in range(max(len(old), len(new))):
        if index >= len(new):
            out.append((new[-1][0] if new else 1, f"mbti block {index + 1} of the base is gone"))
        elif index >= len(old):
            out.append((new[index][0], f"mbti block {index + 1} is new"))
        elif old[index][1] != new[index][1]:
            out.append((new[index][0], f"mbti block {index + 1} differs from the base"))
    return out


@dataclass
class Message:
    line: int
    refs: list[str]
    flags: list[str]
    has_previous: bool
    msgid: str
    msgstr: str

    @property
    def paths(self) -> set[str]:
        return {r.split(":", 1)[0] for r in self.refs}


_UNESCAPE = {"n": "\n", "t": "\t", '"': '"', "\\": "\\"}


def _unquote(raw: str) -> str:
    raw = raw.strip()
    if raw.startswith('"') and raw.endswith('"') and len(raw) >= 2:
        raw = raw[1:-1]
    return re.sub(r"\\(.)", lambda m: _UNESCAPE.get(m.group(1), m.group(0)), raw)


def parse_po(text: str) -> list[Message]:
    """Messages of a PO file in file order, the header (empty msgid) left out."""
    messages: list[Message] = []
    refs: list[str] = []
    flags: list[str] = []
    previous = False
    target: str | None = None
    parts: dict[str, list[str]] = {"msgid": [], "msgstr": []}
    start = 0

    def finish() -> None:
        nonlocal refs, flags, previous, target, parts, start
        msgid = "".join(parts["msgid"])
        if target is not None and msgid:
            messages.append(Message(start, refs, flags, previous, msgid, "".join(parts["msgstr"])))
        refs, flags, previous, target = [], [], False, None
        parts = {"msgid": [], "msgstr": []}

    for number, line in enumerate(text.split("\n"), 1):
        if line.startswith("msgid "):
            if target == "msgstr":
                finish()
            target = "msgid"
            start = number
            parts["msgid"].append(_unquote(line[6:]))
        elif line.startswith("msgstr "):
            target = "msgstr"
            parts["msgstr"].append(_unquote(line[7:]))
        elif line.startswith('"') and target:
            parts[target].append(_unquote(line))
        elif line.startswith("#"):
            if target == "msgstr":
                finish()
            if line.startswith("#:"):
                refs.extend(line[2:].split())
            elif line.startswith("#,"):
                flags.extend(f.strip() for f in line[2:].split(","))
            elif line.startswith("#|"):
                previous = True
        elif not line.strip():
            if target == "msgstr":
                finish()
    if target == "msgstr":
        finish()
    return messages


def changed_messages(base: list[Message], head: list[Message]) -> list[Message]:
    known = {(m.msgid, m.msgstr) for m in base}
    return [m for m in head if (m.msgid, m.msgstr) not in known]


def _spans(text: str) -> dict[str, Counter[str]]:
    return {
        "code span": Counter(re.findall(r"`[^`\n]+`", text)),
        "formula": Counter(re.findall(r"\$\$.+?\$\$|\$[^$\n]+?\$", text, re.S)),
        "link target": Counter(re.findall(r"\]\(([^)\s]*)\)", text)),
    }


def span_problems(msgid: str, msgstr: str) -> list[str]:
    if not msgstr:
        return []
    a, b = _spans(msgid), _spans(msgstr)
    out: list[str] = []
    for kind in a:
        missing = sorted((a[kind] - b[kind]).elements())
        extra = sorted((b[kind] - a[kind]).elements())
        if missing or extra:
            out.append(f"{kind}: missing {missing} extra {extra}")
    return out


def backslash_problem(msgid: str, msgstr: str) -> str | None:
    # a `\\` line break of a formula is a pair; only a lone backslash before white space is damage
    lf = r"(?<!\\)\\\n"
    ws = r"(?<!\\)\\[ \t\r]"
    if len(re.findall(lf, msgstr)) > len(re.findall(lf, msgid)) and re.search(r"\\[A-Za-z]", msgid):
        return "backslash followed by a line feed in msgstr, msgid has a backslash command"
    if len(re.findall(ws, msgstr)) > len(re.findall(ws, msgid)):
        return "backslash followed by white space in msgstr, msgid has none"
    return None


# Han-only strings are valid Japanese (headings, table cells, names), so a ja_JP msgstr
# without kana is reported only when it reads as Chinese: the full-width comma, or two
# characters of simplified Chinese that Japanese writes differently.
SIMPLIFIED_ONLY = set("这个们与对将该时还会说无种样应进过从单并为后个关页")


def reads_as_chinese(text: str) -> bool:
    text = re.sub(r"`[^`\n]*`|\$[^$\n]*\$|\]\([^)\s]*\)", " ", text)
    return "\uff0c" in text or sum(c in SIMPLIFIED_ONLY for c in text) >= 2


def language_problems(locale: str, msg: Message) -> list[str]:
    out: list[str] = []
    if "fuzzy" in msg.flags:
        out.append("fuzzy message")
    if msg.has_previous:
        out.append("`#|` previous-msgid line")
    if not msg.msgstr.strip():
        out.append("empty msgstr")
        return out
    kana = KANA_RE.search(msg.msgstr)
    if locale == "zh_CN" and kana:
        out.append(f"kana in zh_CN msgstr ({kana.group(0)})")
    if locale == "ja_JP" and not kana and msg.msgstr != msg.msgid and reads_as_chinese(msg.msgstr):
        out.append("ja_JP msgstr has no kana and reads as Chinese")
    return out


def _numbers(text: str) -> Counter[str]:
    return Counter(re.findall(r"\d+(?:[.,]\d+)*", text))


def stale_mismatch(locale: str, msgid: str, msgstr: str) -> list[str]:
    notes: list[str] = []
    num_en, num_tr = _numbers(msgid), _numbers(msgstr)
    if num_en != num_tr:
        notes.append(f"numbers differ (English {sorted(num_en.elements())}, translation {sorted(num_tr.elements())})")
    words = QUANTIFIER_CJK[locale]
    in_en = quantifiers_in(msgid)
    for q in QUANTIFIERS:
        if q in in_en and not any(w in msgstr for w in words[q]):
            notes.append(f"English has '{q}', translation has none of {'/'.join(words[q][:3])}")
    return notes


def stale_translations(locale: str, base: list[Message], head: list[Message]) -> list[tuple[Message, Message, list[str]]]:
    head_ids = {m.msgid for m in head}
    base_ids = {m.msgid for m in base}
    removed = [m for m in base if m.msgid not in head_ids]
    out: list[tuple[Message, Message, list[str]]] = []
    for m in head:
        if m.msgid in base_ids or not m.msgstr.strip() or m.msgstr == m.msgid:
            continue
        for old in removed:
            if old.msgstr == m.msgstr and (m.paths & old.paths or not m.paths):
                out.append((m, old, stale_mismatch(locale, m.msgid, m.msgstr)))
                break
    return out


def tracked_paths(paths: list[str]) -> list[str]:
    return sorted(p for p in paths if p.startswith(TRACKED_PREFIXES) or p.endswith(TRACKED_SUFFIXES))


def short(text: str, width: int = 70) -> str:
    text = " ".join(text.split())
    return text if len(text) <= width else text[: width - 3] + "..."


def check_manual_page(path: str, old_text: str | None, new_text: str) -> list[Finding]:
    if old_text is None:
        return []
    out = [
        Finding(path, line, "QUANTIFIER", f"'{word}' lost: removed \"{short(sample)}\"")
        for line, word, sample in quantifier_drift(old_text, new_text)
    ]
    out += [Finding(path, line, "SIGNATURE", text) for line, text in signature_diffs(old_text, new_text)]
    return out


def check_catalog(path: str, locale: str, old_text: str | None, new_text: str) -> list[Finding]:
    base = parse_po(old_text) if old_text else []
    head = parse_po(new_text)
    out: list[Finding] = []
    for msg in changed_messages(base, head):
        label = f"\"{short(msg.msgid, 50)}\""
        for text in language_problems(locale, msg):
            out.append(Finding(path, msg.line, "LANGUAGE", f"{text}: {label}"))
        if not msg.msgstr.strip():
            continue
        for text in span_problems(msg.msgid, msg.msgstr):
            out.append(Finding(path, msg.line, "SPANS", f"{text}: {label}"))
        problem = backslash_problem(msg.msgid, msg.msgstr)
        if problem:
            out.append(Finding(path, msg.line, "BACKSLASH", f"{problem}: {label}"))
    for msg, old, notes in stale_translations(locale, base, head):
        detail = "; ".join(notes) if notes else "numbers and quantifiers agree, read the meaning"
        out.append(
            Finding(path, msg.line, "STALE", f"msgstr is that of the removed \"{short(old.msgid, 40)}\" ({detail}): \"{short(msg.msgid, 40)}\"")
        )
    return out


# --------------------------------------------------------------------------- git side


def git(*args: str, cwd: Path = REPO, check: bool = True) -> str:
    proc = subprocess.run(("git", *args), cwd=cwd, capture_output=True, text=True, encoding="utf-8")
    if check and proc.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)}: {proc.stderr.strip()}")
    return proc.stdout


def show(rev: str, path: str, cwd: Path = REPO) -> str | None:
    proc = subprocess.run(
        ("git", "show", f"{rev}:{path}"), cwd=cwd, capture_output=True, text=True, encoding="utf-8"
    )
    return proc.stdout if proc.returncode == 0 else None


def check_range(base: str, head: str, cwd: Path = REPO) -> list[Finding]:
    merge_base = git("merge-base", base, head, cwd=cwd).strip()
    names = [
        n for n in git("diff", "--name-only", "--diff-filter=ACMR", "-z", merge_base, head, cwd=cwd).split("\0") if n
    ]
    findings = [Finding(p, 1, "TRACKED", "added path of a class that stays untracked") for p in tracked_paths(names)]
    for name in sorted(names):
        new_text = show(head, name, cwd)
        if new_text is None:
            continue
        old_text = show(merge_base, name, cwd)
        catalog = CATALOG_RE.match(name)
        if MANUAL_RE.match(name):
            findings += check_manual_page(name, old_text, new_text)
        elif catalog:
            findings += check_catalog(name, catalog.group(1), old_text, new_text)
    return sorted(set(findings))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("base", nargs="?", default="origin/main")
    parser.add_argument("head", nargs="?", default="HEAD")
    parser.add_argument("--json", action="store_true", help="print the findings as a JSON list")
    args = parser.parse_args(argv)
    try:
        findings = check_range(args.base, args.head)
    except RuntimeError as error:
        print(f"check_rewrite_pr: {error}", file=sys.stderr)
        return 2
    if args.json:
        print(json.dumps([asdict(f) for f in findings], ensure_ascii=False, indent=2))
    else:
        for finding in findings:
            print(finding.render())
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
