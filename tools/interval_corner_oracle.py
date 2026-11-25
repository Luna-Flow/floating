#!/usr/bin/env python3
"""Independent hulls of sinpi, cospi and atan2 over intervals, for the tests of the `interval` package.

Level A in the sense of the oracle rule. The point values come from MPFR (through the C program
`tools/interval_forward_oracle.c`: `RNDD` and `RNDU` at the precision of the row, so the values are
already the directed p-bit numbers); the choice of the points is written here from the definitions:

* sinpi over [a, b]: the endpoints, and the extrema +1 at x = k + 1/2 with k even and -1 with k odd,
  for the k with k + 1/2 in [a, b]. cospi: the endpoints and the extrema at the integers x = k in
  [a, b], +1 for k even and -1 for k odd.
* atan2(y, x) over the box [y_lo, y_hi] x [x_lo, x_hi], without the origin (IEEE 1788-2015 Table 9.1
  note f: the principal value, discontinuous on y = 0, x < 0, where it is pi at y = +0). The box has
  the whole range [-pi, pi] when it has points on both sides of that half-line (x_lo < 0 and
  y_lo < 0 <= y_hi); otherwise the extreme angles are met at a corner other than the origin, or on
  an axis: (0, y_hi) with y_hi > 0 and (0, y_lo) with y_lo < 0 when 0 is in [x_lo, x_hi], and
  (x_hi, 0) with x_hi > 0 and (x_lo, 0) with x_lo < 0 when 0 is in [y_lo, y_hi]. The box {origin}
  is empty.

The pure logic is unit tested (tools/interval_corner_oracle_test.py), including a comparison with
the angles of a fine grid of the box computed with `math.atan2`.

`--write` writes `library/src/interval/corner_table_wbtest.mbt` (byte-stable; needs a C compiler and
MPFR, `--prefix` or `EXTBENCH_PREFIX`, default /opt/homebrew); `--check` recomputes it and compares
(skipped with a message when MPFR is not installed).
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from fractions import Fraction
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import interval_forward_oracle as forward  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[1]
TARGET = REPO_ROOT / "library/src/interval/corner_table_wbtest.mbt"
PRECISIONS = (5, 24)  # every value below has at most 5 bits
TRIG_VALUES = tuple(Fraction(*v) for v in (
    (-21, 4), (-3, 1), (-5, 2), (-3, 2), (-1, 1), (-3, 4), (-1, 2), (-1, 8), (0, 1), (1, 4), (1, 2), (5, 8),
    (1, 1), (5, 4), (3, 2), (7, 4), (2, 1), (19, 8), (3, 1), (7, 2), (9, 2), (7, 1),
))  # fmt: skip
ATAN2_VALUES = tuple(Fraction(*v) for v in ((-3, 1), (-3, 2), (-1, 2), (0, 1), (1, 2), (5, 4), (19, 8)))
GRID = tuple(Fraction(v) for v in (-2, -1, 0, 1, 2))

Point = tuple[Fraction, Fraction]  # (abscissa, ordinate)


def hex_text(value: Fraction) -> str:
    """`value` (a dyadic rational) as `[-]0x<odd>p<exp>`, or `0x0p0`."""
    if value == 0:
        return "0x0p0"
    numerator, denominator = value.numerator, value.denominator
    assert denominator & (denominator - 1) == 0, "not dyadic"
    exponent = -(denominator.bit_length() - 1)
    while numerator % 2 == 0:
        numerator //= 2
        exponent += 1
    sign = "-" if numerator < 0 else ""
    return f"{sign}0x{abs(numerator):x}p{exponent}"


def ceil_fraction(value: Fraction) -> int:
    return -((-value.numerator) // value.denominator)


def floor_fraction(value: Fraction) -> int:
    return value.numerator // value.denominator


def pi_scaled_extrema(op: str, a: Fraction, b: Fraction) -> tuple[bool, bool]:
    """(the value -1 is taken in [a, b], the value +1 is taken in [a, b]) for sinpi or cospi."""
    if op == "sinpi":  # extrema at x = k + 1/2: sinpi = +1 for k even, -1 for k odd
        ks = range(ceil_fraction(a - Fraction(1, 2)), floor_fraction(b - Fraction(1, 2)) + 1)
    else:  # cospi: extrema at x = k
        ks = range(ceil_fraction(a), floor_fraction(b) + 1)
    return any(k % 2 != 0 for k in ks), any(k % 2 == 0 for k in ks)


def atan2_plan(ylo: Fraction, yhi: Fraction, xlo: Fraction, xhi: Fraction) -> str | list[Point]:
    """`"empty"`, `"full"` ([-pi, pi]) or the points (x, y) whose angles give the hull."""
    if ylo == yhi == 0 and xlo == xhi == 0:
        return "empty"
    if xlo < 0 and ylo < 0 <= yhi:
        return "full"
    points: list[Point] = []
    for x in (xlo, xhi):
        for y in (ylo, yhi):
            if (x, y) != (0, 0) and (x, y) not in points:
                points.append((x, y))
    if xlo <= 0 <= xhi:
        for y in (ylo, yhi):
            if y != 0 and (Fraction(0), y) not in points:
                points.append((Fraction(0), y))
    if ylo <= 0 <= yhi:
        for x in (xlo, xhi):
            if x != 0 and (x, Fraction(0)) not in points:
                points.append((x, Fraction(0)))
    return points


Row = tuple  # (op, precision, operands..., result...)


def generate_rows() -> list[tuple[str, int, tuple[Fraction, ...]]]:
    rows: list[tuple[str, int, tuple[Fraction, ...]]] = []
    for p in PRECISIONS:
        for op in ("sinpi", "cospi"):
            for i, a in enumerate(TRIG_VALUES):
                for b in TRIG_VALUES[i:]:
                    rows.append((op, p, (a, b)))
        boxes = [(lo, hi) for i, lo in enumerate(ATAN2_VALUES) for hi in ATAN2_VALUES[i:]]
        grid = [(lo, hi) for i, lo in enumerate(GRID) for hi in GRID[i:]]
        seen: set[tuple[Fraction, ...]] = set()
        for family in (boxes, grid):
            for ylo, yhi in family:
                for xlo, xhi in family:
                    key = (ylo, yhi, xlo, xhi)
                    if key not in seen:
                        seen.add(key)
                        rows.append(("atan2", p, key))
    return rows


def point_requests(row: tuple[str, int, tuple[Fraction, ...]]) -> list[tuple[str, int, str, str | None]]:
    """The MPFR requests (op, precision, x, y) that the row needs."""
    op, p, operands = row
    if op != "atan2":
        return [(op, p, hex_text(v), None) for v in operands]
    plan = atan2_plan(*operands)
    if plan == "empty":
        return []
    if plan == "full":
        return [("atan2", p, "0x0p0", "-0x1p0")]  # atan2(+0, -1) = pi
    return [("atan2", p, hex_text(y), hex_text(x)) for (x, y) in plan]  # type: ignore[union-attr]


def input_text(requests: list[tuple[str, int, str, str | None]]) -> str:
    return "".join(f"{op} {p} {x}" + (f" {y}" if y is not None else "") + "\n" for op, p, x, y in requests)


def run_oracle(requests: list[tuple[str, int, str, str | None]], prefix: Path, cc: str) -> list[tuple[str, str]]:
    with tempfile.TemporaryDirectory() as tmp:
        directory = Path(tmp)
        binary = forward.compile_oracle(directory, prefix, cc)
        (directory / "in.txt").write_text(input_text(requests))
        subprocess.run([str(binary), str(directory / "in.txt"), str(directory / "out.txt")], check=True)
        pairs = [tuple(line.split()) for line in (directory / "out.txt").read_text().splitlines()]
    assert len(pairs) == len(requests)
    return [(lo, hi) for lo, hi in pairs]


def mpfr_value(text: str) -> Fraction:
    """The exact value of an MPFR `%Ra` text (`[-]0x1.8p+3`) or of the `hex_text` form."""
    sign = -1 if text.startswith("-") else 1
    body = text.lstrip("-")
    mantissa, _, exponent = body[2:].partition("p")
    whole, _, fraction = mantissa.partition(".")
    value = Fraction(int(whole or "0", 16)) + (Fraction(int(fraction, 16), 16 ** len(fraction)) if fraction else 0)
    return sign * value * Fraction(2) ** int(exponent)


def combine(row: tuple[str, int, tuple[Fraction, ...]], values: list[tuple[str, str]]) -> tuple[str, str]:
    """The bounds of the hull of the row, as texts, from the directed point values."""
    op, _, operands = row
    if op == "atan2":
        plan = atan2_plan(*operands)
        if plan == "empty":
            return "empty", "empty"
        lows = [mpfr_value(lo) for lo, _ in values]
        highs = [mpfr_value(hi) for _, hi in values]
        if plan == "full":
            return "-" + values[0][1].lstrip("-"), values[0][1]  # [-RU(pi), RU(pi)]
        return pick_text(values, min(lows), True), pick_text(values, max(highs), False)
    a, b = operands
    has_min, has_max = pi_scaled_extrema(op, a, b)
    lows = [mpfr_value(lo) for lo, _ in values]
    highs = [mpfr_value(hi) for _, hi in values]
    lo_text = "-0x1p+0" if has_min else pick_text(values, min(lows), True)
    hi_text = "0x1p+0" if has_max else pick_text(values, max(highs), False)
    return lo_text, hi_text


def pick_text(values: list[tuple[str, str]], target: Fraction, lower: bool) -> str:
    for lo, hi in values:
        text = lo if lower else hi
        if mpfr_value(text) == target:
            return text
    raise AssertionError("no value found")


def render(rows: list[tuple[str, int, tuple[Fraction, ...]]], texts: list[tuple[str, str]]) -> str:
    lines = [
        "///|",
        "// oracle-file: A",
        "// producer: tools/interval_corner_oracle.py (MPFR through tools/interval_forward_oracle.c)",
        "// input: sinpi and cospi over the intervals made of 22 dyadic values, and atan2 over the boxes of 7 values and of the grid -2, -1, 0, 1, 2,",
        "//   at p = 5 and 24; the hull of the directed p-bit values of MPFR at the endpoints, at the extrema (sinpi at k + 1/2, cospi at k) and,",
        "//   for atan2, at the corners and the axis points of the box; the whole range [-RU(pi), RU(pi)] across the half-line y = 0, x < 0",
        "// library-ran: no",
        "// shares: nothing; the table is read with Binary::from_hex and String::split only",
        "// check: python3 tools/interval_corner_oracle.py --check",
        "",
        "///|",
        "fn corner_table() -> String {",
        "  (",
    ]
    for (op, p, operands), (lo, hi) in zip(rows, texts):
        fields = [op, str(p)] + [hex_text(v) for v in operands] + [lo, hi]
        lines.append("    #|" + " ".join(fields))
    lines += ["  )", "}", ""]
    return "\n".join(lines)


def build(prefix: Path, cc: str) -> str:
    rows = generate_rows()
    requests: list[tuple[str, int, str, str | None]] = []
    spans: list[tuple[int, int]] = []
    for row in rows:
        asked = point_requests(row)
        spans.append((len(requests), len(requests) + len(asked)))
        requests.extend(asked)
    values = run_oracle(requests, prefix, cc)
    texts = [combine(row, values[start:end]) for row, (start, end) in zip(rows, spans)]
    return render(rows, texts)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--write", action="store_true")
    group.add_argument("--check", action="store_true")
    parser.add_argument("--prefix", type=Path, default=Path(os.environ.get("EXTBENCH_PREFIX", "/opt/homebrew")))
    parser.add_argument("--cc", default="cc")
    args = parser.parse_args(argv)
    have_mpfr = shutil.which(args.cc) is not None and (args.prefix / "include" / "mpfr.h").exists()
    if not have_mpfr:
        if args.check:
            print("interval_corner_oracle: no C compiler or no MPFR under the prefix; check skipped")
            return 0
        print("interval_corner_oracle: MPFR is required to write the table")
        return 2
    text = build(args.prefix, args.cc)
    if args.write:
        TARGET.write_text(text)
        return 0
    if not TARGET.exists() or TARGET.read_text() != text:
        print("the generated file differs from the oracle; run --write and review")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
