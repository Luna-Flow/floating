#!/usr/bin/env python3
"""Independent directed bounds of exp and ln of a point interval, from MPFR.

Level A in the sense of the oracle rule: every expected value is computed by MPFR (through
`tools/interval_forward_oracle.c`, the operations `exp` and `ln`: `RNDD` and `RNDU` of the exact
operand to p bits), not by `binary` or `interval`. The operands are chosen here with Python
integers: p-bit numbers `c * 2^(top - 31)` with a random coefficient of at most min(p, 32) bits,
for the precisions p = 24, 53, 64, 128, 200 and for the magnitudes 2^-30 up to 2^20, small integers,
and the exponent-range ends 2^-1073741000 and 2^1073741000 (ln only: exp of 2^1073741000 overflows
and exp of 2^40 is beyond the range, those are checked by hand in the test of the exponent range).

`--write` writes `library/src/interval/point_elementary_table_wbtest.mbt` (byte-stable; needs a C
compiler and MPFR, `--prefix` or `EXTBENCH_PREFIX`, default /opt/homebrew); `--check` recomputes it
and compares (skipped with a message when MPFR is not installed).
"""

from __future__ import annotations

import argparse
import os
import random
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import interval_forward_oracle as forward  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[1]
TARGET = REPO_ROOT / "library/src/interval/point_elementary_table_wbtest.mbt"
BIG_TARGET = REPO_ROOT / "library/src/interval/point_elementary_big_table_wbtest.mbt"
SEED = 20261125
PRECISIONS = (24, 53, 64, 128, 200)
TOPS = (-30, -8, -3, -1, 0, 1, 2, 3, 5, 8, 12, 20)
LN_ONLY_TOPS = (30,)
EDGE_EXPONENT = 1073741000

Row = tuple[str, int, str]  # operation, precision, operand (hexadecimal)


def operand(coefficient: int, exponent: int, negative: bool) -> str:
    return forward.hex_value(-coefficient if negative else coefficient, exponent)


def generate_rows(seed: int = SEED) -> list[Row]:
    rng = random.Random(seed)
    rows: list[Row] = []
    for p in PRECISIONS:
        bits = min(p, 32)
        values: list[tuple[int, int, bool]] = []  # coefficient, exponent, negative
        for top in TOPS + LN_ONLY_TOPS:
            for _ in range(4):
                values.append((rng.randrange(3, 1 << bits), top - 31, rng.random() < 0.5))
        for k in (-5, -2, 0, 1, 3):
            values.append((abs(k), 0, k < 0))
        for negative_exponent in (False, True):
            exponent = -EDGE_EXPONENT if negative_exponent else EDGE_EXPONENT
            values.append((1, exponent, False))
        values.append((1, 40, False))
        for coefficient, exponent, negative in values:
            if coefficient == 0:
                continue
            top = exponent + coefficient.bit_length() - 1
            text = operand(coefficient, exponent, negative)
            if abs(top) <= 20:
                rows.append(("exp", p, text))
            if exponent == -EDGE_EXPONENT:
                rows.append(("exp", p, text))  # exp(2^-1073741000) is 1 + a tiny number
            if not negative:
                rows.append(("ln", p, text))
    return rows


def big_rows() -> list[Row]:
    """The two extreme precisions of issue 449: ln 3 at 32,000 bits and exp 1 at 160,000 bits."""
    return [("ln", 32_000, forward.hex_value(3, 0)), ("exp", 160_000, forward.hex_value(1, 0))]


def input_text(rows: list[Row]) -> str:
    return "\n".join(f"{op} {p} {x}" for op, p, x in rows) + "\n"


def run_oracle(rows: list[Row], prefix: Path, cc: str) -> list[tuple[str, str]]:
    with tempfile.TemporaryDirectory() as tmp:
        directory = Path(tmp)
        binary = forward.compile_oracle(directory, prefix, cc)
        (directory / "in.txt").write_text(input_text(rows))
        subprocess.run([str(binary), str(directory / "in.txt"), str(directory / "out.txt")], check=True)
        pairs = [tuple(line.split()) for line in (directory / "out.txt").read_text().splitlines()]
    assert len(pairs) == len(rows)
    return [(lo, hi) for lo, hi in pairs]


def render(rows: list[Row], values: list[tuple[str, str]], big: bool = False) -> str:
    name = "point_elementary_big_table" if big else "point_elementary_table"
    inputs = (
        "ln 3 at 32,000 bits and exp 1 at 160,000 bits (issue 449)"
        if big
        else "exp and ln of p-bit operands (p = 24, 53, 64, 128, 200) of magnitudes 2^-30 to 2^30, small integers and 2^-1073741000"
    )
    lines = [
        "///|",
        "// oracle-file: A",
        "// producer: tools/interval_point_elementary_oracle.py (MPFR through tools/interval_forward_oracle.c)",
        f"// input: {inputs};",
        "//   for each row the two directed roundings (down, up) of the exact result to p bits",
        "// library-ran: no",
        "// shares: nothing; the table is read with Binary::from_hex and String::split only",
        "// check: python3 tools/interval_point_elementary_oracle.py --check",
        "",
        "///|",
        f"fn {name}() -> String {{",
        "  (",
    ]
    for (op, p, x), (lo, hi) in zip(rows, values):
        lines.append(f"    #|{op} {p} {x} {lo} {hi}")
    lines += ["  )", "}", ""]
    return "\n".join(lines)


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
            print("interval_point_elementary_oracle: no C compiler or no MPFR under the prefix; check skipped")
            return 0
        print("interval_point_elementary_oracle: MPFR is required to write the table")
        return 2
    rows = generate_rows()
    big = big_rows()
    outputs = [
        (TARGET, render(rows, run_oracle(rows, args.prefix, args.cc))),
        (BIG_TARGET, render(big, run_oracle(big, args.prefix, args.cc), big=True)),
    ]
    if args.write:
        for target, text in outputs:
            target.write_text(text)
            print(f"wrote {target.relative_to(REPO_ROOT)}")
        return 0
    if any(not target.exists() or target.read_text() != text for target, text in outputs):
        print("a generated file differs from the oracle; run --write and review")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
