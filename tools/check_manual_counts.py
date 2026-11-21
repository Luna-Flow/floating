#!/usr/bin/env python3
"""Fail when a manual page or README states a corpus count that the manifests do not.

The pinned binary corpora and the committed smoke fixtures have their row counts
in `testdata/bin_float/corpora.json` and `testdata/bin_float/smoke/manifest.json`
(`expectedCases`). The pages that quote those counts (the verification page, the
binary conformance page, the testdata README) repeat them in prose; this check
reads the manifests and compares every quoted number, so a count cannot go stale
again without a failing test. A pattern that no longer matches a page is a
failure too (the page changed shape: update the pattern here).

    check_manual_counts.py          check the repository
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent


def fmt(number: int) -> str:
    return f"{number:,}"


def manifest_counts(root: Path = REPO) -> dict[str, int]:
    corpora = json.loads((root / "testdata/bin_float/corpora.json").read_text())
    smoke = json.loads((root / "testdata/bin_float/smoke/manifest.json").read_text())
    mpfr = {Path(entry["path"]).name: entry["expectedCases"] for entry in smoke["mpfr"]}
    counts = {
        "elementary": corpora["mpfrCorpora"]["mpfr-4.2.2-elementary"]["expectedCases"],
        "strtofr": corpora["mpfrCorpora"]["mpfr-4.2.2-strtofr"]["expectedCases"],
        "decimal-output": corpora["mpfrCorpora"]["mpfr-4.2.2-decimal-output"]["expectedCases"],
        "sqrt-data": corpora["artifacts"]["mpfr-4.2.2-sqrt"]["expectedExecutableRows"],
        "testfloat-smoke": sum(entry["expectedCases"] for entry in smoke["testfloat"]),
        "hex-sqrt": mpfr["mpfr-hex-sqrt.txt"],
        "pow-si": mpfr["mpfr-pow-si.txt"],
    }
    counts["smoke-total"] = (
        counts["testfloat-smoke"]
        + counts["hex-sqrt"]
        + counts["pow-si"]
        + counts["elementary"]
        + counts["strtofr"]
        + counts["decimal-output"]
    )
    # the fixtures of the manifest must agree with the files themselves
    for name, key in (
        ("mpfr-4.2.2-elementary.txt", "elementary"),
        ("mpfr-4.2.2-strtofr.txt", "strtofr"),
        ("mpfr-4.2.2-decimal-output.txt", "decimal-output"),
    ):
        rows = [
            line
            for line in (root / "testdata/bin_float" / name).read_text().splitlines()
            if line and not line.startswith("#")
        ]
        if len(rows) != counts[key]:
            raise ValueError(f"{name}: manifest says {counts[key]} rows, the file has {len(rows)}")
    return counts


# (page, pattern with one group, key): the text of the page is whitespace
# normalised first, so a line break inside a sentence does not matter.
CLAIMS: list[tuple[str, str, str]] = [
    ("doc/manual/verification.md", r"([\d,]+) hash-pinned witnesses covering 29 elementary", "elementary"),
    ("doc/manual/verification.md", r"([\d,]+) `mpfr_strtofr` witnesses \(decimal text", "strtofr"),
    ("doc/manual/verification.md", r"and ([\d,]+) `mpfr_get_str` witnesses", "decimal-output"),
    ("doc/manual/verification.md", r"adds the ([\d,]+) executable rows of the pinned square-root data", "sqrt-data"),
    ("doc/manual/verification.md", r"binary smoke, for example, has ([\d,]+) rows", "smoke-total"),
    ("doc/manual/verification.md", r"rows \(([\d,]+) TestFloat vectors,", "testfloat-smoke"),
    ("doc/manual/verification.md", r"vectors, ([\d,]+) square-root witnesses,", "hex-sqrt"),
    ("doc/manual/verification.md", r"witnesses, ([\d,]+) integer-power witnesses,", "pow-si"),
    ("doc/manual/verification.md", r"integer-power witnesses, ([\d,]+) elementary witnesses,", "elementary"),
    ("doc/manual/verification.md", r"elementary witnesses, ([\d,]+) `strtofr` witnesses", "strtofr"),
    ("doc/manual/verification.md", r"`strtofr` witnesses and ([\d,]+) decimal output witnesses", "decimal-output"),
    ("doc/manual/conformance/bin_float.md", r"`mpfr_strtofr` corpus \(([\d,]+) rows\)", "strtofr"),
    ("doc/manual/conformance/bin_float.md", r"`mpfr_get_str` corpus \(([\d,]+) rows\)", "decimal-output"),
    ("doc/manual/conformance/bin_float.md", r"MPFR elementary fixture \(([\d,]+) rows\)", "elementary"),
    ("doc/manual/conformance/bin_float.md", r"all executable hexadecimal sqrt rows \| ([\d,]+) / ([\d,]+) \|", "sqrt-data"),
    ("doc/manual/conformance/bin_float.md", r"`pow_si` fixture \| [^|]*\| ([\d,]+) / ([\d,]+) \|", "pow-si"),
    ("doc/manual/conformance/bin_float.md", r"elementary fixture \| 29 operations[^|]*\| ([\d,]+) / ([\d,]+) \|", "elementary"),
    ("doc/manual/conformance/bin_float.md", r"`mpfr_strtofr` fixture \|[^|]*\| ([\d,]+) / ([\d,]+) \|", "strtofr"),
    ("doc/manual/conformance/bin_float.md", r"`mpfr_get_str` fixture \|[^|]*\| ([\d,]+) / ([\d,]+) \|", "decimal-output"),
    ("doc/manual/conformance/bin_float.md", r"Committed smoke \|[^|]*\| ([\d,]+) / ([\d,]+) \|", "smoke-total"),
    ("doc/manual/conformance/bin_float.md", r"the ([\d,]+)-row hash-pinned fixture remains", "elementary"),
    ("testdata/bin_float/README.md", r"runs the committed ([\d,]+)-row TestFloat subset", "testfloat-smoke"),
    ("testdata/bin_float/README.md", r"([\d,]+) MPFR-generated integer-power witnesses", "pow-si"),
    ("testdata/bin_float/README.md", r"([\d,]+) full-family elementary witnesses", "elementary"),
    ("testdata/bin_float/README.md", r"([\d,]+) `mpfr_strtofr` witnesses", "strtofr"),
    ("testdata/bin_float/README.md", r"([\d,]+) `mpfr_get_str` witnesses", "decimal-output"),
]


def normalised(path: Path) -> str:
    return re.sub(r"\s+", " ", path.read_text())


def check(root: Path = REPO) -> list[str]:
    counts = manifest_counts(root)
    problems: list[str] = []
    cache: dict[str, str] = {}
    for page, pattern, key in CLAIMS:
        text = cache.setdefault(page, normalised(root / page))
        matches = re.findall(pattern, text)
        if not matches:
            problems.append(f"{page}: no match for {pattern!r} (the page changed shape: update tools/check_manual_counts.py)")
            continue
        for match in matches:
            for number in (match,) if isinstance(match, str) else match:
                if number != fmt(counts[key]):
                    problems.append(f"{page}: says {number} for {key}, the manifest says {fmt(counts[key])}")
    return problems


def main() -> int:
    problems = check()
    for problem in problems:
        sys.stderr.write(problem + "\n")
    if not problems:
        print(f"check_manual_counts: ok ({len(CLAIMS)} claims)")
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
