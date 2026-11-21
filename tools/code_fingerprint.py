#!/usr/bin/env python3
"""Reachable-code fingerprints of a MoonBit native program, taken from its generated C.

The native backend compiles a package graph to one C file. This module splits that file into
top-level items, normalises each item, and fingerprints the code reachable from a chosen
entry. Two builds whose fingerprints of an entry are equal run the same C code from that
entry, so a verification result recorded for one is valid for the other.

Soundness rules (see doc/manual/verification.md):

* Normalisation deletes `#line` directives and renames identifiers that are local to one
  item (and the compiler-numbered closures of one parent), by order of first appearance.
  Nothing else is changed.
* A reference is any occurrence of a defined name in an item, calls and data alike.
* Text that is not attributed to a named item goes into the residue, and the residue is part
  of every key. Unknown text makes a key coarser, never finer.

The pure functions take and return values; only `read_c_file` and `main` touch files.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import platform
import re
import subprocess
import sys
from collections.abc import Callable, Collection, Iterable
from dataclasses import dataclass, field
from pathlib import Path

# ---------------------------------------------------------------------------------------
# Splitting the C file into items
# ---------------------------------------------------------------------------------------

# Structural characters outside string literals, character literals and comments.
_STRUCTURE = re.compile(
    r'"(?:\\.|[^"\\\n])*"|\'(?:\\.|[^\'\\\n])*\'|//[^\n]*|/\*.*?\*/|(/\*)|([{}();=])',
    re.S,
)
_IDENT = re.compile(r"(?:\b(struct|union|enum)\s+)?([A-Za-z_$][A-Za-z0-9_$]*)")
_ANONYMOUS = re.compile(r"\b(?:struct|union|enum)\s*\{\}")
_DEFINE = re.compile(r"[ \t]*#[ \t]*define[ \t]+([A-Za-z_$][A-Za-z0-9_$]*)")
_LINE_DIRECTIVE = re.compile(r"^[ \t]*#[ \t]*line\b")


@dataclass(frozen=True)
class RawItem:
    """One top-level piece of the C file, `#line` directives already removed."""

    text: str
    is_function: bool
    macro: str | None = None


class ParseError(ValueError):
    """The C file does not have the shape the splitter relies on."""


def drop_line_directives(lines: list[str]) -> list[str]:
    """Delete `#line` directives (including continuation lines); keep everything else."""
    out: list[str] = []
    skipping = False
    for line in lines:
        if skipping or _LINE_DIRECTIVE.match(line):
            skipping = line.rstrip().endswith("\\")
            continue
        out.append(line)
    return out


@dataclass(frozen=True)
class LineAccount:
    """Where every line of the C file went. The buckets sum to `total`."""

    total: int
    directives: int  # `#line` lines, deleted
    blank: int  # blank lines between items
    residue: int  # preprocessor (not `#define`), comments, `extern "C"` and its brace
    items: int  # lines of named or unnamed items, `#define` macros included

    @property
    def unaccounted(self) -> int:
        return self.total - self.directives - self.blank - self.residue - self.items


def split_items(text: str) -> tuple[list[RawItem], str, LineAccount]:
    """Split the file into top-level items and the preprocessor/comment residue.

    An item starts at a non-blank, non-preprocessor line outside any item and ends at a `;`
    at depth 0, or, for a function definition (the first `{` at depth 0 follows a `)`), at the
    `}` that closes it. Preprocessor lines (and their continuations) outside an item, blank
    lines and `//` comment lines are residue. Raises ParseError when the file ends inside an
    item.
    """
    all_lines = text.split("\n")
    lines = drop_line_directives(all_lines)
    blank = 0
    items: list[RawItem] = []
    residue: list[str] = []
    current: list[str] = []
    depth = 0
    paren = 0
    is_function = False
    seen_brace = False
    continuing = False
    macro_lines: list[str] = []

    def flush_macro() -> None:
        """A `#define` is an item named by the macro (its body may name definitions)."""
        text_ = "\n".join(macro_lines)
        macro_lines.clear()
        found = _DEFINE.match(text_)
        if found:
            items.append(RawItem(text_, False, macro=found.group(1)))
        else:
            residue.append(text_)

    in_comment = False
    in_block = False
    for line in lines:
        if not current:
            stripped = line.strip()
            if in_comment or stripped.startswith("/*"):
                residue.append(line)
                in_comment = "*/" not in line[line.find("/*") + 2 if not in_comment else 0 :]
                continue
            if continuing:
                macro_lines.append(line)
                continuing = line.rstrip().endswith("\\")
                if not continuing:
                    flush_macro()
                continue
            if stripped.startswith("#"):
                continuing = line.rstrip().endswith("\\")
                macro_lines.append(line)
                if not continuing:
                    flush_macro()
                continue
            if not stripped:
                blank += 1
                continue
            if stripped.startswith("//") or stripped in ('extern "C" {', "}"):
                residue.append(line)
                continue
        current.append(line)
        if line.lstrip().startswith("#"):
            continue  # a directive inside an item: kept in the text, not scanned
        end = False
        scan = line
        if in_block:
            close = line.find("*/")
            if close == -1:
                continue
            scan = " " * (close + 2) + line[close + 2 :]
            in_block = False
        for match in _STRUCTURE.finditer(scan):
            char = match.group(2)
            if match.group(1):
                in_block = "*/" not in scan[match.start() + 2 :]
                if in_block:
                    break
                continue
            if char is None:
                continue
            if char == "{":
                if depth == 0 and not seen_brace:
                    head = "\n".join(current[:-1]) + "\n" + line[: match.start()]
                    is_function = head.rstrip().endswith(")")
                    seen_brace = True
                depth += 1
            elif char == "}":
                depth -= 1
                if depth == 0 and is_function and paren == 0:
                    end = True
            elif char == "(":
                paren += 1
            elif char == ")":
                paren -= 1
            elif char == ";" and depth == 0 and paren == 0:
                end = True
            if end:
                break
        if end:
            items.append(RawItem("\n".join(current), is_function))
            current = []
            depth = paren = 0
            is_function = False
            seen_brace = False
    if current:
        raise ParseError("file ends inside an item starting with: " + current[0][:80])
    account = LineAccount(
        total=len(all_lines),
        directives=len(all_lines) - len(lines),
        blank=blank,
        residue=sum(r.count("\n") + 1 for r in residue),
        items=sum(i.text.count("\n") + 1 for i in items),
    )
    return items, "\n".join(residue), account


# ---------------------------------------------------------------------------------------
# Naming an item
# ---------------------------------------------------------------------------------------


def _skeleton(text: str) -> str:
    """The text with literals and comments blanked and every `{...}` replaced by `{}`."""
    out: list[str] = []
    depth = 0
    position = 0
    for match in _STRUCTURE.finditer(text):
        char = match.group(2)
        chunk = text[position : match.start()]
        if depth == 0:
            out.append(chunk)
        if char is None:
            if depth == 0:
                out.append(" ")
        elif char == "{":
            if depth == 0:
                out.append("{}")
            depth += 1
        elif char == "}":
            depth -= 1
        elif depth == 0:
            out.append(char)
        position = match.end()
    if depth == 0:
        out.append(text[position:])
    return "".join(out)


def item_key(item: RawItem) -> str | None:
    """The name an item declares or defines, or None when it cannot be named.

    Struct, union and enum tags live in their own namespace and are keyed `struct NAME`.
    """
    if item.macro is not None:
        return item.macro
    skeleton = _skeleton(item.text)
    skeleton = _ANONYMOUS.sub("struct _anonymous", skeleton)
    cut = len(skeleton)
    for char in "=(;{":
        position = skeleton.find(char)
        if position != -1:
            cut = min(cut, position)
    head = skeleton[:cut]
    follower = skeleton[cut : cut + 1]
    words = [m for m in _IDENT.finditer(head)]
    if not words:
        return None
    tag = re.fullmatch(r"\s*(?:typedef\s+)?(struct|union|enum)\s+([A-Za-z_$][A-Za-z0-9_$]*)\s*", head)
    if tag and follower in ("{", ";"):
        return f"{tag.group(1)} {tag.group(2)}"
    if follower == "(" and not item.is_function and "(" in skeleton[cut + 1 :].lstrip()[:1]:
        return None  # a function-pointer declarator: not attributed
    last = words[-1]
    if last.group(1):
        return None
    name = last.group(2)
    if name in _KEYWORDS:
        return None
    return name


_KEYWORDS = frozenset(
    "static extern const volatile inline void int char short long signed unsigned float "
    "double struct union enum typedef return if else for while do switch case default "
    "break continue goto sizeof".split()
)


# ---------------------------------------------------------------------------------------
# Normalisation
# ---------------------------------------------------------------------------------------

# Identifiers that are local to one item and carry a compiler-wide counter.
_LOCAL = re.compile(
    r"\b(_M0L[A-Za-z0-9_]*?S\d+|_[a-z][a-z_]*_\d+|join_\d+|joinlet_\d+|_L\d+|loop_\d+)\b"
)


def local_kind(name: str) -> str:
    """The kind of a local-looking name: which alternative of `_LOCAL` it is."""
    for prefix, kind in (("_M0L", "var"), ("joinlet_", "joinlet"), ("join_", "join"), ("loop_", "loop")):
        if name.startswith(prefix):
            return kind
    return "label" if re.fullmatch(r"_L\d+", name) else "tmp"


# String and character literals and comments: text that is not code. The renamings and the
# reference scan skip them; the hash still covers their bytes.
_LITERAL = re.compile(r'"(?:\\.|[^"\\\n])*"|\'(?:\\.|[^\'\\\n])*\'|//[^\n]*|/\*.*?\*/', re.S)


def map_code(text: str, function: Callable[[str], str]) -> str:
    """Apply `function` to the code segments of `text`, leaving literals and comments as they are."""
    out: list[str] = []
    position = 0
    for match in _LITERAL.finditer(text):
        out.append(function(text[position : match.start()]))
        out.append(match.group(0))
        position = match.end()
    out.append(function(text[position:]))
    return "".join(out)


def local_candidates(text: str) -> set[str]:
    """Names in the code of `text` that look like compiler-numbered locals."""
    found: set[str] = set()

    def collect(segment: str) -> str:
        found.update(m.group(1) for m in _LOCAL.finditer(segment))
        return segment

    map_code(text, collect)
    return found


def rename_locals(text: str, keep: frozenset[str]) -> str:
    """Rename counter-carrying local identifiers by order of first appearance.

    Once a name is checked local its spelling carries nothing (a parameter may be spelled
    `_M0L10_2ax__4387S12`, with a second compiler counter inside the stem): it becomes
    `__L_<kind>_<k>`, k counting the distinct identifiers seen, so the new name depends only on
    the kind of the name and its position. A name in
    `keep` (a defined top-level name, or one found outside a single definition) is never
    renamed. Literals and comments are skipped.
    """
    names: dict[str, str] = {}

    def replace(match: re.Match[str]) -> str:
        name = match.group(1)
        if name in keep:
            return name
        if name not in names:
            names[name] = f"__L_{local_kind(name)}_{len(names)}"
        return names[name]

    return map_code(text, lambda segment: _LOCAL.sub(replace, segment))


def identifiers(text: str) -> set[str]:
    """Every identifier in the code of a text (literals skipped), a tag as `struct NAME`."""
    found: set[str] = set()

    def collect(segment: str) -> str:
        for match in _IDENT.finditer(segment):
            tag, name = match.groups()
            found.add(f"{tag} {name}" if tag else name)
            if tag:
                found.add(name)
        return segment

    map_code(text, collect)
    return found


@dataclass
class Definition:
    """All items that carry one name (prototypes and the definition), normalised."""

    parts: list[str] = field(default_factory=list)
    refs: set[str] = field(default_factory=set)
    is_function: bool = False

    @property
    def digest(self) -> str:
        return hashlib.sha256("\x00".join(sorted(self.parts)).encode()).hexdigest()


@dataclass
class Program:
    """The attributed items of one C file, its residue and where every line went."""

    definitions: dict[str, Definition]
    residue: str
    unnamed: list[str]
    account: LineAccount
    normalisations: tuple[str, ...]
    layout_rewritten: int = 0  # header macros whose layout index was replaced by its entry
    layout_fallbacks: int = 0  # header macros left with the raw index
    layout_fallback_definitions: int = 0
    path_hits: int = 0  # occurrences of a forbidden path outside `#line` directives
    nonlocal_names: list[str] = field(default_factory=list)  # local-looking names left unrenamed
    shared_locals: int = 0  # local-looking names shared by several definitions, renamed jointly
    renamed_locals: frozenset[str] = frozenset()  # every name that was renamed as a local

    @property
    def residue_digest(self) -> str:
        return hashlib.sha256((self.residue + "\x00".join(self.unnamed)).encode()).hexdigest()

    @property
    def residue_bytes(self) -> int:
        return len(self.residue) + sum(len(u) for u in self.unnamed)

    @property
    def version(self) -> str:
        """The set of normalisations in force; part of every ledger key."""
        return "+".join(self.normalisations)


NORMALISATION_BASE = ("line-directives", "local-rename", "counter-names")
NORMALISATION_LAYOUT = "layout-index"

# `Moonbit_make_regular_object_header(CLASS, INDEX, TAG)`: INDEX selects an entry of
# `moonbit_layout_table_data`. The only use of the index in the pinned runtime is
# `&moonbit_layout_table[index]` (~/.moon/lib/runtime/runtime.c:186-191); it is never
# compared, hashed or printed.
_HEADER = re.compile(r"(Moonbit_make_regular_object_header\(\s*[A-Za-z_0-9]+\s*,\s*)(\d+)(\s*,)")
_HEADER_ANY = re.compile(r"Moonbit_make_regular_object_header")
_LAYOUT_TABLE = "moonbit_layout_table_data"


def _split_top_level(text: str) -> list[str]:
    """Split on commas outside parentheses; whitespace inside a piece is collapsed."""
    pieces: list[str] = []
    depth = 0
    start = 0
    for position, char in enumerate(text):
        if char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
        elif char == "," and depth == 0:
            pieces.append(text[start:position])
            start = position + 1
    pieces.append(text[start:])
    return [" ".join(piece.split()) for piece in pieces if piece.strip()]


def parse_layout_table(text: str) -> dict[int, str] | None:
    """Decode `moonbit_layout_table_data` into {entry start index: entry text}.

    The documented shape (runtime.c:193-201) is a flat array of entries
    `[size_in_word, child_count, tagged_child...]`. Returns None when the text does not have
    that shape: a count that is not an integer literal, an entry running past the end, or a
    word count different from the declared length.
    """
    declared = re.search(_LAYOUT_TABLE + r"\[(\d+)\]\s*=\s*\{(.*)\}\s*;", text, re.S)
    if declared is None:
        return None
    words = _split_top_level(declared.group(2))
    if len(words) != int(declared.group(1)):
        return None
    entries: dict[int, str] = {}
    index = 0
    while index < len(words):
        if index + 1 >= len(words) or not words[index + 1].isdigit():
            return None
        count = int(words[index + 1])
        end = index + 2 + count
        if end > len(words):
            return None
        entries[index] = "LAYOUT{" + "|".join(words[index:end]) + "}"
        index = end
    return entries


def rewrite_layout_indices(text: str, entries: dict[int, str]) -> tuple[str, int, int]:
    """Replace each header's layout index by its table entry; returns (text, rewritten, fallbacks).

    A header whose index is not at an entry boundary stays as it is (a coarser key). A mention
    of the header macro that the pattern does not match is also counted as a fallback.
    """
    rewritten = 0

    def replace(match: re.Match[str]) -> str:
        nonlocal rewritten
        entry = entries.get(int(match.group(2)))
        if entry is None:
            return match.group(0)
        rewritten += 1
        return f"{match.group(1)}{entry}{match.group(3)}"

    new = _HEADER.sub(replace, text)
    mentions = len(_HEADER_ANY.findall(text))
    return new, rewritten, mentions - rewritten


# Compiler-wide counters inside the name of a top-level definition: the nested entities
# `<parent>N<len>constrS<n>`, closures `C<n>l<line>`, anonymous records `u<n>__l<line>__`
# and string literals `moonbit_string_literal_<n>`.
_COUNTER = re.compile(r"S\d+(?=(?:\$\w+)?$)|C\d+l\d+|u\d+__l\d+__|(?<=literal_)\d+")


def counter_stem(name: str) -> str:
    """The name with its compiler counters replaced by `#`."""
    return _COUNTER.sub("N", name)


def _short(owner: str) -> str:
    return hashlib.sha256(owner.encode()).hexdigest()[:16]


def canonical_names(texts: dict[str, str]) -> dict[str, str]:
    """Rename counter-carrying definitions by where they are first referenced.

    `texts` maps every definition name to its text. A definition whose name contains a
    compiler counter is renamed `<stem>__canon__<owner>__<k>` (an identifier, so references still tokenise): the owner is the definition that
    mentions it first (stable names in sorted order, then the derived ones in the order
    they were named, each scanned in textual order), and k counts the derived names of this
    stem the owner mentions, in textual order. The renaming is injective within one
    program, so equal canonical programs are equal up to renaming. A derived definition that
    nothing mentions keeps its name (a coarser key).
    """
    derived = {name for name in texts if counter_stem(name) != name}
    assigned: dict[str, str] = {}
    queue: list[tuple[str, str]] = []
    counts: dict[tuple[str, str], int] = {}

    def scan(owner: str, text: str) -> None:
        def visit(segment: str) -> str:
            for match in _IDENT.finditer(segment):
                name = match.group(2)
                if name in derived and name not in assigned:
                    stem = counter_stem(name)
                    index = counts.get((owner, stem), 0)
                    counts[(owner, stem)] = index + 1
                    assigned[name] = f"{stem}__canon__{_short(owner)}__{index}"
                    queue.append((name, assigned[name]))
            return segment

        map_code(text, visit)

    for name in sorted(texts):
        if name not in derived:
            scan(name, texts[name])
    position = 0
    while position < len(queue):
        name, canonical = queue[position]
        position += 1
        scan(canonical, texts[name])
    if len(set(assigned.values())) != len(assigned):
        raise ParseError("the canonical renaming is not injective")
    clash = set(assigned.values()) & set(texts)
    if clash:
        raise ParseError(f"canonical name collides with a defined name: {sorted(clash)[:3]}")
    return assigned


def apply_names(text: str, names: dict[str, str]) -> str:
    def replace(match: re.Match[str]) -> str:
        tag, name = match.groups()
        new = names.get(name, name)
        return f"{tag} {new}" if tag else new

    return map_code(text, lambda segment: _IDENT.sub(replace, segment))


def _merge_bodies(keys: list[str], bodies: list[str]) -> dict[str, str]:
    merged: dict[str, str] = {}
    for key, body in zip(keys, bodies):
        merged[key] = merged.get(key, "") + "\n" + body
    return merged


def _joint_names(shared: list[str], owners: dict[str, set[str]], bodies: dict[str, str]) -> dict[str, str]:
    """Fresh names for local-looking names shared by several definitions (injective)."""
    groups: dict[tuple[str, ...], list[str]] = {}
    for name in shared:
        groups.setdefault(tuple(sorted(owners[name])), []).append(name)
    joint: dict[str, str] = {}
    for group, names in groups.items():
        first = bodies[group[0]]
        ordered = sorted(names, key=lambda n: (first.find(n), n))
        tag = hashlib.sha256("|".join(group).encode()).hexdigest()[:16]
        for index, name in enumerate(ordered):
            joint[name] = f"__J_{tag}_{local_kind(name)}_{index}"
    if len(set(joint.values())) != len(joint):
        raise ParseError("the joint renaming of shared locals is not injective")
    return joint


def _rename_exact(segment: str, joint: dict[str, str]) -> str:
    if not joint:
        return segment
    return _LOCAL.sub(lambda m: joint.get(m.group(1), m.group(1)), segment)


_HOOKS = re.compile(r"__attribute__\s*\(\(\s*(?:constructor|destructor)|\batexit\s*\(|\bon_exit\s*\(")


def parse_program(
    text: str,
    *,
    layout: bool = True,
    forbidden_paths: tuple[str, ...] = (),
    allow_token_pasting: bool = False,
) -> Program:
    """Split, name, normalise and cross-reference a generated C file.

    `layout=False` turns the layout-index normalisation off (raw indices stay in the keys).
    `forbidden_paths` are strings that must not occur outside `#line` directives (for example
    the checkout root); the occurrences are counted in `path_hits`. Raises ParseError for a
    `##` (a reference built by token pasting is invisible to the scan), for a start-up or
    exit hook (`constructor`, `destructor`, `atexit`, `on_exit`): code that runs without being
    reachable from an entry, and for a canonical renaming that is not injective.
    """
    pastes = text.count("##")
    if pastes and not allow_token_pasting:
        raise ParseError(f"{pastes} token pastes (`##`) in the generated C: a reference built that way is invisible to the scan")
    hooks = len(_HOOKS.findall(text))
    if hooks:
        raise ParseError(f"{hooks} constructor, destructor or exit hooks in the generated C: code that runs outside every entry")
    items, residue, account = split_items(text)
    keyed: list[tuple[str, RawItem]] = []
    unnamed: list[str] = []
    for item in items:
        key = item_key(item)
        if key is None:
            unnamed.append(item.text)
        else:
            keyed.append((key, item))
    bare = [key.split(" ", 1)[1] if " " in key else key for key, _ in keyed]
    texts: dict[str, str] = {}
    for name, (_, item) in zip(bare, keyed):
        texts[name] = texts.get(name, "") + "\n" + item.text
    # The layout table names every type: it must not own the derived names it mentions.
    names = canonical_names({n: t for n, t in texts.items() if n != _LAYOUT_TABLE})
    entries: dict[int, str] | None = None
    if layout and _LAYOUT_TABLE in texts:
        entries = parse_layout_table(apply_names(texts[_LAYOUT_TABLE], names))
    defined = frozenset(names.get(n, n) for n in bare)
    rewritten = fallbacks = fallback_definitions = 0
    keys: list[str] = []
    bodies: list[str] = []
    for (key, item), name in zip(keyed, bare):
        canonical = names.get(name, name)
        keys.append(key.replace(name, canonical, 1) if key != name else canonical)
        body = apply_names(item.text, names)
        if layout and name != _LAYOUT_TABLE:
            body, done, missed = rewrite_layout_indices(body, entries or {})
            rewritten += done
            fallbacks += missed
            fallback_definitions += 1 if missed else 0
        bodies.append(body)
    # A name that looks like a local is renamed per definition when it occurs in one definition.
    # A closure and its parent share the names of the captured variables: a name that occurs in
    # several definitions and nowhere else (not in the residue, not in an unnamed item) is
    # renamed jointly, by the set of definitions that contain it and the order of first
    # appearance in the first of them. Anything else is left as it is and counted.
    owners: dict[str, set[str]] = {}
    for key, body in zip(keys, bodies):
        for candidate in local_candidates(body):
            owners.setdefault(candidate, set()).add(key)
    outside = local_candidates(residue)
    for u in unnamed:
        outside |= local_candidates(u)
    nonlocal_names = sorted(n for n in owners if n in outside and n not in defined)
    shared = sorted(n for n, o in owners.items() if len(o) > 1 and n not in outside and n not in defined)
    joint = _joint_names(shared, owners, dict(zip(keys, bodies)) if len(set(keys)) == len(keys) else _merge_bodies(keys, bodies))
    keep = defined | frozenset(nonlocal_names) | frozenset(joint)
    definitions: dict[str, Definition] = {}
    for key, body, (_, item) in zip(keys, bodies, keyed):
        normalised = rename_locals(map_code(body, lambda segment: _rename_exact(segment, joint)), keep)
        definition = definitions.setdefault(key, Definition())
        definition.parts.append(normalised)
        definition.refs |= identifiers(normalised)
        definition.is_function = definition.is_function or item.is_function
    for key, definition in definitions.items():
        definition.refs = {r for r in definition.refs if r in definitions and r != key}
    if layout and entries is not None and fallbacks == 0:
        # Every header carries its entry; the runtime reads the table only through headers.
        for definition in definitions.values():
            definition.refs.discard(_LAYOUT_TABLE)
    hits = 0
    for path in forbidden_paths:
        hits += residue.count(path)
        hits += sum(u.count(path) for u in unnamed)
        hits += sum(p.count(path) for d in definitions.values() for p in d.parts)
    normalisations = NORMALISATION_BASE + ((NORMALISATION_LAYOUT,) if layout else ())
    return Program(
        definitions,
        residue,
        unnamed,
        account,
        normalisations,
        layout_rewritten=rewritten,
        layout_fallbacks=fallbacks,
        layout_fallback_definitions=fallback_definitions,
        path_hits=hits,
        nonlocal_names=nonlocal_names,
        shared_locals=len(joint),
        renamed_locals=frozenset(n for n in owners if n not in defined and n not in nonlocal_names),
    )


# ---------------------------------------------------------------------------------------
# Closures and fingerprints
# ---------------------------------------------------------------------------------------


class UnknownEntryError(KeyError):
    """An entry (or a start-up root) is not a definition of the program."""


# What runs in the process of a unit although no entry reaches it by references, and where
# the key covers it:
# * the C `main` and `moonbit_init()`, which assigns every global of every package before
#   the first entry runs: `START_UP`, part of every fingerprint, closure included (a changed
#   initialiser of a top-level `let` changes `moonbit_init` and so every key);
# * the runtime (`runtime.c`, the GC, `moonbit_runtime_init`) and the native stubs of the
#   library and of the dependencies: the toolchain key hashes their sources and objects;
# * constructors, destructors and exit handlers: none exist in the generated C, the stubs
#   or the runtime today; `parse_program` raises when one appears;
# * code reached through a function pointer in data is reached by references (the pointer is
#   an occurrence of a defined name); a callback the runtime calls on its own is registered
#   by code that an entry reaches or by `moonbit_init`;
# * a reference built by token pasting: `parse_program` raises on `##`;
# * the object-header layout table, read by the runtime through headers: the entry of every
#   header is inlined in the code that builds it (see `rewrite_layout_indices`).
START_UP = ("moonbit_init", "main")


def reachable(program: Program, entry: str | Iterable[str], cut: Collection[str] = ()) -> set[str]:
    """The names reachable from the entries through references (the entries included).

    A name in `cut` that is reached is in the result but its references are not followed
    (an entry itself is always followed). Raises UnknownEntryError for an entry that is not
    a definition.
    """
    roots = [entry] if isinstance(entry, str) else list(entry)
    for root in roots:
        if root not in program.definitions:
            raise UnknownEntryError(root)
    seen: set[str] = set()
    stack = list(roots)
    followed = set(roots)
    while stack:
        name = stack.pop()
        if name in seen:
            continue
        seen.add(name)
        if name in cut and name not in followed:
            continue
        stack.extend(r for r in program.definitions[name].refs if r not in seen)
    return seen


def fingerprint(
    program: Program,
    entry: str | Iterable[str],
    *,
    cut: Collection[str] = (),
    startup: bool = True,
) -> str:
    """The fingerprint of the code a unit with these entries can run, residue and start-up included.

    The roots are the entries and, unless `startup=False`, `START_UP`. Names in `cut` (the
    dispatchers that lead to other units) are covered by their own text only. The version of
    the normalisations and the residue digest are part of the digest.
    """
    roots = [entry] if isinstance(entry, str) else list(entry)
    if startup:
        roots = [*START_UP, *roots]
    digest = hashlib.sha256()
    digest.update(program.version.encode())
    digest.update(program.residue_digest.encode())
    for name in sorted(reachable(program, roots, cut)):
        digest.update(name.encode())
        digest.update(program.definitions[name].digest.encode())
    return digest.hexdigest()


def read_c_file(path: Path, *, layout: bool = True, forbidden_paths: tuple[str, ...] = ()) -> Program:
    text = path.read_text(encoding="utf-8", errors="replace")
    return parse_program(text, layout=layout, forbidden_paths=forbidden_paths)


# ---------------------------------------------------------------------------------------
# The toolchain part of a key
# ---------------------------------------------------------------------------------------

_NATIVE_KEYWORDS = re.compile(r"native-stub|cc-flags|link-flags|stub-cc|link-libs|\bcc\b\s*:")
_GETENV = re.compile(r'getenv\(\s*"([A-Za-z_][A-Za-z0-9_]*)"\s*\)')
_SOURCE_SUFFIXES = (".c", ".h", ".s", ".S", ".asm")


def toolchain_digest(parts: dict[str, str]) -> str:
    """The digest of the named parts of a toolchain description (pure)."""
    digest = hashlib.sha256()
    for name in sorted(parts):
        digest.update(f"{name}={parts[name]}\n".encode())
    return digest.hexdigest()


def env_names_read(sources: list[str]) -> list[str]:
    """Names of the environment variables the given C sources read with `getenv`."""
    return sorted({name for text in sources for name in _GETENV.findall(text)})


def file_hash(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def hash_tree(paths: list[Path], root: Path) -> str:
    """One digest over (relative path, content hash) of each file, sorted by path."""
    digest = hashlib.sha256()
    for path in sorted(paths):
        try:
            label = str(path.relative_to(root))
        except ValueError:
            label = str(path)
        digest.update(f"{label}:{file_hash(path)}\n".encode())
    return digest.hexdigest()


def compile_commands(dry_run_output: str, target_dir: Path, repo_root: Path) -> str:
    """The C compiler, archiver and linker command lines of a `moon ... --dry-run` (pure).

    The `moonc` lines are dropped (their result is the generated C that is fingerprinted); the
    others are kept with the target directory written `<target>` and the checkout `<repo>`.
    """
    lines = []
    for line in dry_run_output.splitlines():
        if not line.strip() or line.startswith("moonc "):
            continue
        lines.append(line.replace(str(target_dir), "<target>").replace(str(repo_root), "<repo>"))
    return "\n".join(lines)


_COMPILED_SOURCE = re.compile(r"(?:^|\s)'?(\./[^\s']+\.(?:c|s|S))'?(?=\s|$)")


def named_sources(commands: str) -> set[str]:
    """Source files inside the checkout that the compile commands name (paths relative to it)."""
    return {m.group(1)[2:] for m in _COMPILED_SOURCE.finditer(commands)}


def unhashed_sources(commands: str, hashed: set[str]) -> list[str]:
    """Source files that the compile commands name inside the checkout and the key does not hash."""
    return sorted(named_sources(commands) - hashed)


def count_token_pastes(paths: list[Path]) -> int:
    return sum(p.read_text(errors="replace").count("##") for p in paths)


def toolchain_problems(parts: dict[str, str]) -> list[str]:
    """What makes a toolchain description unusable as a key (pure); an empty list is fine."""
    problems = []
    if parts.get("compile-commands", "<not collected>") == "<not collected>":
        problems.append("the compile and link commands of moon were not collected")
    if parts.get("unhashed-sources", ""):
        problems.append("compiled sources the key does not hash: " + parts["unhashed-sources"])
    if parts.get("token-pasting-headers", "0") != "0":
        problems.append(f"{parts['token-pasting-headers']} token pastes in the hashed headers and stubs")
    return problems


STUB_ROOTS = ("library", "tooling", ".mooncakes")


def source_files(repo_root: Path, moon_home: Path) -> tuple[list[Path], list[Path], list[Path]]:
    """(runtime sources, runtime headers, native stub sources) that the key hashes."""
    runtime = [p for p in (moon_home / "lib" / "runtime").rglob("*") if p.suffix in _SOURCE_SUFFIXES + (".js",) and p.is_file()]
    headers = [p for p in (moon_home / "include").glob("*.h") if p.is_file()]
    stubs: list[Path] = []
    for top in STUB_ROOTS:
        stubs.extend(
            p
            for p in (repo_root / top).rglob("*")
            if p.suffix in _SOURCE_SUFFIXES and p.is_file() and "_build" not in p.parts
        )
    return runtime, headers, stubs


def local_name_overlap(program: Program, repo_root: Path, moon_home: Path) -> list[str]:
    """Names renamed as locals that also occur in the hashed headers, runtime or stub sources.

    A name declared there is not local to one definition. Expected: none."""
    runtime, headers, stubs = source_files(repo_root, moon_home)
    seen: set[str] = set()
    for path in runtime + headers + stubs:
        seen |= local_candidates(path.read_text(errors="replace"))
    return sorted(seen & program.renamed_locals)


def collect_toolchain(
    repo_root: Path,
    moon_home: Path,
    run: Callable[[list[str]], str],
    stage_env: dict[str, str] | None = None,
    environ: dict[str, str] | None = None,
    build_commands: str | None = None,
) -> dict[str, str]:
    """Everything outside the generated C that the code of a unit depends on.

    `run` executes a command and returns its output (an empty string when it cannot run).
    `build_commands` is the output of `compile_commands` for the release native build of the
    program. The parts: `moon` and `moonc` versions, the compile and link command lines of
    `moon` (the compiler, flags and defines it really uses), the C compiler and its target, the
    CPU model, the runtime sources, headers and prebuilt objects of the toolchain, the native
    stub sources of the repository and of the dependencies (`.mooncakes`; the count per root is
    in `stub-files:<root>`) and the package files that set native options, the values of every
    environment variable the stub sources read, and the variables a stage sets.
    """
    environ = dict(os.environ if environ is None else environ)
    stage_env = dict(stage_env or {})
    parts: dict[str, str] = {
        "moon": run(["moon", "version"]).strip(),
        "moonc": run(["moonc", "-v"]).strip(),
        "cc": run(["cc", "--version"]).strip(),
        "cc-target": run(["cc", "-dumpmachine"]).strip(),
        "cpu": run(["sysctl", "-n", "machdep.cpu.brand_string"]).strip() or platform.machine(),
        "platform": platform.platform(),
        "compile-commands": build_commands if build_commands is not None else "<not collected>",
    }
    runtime, headers, stubs = source_files(repo_root, moon_home)
    prebuilt = [p for p in (moon_home / "lib").glob("*") if p.suffix in (".o", ".a") and p.is_file()]
    parts["runtime-sources"] = hash_tree(runtime, moon_home)
    parts["runtime-headers"] = hash_tree(headers, moon_home)
    parts["runtime-objects"] = hash_tree(prebuilt, moon_home)
    for top in STUB_ROOTS:
        parts[f"stub-files:{top}"] = str(sum(1 for p in stubs if (repo_root / top) in p.parents))
    parts["native-stubs"] = hash_tree(stubs, repo_root)
    parts["unhashed-sources"] = ",".join(
        unhashed_sources(parts["compile-commands"], {str(p.relative_to(repo_root)) for p in stubs})
    ) if build_commands is not None else ""
    # Every stub is hashed; pastes matter in the headers and in the stubs that are compiled
    # (all of them when the commands were not collected).
    compiled = stubs if build_commands is None else [p for p in stubs if str(p.relative_to(repo_root)) in named_sources(build_commands)]
    parts["token-pasting-headers"] = str(count_token_pastes(headers + compiled))
    option_files: list[Path] = []
    for top in ("library", "tooling"):
        for pkg in (repo_root / top).rglob("moon.pkg"):
            if "_build" not in pkg.parts and _NATIVE_KEYWORDS.search(pkg.read_text(errors="replace")):
                option_files.append(pkg)
        option_files.extend((repo_root / top).glob("moon.mod*"))
    parts["native-options"] = hash_tree(option_files, repo_root)
    read = env_names_read([p.read_text(errors="replace") for p in stubs if p.suffix == ".c"])
    for name in sorted(set(read) | {"CC", "CFLAGS", "LDFLAGS", "MOON_CC", "MOON_AR"}):
        parts[f"env:{name}"] = stage_env.get(name, environ.get(name, "<unset>"))
    for name in sorted(set(stage_env) - set(read)):
        parts[f"stage-env:{name}"] = stage_env[name]
    return parts


def run_command(command: list[str], cwd: Path | None = None) -> str:
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=300, cwd=cwd)
    except (OSError, subprocess.SubprocessError):
        return ""
    return result.stdout + result.stderr if result.returncode == 0 else ""


def moon_build_commands(repo_root: Path, target_dir: Path, run: Callable[..., str] = run_command) -> str | None:
    """`compile_commands` of the release native build of `tooling/src/cli`, or None if moon cannot print it."""
    output = run(
        ["moon", "--target-dir", str(target_dir), "run", "--release", "--target", "native",
         "--build-only", "tooling/src/cli", "--dry-run"],
        cwd=repo_root,
    )
    return compile_commands(output, target_dir, repo_root) if output.strip() else None


def report(program: Program) -> list[str]:
    """The summary lines of a parsed program (pure)."""
    functions = sum(1 for d in program.definitions.values() if d.is_function)
    account = program.account
    return [
        f"{len(program.definitions)} names ({functions} functions); normalisations: {program.version}",
        f"lines: {account.total} = {account.directives} #line + {account.blank} blank + "
        f"{account.residue} residue + {account.items} items; unaccounted {account.unaccounted}",
        f"residue {program.residue_bytes} bytes, unnamed items {len(program.unnamed)}",
        f"layout indices: {program.layout_rewritten} rewritten, {program.layout_fallbacks} left raw "
        f"in {program.layout_fallback_definitions} definitions",
        f"forbidden paths outside #line: {program.path_hits}",
        f"local-looking names: {program.shared_locals} shared by several definitions (renamed jointly), "
        f"{len(program.nonlocal_names)} also outside every definition (left as they are)",
    ]


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Fingerprint the code reachable from entries of a generated C file.")
    parser.add_argument("c_file", type=Path)
    parser.add_argument("entries", nargs="*", help="substrings of entry names")
    parser.add_argument("--cut", action="append", default=[], help="substring of a dispatcher name whose references are not followed")
    parser.add_argument("--no-layout", action="store_true", help="keep raw layout indices")
    parser.add_argument("--root", action="append", default=[], help="a path that must not occur outside #line")
    arguments = parser.parse_args(argv[1:])
    program = read_c_file(arguments.c_file, layout=not arguments.no_layout, forbidden_paths=tuple(arguments.root))
    print("\n".join(report(program)))
    cut = {n for n in program.definitions if any(c in n for c in arguments.cut)}
    for needle in arguments.entries:
        for name in sorted(n for n in program.definitions if needle in n)[:5]:
            roots = [*START_UP, name]
            print(f"{len(reachable(program, roots, cut)):6d} {fingerprint(program, name, cut=cut)[:12]} {name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
