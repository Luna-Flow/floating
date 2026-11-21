#!/usr/bin/env python3
"""Oracle for the coefficient kernel (`library/src/internal/bin_kernel`).

Level A oracle in the sense of RULES.md ("the oracle of a test must be
independent of the code under test"): every expected value here is computed
with CPython integers (`+ - * // % ** << >>`, `math.gcd`, `math.isqrt`) and
nothing else. The program imports no library of this repository, no MPFR and
no `gmpy`. It is the separate program in another language that the tests of
the kernel name as their oracle.

A row of a table is `(case id, parameters, seed, digest)`. No operand and no
result is stored: the operands are regenerated from the seed on both sides
(here and in the MoonBit test) with the 64-bit linear congruential generator
`state = state * 6364136223846793005 + 1442695040888963407` (mod 2^64), output
`state >> 11`, and the shapes of `regression_value` (random, all ones, `2^k`,
`2^k + 1`, `2^k - 1`, sparse, zero limbs inside). The digest is FNV-1a (64 bits)
over the big-endian bytes of each expected integer (a zero is the single byte
`00`), then one separating `0xff` byte step.

Tables in this file:

* `regression`: the 12 digests of `coeff_regression_wbtest.mbt` (issue #19).
  They were recorded with the 32-bit-limb implementation; this program
  reproduces them from the mathematical definition of each operation, so the
  test they guard is level A, not an equivalence with an old build.

    python3 tools/kernel_oracle.py              # print the tables
    python3 tools/kernel_oracle.py --check      # fail if a committed table differs

`--check` reads the committed MoonBit tables and compares them with the values
computed here; it never writes a file. It takes a few seconds.

Error classes of the digests: the FNV-1a digest of the exact bytes detects any
single wrong bit with probability 1 - 2^-64 per row (it is not a cryptographic
hash; the rows are not adversarial against it). Later tables that cannot form
the exact result in Python use residues modulo 2^64 - 1, 2^64 + 1 and 2^61 - 1
instead and say in their own header which errors those residues cannot miss.
"""

from __future__ import annotations

import argparse
import math
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
KERNEL_TESTS = ROOT / "library/src/internal/bin_kernel"
REGRESSION_TEST = KERNEL_TESTS / "coeff_regression_wbtest.mbt"

MASK64 = (1 << 64) - 1
FNV_BASIS = 0xCBF29CE484222325
FNV_PRIME = 0x100000001B3
LCG_MULTIPLIER = 6364136223846793005
LCG_INCREMENT = 1442695040888963407


class Random:
    """The generator of `RegressionRandom` in the MoonBit tests."""

    def __init__(self, seed: int) -> None:
        self.state = seed & MASK64

    def next(self) -> int:
        self.state = (self.state * LCG_MULTIPLIER + LCG_INCREMENT) & MASK64
        return self.state >> 11


def value(random: Random, bits: int, shape: int) -> int:
    """A value of `bits` bits (`bits >= 1`) in one of seven shapes (`regression_value`)."""
    length = (bits + 7) // 8
    data = [0] * length
    top_mask = (1 << ((bits - 1) % 8 + 1)) - 1
    if shape == 0:  # random, the top bit is set below
        for index in range(length):
            data[index] = random.next() & 0xFF
    elif shape == 1:  # all ones
        data = [0xFF] * length
    elif shape == 2:  # 2^(bits - 1), set below
        pass
    elif shape == 3:  # 2^(bits - 1) + 1
        data[length - 1] = 1
    elif shape == 4:  # all ones below the top bit
        data = [0xFF] * length
    elif shape == 5:  # sparse: a few random set bits
        for _ in range(5):
            position = random.next() % bits
            byte = length - 1 - position // 8
            data[byte] |= 1 << (position % 8)
    else:  # zero limbs inside: random head and tail bytes, zeros between
        for index in range(length):
            near_end = index < 8 or index >= length - 8
            data[index] = (random.next() & 0xFF) if near_end else 0
    data[0] &= top_mask
    if shape == 4:
        data[0] &= top_mask >> 1
        if bits == 1:
            data[0] = 1
    if shape != 4:
        data[0] |= 1 << ((bits - 1) % 8)
    return int.from_bytes(bytes(data), "big")


def to_bytes(number: int) -> bytes:
    """Minimal big-endian bytes; zero is the single byte 00 (`Coeff::to_bytes_be`)."""
    if number == 0:
        return b"\x00"
    return number.to_bytes((number.bit_length() + 7) // 8, "big")


def mix(state: int, number: int) -> int:
    """Fold an integer into a digest (`regression_mix`)."""
    for byte in to_bytes(number):
        state = ((state ^ byte) * FNV_PRIME) & MASK64
    return (((state ^ 0xFF) * FNV_PRIME)) & MASK64


def mix_int(state: int, number: int) -> int:
    """Fold a small signed integer as a 32-bit word (`regression_mix_int`)."""
    return ((state ^ (number & 0xFFFFFFFF)) * FNV_PRIME) & MASK64


def mix_string(state: int, text: str) -> int:
    """Fold a string character by character (`regression_mix_string`)."""
    for char in text:
        state = ((state ^ ord(char)) * FNV_PRIME) & MASK64
    return (state * FNV_PRIME) & MASK64


def to_radix(number: int, radix: int) -> str:
    """Digits of a non-negative integer by repeated `divmod`; lower-case letters above 9.

    Written out here (not `str`, `format`, `hex`) so that the radix text of the
    kernel is compared with an independent conversion for every radix.
    """
    if number == 0:
        return "0"
    digits = "0123456789abcdefghijklmnopqrstuvwxyz"
    out = []
    while number:
        number, digit = divmod(number, radix)
        out.append(digits[digit])
    return "".join(reversed(out))


def compare(left: int, right: int) -> int:
    return (left > right) - (left < right)


REGRESSION_SIZES = [
    1, 2, 31, 32, 33, 63, 64, 65, 100, 127, 128, 129, 130, 160, 191, 192, 193, 255,
    256, 257, 320, 512, 1000, 1023, 1024, 1025, 2047, 2048, 2049, 3071, 3072, 3073,
    3100, 4096, 6143, 6144, 6145, 8192,
]
REGRESSION_LARGE_SIZES = [
    16383, 16384, 16385, 24575, 24576, 24577, 65535, 65536, 65537, 131071, 131072,
    131073,
]
REGRESSION_NAMES = [
    "add", "sub", "compare", "shift", "bits", "mul", "square", "div", "gcd", "sqrt",
    "text", "large_mul",
]


def regression() -> dict[str, int]:
    """The 12 digests of `regression_digests()`, from the definitions of the operations."""
    random = Random(0xC0FFEE1234567)
    d = {name: FNV_BASIS for name in REGRESSION_NAMES}
    for size in REGRESSION_SIZES:
        for shape in range(7):
            a = value(random, size, shape)
            b = value(random, size, (shape + 3) % 7)
            c = value(random, max(1, size // 3 + 1), shape)
            small = value(random, 30, 0)
            word = value(random, 64, 0)
            # addition, subtraction, comparison, bit queries
            d["add"] = mix(d["add"], a + b)
            d["add"] = mix(d["add"], a + c)
            d["add"] = mix(d["add"], a + a)
            larger, smaller = (a, b) if compare(a, b) >= 0 else (b, a)
            d["sub"] = mix(d["sub"], larger - smaller)
            d["sub"] = mix(d["sub"], larger - larger)
            d["compare"] = mix_int(d["compare"], compare(a, b))
            d["compare"] = mix_int(d["compare"], compare(a, c))
            d["compare"] = mix_int(d["compare"], compare(c, a))
            d["compare"] = mix_int(d["compare"], compare(a, a))
            d["bits"] = mix_int(d["bits"], a.bit_length())
            d["bits"] = mix_int(d["bits"], (a & -a).bit_length() - 1)  # trailing zeros
            for position in (size // 2, size - 1, size):
                d["bits"] = mix_int(d["bits"], (a >> position) & 1)
            # shifts and bit operations
            for amount in (1, 31, 32, 33, 63, 64, 65, size // 2, size + 7):
                d["shift"] = mix(d["shift"], a << amount)
                d["shift"] = mix(d["shift"], a >> amount)
            d["shift"] = mix(d["shift"], a & b)
            d["shift"] = mix(d["shift"], a | c)
            d["shift"] = mix(d["shift"], a ^ b)
            # multiplication and squaring
            d["mul"] = mix(d["mul"], a * b)
            d["mul"] = mix(d["mul"], a * c)
            d["mul"] = mix(d["mul"], c * a)
            d["mul"] = mix(d["mul"], a * small)
            d["mul"] = mix(d["mul"], a * word)
            d["square"] = mix(d["square"], a * a)
            d["square"] = mix(d["square"], c * c)
            # division
            if size <= 8192:
                wide = a * b
                for numerator, denominator in (
                    (a, small), (a, word), (a, c), (wide, a), (wide + c, b),
                ):
                    quotient, remainder = divmod(numerator, denominator)
                    d["div"] = mix(mix(d["div"], quotient), remainder)
            # gcd, square root, text
            if size <= 1025:
                d["gcd"] = mix(d["gcd"], math.gcd(a, b))
                d["gcd"] = mix(d["gcd"], math.gcd(a * c, a * small))
            if size <= 2049:
                for radicand in (a, a * a + c):
                    root = math.isqrt(radicand)
                    d["sqrt"] = mix(mix(d["sqrt"], root), radicand - root * root)
            if size <= 3100:
                text = to_radix(a, 10)
                d["text"] = mix_string(d["text"], text)
                d["text"] = mix_string(d["text"], to_radix(a, 16))
                d["text"] = mix_string(d["text"], to_radix(c, 7))
                d["text"] = mix(d["text"], int(text, 10))
    for size in REGRESSION_LARGE_SIZES:
        for shape in (0, 1, 6):
            a = value(random, size, shape)
            b = value(random, size - 1, (shape + 1) % 7)
            d["large_mul"] = mix(d["large_mul"], a * b)
            d["large_mul"] = mix(d["large_mul"], a * a)
            d["large_mul"] = mix(d["large_mul"], a + b)
            d["large_mul"] = mix(d["large_mul"], a * value(random, 200, 0))
    return d


def committed_regression() -> dict[str, int]:
    """The digests asserted by `coeff_regression_wbtest.mbt` (`assert_eq(d.add, 123UL)`)."""
    text = REGRESSION_TEST.read_text(encoding="utf-8")
    found = {
        name: int(literal)
        for name, literal in re.findall(r"assert_eq\(d\.(\w+), (\d+)UL\)", text)
    }
    if set(found) != set(REGRESSION_NAMES):
        raise SystemExit(
            f"{REGRESSION_TEST}: asserted digests {sorted(found)} differ from {REGRESSION_NAMES}"
        )
    return found


def check() -> int:
    computed = regression()
    committed = committed_regression()
    failed = False
    for name in REGRESSION_NAMES:
        if computed[name] != committed[name]:
            print(
                f"regression.{name}: committed {committed[name]}, "
                f"computed {computed[name]}",
                file=sys.stderr,
            )
            failed = True
    if failed:
        return 1
    print(f"kernel_oracle: regression table: {len(REGRESSION_NAMES)} digests match")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--check", action="store_true", help="compare with the committed MoonBit tables")
    args = parser.parse_args()
    if args.check:
        return check()
    for name, digest in regression().items():
        print(f"regression.{name} {digest}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
