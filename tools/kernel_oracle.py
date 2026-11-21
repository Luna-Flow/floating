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
* `product`: exact digests of products and squares at the sizes where the
  production routes switch (`coeff_product_oracle_wbtest.mbt`, rows file
  `coeff_product_oracle_rows_wbtest.mbt`). The expected integer is `a * b` or
  `a * a` of CPython, folded with the same digest as above. A row names the
  routes of the kernel that must produce it (the default `Coeff::mul` or
  `Coeff::square`, the NTT, Toom-3 or the word Karatsuba called directly).
* `overlap`: products too large for one NTT transform (the overlap-add route),
  where CPython could form the product but would take minutes. The expected
  value is the residue of `a * b` modulo each of the four moduli below,
  computed from the residues of the operands.

* `sqrt`: roots, remainders and the packed rounded root of the square root routes
  (`coeff_sqrt_oracle_wbtest.mbt`): exact squares, squares minus one and plus one and
  random radicands at the limits of the word kernels and at every level of the
  recursion. The radicand digest is part of the row, so a wrong square cannot hide a wrong root.
* `div`: quotients and remainders of the division routes (Knuth, Burnikel-Ziegler, the
  short exact division), the packed scaled quotient and the rounded short quotient
  (`coeff_div_oracle_wbtest.mbt`). The expected values are `divmod` of CPython. The operands
  are built from the row (bases of `value` and limb terms, grammar in `DIV_HEADER`); the
  generator's port of Knuth's algorithm D (`knuth_events`) only says which rows reach a
  correction step and is never an expected value.

    python3 tools/kernel_oracle.py              # write the rows files
    python3 tools/kernel_oracle.py --print      # print the regression digests
    python3 tools/kernel_oracle.py --check      # fail if a committed table differs
    python3 tools/kernel_oracle.py --check --all  # also the rows that are slow to compute

`--check` compares the committed MoonBit tables with the values computed here
and never writes a file. Without `--all` it skips the rows whose operands are
large (a product above 12,000 limbs, and every `overlap` row: they take about a
minute to compute in CPython); the binary gate runs it with `--all`.

Error classes of the digests. The FNV-1a digest over the exact bytes detects
any change of the result with probability 1 - 2^-64 per row for errors that are
not adversarial against it (it is not a cryptographic hash).

Error classes of the residues. The moduli are M1 = 2^64 - 1, M2 = 2^61 - 1 and
the primes P1 = 2147483587 and P2 = 2147483629. A limb at position `i` has the
weight `2^(64 i)` modulo the modulus: 1 for M1 (since 2^64 = 1), `8^i` for M2
(period 61 limbs), and for P1 and P2 weights of the multiplicative orders
1,073,741,793 and 536,870,907 (`2^64` modulo each prime), far above the number
of limbs of any row, so every position has its own weight. P1 and P2 are
31-bit so that a Horner step `(acc << 32 | piece) % p` stays in 64 bits in the
MoonBit test. A modulus misses an error only if the error is a multiple of it.

| error in the product | M1 | M2 | P1, P2 | why |
| --- | --- | --- | --- | --- |
| a lost or doubled carry at a limb boundary (a limb off by 1) | sees | sees | see | the change is `+-w` with `w` the weight of the limb, never 0 modulo a prime or M1 |
| a limb changed by `d` with `0 < |d| < 2^61 - 1` (a wrong low or high limb, a wrong digit anywhere) | sees | sees | see unless p divides d | the change is `d w`, `w` a unit: not a multiple of M1 or M2 because `|d|` is below both |
| a dropped block (limbs zeroed or removed) | sees | sees | see | the change is the value of the block times a weight: it is a multiple of a modulus only if the block value is |
| two blocks swapped | MISSES | sees unless the offset is a multiple of 61 limbs | see | M1 gives every limb the weight 1, so any rearrangement of limbs has the same sum; the weights of M2 repeat every 61 limbs; the weights of P1 and P2 differ for every pair of positions |
| a block shifted by one limb inside the result | sees | sees | see | the limbs change value; same as the first row |
| the whole result shifted by one limb (multiplied by 2^64) | MISSES | sees | see | `2^64 = 1` modulo M1, but `2^64 = 8` modulo M2 and it is neither 1 nor 8 modulo the primes |

An error is missed only if it is a multiple of all four moduli (a number of
about 2^187), except for the two structured blind spots of M1 and M2 stated
above, which P1 and P2 cover. `kernel_oracle_test.py` injects one error of each
row into a known product and asserts which residues change.
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


PRODUCT_TABLE = KERNEL_TESTS / "coeff_product_oracle_rows_wbtest.mbt"
PRODUCT_HEADER = """///|
/// Rows of the product oracle, generated by `tools/kernel_oracle.py` (do not edit).
/// One row per line: `id kind routes left_limbs right_limbs left_shape right_shape
/// seed where digest...`. `kind` is `mul`, `square` or `overlap`. The operands are
/// `regression_value(random, 64 * limbs, shape)` drawn from one generator seeded
/// with `seed` (left first); `where` is `pr` (run by the default test, quick gate) or `gate`
/// (the `#skip` test run by the binary gate stage). `digest` is the FNV-1a
/// digest of the expected integer (`exact`) or, for `overlap`, the four residues
/// of the expected product modulo 2^64 - 1, 2^61 - 1, 2147483587 and 2147483629.
let product_oracle_table : String =
"""

MODULI = [(1 << 64) - 1, (1 << 61) - 1, 2147483587, 2147483629]

# (left shape, right shape): random, all ones, zero limbs inside, 2^k and 2^k + 1,
# sparse and random
PR_LIMBS = 600  # rows up to this size run in the default test

PATTERNS = [(0, 0), (1, 1), (6, 6), (2, 3), (5, 0)]


HEAVY_LIMBS = 12000  # rows with a product above this are slow to compute in CPython


def row_where(left: int, right: int) -> str:
    return "pr" if max(left, right) <= PR_LIMBS else "gate"


def row_heavy(left: int, right: int) -> bool:
    return left + right > HEAVY_LIMBS


def row_seed(text: str) -> int:
    """A seed that depends on the row id only (FNV-1a of its text)."""
    state = FNV_BASIS
    for char in text:
        state = ((state ^ ord(char)) * FNV_PRIME) & MASK64
    return state


def product_digest(kind: str, left_limbs: int, right_limbs: int, shape_l: int, shape_r: int, seed: int) -> int:
    random = Random(seed)
    a = value(random, 64 * left_limbs, shape_l)
    if kind == "square":
        return mix(FNV_BASIS, a * a)
    b = value(random, 64 * right_limbs, shape_r)
    return mix(FNV_BASIS, a * b)


def product_rows() -> list[tuple[str, str, str, int, int, int, int, str]]:
    """(id, kind, routes, left limbs, right limbs, left shape, right shape, where).

    Sizes are limbs of 64 bits. `routes` lists what the test must run on the row:
    `mul` the default `Coeff::mul`, `ntt` `bin_coeff_mul_ntt`, `toom3`
    `bin_coeff_mul_toom3`, `words` `bin_coeff_mul_words`, `square` the default
    `Coeff::square`, `square_ntt` `bin_coeff_square_ntt`.
    """
    rows = []

    def add(kind: str, routes: str, left: int, right: int, shapes: tuple[int, int], _weight: str = "") -> None:
        name = f"{kind}-{left}x{right}-{shapes[0]}{shapes[1]}"
        rows.append((name, kind, routes, left, right, shapes[0], shapes[1], row_where(left, right)))

    # R1.6: products where the NTT, Toom-3 and the word blocks are selected
    # (`coeff_advanced_nonjs.mbt`, `bin_coeff_mul_large_dispatch`): balanced on
    # both sides of 4,096 limbs and of the product limit of each tier (15,360 C
    # rows, 30,720 assembly rows), ratio 2, ratio above 2.
    balanced = [4095, 4096, 4097, 5120, 6143, 7168, 7169, 14336, 15359, 15360, 15361, 30719, 30720, 30721]
    for size in balanced:
        for shapes in PATTERNS:
            heavy = size >= 14336
            routes = "mul,ntt"
            if size <= 8192:
                routes += ",toom3,words"
            add("mul", routes, size, size, shapes, "heavy" if heavy else "quick")
    for left, right in [(8192, 4096), (8191, 4096), (15360, 7680), (12288, 4096), (10240, 4096), (13000, 4097), (30000, 4096), (30720, 15360)]:
        for shapes in PATTERNS[:3]:
            routes = "mul,ntt"
            if left <= 2 * right and left <= 8192:
                routes += ",toom3"
            if left <= 13000:
                routes += ",words"
            add("mul", routes, left, right, shapes, "heavy" if left >= 15360 else "quick")
    # R1.4: squares from the NTT limit of 3,584 limbs (the old test stopped at
    # 3,585) up to the transform limit
    for size in [3583, 3584, 3585, 3586, 4096, 5000, 8192, 15360, 30000, 61440]:
        for shapes in [(0, 0), (1, 1), (6, 6), (3, 3)]:
            heavy = size >= 15360
            add("square", "square" if size < 3584 else "square,square_ntt", size, 0, shapes, "heavy" if heavy else "quick")
    # R1.7: the routes below the NTT, around every cutoff of the targets: the
    # word Karatsuba (cutoffs 32 and 48 limbs, 96 and 64 for the square), the
    # unbalanced blocks, the Toom-3 square (384), the recursive square (256)
    sizes = [15, 16, 17, 31, 32, 33, 35, 36, 37, 47, 48, 49, 63, 64, 65, 95, 96, 97, 127, 128, 129,
             191, 192, 193, 255, 256, 257, 383, 384, 385, 511, 512, 513, 1023, 1024, 1025, 2047, 2048, 2049, 3583]
    for size in sizes:
        for shapes in [(0, 0), (1, 1), (6, 6), (2, 3)]:
            add("mul", "mul,words", size, size, shapes, "quick")
            add("mul", "mul,words", size, max(1, size // 3 + 1), shapes, "quick")
            add("square", "square", size, 0, shapes, "quick")
    # remove duplicates produced by the lists above (same id), keep the first
    seen = set()
    unique = []
    for row in rows:
        if row[0] in seen:
            continue
        seen.add(row[0])
        unique.append(row)
    return unique


def residues(number: int) -> list[int]:
    return [number % modulus for modulus in MODULI]


def overlap_rows() -> list[tuple[str, int, int, int, int, str]]:
    """(id, short limbs, long limbs, short shape, long shape, where).

    A product needs the overlap-add when the transform length for its digits
    (16 bits each) is above `bin_coeff_ntt_max_length` = 2^23: `bin_coeff_mul_ntt_overlap`
    cuts the longer operand into blocks of `(2^23 - shorter digits + 1) / 4` limbs.
    Five rows (each takes about 7 s of a debug build; the first run of 18 rows took
    123 s): the long operand a few limbs past one block (the second block is tiny),
    half a block past one block (two large blocks) and 7 limbs past one block, with
    a short operand of 16 limbs and one of 4,096 limbs (the size from which the
    default product selects the NTT).
    """
    rows = []
    for short, over_kind, shapes in (
        (16, "three", (0, 1)),
        (16, "block", (6, 3)),
        (4096, "three", (0, 1)),
        (4096, "half", (1, 6)),
        (4096, "block", (6, 3)),
    ):
        block = max(1, ((1 << 23) - short * 4 + 1) // 4)
        over = {"three": 3, "half": block // 2, "block": block + 7}[over_kind]
        long_limbs = block + over
        rows.append((f"overlap-{short}x{long_limbs}-{shapes[0]}{shapes[1]}", short, long_limbs, shapes[0], shapes[1], "gate"))
    return rows


def overlap_residues(short: int, long: int, shape_s: int, shape_l: int, seed: int) -> list[int]:
    random = Random(seed)
    a = value(random, 64 * short, shape_s)
    b = value(random, 64 * long, shape_l)
    return [(x * y) % modulus for x, y, modulus in zip(residues(a), residues(b), MODULI)]


def render_product_table(include_heavy: bool) -> dict[str, str]:
    """Row lines by id, in file order, for the quick rows (and the heavy ones if asked)."""
    lines: dict[str, str] = {}
    for name, kind, routes, left, right, shape_l, shape_r, weight in product_rows():
        if row_heavy(left, right) and not include_heavy:
            continue
        seed = row_seed(name)
        digest = product_digest(kind, left, right, shape_l, shape_r, seed)
        lines[name] = f"{name} {kind} {routes} {left} {right} {shape_l} {shape_r} {seed} {weight} exact {digest}"
    for name, short, long, shape_s, shape_l, weight in overlap_rows():
        if not include_heavy:
            continue
        seed = row_seed(name)
        res = " ".join(str(r) for r in overlap_residues(short, long, shape_s, shape_l, seed))
        lines[name] = f"{name} overlap overlap {short} {long} {shape_s} {shape_l} {seed} {weight} residues {res}"
    return lines


def row_names_in_order() -> list[str]:
    return [row[0] for row in product_rows()] + [row[0] for row in overlap_rows()]


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


class Table:
    """A generated MoonBit rows file: its path, header, row ids in order and row lines."""

    def __init__(self, name: str, path: Path, header: str, names, compute) -> None:
        self.name = name
        self.path = path
        self.header = header
        self.names = names  # () -> list of row ids in file order
        self.compute = compute  # (include_heavy) -> {id: line}

    def committed(self) -> dict[str, str]:
        text = self.path.read_text(encoding="utf-8")
        return {
            line.split(" ", 1)[0]: line
            for line in (raw.strip()[2:] for raw in text.splitlines() if raw.strip().startswith("#|"))
        }

    def write(self) -> None:
        lines = self.compute(True)
        body = "\n".join(f"  #|{lines[name]}" for name in self.names())
        self.path.write_text(self.header + body + "\n", encoding="utf-8")

    def check(self, include_heavy: bool) -> bool:
        table = self.committed()
        expected = set(self.names())
        ok = True
        if set(table) != expected:
            extra = sorted(set(table) - expected)[:5]
            missing = sorted(expected - set(table))[:5]
            print(f"{self.name} table: rows differ from the generator (extra {extra}, missing {missing})", file=sys.stderr)
            ok = False
        lines = self.compute(include_heavy)
        for name, line in lines.items():
            if table.get(name) != line:
                print(f"{self.name} row {name}: committed {table.get(name)!r}, computed {line!r}", file=sys.stderr)
                ok = False
        print(
            f"kernel_oracle: {self.name} table: {len(lines)} of {len(table)} rows compared"
            + ("" if include_heavy else " (slow rows skipped)")
        )
        return ok


TABLES: list[Table] = []


def check_regression() -> bool:
    computed = regression()
    committed = committed_regression()
    ok = True
    for name in REGRESSION_NAMES:
        if computed[name] != committed[name]:
            print(
                f"regression.{name}: committed {committed[name]}, "
                f"computed {computed[name]}",
                file=sys.stderr,
            )
            ok = False
    print(f"kernel_oracle: regression table: {len(REGRESSION_NAMES)} digests compared")
    return ok


def check(include_heavy: bool = False) -> int:
    failed = not check_regression()
    for table in TABLES:
        if not table.check(include_heavy):
            failed = True
    return 1 if failed else 0


TABLES.append(Table("product", PRODUCT_TABLE, PRODUCT_HEADER, row_names_in_order, render_product_table))


SHORT_TABLE = KERNEL_TESTS / "coeff_short_oracle_rows_wbtest.mbt"
SHORT_HEADER = """///|
/// Rows of the short product oracle, generated by `tools/kernel_oracle.py` (do not edit).
/// One row per line: `id short precision left_bits right_bits left_shape right_shape
/// seed where must_return digest`. The operands are `regression_value(random, bits,
/// shape)` drawn from one generator seeded with `seed` (left first). `must_return`
/// is 1 when the exact product is farther than `2 (m + 2)` units of the short
/// product's last limb from every rounding boundary (`m` the limbs of the short
/// product): the kernel must then return a value. `digest` is the FNV-1a digest of
/// the three roundings of the exact product to `precision` bits (to nearest even,
/// down, up), each as an odd coefficient and an exponent.
let short_oracle_table : String =
"""

# precisions where the window of a tier starts and ends: m = ceil(p / 64) + 1 limbs;
# portable 13 .. 64, C rows 20 .. 192, assembly 31 .. 384; one above each end
SHORT_PRECISIONS = [
    768, 769, 832, 1000, 1152, 1153, 1920, 1921, 3000, 4032, 4033, 6000, 12224, 12225,
    20000, 24512, 24513,
]
SHORT_WIDTHS = [(0, 0), (1, 0), (63, 0), (0, 17), (5, 63)]  # bits below the precision (left, right)
SHORT_SHAPES = [(0, 0), (1, 1), (3, 3), (2, 3), (6, 6), (5, 0)]
SHORT_PR_PRECISION = 4033  # rows up to this precision run in the default test


def round_product(product: int, precision: int) -> list[tuple[int, int]]:
    """The product rounded to `precision` bits: to nearest even, down, up, each as (odd q, exponent).

    Written from the definitions: the kept bits `q = floor(P / 2^s)` with
    `s = bits(P) - precision`, the discarded part `r = P mod 2^s`, half `2^(s - 1)`.
    """
    s = product.bit_length() - precision
    q = product >> s
    r = product - (q << s)
    half = 1 << (s - 1)
    nearest = q + 1 if (r > half or (r == half and q & 1)) else q
    up = q + 1 if r > 0 else q
    out = []
    for kept in (nearest, q, up):
        exponent = s
        while kept and kept % 2 == 0:
            kept //= 2
            exponent += 1
        out.append((kept, exponent))
    return out


def short_must_return(product: int, precision: int, left_bits: int, right_bits: int) -> int:
    """1 if the exact product is far from every rounding boundary (the kernel must return)."""
    limbs = (precision + 63) // 64 + 1
    unit_log = left_bits + right_bits - 64 * limbs  # one unit of the last limb of the short product
    s = product.bit_length() - precision
    # a boundary is a multiple of 2^(s - 1) (halfway points and representable points)
    grid = 1 << (s - 1)
    remainder = product % grid
    distance = min(remainder, grid - remainder)
    unit = 1 << max(unit_log, 0)
    return 1 if unit_log >= 0 and distance > 2 * (limbs + 2) * unit else 0


def short_row_values(precision: int, left_bits: int, right_bits: int, shape_l: int, shape_r: int, seed: int) -> tuple[int, int]:
    random = Random(seed)
    a = value(random, left_bits, shape_l)
    b = value(random, right_bits, shape_r)
    return a, b


def short_line(name: str, precision: int, dl: int, dr: int, shape_l: int, shape_r: int) -> str:
    left_bits, right_bits = precision - dl, precision - dr
    seed = row_seed(name)
    a, b = short_row_values(precision, left_bits, right_bits, shape_l, shape_r, seed)
    product = a * b
    state = FNV_BASIS
    for q, exponent in round_product(product, precision):
        state = mix_int(mix(state, q), exponent)
    where = "pr" if precision <= SHORT_PR_PRECISION else "gate"
    must = short_must_return(product, precision, a.bit_length(), b.bit_length())
    return f"{name} short {precision} {left_bits} {right_bits} {shape_l} {shape_r} {seed} {where} {must} {state}"


def short_names() -> list[str]:
    names = []
    for precision in SHORT_PRECISIONS:
        for dl, dr in SHORT_WIDTHS:
            for shape_l, shape_r in SHORT_SHAPES:
                names.append(f"short-{precision}-{dl}-{dr}-{shape_l}{shape_r}")
    return names


def short_compute(include_heavy: bool) -> dict[str, str]:
    lines = {}
    for precision in SHORT_PRECISIONS:
        for dl, dr in SHORT_WIDTHS:
            for shape_l, shape_r in SHORT_SHAPES:
                name = f"short-{precision}-{dl}-{dr}-{shape_l}{shape_r}"
                lines[name] = short_line(name, precision, dl, dr, shape_l, shape_r)
    return lines


TABLES.append(Table("short", SHORT_TABLE, SHORT_HEADER, short_names, short_compute))


LIMBS_TABLE = KERNEL_TESTS / "coeff_limbs_oracle_rows_wbtest.mbt"
LIMBS_HEADER = """///|
/// Rows of the limb row oracle, generated by `tools/kernel_oracle.py` (do not edit).
/// One row per line: `id kind a b c d e f g seed digest`, the parameters by kind:
///
/// - `mul1`, `addmul1`, `submul1`: `n ro ao shape_r shape_a bkind _`: `r[ro ..< ro + n]`
///   (the row of the array `r`, which has `ro + n + 2` limbs) is replaced by the
///   low limbs of `a * b` (`mul1`), `r + a * b` (`addmul1`) or `r - a * b` (`submul1`),
///   `a` a row of `n` limbs at `ao` of an array of `ao + n + 2` limbs, `b` one limb
///   (`bkind`: 0 random with the top bit set, 1 `2^64 - 1`, 2 `1`, 3 `2^63`, 4 `0`,
///   5 sparse, 6 `2^32 + 1`); the digest is that of the whole array `r` as one
///   integer (the limbs outside the row must not change) and of the limb returned
///   (the high limb for `mul1`/`addmul1`; for `submul1` the limb `c` with
///   `r_new = r - a b + c 2^(64 n)`, the carry limb and the borrow folded together).
/// - `product`: `an bn ro ao bo shape_a shape_b`, with `shape_r = 0`: the row
///   `r[ro ..< ro + an + bn]` is replaced by `a * b` (all `an + bn` limbs written).
/// - `square`: `n ro so shape_s 0 0 0`: `r[ro ..< ro + 2 n]` is replaced by `s^2`.
///
/// The arrays are `regression_value(random, 64 * count, shape)` limbs drawn from
/// one generator seeded with `seed` in the order r, a, b (then the word `b`).
let limbs_oracle_table : String =
"""

WINDOW_TABLE = KERNEL_TESTS / "coeff_window_oracle_rows_wbtest.mbt"
WINDOW_HEADER = """///|
/// Rows of the window row oracle, generated by `tools/kernel_oracle.py` (do not edit).
/// One row per line: `id count x_len x_ws x_bs y_len y_ws y_bs subtract carry_in
/// shape_x shape_y seed digest`. `x` and `y` are arrays of `x_len` and `y_len` limbs
/// (`regression_value`, drawn in that order from the generator seeded with `seed`;
/// `y_len = 0` is no second operand). Each operand is viewed through a window: limb
/// `j` of the window is bits `64 j .. 64 j + 63` of `operand * 2^(64 ws + bs)` (the low
/// bits dropped for a negative shift), zero outside the operand. The row computes
/// `count` limbs of `x_window + (y_window xor mask) + carry` with `mask` all ones for a
/// subtraction and carry `carry_in` (addition) or `1 - carry_in` (subtraction); the
/// digest is that of the result limbs as one integer and of the limb returned
/// (the carry out for an addition, `1 - carry out` for a subtraction).
let window_oracle_table : String =
"""

LIMB_COUNTS = [1, 2, 3, 4, 5, 7, 8, 9, 15, 16, 17, 31, 32, 33, 63, 64, 65, 127, 128, 129, 255, 256, 257]
LIMB_OFFSETS = [(0, 0), (1, 0), (0, 1), (3, 2), (7, 5)]
LIMB_SHAPE_PAIRS = [(0, 0), (1, 1), (1, 0), (2, 6), (6, 5)]
LIMB_BKINDS = [0, 1, 2, 3, 4, 5, 6]
MASK_LIMB = (1 << 64) - 1


def limb_list(random: Random, count: int, shape: int) -> list[int]:
    number = value(random, 64 * count, shape)
    return [(number >> (64 * i)) & MASK_LIMB for i in range(count)]


def limbs_to_int(limbs: list[int]) -> int:
    return sum(limb << (64 * i) for i, limb in enumerate(limbs))


def b_word(random: Random, bkind: int) -> int:
    if bkind == 0:
        return value(random, 64, 0)
    return {1: MASK_LIMB, 2: 1, 3: 1 << 63, 4: 0, 6: (1 << 32) + 1}.get(bkind) if bkind != 5 else value(random, 64, 5)


def limbs_rows() -> list[tuple]:
    """(id, kind, params...) in file order; the combinations rotate through the lists."""
    rows = []
    for kind in ("mul1", "addmul1", "submul1"):
        for n in LIMB_COUNTS:
            combos = [((1, 1), 1)]  # the maximum carry: all ones times all ones
            for i in range(7):
                combos.append((LIMB_SHAPE_PAIRS[(i + n) % 5], LIMB_BKINDS[(i * 2 + n) % 7]))
            for i, (shapes, bkind) in enumerate(combos):
                ro, ao = LIMB_OFFSETS[(i + n) % 5]
                rows.append((f"limbs-{kind}-{n}-{i}", kind, n, ro, ao, shapes[0], shapes[1], bkind, 0))
    for an, bn in [(1, 1), (1, 7), (7, 1), (2, 2), (3, 5), (8, 8), (9, 16), (16, 9), (17, 17), (31, 33), (32, 32), (33, 31), (64, 64), (65, 64), (100, 37), (129, 128), (257, 3)]:
        for i in range(6):
            ro, ao = LIMB_OFFSETS[i % 5]
            bo = LIMB_OFFSETS[(i + 2) % 5][1]
            shapes = LIMB_SHAPE_PAIRS[i % 5]
            rows.append((f"limbs-product-{an}x{bn}-{i}", "product", an, bn, ro, ao, bo, shapes[0], shapes[1]))
    for n in LIMB_COUNTS + [384, 385]:
        for i in range(5):
            ro, so = LIMB_OFFSETS[i]
            shapes = LIMB_SHAPE_PAIRS[(i + n) % 5]
            rows.append((f"limbs-square-{n}-{i}", "square", n, ro, so, shapes[1], 0, 0, 0))
    return rows


def limbs_line(row: tuple) -> str:
    name, kind = row[0], row[1]
    params = row[2:]
    seed = row_seed(name)
    random = Random(seed)
    if kind in ("mul1", "addmul1", "submul1"):
        n, ro, ao, shape_r, shape_a, bkind, _ = params
        r = limb_list(random, ro + n + 2, shape_r)
        a = limb_list(random, ao + n + 2, shape_a)
        b = b_word(random, bkind)
        a_int = limbs_to_int(a[ao : ao + n])
        r_int = limbs_to_int(r[ro : ro + n])
        modulus = 1 << (64 * n)
        if kind == "mul1":
            total = a_int * b
            new_row, ret = total % modulus, total // modulus
        elif kind == "addmul1":
            total = r_int + a_int * b
            new_row, ret = total % modulus, total // modulus
        else:
            total = r_int - a_int * b
            new_row = total % modulus
            ret = (new_row - total) // modulus
        assert 0 <= ret < (1 << 64)
        out = r[:ro] + [(new_row >> (64 * i)) & MASK_LIMB for i in range(n)] + r[ro + n :]
        return f"{name} {kind} {n} {ro} {ao} {shape_r} {shape_a} {bkind} 0 {seed} {mix(mix(FNV_BASIS, limbs_to_int(out)), ret)}"
    if kind == "product":
        an, bn, ro, ao, bo, shape_a, shape_b = params
        r = limb_list(random, ro + an + bn + 2, 0)
        a = limb_list(random, ao + an + 2, shape_a)
        b = limb_list(random, bo + bn + 2, shape_b)
        total = limbs_to_int(a[ao : ao + an]) * limbs_to_int(b[bo : bo + bn])
        out = r[:ro] + [(total >> (64 * i)) & MASK_LIMB for i in range(an + bn)] + r[ro + an + bn :]
        return f"{name} {kind} {an} {bn} {ro} {ao} {bo} {shape_a} {shape_b} {seed} {mix(FNV_BASIS, limbs_to_int(out))}"
    n, ro, so, shape_s, _, _, _ = params
    r = limb_list(random, ro + 2 * n + 2, 0)
    s = limb_list(random, so + n + 2, shape_s)
    total = limbs_to_int(s[so : so + n]) ** 2
    out = r[:ro] + [(total >> (64 * i)) & MASK_LIMB for i in range(2 * n)] + r[ro + 2 * n :]
    return f"{name} {kind} {n} {ro} {so} {shape_s} 0 0 0 {seed} {mix(FNV_BASIS, limbs_to_int(out))}"


def limbs_names() -> list[str]:
    return [row[0] for row in limbs_rows()]


def limbs_compute(include_heavy: bool) -> dict[str, str]:
    return {row[0]: limbs_line(row) for row in limbs_rows()}


TABLES.append(Table("limbs", LIMBS_TABLE, LIMBS_HEADER, limbs_names, limbs_compute))


WORD_SHIFT_MAX = 1 << 28  # `bin_limbs_window_max`


def window_view(operand: int, length: int, word_shift: int, bit_shift: int, count: int) -> int:
    """The window of `operand` (`length` limbs): `count` limbs of `operand * 2^(64 ws + bs)`."""
    if length == 0 or operand == 0:
        return 0
    shift = 64 * word_shift + bit_shift
    if shift >= 64 * count:
        return 0
    if shift >= 0:
        shifted = operand << shift
    elif -shift >= operand.bit_length():
        return 0
    else:
        shifted = operand >> -shift
    return shifted % (1 << (64 * count))


def window_rows() -> list[tuple]:
    """(id, count, x_len, x_ws, x_bs, y_len, y_ws, y_bs, subtract, carry_in, shape_x, shape_y)."""
    rng = Random(0x57494E444F57)  # "WINDOW": the choice of parameters, fixed here
    counts = [1, 2, 3, 12, 13, 14, 15, 16, 17, 31, 32, 33, 64, 65, 129]
    bit_shifts = [0, 0, 1, 7, 31, 32, 33, 63]
    shapes = [0, 0, 1, 6, 2, 3, 5]
    rows = []
    index = 0
    for count in counts:
        for variant in range(40):
            x_len = 1 + rng.next() % (count + 2)
            y_len = 0 if rng.next() % 9 == 0 else 1 + rng.next() % (count + 2)
            # word shifts: mostly small, some at the edges of the window and of the limit
            choices_x = [0, 0, 1, 2, count - 1, count, count + 1, WORD_SHIFT_MAX, 3]
            choices_y = [0, 1, -1, -2, -3, 2, -count, -count - 1, count - 1, count, WORD_SHIFT_MAX, -WORD_SHIFT_MAX, -x_len, -(y_len or 1) + 1, 5]
            x_ws = choices_x[rng.next() % len(choices_x)]
            y_ws = choices_y[rng.next() % len(choices_y)]
            x_bs = bit_shifts[rng.next() % len(bit_shifts)]
            y_bs = bit_shifts[rng.next() % len(bit_shifts)]
            subtract = rng.next() % 2
            carry_in = rng.next() % 2
            shape_x = shapes[rng.next() % len(shapes)]
            shape_y = shapes[rng.next() % len(shapes)]
            rows.append((f"window-{count}-{variant:02d}", count, x_len, x_ws, x_bs, y_len, y_ws, y_bs, subtract, carry_in, shape_x, shape_y))
            index += 1
    return rows


def window_line(row: tuple) -> str:
    name, count, x_len, x_ws, x_bs, y_len, y_ws, y_bs, subtract, carry_in, shape_x, shape_y = row
    seed = row_seed(name)
    random = Random(seed)
    x = value(random, 64 * x_len, shape_x)
    y = value(random, 64 * y_len, shape_y) if y_len else 0
    mask = (1 << (64 * count)) - 1 if subtract else 0
    x_window = window_view(x, x_len, x_ws, x_bs, count)
    y_window = window_view(y, y_len, y_ws, y_bs, count) ^ mask
    carry = (1 - carry_in) if subtract else carry_in
    total = x_window + y_window + carry
    result = total % (1 << (64 * count))
    out = total >> (64 * count)
    ret = (1 - out) if subtract else out
    return (
        f"{name} {count} {x_len} {x_ws} {x_bs} {y_len} {y_ws} {y_bs} {subtract} {carry_in} {shape_x} {shape_y} {seed} "
        f"{mix(mix(FNV_BASIS, result), ret)}"
    )


def window_names() -> list[str]:
    return [row[0] for row in window_rows()]


def window_compute(include_heavy: bool) -> dict[str, str]:
    return {row[0]: window_line(row) for row in window_rows()}


TABLES.append(Table("window", WINDOW_TABLE, WINDOW_HEADER, window_names, window_compute))


DIV_TABLE = KERNEL_TESTS / "coeff_div_oracle_rows_wbtest.mbt"
DIV_HEADER = """///|
/// Rows of the division oracle, generated by `tools/kernel_oracle.py` (do not edit).
/// One row per line: `id route divisor dividend seed where scale precision must digest`.
/// `route` names the function under test: `div` (`Coeff::div_rem_checked`, the default
/// dispatch), `knuth` (`bin_coeff_div_rem_knuth_words`), `bz`
/// (`bin_coeff_div_rem_burnikel_ziegler`), `short` (`bin_coeff_short_div_rem`),
/// `scaled` (`bin_coeff_div_scaled_quotient`), `shortq` (`bin_coeff_div_short_quotient`).
/// An operand is `BASE` or `BASE:TERM,TERM`: `BASE` is `0` or `bits.shape`
/// (`regression_value`, the divisor drawn first from the generator seeded with `seed`),
/// a `TERM` is `+HEX@k` or `-HEX@k` (one limb in hexadecimal times `2^(64 k)`) or `+D@k` /
/// `-D@k` (the divisor times `2^(64 k)`, in the dividend only); positive terms come first.
/// `digest` is the FNV-1a digest of the quotient and the remainder (`div`, `knuth`, `bz`,
/// `short`), of `2 q + s` with `s = 1` for a nonzero remainder of `dividend 2^scale / divisor`
/// (`scaled`), or of the three roundings to `precision` bits of the exact quotient of
/// `dividend 2^scale / divisor` (`shortq`, as the short product: nearest even, down, up,
/// each as an odd coefficient and an exponent); `must` is 1 for `shortq` when the exact
/// quotient is far from every rounding boundary, so that the kernel must not decline.
let div_oracle_table : String =
"""

B64 = 1 << 64


def limb_terms(number: int, shift: int, sign: str) -> list[str]:
    """Terms `sign HEX@k` of the nonzero limbs of `number * 2^(64 shift)`."""
    out = []
    index = 0
    while number:
        limb = number & MASK64
        if limb:
            out.append(f"{sign}{limb:016X}@{shift + index}")
        number >>= 64
        index += 1
    return out


def eval_spec(spec: str, divisor: int, random: Random) -> int:
    base, _, terms = spec.partition(":")
    total = 0
    if base != "0":
        bits, shape = base.split(".")
        total = value(random, int(bits), int(shape))
    for term in terms.split(",") if terms else []:
        sign = 1 if term[0] == "+" else -1
        magnitude, shift = term[1:].split("@")
        factor = divisor if magnitude == "D" else int(magnitude, 16)
        total += sign * (factor << (64 * int(shift)))
    assert total >= 0, spec
    return total


def knuth_events(numerator: int, divisor: int) -> dict[str, int]:
    """Counts of the corrections of Knuth's algorithm D on 64-bit digits for one division.

    Written from the algorithm (normalise, estimate each digit from the top limbs,
    multiply and subtract, add back): used only to say which rows reach a correction
    step, never as an expected value. `top` counts digits whose window top limb equals
    the divisor's top limb (the estimate `B - 1` and its decrements, counted in
    `top_decrements`), `addback` the digits whose estimate was one too large after the
    multiply-subtract, `two` those that were two too large.
    """
    limbs = (divisor.bit_length() + 63) // 64
    shift = 64 * limbs - divisor.bit_length()
    v = divisor << shift
    r = numerator << shift
    top = v >> (64 * (limbs - 1))
    out = {"digits": 0, "top": 0, "top_decrements": 0, "addback": 0, "two": 0}
    if limbs < 2:
        return out
    next_limb = (v >> (64 * (limbs - 2))) & MASK64
    two_limbs = v >> (64 * (limbs - 2))
    count = (r.bit_length() + 63) // 64 - limbs + 1
    for j in range(count - 1, -1, -1):
        window = r >> (64 * j)
        high = window >> (64 * limbs)
        if high < top:
            trial = (window >> (64 * (limbs - 2))) // two_limbs
        else:
            trial = B64 - 1
            out["top"] += 1
            u_next = (window >> (64 * (limbs - 1))) & MASK64
            u_after = (window >> (64 * (limbs - 2))) & MASK64
            remainder = u_next + top
            while remainder < B64 and trial * next_limb > (remainder << 64) + u_after:
                trial -= 1
                remainder += top
                out["top_decrements"] += 1
        out["digits"] += 1
        product = trial * v << (64 * j)
        misses = 0
        while product > r:
            trial -= 1
            product -= v << (64 * j)
            misses += 1
        if misses == 1:
            out["addback"] += 1
        elif misses >= 2:
            out["two"] += 1
        r -= trial * v << (64 * j)
    return out


def div_digest_pair(quotient: int, remainder: int) -> int:
    return mix(mix(FNV_BASIS, quotient), remainder)


def round_exact_quotient(quotient: int, sticky: bool, precision: int) -> list[tuple[int, int]]:
    """The exact value `quotient + (sticky ? fraction : 0)` to `precision` bits: nearest even, down, up."""
    s = quotient.bit_length() - precision
    q = quotient >> s
    r = quotient - (q << s)
    half = 1 << (s - 1)
    if r > half or (r == half and (sticky or q & 1)):
        nearest = q + 1
    else:
        nearest = q
    up = q + 1 if (r > 0 or sticky) else q
    out = []
    for kept in (nearest, q, up):
        exponent = s
        while kept and kept % 2 == 0:
            kept //= 2
            exponent += 1
        out.append((kept, exponent))
    return out


def shortq_must(quotient: int, precision: int, divisor_limbs: int) -> int:
    s = quotient.bit_length() - precision
    if s - 1 < 40:
        return 0
    grid = 1 << (s - 1)
    remainder = quotient % grid
    distance = min(remainder, grid - remainder)
    return 1 if distance > 2 * (2 * divisor_limbs + 8) else 0


def div_line(row: tuple) -> str:
    name, route, d_spec, n_spec, scale, precision, where = row
    seed = row_seed(name)
    random = Random(seed)
    d = eval_spec(d_spec, 0, random)
    n = eval_spec(n_spec, d, random)
    must = 0
    if route in ("div", "knuth", "bz", "short"):
        digest = div_digest_pair(*divmod(n, d))
    elif route == "scaled":
        q, r = divmod(n << scale, d)
        digest = mix(FNV_BASIS, 2 * q + (1 if r else 0))
    else:
        q, r = divmod(n << scale, d)
        digest = FNV_BASIS
        for kept, exponent in round_exact_quotient(q, r != 0, precision):
            digest = mix_int(mix(digest, kept), exponent)
        must = shortq_must(q, precision, (d.bit_length() + 63) // 64)
    return f"{name} {route} {d_spec} {n_spec} {seed} {where} {scale} {precision} {must} {digest}"


def dspec_kinds(limbs: int) -> dict[str, str]:
    """Divisors of `limbs` limbs (at least 2) whose top limb sits on the edges of the estimate."""
    n = limbs
    return {
        "ones": f"{64 * n}.1",  # 2^(64 n) - 1: top limb all ones
        "min": f"{64 * n}.2",  # 2^(64 n - 1): top limb 2^63, nothing below
        "min1": f"{64 * n}.3",  # 2^(64 n - 1) + 1
        "minmid": f"{64 * (n - 1)}.0:+8000000000000000@{n - 1}",  # top limb 2^63, random below
        "onesmid": f"{64 * (n - 1)}.0:+FFFFFFFFFFFFFFFF@{n - 1}",  # top limb all ones, random below
        "minones": f"{64 * (n - 1)}.1:+8000000000000000@{n - 1}",  # top limb 2^63, all ones below
        "rand": f"{64 * n}.0",
        "unnorm63": f"{64 * n - 63}.0",  # top limb 1: normalisation shift 63
        "unnorm31": f"{64 * n - 31}.0",
        "unnorm1": f"{64 * n - 1}.1",
    }


def nspec_kinds(k: int, d_limbs: int) -> dict[str, str]:
    """Dividends built from the divisor `D` and `k` quotient limbs: the quotient and the
    remainder sit on the edges (remainder 0, `D - 1`; quotient `B^k`, `B^k - 1`, `B^k - 2`)."""
    out = {
        "rand": f"{64 * (d_limbs + k)}.0",
        "ones": f"{64 * (d_limbs + k)}.1",
        "zeros": f"{64 * (d_limbs + k)}.6",
        "s1": f"0:+D@{k}",
        "s2": f"0:+D@{k},-1@0",
        "s3": f"0:+D@{k},+D@0,-1@0",
        "s4": f"0:+D@{k},-D@0",
        "s5": f"0:+D@{k},-D@0,-1@0",
        "s6": f"0:+D@{k},+1@0",
    }
    if k >= 1:
        out["t"] = f"{64 * k}.0:+D@{k}"
    return out


def addback_rows() -> list[tuple]:
    """Dividends `Q * (d1, d0) * B^(n-2)` for a divisor `(d1, d0) * B^(n-2) + e`: the top three
    limbs divided by the top two give `Q` exactly, and the divisor's lower part `e` makes the
    quotient `Q - 1`: the estimate is one too large and the add-back step runs."""
    rows = []
    two = [(1 << 63, 1), (1 << 63, 0), ((1 << 63) + 1, 0), (B64 - 1, B64 - 1), (B64 - 1, 1), (1 << 63, B64 - 1)]
    quotients = [B64 - 1, B64 - 2, (1 << 63) + 12345, (1 << 32) + 7, 3]
    tails = [1, 2, MASK64, (1 << 63) + 1]
    for n in (3, 4, 9):
        for ti, (d1, d0) in enumerate(two):
            for qi, big_q in enumerate(quotients):
                e = tails[(ti + qi) % len(tails)]
                d_val = (((d1 << 64) | d0) << (64 * (n - 2))) | e
                if big_q * e > d_val:
                    continue
                # the window must stay below B^3 with top limb below d1 for the 3-by-2 estimate
                product = big_q * ((d1 << 64) | d0)
                if (product >> 128) >= d1:
                    continue
                d_spec = "0:" + ",".join(limb_terms(d_val, 0, "+"))
                n_spec = "0:" + ",".join(limb_terms(product, n - 2, "+"))
                rows.append((f"div-addback-{n}-{ti}-{qi}", "div,knuth,bz", d_spec, n_spec, "pr"))
    return rows


DIV_PR_LIMBS = 130  # divisors up to this size run in the default test
# the thresholds of the three tiers (752, 352, 208), the leaf (64), the padding boundaries
DIV_SIZES = [3, 33, 63, 64, 65, 96, 97, 129, 130, 192, 193, 207, 208, 209, 256, 257, 351, 352, 353,
             385, 512, 513, 751, 752, 753, 1025]


def div_row_list() -> list[tuple]:
    """(id, route, divisor spec, dividend spec, scale, precision, where)."""
    rows: list[tuple] = []

    def add(name: str, routes: str, d_spec: str, n_spec: str, where: str = "pr", scale: int = 0, precision: int = 0) -> None:
        for route in routes.split(","):
            rows.append((f"{name}-{route}", route, d_spec, n_spec, scale, precision, where))

    # 1. one-limb divisors: below 2^32 (the half-limb loop), above it (one 128 by 64 bit division per limb)
    for label, divisor in (("1", 1), ("3", 3), ("m32", (1 << 32) - 1), ("p32", 1 << 32), ("p32p1", (1 << 32) + 1), ("h63", 1 << 63), ("h63p1", (1 << 63) + 1), ("ones", MASK64)):
        d_spec = f"0:+{divisor:016X}@0"
        for k, n_name in ((0, "rand1"), (1, "rand2"), (2, "rand3"), (9, "rand10"), (99, "rand100")):
            add(f"div-w{label}-{n_name}", "div,knuth", d_spec, f"{64 * (k + 1)}.0")
        for k in (1, 3, 40):
            add(f"div-w{label}-pow{k}", "div,knuth", d_spec, f"0:+1@{k}")
            add(f"div-w{label}-pow{k}m1", "div,knuth", d_spec, f"0:+1@{k},-1@0")
    # 2. structured divisors against structured dividends, small sizes
    for n in (2, 3, 5):
        for dk, d_spec in dspec_kinds(n).items():
            for k in (0, 2):
                for nk, n_spec in nspec_kinds(k, n).items():
                    if k == 0 and nk in ("s4", "s5"):
                        continue  # zero and a negative number
                    add(f"div-s{n}-{dk}-{k}-{nk}", "div,knuth,bz", d_spec, n_spec)
    rows.extend((f"{name}-{route}", route, d_spec, n_spec, 0, 0, where) for name, routes, d_spec, n_spec, where in addback_rows() for route in routes.split(","))
    # the estimate `B - 1` of a window whose top limb equals the divisor's (`bin_knuth_digit_top`),
    # decremented one to two times: divisor `(top, d0, low...)` and a one-digit quotient window
    # `(top, next, after, low...)`; only the combinations for which the port of algorithm D
    # decrements at least once are rows
    top_rows = 0
    for n in (3, 4, 9):
        for top in (1 << 63, (1 << 63) + 1, B64 - 1):
            for d0 in (B64 - 1, B64 - 2, 1 << 63, 0):
                for low in (0, B64 - 1):
                    for nxt in (0, 1, B64 - 1):
                        for after in (0, B64 - 1):
                            d = (top << (64 * (n - 1))) | (d0 << (64 * (n - 2)))
                            if low:
                                d |= (1 << (64 * (n - 2))) - 1
                            window = (top << (64 * n)) | (nxt << (64 * (n - 1))) | (after << (64 * (n - 2)))
                            if low:
                                window |= (1 << (64 * (n - 2))) - 1
                            if window < d or knuth_events(window, d)["top_decrements"] == 0:
                                continue
                            d_spec = "0:" + ",".join(limb_terms(d, 0, "+"))
                            n_spec = "0:" + ",".join(limb_terms(window, 0, "+"))
                            add(f"div-top{n}-{top_rows}", "div,knuth,bz", d_spec, n_spec)
                            top_rows += 1
    assert top_rows >= 20, top_rows
    # 3. the sizes where the routes switch, in every state of the limb tier: Burnikel-Ziegler
    # from 752 (assembly rows), 352 (C rows) and 208 limbs (portable loops)
    # (`bin_coeff_bz_division_min_words`), the leaf of 64 limbs and the padding
    # boundaries `j 2^k` (`bin_coeff_bz_padded_words`), one limb either side of each
    for n in DIV_SIZES:
        where = "pr" if n <= DIV_PR_LIMBS else "gate"
        kinds = dspec_kinds(n)
        for dk in ("rand", "ones", "minmid"):
            d_spec = kinds[dk]
            half = n // 2 if n >= 2 else 1
            for nk, n_spec in (
                ("r", f"{64 * (n + half)}.0"),
                ("s3", nspec_kinds(half, n)["s3"]),
                ("s5", nspec_kinds(half, n)["s5"]),
                ("t", nspec_kinds(n, n)["t"]),
            ):
                add(f"div-n{n}-{dk}-{nk}", "div,knuth,bz", d_spec, n_spec, where)
    # 4. the packed scaled quotient (divisors of 2 to 95 limbs) and the short quotient (2 to 256)
    for n in (2, 3, 4, 8, 16, 33, 64, 65, 94, 95):
        kinds = dspec_kinds(n)
        for dk in ("rand", "ones", "min", "minmid", "unnorm63"):
            for nk, n_spec, scale in (
                ("r", f"{64 * n + 7}.0", 0),
                ("r5", f"{64 * n + 7}.0", 5),
                ("r64", f"{64 * n}.1", 64),
                ("r100", f"{64 * n - 3}.6", 100),
                ("s3", nspec_kinds(1, n)["s3"], 0),
                ("s5", nspec_kinds(2, n)["s5"], 33),
                ("e", nspec_kinds(0, n)["s2"], 64 * n),  # the dividend below the divisor, scaled up
            ):
                add(f"div-sc{n}-{dk}-{nk}", "scaled", kinds[dk], n_spec, "pr", scale)
    for n in (2, 3, 5, 16, 33, 64, 95, 96, 97, 128, 192, 255, 256):
        kinds = dspec_kinds(n)
        where = "pr" if n <= 64 else "gate"
        for dk in ("rand", "ones", "minmid", "unnorm31"):
            for pi, precision in enumerate((64 * n, 64 * n + 1, 64 * n - 63, 64 * n - 70, 64 * n + 90)):
                if precision < 8:
                    continue
                for ni, nbits in enumerate((precision, precision - 1, precision + 2)):
                    scale = max(0, precision + 2 + 32 + (64 * n - (63 if dk == "unnorm63" else 31 if dk == "unnorm31" else 0)) - nbits)
                    add(f"div-sq{n}-{dk}-{pi}{ni}", "shortq", kinds[dk], f"{nbits}.{(pi + ni) % 2 * 6}", where, scale, precision)
    # the short quotient next to a rounding boundary: the dividend is `D B^k + e` or
    # `D B^k - e`, so the exact quotient is `B^k` (a representable point) or one unit
    # from it, and the kernel must decline or round as the exact quotient does
    for n in (3, 16, 64):
        kinds = dspec_kinds(n)
        for dk in ("rand", "minmid", "ones"):
            for nk in ("s1", "s2", "s3", "s4", "s5", "s6"):
                for pi, precision in enumerate((64 * n, 64 * n + 30)):
                    add(f"div-sb{n}-{dk}-{nk}-{pi}", "shortq", kinds[dk], nspec_kinds(n + 1, n)[nk], "pr", 0, precision)
    # 5. the short exact division: a quotient of at most 17 bits above 96 bits of divisor
    # is found by bisection on the high product, else the long division
    for dbits in (65, 95, 96, 97, 128, 129, 192, 193, 320, 1000):
        for gap in (0, 1, 2, 15, 16, 17, 18, 40, 64, 200):
            for shape in (0, 1, 6):
                add(f"div-sh{dbits}-{gap}-{shape}", "short", f"{dbits}.{shape}", f"{dbits + gap}.{(shape + 3) % 7}", "pr")
    # direct routes need a dividend of at least the divisor's width
    kept = []
    for row in rows:
        name, route, d_spec, n_spec, scale, precision, where = row
        if route in ("knuth", "bz"):
            random = Random(row_seed(name))
            d = eval_spec(d_spec, 0, random)
            n = eval_spec(n_spec, d, random)
            if n < d:
                continue
        if route in ("scaled", "shortq"):
            random = Random(row_seed(name))
            d = eval_spec(d_spec, 0, random)
            n = eval_spec(n_spec, d, random)
            limbs = (d.bit_length() + 63) // 64
            top = 95 if route == "scaled" else 256  # `bin_coeff_div_scaled_ok`, `bin_coeff_div_short_ok`
            if not (2 <= limbs <= top) or n == 0 or n.bit_length() + scale < d.bit_length():
                continue
        kept.append(row)
    return kept


def div_names() -> list[str]:
    return [row[0] for row in div_row_list()]


def div_compute(include_heavy: bool) -> dict[str, str]:
    return {row[0]: div_line(row) for row in div_row_list()}


TABLES.append(Table("div", DIV_TABLE, DIV_HEADER, div_names, div_compute))


SQRT_TABLE = KERNEL_TESTS / "coeff_sqrt_oracle_rows_wbtest.mbt"
SQRT_HEADER = """///|
/// Rows of the square root oracle, generated by `tools/kernel_oracle.py` (do not edit).
/// One row per line: `id route kind spec delta seed where scale precision radicand digest`.
/// `route` is `kernel` (`bin_coeff_sqrt_rem_kernel`), `scaled` (`bin_coeff_sqrt_rem_scaled`
/// of the radicand and `scale`) or `rounded` (`bin_coeff_sqrt_scaled_rounded` with `scale`
/// and `precision`). The radicand is `spec` (`kind` `v`: a `bits.shape` operand of
/// `regression_value`) or `s^2 + delta` (`kind` `sq`: `s` the operand `spec`, `delta` -1, 0 or 1,
/// formed with `Coeff::square`); `radicand` is the FNV-1a digest of the radicand, which the
/// test checks before it calls the route, so that a wrong square cannot hide a wrong root.
/// `digest` is that of the root and the remainder of `radicand * 2^scale` (`kernel` has
/// scale 0), or of the packed value of `bin_coeff_sqrt_scaled_rounded`: the root rounded to
/// nearest (`root + 1` when the remainder exceeds the root) if it has exactly `precision`
/// bits, else `4 root + 2 b + s` with `b = 1` when the remainder exceeds the root and
/// `s = 1` when it is not zero.
let sqrt_oracle_table : String =
"""

SQRT_SIZES_LIMBS = [4, 6, 8, 12, 16, 24, 32, 48, 64, 96, 128, 192, 256, 512, 1024]
SQRT_PR_BITS = 4100  # radicands up to this size run in the default test


def sqrt_bits_list() -> list[int]:
    sizes = {1, 2, 3, 7, 8, 9, 31, 32, 33, 63, 64, 65, 66, 127, 128, 129, 130, 255}
    for n in SQRT_SIZES_LIMBS:
        sizes.update((64 * n - 1, 64 * n, 64 * n + 1))
    sizes.update((4097, 4098, 33000))
    return sorted(sizes)


def sqrt_row_list() -> list[tuple]:
    """(id, route, kind, spec, delta, scale, precision, where)."""
    rows = []
    for bits in sqrt_bits_list():
        where = "pr" if bits <= SQRT_PR_BITS else "gate"
        root_bits = (bits + 1) // 2
        specs = []
        for shape in (0, 1, 3, 6):
            for delta in (-1, 0, 1):
                specs.append(("sq", f"{root_bits}.{shape}", delta))
        for shape in (0, 1, 2, 6):
            specs.append(("v", f"{bits}.{shape}", 0))
        for index, (kind, spec, delta) in enumerate(specs):
            if kind == "sq" and root_bits < 2 and delta < 0:
                continue
            base = f"sqrt-{bits}-{kind}-{spec.replace('.', 's')}-{delta + 1}"
            scale = (0, 1, 2, 63, 64, 65, 130, 257)[index % 8]
            rows.append((f"{base}-kernel", "kernel", kind, spec, delta, 0, 0, where))
            rows.append((f"{base}-scaled", "scaled", kind, spec, delta, scale, 0, where))
            rows.append((f"{base}-rounded", "rounded", kind, spec, delta, scale, index % 3, where))
    return rows


def sqrt_line(row: tuple) -> str | None:
    name, route, kind, spec, delta, scale, precision, where = row
    seed = row_seed(name)
    random = Random(seed)
    s = eval_spec(spec, 0, random)
    x = s if kind == "v" else s * s + delta
    assert x >= 0
    if x == 0:
        return None
    shifted = x << scale
    root = math.isqrt(shifted)
    rem = shifted - root * root
    if route == "rounded":
        root_bits = root.bit_length()
        precision = max(2, root_bits - (0, 1, 30)[precision])
        if precision > root_bits:
            return None
        if root_bits == precision:
            packed = root + 1 if rem > root else root
        else:
            packed = 4 * root + (2 if rem > root else 0) + (1 if rem else 0)
        digest = mix(FNV_BASIS, packed)
    else:
        digest = div_digest_pair(root, rem)
    precision = precision if route == "rounded" else 0
    return f"{name} {route} {kind} {spec} {delta} {seed} {where} {scale} {precision} {mix(FNV_BASIS, x)} {digest}"


_SQRT_VALID: list[tuple] = []


def sqrt_valid_rows() -> list[tuple]:
    if not _SQRT_VALID:
        # only a tiny radicand can be zero; larger rows are valid without computing them
        _SQRT_VALID.extend(
            row for row in sqrt_row_list() if int(row[0].split("-")[1]) > 130 or sqrt_line(row) is not None
        )
    return _SQRT_VALID


def sqrt_names() -> list[str]:
    return [row[0] for row in sqrt_valid_rows()]


def sqrt_compute(include_heavy: bool) -> dict[str, str]:
    lines = {}
    for row in sqrt_valid_rows():
        if row[7] == "gate" and not include_heavy:
            continue
        lines[row[0]] = sqrt_line(row)
    return lines


TABLES.append(Table("sqrt", SQRT_TABLE, SQRT_HEADER, sqrt_names, sqrt_compute))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--check", action="store_true", help="compare with the committed MoonBit tables")
    parser.add_argument("--all", action="store_true", help="with --check: also the rows marked heavy")
    parser.add_argument("--print", action="store_true", help="print the regression digests")
    args = parser.parse_args()
    if args.check:
        return check(args.all)
    if args.print:
        for name, digest in regression().items():
            print(f"regression.{name} {digest}")
        return 0
    for table in TABLES:
        table.write()
        print(f"wrote {table.path.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
