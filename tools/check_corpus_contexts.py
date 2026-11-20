#!/usr/bin/env python3
"""Check that every checked-in row file and generated table has only legal contexts.

The rules are those of `tools/context_rules.py` (the one definition, tested against
the library constructors by `testdata/context_vectors.txt`). The generators validate
what they emit when they construct a context through the module; this gate covers
what they cannot: a table edited by hand, a generator that builds a context some other
way, and the white-box tables compiled into the tests.

Files read: the binary and decimal text rows of `testdata/` (the context columns are
named by the `# id op ...` header line of the file), the `decTest` files (the
`precision`, `maxexponent`, `minexponent`, `rounding` and `clamp` directives), and the
tuple tables of `library/src/decimal/*_rows_wbtest.mbt`. A path that matches no file is
an error, so a moved or renamed table cannot drop out of the check unnoticed.
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

import context_rules as cr

REPO_ROOT = Path(__file__).resolve().parent.parent

DECIMAL_TEXT_GLOBS = ("testdata/decimal/ieee/rows/*.txt", "testdata/decimal/random/*.txt")
BINARY_TEXT_GLOBS = ("testdata/bin_float/mpfr-4.2.2-random.txt", "testdata/bin_float/random-regressions.txt")
DECTEST_GLOBS = ("testdata/decimal_gda/*.decTest", "testdata/decimal_gda/random/*.decTest")
FETCHED_DECTEST_GLOBS = ("testdata/decimal_gda/official/**/*.decTest", "testdata/decimal_gda/official0/**/*.decTest")  # git-ignored
TABLE_GLOBS = ("library/src/decimal/*_rows_wbtest.mbt",)


@dataclass
class Report:
    """What one file has: its rows, the distinct contexts, and the illegal ones with a reason."""

    path: str
    rows: int = 0
    contexts: set[tuple[object, ...]] = field(default_factory=set)
    illegal: dict[tuple[object, ...], str] = field(default_factory=dict)

    def add(self, key: tuple[object, ...], problem: str | None) -> None:
        self.rows += 1
        self.contexts.add(key)
        if problem is not None:
            self.illegal.setdefault(key, problem)


def _problem(check: object, *arguments: object) -> str | None:
    try:
        check(*arguments)  # type: ignore[operator]
    except ValueError as error:
        return str(error)
    return None


# ---------------------------------------------------------------------------
# Text rows
# ---------------------------------------------------------------------------


def _columns(text: str) -> list[str]:
    """The column names of the last `# id op ...` header line of a row file."""
    names: list[str] = []
    for line in text.splitlines():
        if line.startswith("# id op"):
            names = line[1:].split()
    if not names:
        raise ValueError("no `# id op ...` header line")
    return names


def scan_decimal_text(text: str, path: str = "") -> Report:
    """`decimal` rows: `precision`, `rounding` and `emax` (v2), with `emin`, `clamp` and `tininess` when the file has them (v1)."""
    report = Report(path)
    names = _columns(text)
    column = {name: names.index(name) for name in names}
    for line in text.splitlines():
        if line.startswith("#") or not line.strip():
            continue
        fields = line.split()
        rounding = fields[column["rounding"]]
        precision = int(fields[column["precision"]])
        emax = int(fields[column["emax"]])
        emin = int(fields[column["emin"]]) if "emin" in column else 1 - emax
        clamp = int(fields[column["clamp"]]) if "clamp" in column else 1
        tininess = fields[column["tininess"]] if "tininess" in column else "b"
        report.add((rounding, precision, emin, emax, clamp, tininess), _problem(cr.check_ieee_decimal_context, precision, rounding, emin, emax, clamp, tininess))
    return report


def scan_binary_text(text: str, path: str = "") -> Report:
    """`bin_float` rows: `rounding`, `precision`, `emin`, `emax` (`-` for the implementation range) and `tininess`."""
    report = Report(path)
    names = _columns(text)
    column = {name: names.index(name) for name in names}
    for line in text.splitlines():
        if line.startswith("#") or not line.strip():
            continue
        fields = line.split()
        rounding, tininess = fields[column["rounding"]], fields[column["tininess"]]
        precision = int(fields[column["precision"]])
        emin = None if fields[column["emin"]] == "-" else int(fields[column["emin"]])
        emax = None if fields[column["emax"]] == "-" else int(fields[column["emax"]])
        # A row without a range (`- - -`) is the precision alone and carries no tininess rule (`-`).
        rule = "a" if (emin is None and emax is None and tininess == "-") else tininess
        report.add((rounding, precision, emin, emax, tininess), _problem(cr.check_binary_context, precision, emax, emin, rounding, rule))
    return report


# ---------------------------------------------------------------------------
# decTest
# ---------------------------------------------------------------------------


def scan_dectest(text: str, path: str = "") -> Report:
    """`decTest` rows: the context is the set of directives in force when a test line is reached."""
    report = Report(path)
    directives: dict[str, str] = {}
    for raw in text.splitlines():
        line = raw.split("--")[0].strip()
        if not line:
            continue
        match = re.match(r"(\w+):\s*(\S+)$", line)
        if match:
            directives[match.group(1).lower()] = match.group(2)
            continue
        if "->" not in line:
            continue
        try:
            precision = int(directives["precision"])
            emax = int(directives["maxexponent"])
            emin = int(directives["minexponent"])
        except (KeyError, ValueError):
            continue
        rounding = directives.get("rounding", "half_even")
        clamp = int(directives.get("clamp", "0"))
        report.add((precision, emin, emax, rounding, clamp), _problem(cr.check_gda_context, precision, emin, emax, rounding, clamp))
    return report


# ---------------------------------------------------------------------------
# The tuple tables compiled into the white-box tests of `decimal`
# ---------------------------------------------------------------------------

_ROUNDING = r'"(half_even|half_up|down|ceiling|floor|half_down|up|05up)"'
# (op, rounding, precision, e_min, e_max, clamp[, tininess], ...): pm1, rcp, pi_inverse, exp_range, atan2pi_scaled
_WIDE_ROW = re.compile(r'\(\s*"[a-z0-9_]+",\s*' + _ROUNDING + r",\s*(\d+),\s*(-?\d+),\s*(-?\d+),\s*(true|false)(?:,\s*\"([ab])\")?")
# (op, precision, e_max, rounding, ...): ieee_ops
_NARROW_ROW = re.compile(r'\(\s*"[a-z0-9_]+",\s*(\d+),\s*(\d+),\s*' + _ROUNDING)


def scan_mbt_tables(text: str, path: str = "") -> Report:
    report = Report(path)
    for match in _WIDE_ROW.finditer(text):
        rounding, precision, emin, emax = match.group(1), int(match.group(2)), int(match.group(3)), int(match.group(4))
        clamp, tininess = int(match.group(5) == "true"), match.group(6) or "b"
        report.add((rounding, precision, emin, emax, clamp, tininess), _problem(cr.check_ieee_decimal_context, precision, rounding, emin, emax, clamp, tininess))
    for match in _NARROW_ROW.finditer(text):
        precision, emax, rounding = int(match.group(1)), int(match.group(2)), match.group(3)
        report.add((rounding, precision, 1 - emax, emax, 1, "b"), _problem(cr.check_ieee_decimal_context, precision, rounding, 1 - emax, emax, 1, "b"))
    return report


# ---------------------------------------------------------------------------
# The repository
# ---------------------------------------------------------------------------


def scan_repository(root: Path = REPO_ROOT) -> tuple[list[Report], list[str]]:
    """Every report, and the globs that matched nothing (errors, except the fetched corpora)."""
    reports: list[Report] = []
    missing: list[str] = []
    groups = (
        (DECIMAL_TEXT_GLOBS, scan_decimal_text, True),
        (BINARY_TEXT_GLOBS, scan_binary_text, True),
        (DECTEST_GLOBS, scan_dectest, True),
        (FETCHED_DECTEST_GLOBS, scan_dectest, False),
        (TABLE_GLOBS, scan_mbt_tables, True),
    )
    for globs, scan, required in groups:
        for pattern in globs:
            paths = sorted(root.glob(pattern))
            if not paths and required:
                missing.append(pattern)
            for path in paths:
                report = scan(path.read_text(encoding="utf-8", errors="replace"), str(path.relative_to(root)))
                if scan is scan_mbt_tables and report.rows == 0:
                    continue  # a table of another shape (conversion rows and the like)
                reports.append(report)
    return reports, missing


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", type=Path, default=REPO_ROOT)
    arguments = parser.parse_args(argv)
    reports, missing = scan_repository(arguments.root)
    failed = False
    for report in reports:
        status = "ok" if not report.illegal else f"{len(report.illegal)} ILLEGAL"
        print(f"{report.path}: {report.rows} rows, {len(report.contexts)} contexts, {status}")
        for key, problem in list(report.illegal.items())[:5]:
            print(f"    {key}: {problem}")
        failed = failed or bool(report.illegal)
    for pattern in missing:
        print(f"check_corpus_contexts: no file matches {pattern}", file=sys.stderr)
        failed = True
    total = sum(report.rows for report in reports)
    print(f"check_corpus_contexts: {len(reports)} files, {total} rows, {'FAILED' if failed else 'all contexts legal'}")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
