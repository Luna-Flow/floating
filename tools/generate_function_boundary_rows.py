#!/usr/bin/env python3
"""Rows of MPFR results for the elementary functions at the underflow and overflow thresholds.

Writes `library/src/binary/function_boundary_rows_wbtest.mbt`: a sample of the sweep of
`range_boundary_rows.py` (exp, exp2, exp10, expm1, pow, pown, rootn, exp2m1, exp10m1, log2p1,
log10p1, rsqrt, compound, powr, asinpi, acospi, atanpi, atan2pi; arguments on and next to the
thresholds log2(result) in {q - 1, q, e_min, e_max, e_max + 1}) in the contexts of binary16,
binary32, binary64, binary128, e_min = -6 and the implementation range, at small precisions,
in all five rounding directions and both tininess rules.

The expected value and the flags come from GNU MPFR through `tools/generate_mpfr_random_oracle.c`
(`eval`: the row's exponent range is set on MPFR, the result goes through `mpfr_subnormalize`,
the underflow flag is derived from IEEE 754-2019 7.5 for the row's tininess rule). Nothing in the
table is produced by the library. A rows whose operand lies outside the implementation range
of `Binary` is left out. A table row is

    (group, operation, p, e_min, e_max, rounding, tininess, a, b, n, expected, flags)

with `e_min = e_max = 0` and tininess "-" for the implementation range ("-" in the MPFR rows),
`a` and `b` hexSequences ("" when absent), `n` the integer argument, `flags` the letters of the
MPFR rows (`x` inexact, `o` overflow, `u` underflow, `v` invalid, `z` division by zero, `-` none).

    python3 tools/generate_function_boundary_rows.py && moon fmt
    python3 tools/generate_function_boundary_rows.py --check

The program needs `cc`, GMP and MPFR (`brew install mpfr`); the C source is built in a
temporary directory.
"""

from __future__ import annotations

import argparse
import re
from fractions import Fraction
import subprocess
import sys
import tempfile
from collections import defaultdict
from pathlib import Path

import range_boundary_rows as sweep

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "library/src/binary/function_boundary_rows_wbtest.mbt"
ORACLE_SOURCE = ROOT / "tools/generate_mpfr_random_oracle.c"
PRECISIONS = (2, 3, 11, 24, 53)
PER_GROUP = 6  # rows kept from each (operation, precision, context) group
HEADER = "# mpfr-random-v1 function boundary rows (expected columns are filled by the oracle)"
Row = tuple[str, str, int, str, str, str, str, str, str, int, str, str]
IMPL = (sweep.IMPL_EMIN, sweep.IMPL_EMAX)
LN2 = 0.6931471805599453  # the doubles that the tests the rows replace used
LOG10_2 = 0.3010299956639812
LOG2_3 = 1.584962500721156
MODES = sweep.MODES


class Builder:
    """Input rows of one group; rounding direction and tininess rule cycle with the row number."""

    def __init__(self, group: str) -> None:
        self.group = group
        self.rows: list[str] = []

    def add(self, op: str, p: int, a: str, b: str = "-", n: int = 0, *, e_max: int | None = None, cycle: bool = True, mode: str | None = None, tininess: str = "a") -> None:
        index = len(self.rows)
        if cycle:
            mode = MODES[index % 5]
            tininess = "ab"[(index // 5) % 2]
        assert mode is not None
        emin, emax = IMPL if e_max is None else (1 - e_max, e_max)
        self.rows.append(f"{self.group}.{index} {op} {mode} {p} {emin} {emax} {tininess} {a} {b} - {n} ? ?")


def dyadic_hex(value: Fraction) -> str:
    return sweep.hexfmt(value)


def around(center: float) -> list[Fraction]:
    """`center` plus the offsets 0, +-2^-10, +-2^-20 and +-2^-40, exactly (as `sib_around` did)."""
    base = Fraction(center)
    result = [base]
    for shift in (10, 20, 40):
        step = Fraction(1, 2**shift)
        result += [base + step, base - step]
    return result


def threshold_args(scale: float, p: int, e_min: int, e_max: int, integers: bool) -> list[Fraction]:
    q = e_min - (p - 1)
    result: list[Fraction] = []
    for level in (q - 1, q, e_min, e_max + 1, e_max):
        for x in around(float(level) * scale):
            if integers or x.denominator != 1:
                result.append(x)
    return result


def small(numerator: int, exponent: int, negative: bool = False) -> str:
    return f"{'-' if negative else ''}0x{numerator:x}p{exponent}"


def group_underflow_exp() -> list[str]:
    b = Builder("underflow_exp")
    for p in (2, 5, 53):
        for e_min, e_max in ((-6, 7), (-20, 21)):
            for x in threshold_args(LN2, p, e_min, e_max, True):
                b.add("exp", p, dyadic_hex(x), e_max=e_max)
            for x in threshold_args(1.0, p, e_min, e_max, False):
                b.add("exp2", p, dyadic_hex(x), e_max=e_max)
            for x in threshold_args(LOG10_2, p, e_min, e_max, False):
                b.add("exp10", p, dyadic_hex(x), e_max=e_max)
            for x in threshold_args(LN2, p, e_min, e_max, True):
                if x > 0:
                    b.add("expm1", p, dyadic_hex(x), e_max=e_max)
            for x in around(-(p + 3) * LN2):
                b.add("expm1", p, dyadic_hex(x), e_max=e_max)
            for level in (e_min - p, e_min - p + 1, e_min - 1, e_min, e_min + 1):
                for numerator in (1024, 1025, 1023, 1536):
                    b.add("expm1", p, small(numerator, level - 10), e_max=e_max)
                    b.add("expm1", p, small(numerator, level - 10, True), e_max=e_max)
    return b.rows


def group_underflow_pow() -> list[str]:
    b = Builder("underflow_pow")
    for p in (2, 5):
        for e_min, e_max in ((-6, 7), (-20, 21)):
            for y in threshold_args(1.0 / LOG2_3, p, e_min, e_max, False):
                b.add("pow", p, "0x3p0", dyadic_hex(y), e_max=e_max)
    return b.rows


def group_underflow_pown_rootn() -> list[str]:
    b = Builder("underflow_pown_rootn")
    for p in (2, 5):
        for _e_min, e_max in ((-6, 7), (-20, 21)):
            for n in range(-40, 41):
                if n != 0:
                    b.add("pown", p, "0x3p0", n=n, e_max=e_max)
            for degree in (-2, -3, 5):
                for step in range(61):
                    b.add("rootn", p, small(5, -90 + 3 * step), n=degree, e_max=e_max)
    return b.rows


def group_pm1_underflow() -> list[str]:
    b = Builder("pm1_underflow")
    for p in (2, 5, 53):
        for e_min, e_max in ((-6, 7), (-20, 21)):
            q = e_min - (p - 1)
            for level in (e_max, e_max + 1):
                for x in around(float(level)):
                    if x.denominator != 1:
                        b.add("exp2m1", p, dyadic_hex(x), e_max=e_max)
                for x in around(float(level) * LOG10_2):
                    if x.denominator != 1:
                        b.add("exp10m1", p, dyadic_hex(x), e_max=e_max)
            for x in around(-(p + 3.0)):
                if x.denominator != 1:
                    b.add("exp2m1", p, dyadic_hex(x), e_max=e_max)
            for x in around(-(p + 3.0) * LOG10_2):
                if x.denominator != 1:
                    b.add("exp10m1", p, dyadic_hex(x), e_max=e_max)
            for level in (q - 1, q, e_min, e_min + 1):
                for numerator in (1024, 1025, 1023, 1536):
                    for name in ("exp2m1", "exp10m1", "log2p1", "log10p1"):
                        b.add(name, p, small(numerator, level - 10), e_max=e_max)
                        if name in ("exp2m1", "exp10m1"):
                            b.add(name, p, small(numerator, level - 10, True), e_max=e_max)
    return b.rows


def group_pown_tininess() -> list[str]:
    b = Builder("pown_tininess")
    for n in (-1835573772, -1835573771):
        for mode in MODES:
            for tininess in "ab":
                b.add("pown", 2, "0x3p-1", n=n, cycle=False, mode=mode, tininess=tininess)
    return b.rows


def group_pown_directed() -> list[str]:
    b = Builder("pown_directed")
    for p, coefficient, exponent, n in ((40, 3, 0, -677455689), (41, 3, -1, -1835573840), (41, 3, -1, -1835573839), (42, 3, -1, -1835573839), (43, 0xB33333333333333, -60, 2086665068)):
        for mode in MODES:
            b.add("pown", p, small(coefficient, exponent), n=n, cycle=False, mode=mode)
    return b.rows


def group_expm1_overflow() -> list[str]:
    b = Builder("expm1_overflow")
    for numerator in (744261118 * 2, 744261118 * 2 + 1, 744261118 * 2 + 2):
        for p in (2, 24, 53):
            for mode in MODES:
                b.add("expm1", p, small(numerator, -1), cycle=False, mode=mode)
    return b.rows


def group_hypot_range() -> list[str]:
    b = Builder("hypot_range")
    pairs = [
        ((1, -600000000), (1, -600000000)),
        ((1, -540000000), (1, -540000001)),
        ((1, 600000000), (1, 600000000)),
        ((3, -1073741780), (5, -1073741785)),
        ((1, -1073741700), (1, -1073741720)),
        ((1, -1073741780), (1, -1073741860)),
        ((7, -1073741800), (1, -1073741790)),
        ((3, -1073741860), (3, -1073741860)),
        ((1, 1073741000), (1, 1073740990)),
    ]
    for (ca, ea), (cb, eb) in pairs:
        for p in (2, 53, 100):
            for mode in MODES:
                for tininess in "ab":
                    b.add("hypot", p, small(ca, ea), small(cb, eb, True), cycle=False, mode=mode, tininess=tininess)
    return b.rows


def group_rsqrt() -> list[str]:
    b = Builder("rsqrt")
    for p in (2, 3, 24, 53):
        for mode in MODES:
            for numerator in (3, 5, 7, 9, 11, 13, 100001):
                for exponent in (-5, 0, 3, 20):
                    if numerator == 9 and exponent % 2 == 0:
                        continue
                    b.add("rsqrt", p, small(numerator, exponent), cycle=False, mode=mode)
    return b.rows


def group_compound() -> list[str]:
    b = Builder("compound")
    for p in (2, 8, 24, 53):
        for numerator in (-7, -3, -1, 1, 3, 5, 9, 21):
            for exponent in (-8, -3, -1, 1, 4):
                for n in (-9, -3, -2, -1, 1, 2, 3, 5, 13, 40):
                    if Fraction(numerator) * Fraction(2) ** exponent > -1:
                        b.add("compound", p, small(abs(numerator), exponent, numerator < 0), n=n, e_max=60)
    return b.rows


def group_powr() -> list[str]:
    b = Builder("powr")
    xs = ["0x2p0", "0x3p0", "0x1p-3", "0x5p-1"]
    ys = ["-0x3p0", "0x5p0", "0x1p-1", "0x7p-2"]
    for p in (2, 24, 53):
        for mode in MODES:
            for x in xs:
                for y in ys:
                    b.add("powr", p, x, y, cycle=False, mode=mode)
    return b.rows


GROUPS = (
    group_underflow_exp,
    group_underflow_pow,
    group_underflow_pown_rootn,
    group_pm1_underflow,
    group_pown_tininess,
    group_pown_directed,
    group_expm1_overflow,
    group_hypot_range,
    group_rsqrt,
    group_compound,
    group_powr,
)


def sample_group(items: list[str], keep: int) -> list[str]:
    """`keep` items spread evenly over `items`, in order (all of them when there are fewer)."""
    if len(items) <= keep:
        return list(items)
    return [items[(index * len(items)) // keep] for index in range(keep)]


def group_key(line: str) -> tuple[str, str, str, str]:
    fields = line.split()
    return fields[1], fields[3], fields[4], fields[5]  # operation, precision, e_min, e_max


def sweep_rows(precisions: tuple[int, ...] = PRECISIONS, keep: int = PER_GROUP) -> list[str]:
    groups: dict[tuple[str, str, str, str], list[str]] = defaultdict(list)
    order: list[tuple[str, str, str, str]] = []
    for p in precisions:
        for line in sweep.rows(p, p, sweep.OPERATIONS):
            key = group_key(line)
            if key not in groups:
                order.append(key)
            groups[key].append(line)
    chosen: list[str] = []
    for key in order:
        chosen.extend(sample_group(groups[key], keep))
    return [line.replace("tgt.", "sweep.", 1) for line in chosen]


def input_rows() -> list[str]:
    lines = sweep_rows()
    for group in GROUPS:
        lines.extend(group())
    return lines


def operand_in_range(text: str) -> bool:
    """False for an operand whose leading bit is below the implementation range of `Binary`."""
    match = re.fullmatch(r"-?0x([0-9a-f]+)p(-?\d+)", text)
    if match is None:
        return True
    mantissa, exponent = int(match.group(1), 16), int(match.group(2))
    if mantissa == 0:
        return True
    leading = exponent + mantissa.bit_length() - 1
    return sweep.IMPL_EMIN <= leading <= sweep.IMPL_EMAX


def parse_evaluated(line: str) -> Row | None:
    fields = line.split()
    if len(fields) != 13:
        return None
    row_id, op, mode, p, emin, emax, tininess, a, b, _c, n, expected, flags = fields
    if not (operand_in_range(a) and operand_in_range(b)):
        return None
    mode_name = {"n": "RNE", "na": "RNA", "z": "RTZ", "u": "RTP", "d": "RTN"}[mode]
    bounded = emin != "-"
    return (
        row_id.split(".")[0],
        op,
        int(p),
        emin if bounded else "0",
        emax if bounded else "0",
        mode_name,
        ("before" if tininess == "b" else "after") if bounded else "-",
        "" if a == "-" else a,
        "" if b == "-" else b,
        int(n),
        expected,
        flags,
    )


def evaluate(lines: list[str]) -> list[Row]:
    """Rows evaluated by MPFR. The evaluator aborts (an MPFR precision assertion of its own) on a few
    tiny expm1 operands at p = 2; a batch that aborts is evaluated row by row and those rows are
    left out (12 of them as of the current sweep)."""
    with tempfile.TemporaryDirectory() as scratch:
        binary = Path(scratch) / "mpfr_oracle"
        flags = ["-I/opt/homebrew/include", "-L/opt/homebrew/lib"] if Path("/opt/homebrew/include/mpfr.h").exists() else []
        subprocess.run(["cc", "-O2", *flags, "-o", str(binary), str(ORACLE_SOURCE), "-lmpfr", "-lgmp"], check=True)

        def run(batch: list[str]) -> subprocess.CompletedProcess[str]:
            return subprocess.run([str(binary), "eval"], input=HEADER + "\n" + "\n".join(batch) + "\n", capture_output=True, text=True)

        output: list[str] = []
        chunk = 200
        for start in range(0, len(lines), chunk):
            batch = lines[start : start + chunk]
            result = run(batch)
            if result.returncode == 0:
                output.extend(result.stdout.splitlines())
                continue
            for line in batch:
                single = run([line])
                if single.returncode == 0:
                    output.extend(single.stdout.splitlines())
    rows = [parse_evaluated(line) for line in output if line and not line.startswith("#")]
    return [row for row in rows if row is not None]


def render_file(rows: list[Row]) -> str:
    lines = [
        "// Generated by tools/generate_function_boundary_rows.py; do not edit.",
        "// Elementary functions at the underflow and overflow thresholds, results and flags of GNU MPFR 4.2.2:",
        "// (group, operation, p, e_min, e_max, rounding, tininess, a, b, n, expected, flags).",
        "// oracle-file: A",
        "// producer: tools/generate_function_boundary_rows.py",
        "// input: a sample of tools/range_boundary_rows.py (arguments on and next to the thresholds of each function), values and flags from tools/generate_mpfr_random_oracle.c eval",
        "// library-ran: no",
        ""
    ]
    tuple_type = "(String, String, Int32, Int32, Int32, String, String, String, String, Int32, String, String)"
    chunk = 1500  # a segment of the formatted file has a line limit of the compiler
    parts = [rows[start : start + chunk] for start in range(0, len(rows), chunk)]
    for index, part in enumerate(parts):
        lines += ["///|", f"fn function_boundary_rows_part{index}() -> Array[{tuple_type}] {{", "  ["]
        for group, op, p, emin, emax, mode, tininess, a, b, n, expected, flags in part:
            lines.append(f'    ("{group}", "{op}", {p}, {emin}, {emax}, "{mode}", "{tininess}", "{a}", "{b}", {n}, "{expected}", "{flags}"),')
        lines += ["  ]", "}", ""]
    lines += ["///|", f"fn function_boundary_rows() -> Array[{tuple_type}] {{", "  let rows = []"]
    lines += [f"  rows.append(function_boundary_rows_part{index}())" for index in range(len(parts))]
    lines += ["  rows", "}", ""]
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args(argv)
    rows = evaluate(input_rows())
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
