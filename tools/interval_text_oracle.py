#!/usr/bin/env python3
"""Independent oracle for the text output of `Interval` (`Show`, `to_exact_string`).

Level A in the sense of the oracle rule: no `interval` code is used; the expected texts are
computed with `fractions.Fraction` from the rules written in doc/manual/api/interval.md and
IEEE 1788-2015 13.3 and 13.4:

- `Show`: each bound is a decimal number rounded outward (the lower bound down, the upper bound
  up) with the fewest significant digits k such that the text, read back at precision p with the
  same outward direction, is at most one unit in the last place (the float next to it) from the
  bound; `d.ddd` stripped of trailing zeros, then `e+x` or `e-x` unless x is 0; `0` for a zero
  bound, `inf` and `-inf`; `[entire]` for both infinite; a bound whose leading bit is beyond
  2^4096 in magnitude is written as its exact text.
- exact text: `0x<odd coefficient in hex>p<exponent>`, `0x0p0` for zero, `inf`, `-inf`, `[entire]`.

Besides the expected texts the oracle checks every generated Show text for containment
(the lower text is at most the lower bound, the upper at least the upper bound, compared as
exact fractions) and for the one-unit bound, which is the rule itself.

`--write` writes `library/src/interval/interval_text_table_wbtest.mbt` (byte-stable);
`--check` recomputes it and compares.
"""

from __future__ import annotations

import argparse
import random
import re
import sys
from fractions import Fraction
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
TABLE = REPO_ROOT / "library/src/interval/interval_text_table_wbtest.mbt"
HEX_LIMIT = 4096


class Dyadic:
    """sign * m * 2^e for exponents too large for a Fraction (the ends of the exponent range)."""

    def __init__(self, sign: int, m: int, e: int):
        while m % 2 == 0:
            m //= 2
            e += 1
        self.sign, self.m, self.e = sign, m, e

    def top(self) -> int:
        return self.e + self.m.bit_length() - 1


def top_exponent(v) -> int:
    return v.top() if isinstance(v, Dyadic) else floor_log2(abs(v))


def floor_log2(v: Fraction) -> int:
    """floor(log2 v) for v > 0."""
    n, d = v.numerator, v.denominator
    e = n.bit_length() - d.bit_length()
    if Fraction(2) ** e > v:
        e -= 1
    return e


def floor_log10(v: Fraction) -> int:
    e = len(str(v.numerator)) - len(str(v.denominator))
    while Fraction(10) ** e > v:
        e -= 1
    while Fraction(10) ** (e + 1) <= v:
        e += 1
    return e


def floor_fraction(q: Fraction) -> int:
    return q.numerator // q.denominator


def ceil_fraction(q: Fraction) -> int:
    return -((-q.numerator) // q.denominator)


def round_p(v: Fraction, p: int, up: bool) -> Fraction:
    """The largest (down) or least (up) p-bit binary number at or below (above) v > 0."""
    e = floor_log2(v)
    quantum = Fraction(2) ** (e - p + 1)
    q = v / quantum
    return (ceil_fraction(q) if up else floor_fraction(q)) * quantum


def neighbour(r: Fraction, p: int, up: bool) -> Fraction:
    """The p-bit binary number next to r > 0 above (up) or below."""
    e = floor_log2(r)
    quantum = Fraction(2) ** (e - p + 1)
    if up:
        return r + quantum
    if r == Fraction(2) ** e:
        return r - quantum / 2
    return r - quantum


def digits_of(v: Fraction, k: int, up: bool) -> tuple[int, int]:
    """(N, E): the value N * 10^(E - k + 1) of k significant digits, rounded down or up, with
    the decimal exponent E of the first digit (a carry moves E up by one)."""
    e = floor_log10(v)
    scale = Fraction(10) ** (e - k + 1)
    q = v / scale
    n = ceil_fraction(q) if up else floor_fraction(q)
    if n == 10**k:
        n //= 10
        e += 1
    return n, e


def format_digits(n: int, e: int) -> str:
    s = str(n).rstrip("0") or "0"
    mantissa = s[0] + ("." + s[1:] if len(s) > 1 else "")
    return mantissa if e == 0 else mantissa + "e" + ("+" if e > 0 else "-") + str(abs(e))


def decimal_text(v: Fraction, p: int, up: bool) -> tuple[str, Fraction]:
    """The text of the magnitude v > 0 rounded in the direction `up`, and its exact value."""
    kmax = int(p * 0.30102999566398120 + 0.999999999) + 3  # ceil(p log10 2) + 3 as in the rule
    found = None
    for k in range(1, kmax + 1):
        n, e = digits_of(v, k, up)
        d = Fraction(n) * Fraction(10) ** (e - k + 1)
        r = round_p(d, p, up)
        # lower bound (down): r <= v and the float above r is at least v
        # upper bound (up): r >= v and the float below r is at most v
        if not up:
            near = r == v or neighbour(r, p, True) >= v
        else:
            near = r == v or neighbour(r, p, False) <= v
        if near:
            found = (n, e, d)
            break
    if found is None:
        n, e = digits_of(v, kmax, up)
        found = (n, e, Fraction(n) * Fraction(10) ** (e - kmax + 1))
    n, e, d = found
    return format_digits(n, e), d


def exact_text(v) -> str:
    if isinstance(v, Dyadic):
        return f"{'-' if v.sign < 0 else ''}0x{v.m:x}p{v.e}"
    if v == 0:
        return "0x0p0"
    sign = "-" if v < 0 else ""
    a = abs(v)
    assert a.denominator & (a.denominator - 1) == 0, "a binary value"
    e = -(a.denominator.bit_length() - 1)
    m = a.numerator
    while m % 2 == 0:
        m //= 2
        e += 1
    return f"{sign}0x{m:x}p{e}"


def bound_show(v, upper: bool, p: int) -> tuple[str, Fraction | None]:
    """The Show text of a bound (a Fraction, or the strings "inf" / "-inf") and, for a decimal
    text, its exact value (for the containment check)."""
    if v == "inf" or v == "-inf":
        return v, None
    if not isinstance(v, Dyadic) and v == 0:
        return "0", Fraction(0)
    if abs(top_exponent(v)) > HEX_LIMIT:
        return exact_text(v), v
    magnitude = abs(v)
    # a lower bound of a positive value rounds down, of a negative value away from zero
    magnitude_up = upper == (v > 0)
    text, d = decimal_text(magnitude, p, magnitude_up)
    if v < 0:
        return "-" + text, -d
    return text, d


def bound_exact(v) -> str:
    if v == "inf" or v == "-inf":
        return v
    return exact_text(v)


def interval_texts(lo, hi, p: int) -> tuple[str, str]:
    if lo == "-inf" and hi == "inf":
        return "[entire]", "[entire]"
    l_text, l_value = bound_show(lo, False, p)
    u_text, u_value = bound_show(hi, True, p)
    # containment, as exact fractions (the hexadecimal fallback is exact)
    if isinstance(lo, Fraction) and l_value is not None:
        assert l_value <= lo, (lo, p, l_text)
    if isinstance(hi, Fraction) and u_value is not None:
        assert u_value >= hi, (hi, p, u_text)
    return f"[{l_text}, {u_text}]", f"[{bound_exact(lo)}, {bound_exact(hi)}]"


def hex_input(v) -> str:
    return v if isinstance(v, str) else exact_text(v)


EMAX = (1 << 30) - 1


def range_end_rows(p: int) -> list[tuple]:
    """Bounds at both ends of the exponent range (largest finite, smallest subnormal), alone
    and together."""
    largest = Dyadic(1, (1 << p) - 1, EMAX - p + 1)
    smallest = Dyadic(1, 1, -1073741821 - p)
    negative_largest = Dyadic(-1, largest.m, largest.e)
    negative_smallest = Dyadic(-1, 1, smallest.e)
    one = Fraction(1)
    return [
        (negative_largest, largest, p),
        (smallest, largest, p),
        (negative_largest, negative_smallest, p),
        (smallest, one, p),
        (-one, negative_smallest, p),
        (negative_smallest, smallest, p),
        (Fraction(0), smallest, p),
        (negative_smallest, Fraction(0), p),
        (largest, "inf", p),
        ("-inf", negative_largest, p),
        ("-inf", smallest, p),
        (Dyadic(1, 1 if p < 3 else 3, EMAX - 5), Dyadic(1, 3 if p < 3 else 5, EMAX - 5), p),
    ]


def random_value(rng: random.Random, p: int, emin: int, emax: int) -> Fraction:
    bits = rng.randint(1, p)
    m = rng.getrandbits(bits) | (1 << (bits - 1))
    if rng.random() < 0.15:
        m = 1 << (bits - 1)  # a power of two: the float below it is closer
    e = rng.randint(emin, emax)
    v = Fraction(m) * Fraction(2) ** e
    return -v if rng.random() < 0.4 else v


def generated(rng: random.Random) -> list[tuple]:
    rows: list[tuple] = []
    precisions = [2, 3, 8, 11, 24, 53, 64, 113]
    for p in precisions:
        for lo, hi in [
            ("-inf", "inf"),
            ("-inf", Fraction(1)),
            (Fraction(-3, 8), "inf"),
            (Fraction(0), Fraction(0)),
            (Fraction(0), Fraction(1, 2)),
            (Fraction(-1, 2), Fraction(0)),
            (Fraction(1), Fraction(1)),
            (Fraction(1, 2), Fraction(3)),
            (Fraction(-1), Fraction(1)),
            (Fraction(2) ** 4096, Fraction(2) ** 4097),
            (Fraction(2) ** 4095, Fraction(2) ** 4096),
            (-(Fraction(2) ** 5000), Fraction(2) ** -5000),
            (Fraction(2) ** -4096, Fraction(2) ** -4095),
            (Fraction(2) ** -4097, Fraction(2) ** -4096),
        ]:
            rows.append((lo, hi, p))
    for p in (256, 1024):
        for _ in range(60):
            emin, emax = (-60, 60) if rng.random() < 0.7 else (-1500, 1500)
            a = random_value(rng, p, emin, emax)
            b = random_value(rng, p, emin, emax)
            rows.append((a, b, p) if a <= b else (b, a, p))
        rows.append((Fraction(((1 << p) // 3) | 1, 2 ** (p + 20)), Fraction((((1 << p) * 2) // 3) | 1, 2**p), p))
    for p in precisions + [256, 1024]:
        rows.extend(range_end_rows(p))
    # a zero bound given as -0 on input: the texts of a zero bound carry no sign
    for p in (2, 24, 53, 256):
        rows.append((Fraction(0), Fraction(1), p, "-0x0p0", None))
        rows.append((Fraction(-1), Fraction(0), p, None, "-0x0p0"))
        rows.append((Fraction(0), Fraction(0), p, "-0x0p0", "-0x0p0"))
        rows.append((Fraction(0), Fraction(0), p, "0x0p0", "-0x0p0"))
    for index in range(2200):
        p = precisions[index % len(precisions)]
        emin, emax = (-60, 60) if index % 4 else (-1500, 1500)
        a = random_value(rng, p, emin, emax)
        b = random_value(rng, p, emin, emax)
        if index % 11 == 0:
            b = a  # a point interval
        if index % 13 == 0:
            a = Fraction(rng.randint(-1000, 1000), 2 ** rng.randint(0, 6))  # a short dyadic
            b = a + Fraction(rng.randint(0, 5), 2 ** rng.randint(0, 6))
            if a.denominator > 2**p or b.numerator.bit_length() > p or a.numerator.bit_length() > p:
                a = b = Fraction(1)
        lo, hi = (a, b) if a <= b else (b, a)
        rows.append((lo, hi, p))
    return rows


def odd_parts(v: Fraction) -> tuple[int, int]:
    """(odd mantissa, exponent) of a nonzero dyadic."""
    n, d = abs(v.numerator), v.denominator
    e = -(d.bit_length() - 1)
    while n % 2 == 0:
        n //= 2
        e += 1
    return n, e


def hex_style(v: Fraction, rng: random.Random) -> str:
    """The value as an exact-text bound in a random hexadecimal style."""
    if v == 0:
        return rng.choice(["0x0p0", "0X0.0P0", "0x.0p5", "0x000p-3"])
    sign = "-" if v < 0 else ""
    m, e = odd_parts(v)
    shift = rng.randint(0, 7)
    n, e2 = m << shift, e - shift
    digits = f"{n:x}"
    trailing = rng.randint(0, 3)
    digits += "0" * trailing
    n_digits = len(digits)
    f = rng.randint(0, n_digits + 2)
    padded = digits.rjust(f, "0")
    int_part, frac = (padded[: len(padded) - f] if f else padded), (padded[len(padded) - f:] if f else "")
    if rng.random() < 0.3:
        int_part = "0" * rng.randint(1, 3) + int_part
    # the text is (int.frac) * 2^X with N = digits * 16^-(f) ... value = N * 2^(e2 - 4*trailing)
    x = e2 - 4 * trailing + 4 * f
    mantissa = int_part + ("." + frac if frac or rng.random() < 0.3 else ("." if rng.random() < 0.2 else ""))
    if mantissa in ("", "."):
        mantissa = "0" + mantissa
    if mantissa.startswith("."):
        mantissa = mantissa if rng.random() < 0.5 else "0" + mantissa
    text = f"{sign}0x{mantissa}p{x:+d}" if rng.random() < 0.5 else f"{sign}0x{mantissa}p{x}"
    text = text.replace("0x", rng.choice(["0x", "0X"]), 1)
    text = text.replace("p", rng.choice(["p", "P"]), 1)
    if rng.random() < 0.3:
        text = text.upper().replace("0X", "0x", 1) if False else text.upper()
    return text


E_MIN = 2 - (1 << 30)
E_MAX = (1 << 30) - 1


def read_dyadic(text: str):
    """(sign, n, e): the exact value sign * n * 2^e of a hexadecimal bound text, read with
    integers only (an independent reader, no Fraction, so any exponent)."""
    t = text.strip().lower()
    sign = -1 if t.startswith("-") else 1
    t = t.lstrip("+-")
    assert t.startswith("0x")
    body, exp = t[2:].split("p")
    int_part, _, frac = body.partition(".")
    digits = (int_part or "0") + frac
    n = int(digits, 16)
    return sign, n, int(exp) - 4 * len(frac)


def representable(sign: int, n: int, e: int, p: int) -> bool:
    """A bound that is a number of the format of p bits in the range of the library: zero, or a
    number whose odd mantissa has b <= p bits, whose leading bit is at most EMAX, and which lies
    on the grid of p bits below the range floor."""
    if n == 0:
        return True
    while n % 2 == 0:
        n //= 2
        e += 1
    b = n.bit_length()
    return b <= p and e + b - 1 <= E_MAX and e >= E_MIN - p + 1


def dy_key(sign: int, n: int, e: int):
    """A comparable key for sign * n * 2^e: (sign, top exponent, aligned mantissa)."""
    if n == 0:
        return (0, 0, 0)
    while n % 2 == 0:
        n //= 2
        e += 1
    return (sign, e + n.bit_length() - 1, n << 0, e)


def dy_less(a, b) -> bool:
    """a < b for two (sign, n, e), exactly."""
    sa, na, ea = a
    sb, nb, eb = b
    if na == 0:
        sa = 0
    if nb == 0:
        sb = 0
    if sa != sb:
        return sa < sb
    if sa == 0:
        return False
    # same sign: compare magnitudes by the leading bit, then the aligned mantissas
    ta, tb = ea + na.bit_length(), eb + nb.bit_length()
    if ta != tb:
        magnitude_less = ta < tb
    else:
        shift = ea - eb
        left, right = (na << shift, nb) if shift >= 0 else (na, nb << -shift)
        magnitude_less = left < right
        if left == right:
            return False
    return magnitude_less if sa > 0 else not magnitude_less


def dy_text(sign: int, n: int, e: int) -> str:
    """The exact text of sign * n * 2^e: odd mantissa, no sign for zero."""
    if n == 0:
        return "0x0p0"
    while n % 2 == 0:
        n //= 2
        e += 1
    return f"{'-' if sign < 0 else ''}0x{n:x}p{e}"


def exact_read_entry(text: str, p: int) -> str:
    """text, precision, ok|err, the expected exact text (or empty). The rule: an exact text is
    read exactly; it is refused for what cannot be an interval of the format of p bits (not [l, u],
    a decimal or malformed bound, a bound that is not a number of the format: more than p
    significant bits, beyond the exponent range, finer than the grid below the range floor;
    lower above upper)."""
    err = "\t".join([text, str(p), "err", ""])
    t = text.strip()
    low = t.lower()
    if low in ("[empty]", "[entire]"):
        return "\t".join([text, str(p), "ok", low])
    if not (t.startswith("[") and t.endswith("]")):
        return err
    parts = [x.strip() for x in t[1:-1].split(",")]
    if len(parts) != 2:
        return err
    values = []
    for part in parts:
        pl = part.lower()
        unsigned = pl.lstrip("+-")
        if unsigned in ("inf", "infinity"):
            values.append("-inf" if pl.startswith("-") else "inf")
        elif unsigned.startswith("0x"):
            if not re.fullmatch(r"[+-]?0x(?:[0-9a-f]+\.?[0-9a-f]*|\.[0-9a-f]+)p[+-]?[0-9]+", pl):
                return err
            d = read_dyadic(part)
            if not representable(*d, p):
                return err
            values.append(d)
        else:
            return err
    lo, hi = values
    if lo == "inf" or hi == "-inf":
        return err
    if not isinstance(lo, str) and not isinstance(hi, str) and dy_less(hi, lo):
        return err
    if lo == "-inf" and hi == "inf":
        return "\t".join([text, str(p), "ok", "[entire]"])

    def bound(x):
        return x if isinstance(x, str) else dy_text(*x)

    return "\t".join([text, str(p), "ok", f"[{bound(lo)}, {bound(hi)}]"])


EXACT_FIXED = [
    "[0.1, 0.2]", "0x1p0", "[0x1p0]", "[0x1p0, 0x2p0, 0x3p0]", "[0x2p0, 0x1p0]", "[inf, 0x1p0]",
    "[0x1p0, -inf]", "[-inf, inf]", "[-Inf, 0x1P+3]", "[0x.8p1, 0x1.8p0]", "[0X.8P1, 0X1.8P0]",
    "[0x1.00000000000001p0, 0x2p0]", "[0x1.00000000000008p0, 0x2p0]", "[0x1.fffffffffffffp0, 0x2p0]",
    "[0x00001.80000000000000000p0, 0x2p0]", "[0x1.8p0, 0x1.8p0]", "[ 0x1p0 , 0x2p0 ]", "[0x1p0,0x2p0]",
    "[0x0.0p0, 0x0p5]", "[-0x0p0, +0x0p0]", "[0x1p]", "[0x1, 0x2p0]", "[0xgp0, 0x2p0]", "[1e3, 0x2p0]",
    "[empty]", "[ENTIRE]", "[nai]", "", "[]", "[,]",
]


def exact_read_rows(rng: random.Random) -> list[str]:
    rows = []
    for text in EXACT_FIXED:
        for p in (53, 8):
            rows.append(exact_read_entry(text, p))
    for p in (2, 8, 24, 53, 113, 256):
        for b in (1, 2, p, p + 1, p + 7):
            m = (1 << (b - 1)) | 1 if b > 1 else 1
            floor_e = E_MIN - p + 1
            top_e = E_MAX - b + 1
            for e, tail in ((floor_e, "inf"), (floor_e - 1, "inf"), (floor_e + 1, "inf")):
                rows.append(exact_read_entry(f"[0x{m:x}p{e}, {tail}]", p))
                rows.append(exact_read_entry(f"[-{tail}, -0x{m:x}p{e}]".replace("--", "-"), p))
            for e in (top_e, top_e + 1, top_e - 1):
                rows.append(exact_read_entry(f"[-inf, 0x{m:x}p{e}]", p))
                rows.append(exact_read_entry(f"[-0x{m:x}p{e}, inf]", p))
    for index in range(1200):
        p = rng.choice([2, 3, 8, 24, 53, 64, 113, 256, 1024])
        bits = max(1, p + rng.choice([-2, -1, 0, 0, 0, 1, 2, 5, 8]))
        values = []
        for _ in range(2):
            b = rng.randint(1, bits)
            m = rng.getrandbits(b) | (1 << (b - 1))
            m |= 1
            v = Fraction(m) * Fraction(2) ** rng.randint(-40, 40)
            values.append(-v if rng.random() < 0.4 else v)
        if rng.random() < 0.05:
            values[0] = Fraction(0)
        lo, hi = sorted(values)
        if rng.random() < 0.08:
            lo, hi = hi, lo  # reversed: an error
        text = f"[{hex_style(lo, rng)}, {hex_style(hi, rng)}]"
        rows.append(exact_read_entry(text, p))
    return rows


CHUNK = 300


def entry(lo, hi, p: int, lo_in: str | None = None, hi_in: str | None = None) -> str:
    show, exact = interval_texts(lo, hi, p)
    return "\t".join([lo_in or hex_input(lo), hi_in or hex_input(hi), str(p), show, exact])


def array_lines(prefix: str, count: int) -> list[str]:
    """The body of `[prefix_0(), prefix_1(), ...]` as `moon fmt` writes it: one line when it fits
    in 80 columns, else one element per line with a trailing comma."""
    items = [f"{prefix}_{index}()" for index in range(count)]
    one = "  [" + ", ".join(items) + "]"
    if len(one) <= 80:
        return [one]
    return ["  ["] + [f"    {item}," for item in items] + ["  ]"]


def build() -> str:
    lines = [
        "///|",
        "/// Generated by `python3 tools/interval_text_oracle.py --write`: the expected `Show` text and",
        "/// exact text of an interval, computed by an independent oracle (`Fraction`, no `interval`",
        "/// code; level A). Each line is tab separated: lower bound and upper bound as hexadecimal",
        "/// numbers (or inf, -inf), precision, the `Show` text, the exact text.",
        "",
    ]
    rng = random.Random(1788013)
    entries = [entry(*row) for row in generated(rng)]
    chunks = [entries[i : i + CHUNK] for i in range(0, len(entries), CHUNK)]
    for index, chunk in enumerate(chunks):
        lines.append("///|")
        lines.append(f"fn text_table_{index}() -> String {{")
        lines.append("  (")
        lines.extend("    #|" + e for e in chunk)
        lines.append("  )")
        lines.append("}")
        lines.append("")
    exact_rows = exact_read_rows(random.Random(1788014))
    exact_chunks = [exact_rows[i : i + CHUNK] for i in range(0, len(exact_rows), CHUNK)]
    for index, chunk in enumerate(exact_chunks):
        lines.append("///|")
        lines.append(f"fn exact_read_table_{index}() -> String {{")
        lines.append("  (")
        lines.extend("    #|" + e for e in chunk)
        lines.append("  )")
        lines.append("}")
        lines.append("")
    lines.append("///|")
    lines.append("fn exact_read_tables() -> Array[String] {")
    lines.extend(array_lines("exact_read_table", len(exact_chunks)))
    lines.append("}")
    lines.append("")
    lines.append("///|")
    lines.append("fn text_tables() -> Array[String] {")
    lines.extend(array_lines("text_table", len(chunks)))
    lines.append("}")
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--write", action="store_true")
    group.add_argument("--check", action="store_true")
    args = parser.parse_args(argv)
    text = build()
    if args.write:
        TABLE.write_text(text, encoding="utf-8")
        print(f"wrote {TABLE.relative_to(REPO_ROOT)}: {text.count(chr(10) + '    #|')} entries")
        return 0
    ok = TABLE.exists() and TABLE.read_text(encoding="utf-8") == text
    if not ok:
        print("the generated table differs from the oracle; run --write and review")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
