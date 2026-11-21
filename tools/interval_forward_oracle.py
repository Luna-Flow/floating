#!/usr/bin/env python3
"""Independent 200-bit values of asin, acos, atan, atan2, tan, cot and pow for the interval tests.

Level A in the sense of the oracle rule: every expected value is computed by MPFR (through the C
program `tools/interval_forward_oracle.c`: `RNDD` and `RNDU` of the exact operand to 200 bits), not
by `binary` or `interval`. The operands are chosen here, with Python integers: p-bit numbers
(p = 24 and 53) of the classes that the reference tests of the reverse functions use, and the
floats next to pi/2 and pi (from `tools/interval_pi_oracle.py`) at p = 53 and 113, where tan and
cot are huge.

`--write` writes `library/src/interval/forward_reference_table_wbtest.mbt` (byte-stable; needs a C
compiler and MPFR, `--prefix` or `EXTBENCH_PREFIX`, default /opt/homebrew); `--check` recomputes
it and compares (it is skipped with a message when MPFR is not installed).
"""

from __future__ import annotations

import argparse
import os
import random
import shutil
import subprocess
import sys
import tempfile
from fractions import Fraction
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import interval_pi_oracle as pi_oracle  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[1]
TARGET = REPO_ROOT / "library/src/interval/forward_reference_table_wbtest.mbt"
SOURCE = REPO_ROOT / "tools/interval_forward_oracle.c"
OUTPUT_PRECISION = 200
SEED = 20261121

Row = tuple[str, str, str | None]  # operation, x, y (hexadecimal operands)


def hex_value(numerator: int, exponent: int) -> str:
    """`numerator * 2^exponent` as `[-]0x<hex>p<exp>` (numerator odd or zero is not required)."""
    if numerator == 0:
        return "0x0p0"
    sign = "-" if numerator < 0 else ""
    return f"{sign}0x{abs(numerator):x}p{exponent}"


def round_down_bits(value_numerator: int, value_exponent: int, bits: int) -> tuple[int, int]:
    """The largest `m * 2^e` with `m` of `bits` bits that is at most `value_numerator * 2^value_exponent`
    (a positive number)."""
    length = value_numerator.bit_length()
    shift = length - bits
    if shift <= 0:
        return value_numerator, value_exponent
    return value_numerator >> shift, value_exponent + shift


def near_multiples_of_pi_half(p: int) -> tuple[str, str]:
    """RD(pi/2) and RD(pi) at p bits, as hexadecimal text (from the bounds of pi, an integer lower bound)."""
    lo, _ = pi_oracle.pi_bounds()
    exponent = -pi_oracle.FRACTION_BITS
    half = round_down_bits(lo, exponent - 1, p)
    whole = round_down_bits(lo, exponent, p)
    return hex_value(*half), hex_value(*whole)


def generate_rows(seed: int = SEED) -> list[Row]:
    rng = random.Random(seed)
    rows: list[Row] = []
    for p in (24, 53):
        scale = 1 << p
        for _ in range(40):
            n = rng.randrange(-scale + 1, scale)  # |x| < 1
            rows.append(("asin", hex_value(n, -p), None))
        for _ in range(40):
            n = rng.randrange(-scale + 1, scale)
            rows.append(("acos", hex_value(n, -p), None))
        for _ in range(40):
            n = rng.randrange(-6 * (scale >> 3), 6 * (scale >> 3) + 1)  # |x| <= 6
            rows.append(("atan", hex_value(n, -(p - 3)), None))
        for _ in range(40):
            base = rng.randrange(1, 20 * (scale >> 4))  # 0 < b < 20
            exponent = rng.randrange(-6 * (scale >> 3), 6 * (scale >> 3) + 1)  # |y| <= 6
            rows.append(("pow", hex_value(base, -(p - 4)), hex_value(exponent, -(p - 3))))
    for p in (24, 53):
        scale = 1 << p
        for _ in range(40):
            ordinate = rng.randrange(-4 * (scale >> 2), 4 * (scale >> 2) + 1)  # |y| <= 4
            abscissa = rng.randrange(-4 * (scale >> 2), 4 * (scale >> 2) + 1)
            if ordinate == 0 and abscissa == 0:
                abscissa = 1
            rows.append(("atan2", hex_value(ordinate, -(p - 2)), hex_value(abscissa, -(p - 2))))
    for special in (0, 1, -1):
        rows.append(("asin", hex_value(special, 0), None))
        rows.append(("acos", hex_value(special, 0), None))
    for half in (1, -1):
        rows.append(("asin", hex_value(half, -1), None))
        rows.append(("acos", hex_value(half, -1), None))
    for op in ("tan", "cot"):
        rows.append((op, hex_value(1, -1), None))  # 0.5
        for p in (53, 113):
            near_half_pi, near_pi = near_multiples_of_pi_half(p)
            rows.append((op, near_half_pi, None))
            rows.append((op, near_pi, None))
    return rows


def input_text(rows: list[Row]) -> str:
    out = []
    for op, x, y in rows:
        out.append(f"{op} {OUTPUT_PRECISION} {x}" + (f" {y}" if y is not None else ""))
    return "\n".join(out) + "\n"


def compile_oracle(directory: Path, prefix: Path, cc: str) -> Path:
    binary = directory / "interval_forward_oracle"
    command = [cc, "-O1", "-std=c11", "-Wall", "-Wextra", f"-I{prefix / 'include'}", str(SOURCE), "-o", str(binary),
               f"-L{prefix / 'lib'}", f"-Wl,-rpath,{prefix / 'lib'}", "-lmpfr", "-lgmp"]  # fmt: skip
    subprocess.run(command, check=True)
    return binary


def run_oracle(rows: list[Row], prefix: Path, cc: str) -> list[tuple[str, str]]:
    with tempfile.TemporaryDirectory() as tmp:
        directory = Path(tmp)
        binary = compile_oracle(directory, prefix, cc)
        (directory / "in.txt").write_text(input_text(rows))
        subprocess.run([str(binary), str(directory / "in.txt"), str(directory / "out.txt")], check=True)
        pairs = [tuple(line.split()) for line in (directory / "out.txt").read_text().splitlines()]
    assert len(pairs) == len(rows)
    return [(lo, hi) for lo, hi in pairs]


def render(rows: list[Row], values: list[tuple[str, str]]) -> str:
    lines = [
        "///|",
        "// oracle-file: A",
        "// producer: tools/interval_forward_oracle.py (MPFR through tools/interval_forward_oracle.c)",
        "// input: asin, acos, atan, atan2, pow of p-bit operands (p = 24, 53) and tan, cot of 0.5 and of the floats next to",
        "//   pi/2 and pi (p = 53, 113); for each row the two directed roundings (down, up) of the exact result to 200 bits",
        "// library-ran: no",
        "// shares: nothing; the table is read with Binary::from_hex and String::split only",
        "// check: python3 tools/interval_forward_oracle.py --check",
        "",
        "///|",
        "fn forward_reference_table() -> String {",
        "  (",
    ]
    for (op, x, y), (lo, hi) in zip(rows, values):
        fields = [op, x] + ([y] if y is not None else ["-"]) + [lo, hi]
        lines.append("    #|" + " ".join(fields))
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
            print("interval_forward_oracle: no C compiler or no MPFR under the prefix; check skipped")
            return 0
        print("interval_forward_oracle: MPFR is required to write the table")
        return 2
    rows = generate_rows()
    text = render(rows, run_oracle(rows, args.prefix, args.cc))
    if args.write:
        TARGET.write_text(text)
        return 0
    if not TARGET.exists() or TARGET.read_text() != text:
        print("the generated file differs from the oracle; run --write and review")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
