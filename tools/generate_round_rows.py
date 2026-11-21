#!/usr/bin/env python3
"""Rows for the rounding core `binary_round_dyadic` (IEEE 754-2019 4.3, 7.4, 7.5), exponents included.

Writes `library/src/binary/round_rows_wbtest.mbt`: a magnitude `m` (a positive integer) and an exponent
`e` give the value `(-1)^s m 2^e`; the row says what rounding it into the context (precision p, e_max,
e_min = 1 - e_max, a rounding direction, a tininess rule) gives, with the flags. The contexts are binary16,
binary32, binary64, three toy formats and the implementation range (e_max = 2^30 - 1) at nine precisions;
the magnitudes are all ones (a carry to a power of two), all ones with a low tail (halfway and just above),
a power of two, 3, 1 and random ones; the leading bit sits around e_min, e_max and, for the implementation
range, at both ends of the exponent range, where a value cannot be built as a rational (2^(2^30)).

The same table has rows for the square root (`binary_round_sqrt`): perfect squares and their neighbours,
`r^2 + r` and `r^2 + r + 1` (either side of the midpoint of the next position), `(2r + 1)^2`, all ones, at
exponents that put the root in the normal, subnormal and overflowing ranges and at the limits of Int32.

The expected result is integer arithmetic only (a shift, a quotient, a remainder, `math.isqrt`), written from the standard
and checked in `generate_round_rows_test.py` against the Fraction-based `generate_hex_ctx_rows.convert` on
small ranges. It does not come from the library.

    python3 tools/generate_round_rows.py && moon fmt
    python3 tools/generate_round_rows.py --check
"""

from __future__ import annotations

import argparse
import random
import sys
from math import isqrt
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "library/src/binary/round_rows_wbtest.mbt"
MODES = ["RNE", "RNA", "RTZ", "RTP", "RTN"]
TININESS = ["before", "after"]
IMPL_EMAX = 2**30 - 1
IMPL_EMIN = 1 - IMPL_EMAX
FORMATS = [(11, 15), (24, 127), (53, 1023), (7, 20), (1, 3), (5, 10)]
IMPL_PRECISIONS = [1, 2, 5, 24, 53, 64, 100, 130, 200]


def round_count(m: int, shift: int, negative: bool, mode: str) -> tuple[int, bool]:
    """m / 2^shift (shift > 0) rounded to an integer by `mode`: (count, inexact)."""
    quotient, rest = m >> shift, m & ((1 << shift) - 1)
    if rest == 0:
        return quotient, False
    half = 1 << (shift - 1)
    if mode == "RNE":
        up = rest > half or (rest == half and quotient % 2 == 1)
    elif mode == "RNA":
        up = rest >= half
    elif mode == "RTZ":
        up = False
    elif mode == "RTP":
        up = not negative
    else:
        up = negative
    return quotient + (1 if up else 0), True


def render(negative: bool, count: int, grid: int) -> str:
    if count == 0:
        return "-0" if negative else "0"
    while count % 2 == 0:
        count //= 2
        grid += 1
    return f"{'-' if negative else ''}{count}p{grid}"


def round_dyadic(negative: bool, m: int, e: int, p: int, emax: int, mode: str, tininess: str) -> tuple[str, str]:
    """(printed result, flags I U O) of rounding (-1)^negative m 2^e into the context."""
    assert m > 0
    emin = 1 - emax
    top = e + m.bit_length() - 1
    # the rounding with an unbounded exponent range: p significant bits
    unbounded_grid = top - p + 1
    if unbounded_grid <= e:
        unbounded_count, unbounded_inexact = m << (e - unbounded_grid), False
    else:
        unbounded_count, unbounded_inexact = round_count(m, unbounded_grid - e, negative, mode)
    unbounded_top = unbounded_grid + unbounded_count.bit_length() - 1
    if unbounded_top > emax:  # overflow (7.4)
        away = {"RNE": True, "RNA": True, "RTZ": False, "RTP": not negative, "RTN": negative}[mode]
        text = ("-" if negative else "") + "inf" if away else render(negative, 2**p - 1, emax - p + 1)
        return text, "I-O"
    grid = max(top, emin) - p + 1
    if grid <= e:
        count, inexact = m << (e - grid), False
    else:
        count, inexact = round_count(m, grid - e, negative, mode)
    tiny = top < emin if tininess == "before" else unbounded_top < emin
    flags = ("I" if inexact else "-") + ("U" if inexact and tiny else "-") + "-"
    return render(negative, count, grid), flags


def sqrt_round(m: int, e: int, p: int, emax: int, mode: str, tininess: str) -> tuple[str, str]:
    """(printed result, flags) of the square root of m 2^e (m > 0) in the context."""
    assert m > 0
    emin = 1 - emax
    top = (e + m.bit_length() - 1) // 2  # the binade of the root: floor of half the binade of the radicand

    def at(grid: int) -> tuple[int, bool]:
        """floor-or-ceiling count of sqrt(m 2^e) / 2^grid by `mode` (the root is positive), and inexact."""
        # sqrt(m 2^e) / 2^grid = sqrt(m 2^(e - 2 grid)); a = e - 2 grid
        a = e - 2 * grid
        if a >= 0:
            x, exact_scale = m << a, True
            root = isqrt(x)
            exact = root * root == x
            # compare 4 x with (2 root + 1)^2
            half = 4 * x - (2 * root + 1) ** 2
        else:
            low = -a
            x = m >> low
            root = isqrt(x)
            exact = (m & ((1 << low) - 1)) == 0 and root * root == x
            half = 4 * m - (2 * root + 1) ** 2 * (1 << low)
        if exact:
            return root, False
        if mode == "RNE":
            up = half > 0 or (half == 0 and root % 2 == 1)
        elif mode == "RNA":
            up = half >= 0
        elif mode == "RTP":
            up = True
        else:  # RTZ, RTN
            up = False
        return root + (1 if up else 0), True

    unbounded_grid = top - p + 1
    unbounded_count, _ = at(unbounded_grid)
    unbounded_top = unbounded_grid + unbounded_count.bit_length() - 1
    if unbounded_top > emax:
        away = mode in ("RNE", "RNA", "RTP")
        return ("inf" if away else render(False, 2**p - 1, emax - p + 1)), "I-O"
    grid = max(top, emin) - p + 1
    count, inexact = at(grid)
    tiny = top < emin if tininess == "before" else unbounded_top < emin
    flags = ("I" if inexact else "-") + ("U" if inexact and tiny else "-") + "-"
    return render(False, count, grid), flags


def sqrt_radicands(rng: random.Random, p: int) -> list[int]:
    root = (1 << (p - 1)) | rng.getrandbits(p - 1) if p > 1 else 1
    out = [root * root, root * root - 1, root * root + 1, root * root + root, root * root + root + 1, (2 * root + 1) ** 2, (1 << (2 * p)) - 1, 1, 3, rng.getrandbits(2 * p + 3) | 1]
    return [m for m in out if m > 0]


def sqrt_exponents(p: int, emax: int, bits: int) -> list[int]:
    out = [0, -2, 2]
    for top in (-2 * (emax + p + 3), -2 * emax - 4, -2 * emax, -2 * emax + 2, 2 * emax - 2, 2 * emax, 2 * emax + 2, 2 * emax + 6):
        out.append(top - bits + 1)
    if emax == IMPL_EMAX:
        out += [IMPL_EMIN - bits, IMPL_EMIN - 1000, IMPL_EMAX - bits + 1, IMPL_EMIN - 2**20]
    # the exponents a Binary can hold: the leading bit at most 2^30 - 1 and the lowest bit not below
    # e_min - p + 1 for the largest precision (about 10^6); an exponent below that is not a value
    # (`binary_round_sqrt` saturates a scale there: 2 * target no longer fits an Int32)
    return [x for x in out if x + bits - 1 <= IMPL_EMAX and x >= IMPL_EMIN - 2**21]


def magnitudes(rng: random.Random, p: int) -> list[int]:
    ones = (1 << p) - 1
    return [ones, (ones << 1) + 1, (ones << 3) + 4, 1 << (p + 2), 3, 1, (1 << (p - 1)) | rng.getrandbits(p) if p > 1 else 1,
            rng.getrandbits(rng.randint(1, 3 * p + 8)) | 1]


def tops(p: int, emax: int) -> list[int]:
    emin = 1 - emax
    out = [emin - p - 2, emin - p, emin - 1, emin, emin + 1, emax - 1, emax, emax + 1]
    if emax == IMPL_EMAX:
        out += [IMPL_EMIN - 3, IMPL_EMIN, IMPL_EMIN + 2, IMPL_EMAX - 1, IMPL_EMAX]
    return out


def build() -> list[tuple]:
    rng = random.Random(20261121)
    contexts = FORMATS + [(p, IMPL_EMAX) for p in IMPL_PRECISIONS]
    rows = []
    counter = 0
    for p, emax in contexts:
        for m in magnitudes(rng, p):
            for top in tops(p, emax):
                e = top - (m.bit_length() - 1)
                for negative in (False, True):
                    counter += 1
                    mode = MODES[counter % 5]
                    tininess = TININESS[(counter // 5) % 2]
                    expected, flags = round_dyadic(negative, m, e, p, emax, mode, tininess)
                    rows.append(("round", int(negative), f"{m:x}", e, p, emax, mode, tininess, expected, flags))
    sqrt_contexts = FORMATS + [(p, IMPL_EMAX) for p in (2, 3, 24, 53, 64, 113, 129, 513)]
    for p, emax in sqrt_contexts:
        for m in sqrt_radicands(rng, p):
            for e in sqrt_exponents(p, emax, m.bit_length()):
                counter += 1
                mode = MODES[counter % 5]
                tininess = TININESS[(counter // 5) % 2]
                expected, flags = sqrt_round(m, e, p, emax, mode, tininess)
                rows.append(("sqrt", 0, f"{m:x}", e, p, emax, mode, tininess, expected, flags))
    return rows


def render_file(rows: list[tuple]) -> str:
    lines = [
        "// Generated by tools/generate_round_rows.py; do not edit.",
        "// binary_round_dyadic against integer arithmetic and the range rule of IEEE 754-2019 4.3, 7.4, 7.5:",
        "// (operation round or sqrt, negative, magnitude in hex, exponent2, p, e_max, rounding, tininess, expected, flags).",
        "// oracle-file: A",
        "// producer: tools/generate_round_rows.py",
        "// input: magnitudes (all ones, halfway, power of two, short, random) with the leading bit around e_min, e_max and the implementation limits",
        "// library-ran: no",
        "",
        "///|",
        "fn round_rows() -> Array[(String, Int32, String, Int32, Int32, Int32, String, String, String, String)] {",
        "  [",
    ]
    for operation, negative, m, e, p, emax, mode, tininess, expected, flags in rows:
        lines.append(f'    ("{operation}", {negative}, "{m}", {e}, {p}, {emax}, "{mode}", "{tininess}", "{expected}", "{flags}"),')
    lines += ["  ]", "}", ""]
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args(argv)
    rows = build()
    text = render_file(rows)
    if args.check:
        squeeze = lambda value: "".join(value.split()).replace(",)", ")").replace(",]", "]")
        ok = OUTPUT.is_file() and squeeze(OUTPUT.read_text(encoding="utf-8")) == squeeze(text)
        if not ok:
            print(f"stale: {OUTPUT}", file=sys.stderr)
        return 0 if ok else 1
    OUTPUT.write_text(text, encoding="utf-8")
    print(f"{OUTPUT}: {len(rows)} rows, {len(text)} bytes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
