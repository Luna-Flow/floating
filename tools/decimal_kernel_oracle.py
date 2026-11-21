#!/usr/bin/env python3
"""Oracle for the decimal coefficient kernel (`library/src/internal/decimal_kernel`).

Level A oracle in the sense of RULES.md: every expected value is computed with CPython
integers (`+ - * // % **`, `math.gcd`, `math.isqrt`) and nothing else. The program imports no
library of this repository. The rounding rules of `round_div_pow10` are written from the
rounding table of the General Decimal Arithmetic specification and IEEE 754-2019 4.3, not
from the library.

A row is `(case id, digest)`. No operand and no result is stored. The operands are
regenerated from a seed on both sides (here and in the MoonBit test) with the xorshift64
generator of `sqrt_diff_next` (`x ^= x << 13; x ^= x >> 7; x ^= x << 17`) and the limb
generators `round_value` (limbs of base 10^9 with a rotating share of all-nine limbs, halves
and zeros) and `random_limbs`, the same loops as the test classes in
`coeff_oracle_wbtest.mbt`. The digest is FNV-1a (64 bits) over the decimal text of every
operand and every expected integer, so that an operand built wrongly by the test cannot hide a
wrong result (and the text `0` or `1` for an inexact flag), each followed by a separating
`0xff` byte step. The test computes the same digest over the results of the kernel and
compares it with the row: a wrong result anywhere in a class changes the digest with
probability 1 - 2^-64 (the digest is not cryptographic).

Tables:

* `round`: `dec_coeff_round_div_pow10` (and its `_owned` entry): quotient and inexact flag for
  every shift at and around the limb and digit boundaries, both signs, the eight rounding
  directions.
* `div`: `dec_coeff_div_rem_knuth_repr` (`divmod`) and `dec_coeff_div_scaled_inexact` (the
  quotient of `c 10^s` by `d`, incremented when a nonzero remainder leaves a last digit 0 or 5,
  and zero when the exact quotient has a finite decimal expansion, tested here by the
  definition: the reduced denominator `d / gcd(n, d)` has no prime factor besides 2 and 5).
* `sqrt`: `dec_coeff_integer_sqrt_rem_repr` (`math.isqrt` and `n - isqrt(n)^2`).
* `mul`: `dec_coeff_mul_schoolbook` and `dec_coeff_square_schoolbook` (`a * b`).
* `unbalanced`: `dec_coeff_mul_unbalanced` and `dec_coeff_multiply_repr` (`a * b`).
* `finite`: `has_finite_decimal_expansion_repr`, by the definition above (zero numerator: finite).

    python3 tools/decimal_kernel_oracle.py          write the rows file
    python3 tools/decimal_kernel_oracle.py --check  fail if the committed file differs
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
KERNEL_TESTS = ROOT / "library/src/internal/decimal_kernel"
ROWS_FILE = KERNEL_TESTS / "coeff_oracle_rows_wbtest.mbt"

sys.set_int_max_str_digits(0)

MASK64 = (1 << 64) - 1
FNV_BASIS = 0xCBF29CE484222325
FNV_PRIME = 0x100000001B3
BASE = 10**9
SMALL_LIMIT = 10**18
CASES = 300


class Digest:
    """FNV-1a over the text of each added value, one `0xff` step after each."""

    def __init__(self) -> None:
        self.state = FNV_BASIS

    def add(self, value: int | str) -> None:
        for byte in str(value).encode("ascii"):
            self.state = ((self.state ^ byte) * FNV_PRIME) & MASK64
        self.state = ((self.state ^ 0xFF) * FNV_PRIME) & MASK64


class Random:
    """`sqrt_diff_next` of the MoonBit tests."""

    def __init__(self, seed: int) -> None:
        self.state = seed & MASK64

    def next(self) -> int:
        x = self.state
        x ^= (x << 13) & MASK64
        x ^= x >> 7
        x ^= (x << 17) & MASK64
        self.state = x
        return x


def from_limbs(limbs: list[int]) -> int:
    value = 0
    for limb in reversed(limbs):
        value = value * BASE + limb
    return value


def round_value(random: Random, length: int, nines: int) -> int:
    """`round_diff_value`."""
    limbs = [0] * length
    for index in range(length):
        pick = random.next() % 12
        width = random.next() % 9 + 1
        if pick < nines:
            limbs[index] = BASE - 1
        elif pick == 11:
            limbs[index] = 0
        elif pick == 10:
            limbs[index] = 5 * 10 ** (width - 1)
        else:
            limbs[index] = random.next() % 10**width
    if limbs[length - 1] == 0:
        limbs[length - 1] = random.next() % 999999999 + 1
    return from_limbs(limbs)


def random_limbs(random: Random, length: int) -> int:
    """`sqrt_diff_random_limbs`."""
    limbs = [0] * length
    for index in range(length):
        width = random.next() % 9 + 1
        value = random.next() % 10**width
        if random.next() % 7 == 0:
            value = 0
        elif random.next() % 7 == 0:
            value = BASE - 1
        limbs[index] = value
    if limbs[length - 1] == 0:
        limbs[length - 1] = random.next() % 999999999 + 1
    return from_limbs(limbs)


def digits_of(value: int) -> int:
    return len(str(value))


# ---- round_div_pow10 ----

MODES = ["HalfEven", "HalfUp", "HalfDown", "Down", "Ceiling", "Floor", "Up", "ZeroFiveUp"]


def round_pow10(value: int, shift: int, negative: bool, mode: str) -> tuple[int, bool]:
    """`value / 10^shift` rounded to an integer in the given direction of the magnitude of a
    value of the given sign, and whether the division was inexact."""
    divisor = 10**shift
    quotient, remainder = divmod(value, divisor)
    if remainder == 0:
        return quotient, False
    twice = 2 * remainder
    if mode == "Down":
        up = False
    elif mode == "Up":
        up = True
    elif mode == "Ceiling":
        up = not negative
    elif mode == "Floor":
        up = negative
    elif mode == "HalfUp":
        up = twice >= divisor
    elif mode == "HalfDown":
        up = twice > divisor
    elif mode == "HalfEven":
        up = twice > divisor or (twice == divisor and quotient % 2 == 1)
    else:
        assert mode == "ZeroFiveUp"
        up = quotient % 10 in (0, 5)
    return (quotient + 1 if up else quotient), True


def round_add(digest: Digest, value: int, shift: int) -> None:
    digest.add(value)
    digest.add(shift)
    for mode in MODES:
        for negative in (False, True):
            quotient, inexact = round_pow10(value, shift, negative, mode)
            digest.add(quotient)
            digest.add(1 if inexact else 0)


def round_shifts(random: Random, value: int) -> list[int]:
    digits = digits_of(value)
    shifts = [0, 1, 8, 9, 10, 17, 18, 19, digits - 10, digits - 9, digits - 8, digits - 2,
              digits - 1, digits, digits + 1]
    for _ in range(3):
        shifts.append(random.next() % (digits + 2))
    return [shift for shift in shifts if shift >= 0]


def round_class(length: int, seed: int) -> int:
    random = Random(seed)
    digest = Digest()
    for iteration in range(CASES):
        nines = (iteration % 4) * 3
        value = round_value(random, length, nines)
        for shift in round_shifts(random, value):
            round_add(digest, value, shift)
    return digest.state


def round_powers() -> int:
    digest = Digest()
    for digits in range(1, 400):
        power = 10**digits
        for value in (power, power - 1, 5 * power):
            for shift in range(digits + 3):
                round_add(digest, value, shift)
    return digest.state


# ---- division ----


def div_add(digest: Digest, numerator: int, denominator: int) -> None:
    quotient, remainder = divmod(numerator, denominator)
    digest.add(numerator)
    digest.add(denominator)
    digest.add(quotient)
    digest.add(remainder)


def finite_expansion(numerator: int, denominator: int) -> bool:
    """The expansion of numerator / denominator terminates: by definition, the reduced
    denominator has no prime factor besides 2 and 5."""
    reduced = denominator // math.gcd(numerator, denominator)
    for prime in (2, 5):
        while reduced % prime == 0:
            reduced //= prime
    return reduced == 1


def scaled_add(digest: Digest, coefficient: int, shift: int, denominator: int) -> None:
    numerator = coefficient * 10**shift
    quotient, _ = divmod(numerator, denominator)
    digest.add(coefficient)
    digest.add(shift)
    digest.add(denominator)
    if finite_expansion(numerator, denominator):
        digest.add(0)
    else:
        digest.add(quotient + 1 if quotient % 10 in (0, 5) else quotient)


def div_class(numerator_limbs: int, denominator_limbs: int, seed: int) -> int:
    random = Random(seed)
    digest = Digest()
    for iteration in range(CASES):
        nines = (iteration % 4) * 3
        numerator = round_value(random, numerator_limbs, nines)
        denominator = round_value(random, denominator_limbs, nines)
        div_add(digest, numerator, denominator)
        multiple = denominator * numerator
        div_add(digest, multiple, denominator)
        div_add(digest, multiple + 1, denominator)
        div_add(digest, multiple - 1, denominator)
        coefficient = round_value(random, numerator_limbs, nines)
        shift = random.next() % 40
        scaled_add(digest, coefficient, shift, denominator)
        twos = random.next() % 12
        fives = random.next() % 8
        composite = denominator * 2**twos * 5**fives
        scaled_add(digest, coefficient, shift, composite)
        scaled_add(digest, coefficient * denominator, shift, composite)
        scaled_add(digest, coefficient, shift, 10 ** (twos + 9))
    return digest.state


def div_powers() -> int:
    digest = Digest()
    for digits in range(10, 400):
        power = 10**digits
        nines = power - 1
        for denominator in (10 ** (digits // 2 + 9), 10 ** (digits // 2 + 9) - 1,
                            10 ** (digits // 3 + 9) + 1):
            for numerator in (power, nines, 7 * power):
                if numerator >= denominator and denominator >= BASE:
                    div_add(digest, numerator, denominator)
                scaled_add(digest, numerator, digits % 25, denominator)
    return digest.state


# ---- square root ----


def sqrt_add(digest: Digest, n: int) -> None:
    root = math.isqrt(n)
    digest.add(n)
    digest.add(root)
    digest.add(n - root * root)


def sqrt_class(length: int, seed: int) -> int:
    random = Random(seed)
    digest = Digest()
    for _ in range(CASES):
        sqrt_add(digest, random_limbs(random, length))
        root = random_limbs(random, (length + 1) // 2)
        square = root * root
        sqrt_add(digest, square)
        sqrt_add(digest, square + 1)
        sqrt_add(digest, square - 1)
    return digest.state


def sqrt_powers() -> int:
    digest = Digest()
    for digits in range(1100):
        power = 10**digits
        sqrt_add(digest, power)
        sqrt_add(digest, power + 1)
        if digits > 0:
            sqrt_add(digest, power - 1)
        sqrt_add(digest, 4 * power)
        sqrt_add(digest, 9 * power)
        sqrt_add(digest, 3 * power)
    return digest.state


def sqrt_small() -> int:
    digest = Digest()
    for value in range(2000):
        sqrt_add(digest, value)
    random = Random(0x123456789ABCDEF1)
    for _ in range(CASES):
        sqrt_add(digest, random.next() % SMALL_LIMIT)
        root = random.next() % BASE
        sqrt_add(digest, root * root)
        if root > 0:
            sqrt_add(digest, root * root - 1)
        sqrt_add(digest, root * root + 1)
    return digest.state


# ---- schoolbook product ----


def mul_add(digest: Digest, left: int, right: int) -> None:
    digest.add(left)
    digest.add(right)
    digest.add(left * right)


def mul_class(left_limbs: int, right_limbs: int, seed: int) -> int:
    random = Random(seed)
    digest = Digest()
    for iteration in range(CASES):
        nines = (iteration % 4) * 3
        left = round_value(random, left_limbs, nines)
        right = round_value(random, right_limbs, nines)
        mul_add(digest, left, right)
        digest.add(left)
        digest.add(left * left)
    return digest.state


def all_nines(length: int) -> int:
    return BASE**length - 1


def mul_nines() -> int:
    digest = Digest()
    for length in range(1, 140):
        nines = all_nines(length)
        mul_add(digest, nines, nines)
        digest.add(nines * nines)
        mul_add(digest, nines, all_nines(length + 1))
        mul_add(digest, all_nines(length // 2 + 1), nines)
    return digest.state


def mul_folds() -> int:
    random = Random(0x243F6A8885A308D3)
    digest = Digest()
    for length in (1, 2, 15, 16, 17, 18, 19, 31, 32, 33, 34, 47, 48, 49, 63, 64, 65, 80, 81, 96, 97):
        for other in (1, length - 1, length, length + 1, 2 * length + 1):
            if other >= 1:
                for iteration in range(20):
                    nines = (iteration % 4) * 3
                    left = round_value(random, length, nines)
                    right = round_value(random, other, nines)
                    mul_add(digest, left, right)
                    mul_add(digest, right, left)
        for iteration in range(20):
            nines = (iteration % 4) * 3
            value = round_value(random, length, nines)
            digest.add(value)
            digest.add(value * value)
    return digest.state


# ---- unbalanced product ----


def unbalanced_add(digest: Digest, short: int, long: int) -> None:
    digest.add(short)
    digest.add(long)
    for _ in range(3):  # the unbalanced entry, multiply(short, long), multiply(long, short)
        digest.add(short * long)


def unbalanced_shapes() -> int:
    random = Random(0x9E3779B97F4A7C15)
    digest = Digest()
    for short_limbs in (1, 2, 3, 5, 9, 17, 18, 19, 20, 33, 34, 50, 96, 150, 191):
        for factor_tenths in (21, 25, 30, 50, 80, 120):
            long_limbs = short_limbs * factor_tenths // 10 + 1
            if long_limbs > 2 * short_limbs:
                for round_ in range(4):
                    nines = round_ * 3
                    short = round_value(random, short_limbs, nines)
                    long = round_value(random, long_limbs, nines)
                    unbalanced_add(digest, short, long)
    return digest.state


def unbalanced_blocks() -> int:
    random = Random(0xD1B54A32D192ED03)
    digest = Digest()
    for short_limbs in (192, 200, 250):
        for long_limbs in (2 * short_limbs + 1, 3 * short_limbs, 4 * short_limbs + 7):
            for nines in (0, 6):
                short = round_value(random, short_limbs, nines)
                long = round_value(random, long_limbs, nines)
                unbalanced_add(digest, short, long)
    return digest.state


def unbalanced_nines() -> int:
    digest = Digest()
    for short_limbs in (1, 2, 15, 16, 17, 18, 19, 31, 32, 33, 64, 100, 191):
        for long_limbs in (2 * short_limbs + 1, 3 * short_limbs + 2, 40 + 5 * short_limbs):
            unbalanced_add(digest, all_nines(short_limbs), all_nines(long_limbs))
    return digest.state


# ---- finite decimal expansion ----


def finite_add(digest: Digest, numerator: int, denominator: int) -> None:
    digest.add(numerator)
    digest.add(denominator)
    digest.add(1 if numerator == 0 or finite_expansion(numerator, denominator) else 0)


def finite_class(limbs: int, seed: int) -> int:
    random = Random(seed)
    digest = Digest()
    for iteration in range(CASES):
        nines = (iteration % 4) * 3
        numerator = round_value(random, limbs, nines)
        part = round_value(random, (limbs + 1) // 2, nines)
        twos = (0, 1, 3, 8, 9, 10, 20, 37)[random.next() % 8]
        fives = (0, 1, 4, 8, 9, 11, 25)[random.next() % 7]
        denominator = part * 2**twos * 5**fives
        finite_add(digest, numerator, denominator)
        finite_add(digest, numerator * part, denominator)
        finite_add(digest, numerator * denominator, denominator)
        finite_add(digest, numerator * part + 1, denominator)
        finite_add(digest, denominator, denominator)
        finite_add(digest, 0, denominator)
        finite_add(digest, 1, denominator)
    return digest.state


def finite_special() -> int:
    digest = Digest()
    for exponent in range(80):
        ten, two, five = 10**exponent, 2**exponent, 5**exponent
        for denominator in (ten, two, five, two * five, ten + 1, 3 * ten, 7 * ten):
            for numerator in (1, 7, ten, 21 * ten, ten + 1):
                finite_add(digest, numerator, denominator)
    return digest.state


ROUND_CLASSES = [(1, 0x9E3779B97F4A7C15), (2, 0xD1B54A32D192ED03), (3, 0x2545F4914F6CDD1D),
                 (6, 0x94D049BB133111EB), (12, 0xBF58476D1CE4E5B9), (56, 0x6A09E667F3BCC909),
                 (112, 0xBB67AE8584CAA73B)]
DIV_CLASSES = [(2, 2, 0x9E3779B97F4A7C15), (4, 2, 0xD1B54A32D192ED03), (4, 3, 0x2545F4914F6CDD1D),
               (8, 4, 0x94D049BB133111EB), (12, 6, 0xBF58476D1CE4E5B9),
               (24, 12, 0x6A09E667F3BCC909), (112, 56, 0xBB67AE8584CAA73B),
               (224, 112, 0x3C6EF372FE94F82B)]
SQRT_CLASSES = ROUND_CLASSES
MUL_CLASSES = [(1, 1, 0x9E3779B97F4A7C15), (1, 2, 0xD1B54A32D192ED03), (2, 2, 0x2545F4914F6CDD1D),
               (3, 3, 0x94D049BB133111EB), (4, 4, 0xBF58476D1CE4E5B9), (6, 3, 0x6A09E667F3BCC909),
               (12, 12, 0xBB67AE8584CAA73B), (17, 17, 0x3C6EF372FE94F82B),
               (18, 18, 0xA54FF53A5F1D36F1), (19, 18, 0x510E527FADE682D1),
               (19, 19, 0x9B05688C2B3E6C1F), (40, 18, 0x1F83D9ABFB41BD6B),
               (56, 56, 0x5BE0CD19137E2179), (112, 112, 0xCBBB9D5DC1059ED8),
               (112, 20, 0x629A292A367CD507)]

FINITE_CLASSES = [(1, 0x9E3779B97F4A7C15), (2, 0xD1B54A32D192ED03), (3, 0x2545F4914F6CDD1D),
                  (4, 0x94D049BB133111EB), (6, 0xBF58476D1CE4E5B9), (12, 0x6A09E667F3BCC909),
                  (24, 0xBB67AE8584CAA73B), (56, 0x3C6EF372FE94F82B), (120, 0xA54FF53A5F1D36F1)]


def rows() -> list[tuple[str, int]]:
    out: list[tuple[str, int]] = []
    for length, seed in ROUND_CLASSES:
        out.append((f"round-{length}", round_class(length, seed)))
    out.append(("round-powers", round_powers()))
    for numerator, denominator, seed in DIV_CLASSES:
        out.append((f"div-{numerator}x{denominator}", div_class(numerator, denominator, seed)))
    out.append(("div-powers", div_powers()))
    for length, seed in SQRT_CLASSES:
        out.append((f"sqrt-{length}", sqrt_class(length, seed)))
    out.append(("sqrt-powers", sqrt_powers()))
    out.append(("sqrt-small", sqrt_small()))
    for left, right, seed in MUL_CLASSES:
        out.append((f"mul-{left}x{right}", mul_class(left, right, seed)))
    out.append(("mul-nines", mul_nines()))
    out.append(("mul-folds", mul_folds()))
    out.append(("unbalanced-shapes", unbalanced_shapes()))
    out.append(("unbalanced-blocks", unbalanced_blocks()))
    out.append(("unbalanced-nines", unbalanced_nines()))
    for limbs, seed in FINITE_CLASSES:
        out.append((f"finite-{limbs}", finite_class(limbs, seed)))
    out.append(("finite-special", finite_special()))
    return out


HEADER = """\
// oracle-file: A
// library-ran: no
// producer: tools/decimal_kernel_oracle.py (CPython integers, math.gcd and math.isqrt only)
// input: the xorshift64 seeds and the limb generators of coeff_oracle_wbtest.mbt; the expected
//   integers are a * b, divmod, isqrt, the rounding table of GDA and IEEE 754-2019 4.3

///|
/// Rows of the decimal coefficient kernel oracle, generated by `tools/decimal_kernel_oracle.py`
/// (do not edit). One row per line: `id digest`, the FNV-1a digest of the decimal text of every
/// expected integer of the class, in the order of the loops of `coeff_oracle_wbtest.mbt`.
let decimal_kernel_oracle_table : String =
"""


def render() -> str:
    lines = [f"  #|{name} {digest}\n" for name, digest in rows()]
    return HEADER + "".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    text = render()
    if args.check:
        if not ROWS_FILE.exists() or ROWS_FILE.read_text() != text:
            print(f"{ROWS_FILE.relative_to(ROOT)} differs from the table computed here", file=sys.stderr)
            return 1
        print("decimal_kernel_oracle: ok")
        return 0
    ROWS_FILE.write_text(text)
    print(f"wrote {ROWS_FILE.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
