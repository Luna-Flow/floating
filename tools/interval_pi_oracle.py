#!/usr/bin/env python3
"""Independent enclosure of pi for the tests of the `interval` package.

Level A in the sense of the oracle rule: no `interval` or `binary` code is used. Pi is computed
with Python integers by Machin's formula, pi = 16 atan(1/5) - 4 atan(1/239), in fixed point with
guard bits, and the two bounds are rounded outward by a margin far above the accumulated error.
The bounds are written as hexadecimal numbers (`0x<hex>p-<N>`), N = 2048 fractional bits.

`--write` writes `library/src/interval/pi_reference_wbtest.mbt` (byte-stable), which defines
`ref_pi_interval(precision)`: `[RD(pi), RU(pi)]` at `precision` bits (at most 2048) from those
bounds. `--check` recomputes the file and compares.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
TARGET = REPO_ROOT / "library/src/interval/pi_reference_wbtest.mbt"
FRACTION_BITS = 2048
GUARD_BITS = 128
MARGIN = 1 << 16  # in units of 2^-(FRACTION_BITS + GUARD_BITS); far above the series error


def atan_inverse(n: int, bits: int) -> int:
    """atan(1/n) * 2^bits, truncated; the error is below 2 * (number of terms) units."""
    unit = 1 << bits
    power = unit // n
    total = power
    n2 = n * n
    k = 1
    sign = -1
    while power:
        power //= n2
        k += 2
        total += sign * (power // k)
        sign = -sign
    return total


def pi_fixed(bits: int) -> int:
    """pi * 2^bits with an error below 2^16 units for bits up to a few thousand."""
    return 16 * atan_inverse(5, bits) - 4 * atan_inverse(239, bits)


def pi_bounds(fraction_bits: int = FRACTION_BITS) -> tuple[int, int]:
    """Integers lo, hi with lo / 2^fraction_bits < pi < hi / 2^fraction_bits."""
    total_bits = fraction_bits + GUARD_BITS
    value = pi_fixed(total_bits)
    lo = (value - MARGIN) >> GUARD_BITS
    hi = ((value + MARGIN) >> GUARD_BITS) + 1
    return lo, hi


def check_rounding_claim(lo: int, hi: int, max_precision: int = FRACTION_BITS) -> None:
    """`ref_pi_interval(p)` claims to be `[RD(pi), RU(pi)]` at p bits: the interval `[RD(lo), RU(hi)]`
    must be exactly one unit in the last place wide for every p from 2 to `max_precision`, or a
    number of p bits could fall between the two bounds. Raises ValueError naming the first p that fails."""
    length = lo.bit_length()
    if hi.bit_length() != length:
        raise ValueError("the bounds of pi do not have the same length")
    for p in range(2, max_precision + 1):
        shift = length - p
        down = lo >> shift
        up = -((-hi) >> shift)  # ceiling
        if up - down != 1:
            raise ValueError(f"[RD(lo), RU(hi)] at p = {p} bits is {up - down} units wide, not 1")


def render() -> str:
    lo, hi = pi_bounds()
    check_rounding_claim(lo, hi)
    lines = [
        "///|",
        "// oracle-file: A",
        "// producer: tools/interval_pi_oracle.py",
        "// input: pi by Machin's formula in Python integers, 2048 fractional bits, outward margin",
        "// library-ran: no",
        "// shares: Binary::from_hex (reads the literal, exact at 2200 bits) and Binary::with_precision (directed rounding to p bits); ref_pi_interval(p) is [RD(pi), RU(pi)] at p bits (p <= 2048), which the generator proves for every p from 2 to 2048",
        "//   from_hex is right on these inputs by the hexadecimal reader tests of the binary package (hex.mbt and its tables), with_precision by the rounding tests of binary and by certified_pi_wbtest.mbt, which compares the result with the Python bounds for 11 precisions",
        "// check: python3 tools/interval_pi_oracle.py --check",
        "",
        "///|",
        "let ref_pi_lo_hex : String = \"0x%x%s\"" % (lo, "p-%d" % FRACTION_BITS),
        "",
        "///|",
        "let ref_pi_hi_hex : String = \"0x%x%s\"" % (hi, "p-%d" % FRACTION_BITS),
        "",
        "///|",
        "fn ref_pi_interval(precision : Int32) -> Interval {",
        "  let lo = @binary.Binary::from_hex(ref_pi_lo_hex, 2200).unwrap()",
        "  let hi = @binary.Binary::from_hex(ref_pi_hi_hex, 2200).unwrap()",
        "  Interval::from_bounds(",
        "    lo.with_precision(",
        "      precision,",
        "      @binary.BinaryRoundingMode::RoundTowardNegative,",
        "    ),",
        "    hi.with_precision(",
        "      precision,",
        "      @binary.BinaryRoundingMode::RoundTowardPositive,",
        "    ),",
        "    precision~,",
        "  )",
        "}",
        "",
    ]
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--write", action="store_true")
    group.add_argument("--check", action="store_true")
    args = parser.parse_args(argv)
    text = render()
    if args.write:
        TARGET.write_text(text)
        return 0
    if not TARGET.exists() or TARGET.read_text() != text:
        print("the generated file differs from the oracle; run --write and review")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
