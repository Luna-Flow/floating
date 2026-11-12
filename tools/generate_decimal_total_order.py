#!/usr/bin/env python3
"""Generate the IEEE 754-2019 §5.10 totalOrder corpus for the decimal interchange formats.

The expected order comes from `total_order`, a direct transcription of the §5.10 rules
(a)-(d) on decoded operands; it does not call any decimal library. Every pair is then
cross-checked against CPython's `decimal.Decimal.compare_total` (libmpdec), which is an
independent implementation but not the specification. NaN payload order is
implementation-defined by §5.10 d) 5) iii); floating orders payloads as unsigned integers,
reversed for a negative sign, and so does libmpdec.

    python3 tools/generate_decimal_total_order.py --write
"""
from __future__ import annotations

import argparse
import itertools
import json
from dataclasses import dataclass
from decimal import Decimal
from fractions import Fraction
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent
FIXTURE_PATH = ROOT / "testdata/decimal/ieee/total_order.json"
FORMATS = {
    # precision p, emin, emax (IEEE 754-2019 Table 3.6)
    "decimal32": (7, -95, 96),
    "decimal64": (16, -383, 384),
    "decimal128": (34, -6143, 6144),
}


@dataclass(frozen=True)
class Operand:
    negative: bool
    kind: str  # "finite", "infinity", "qnan", "snan"
    coefficient: int = 0
    exponent: int = 0

    def text(self) -> str:
        sign = "-" if self.negative else ""
        if self.kind == "infinity":
            return f"{sign}Infinity"
        if self.kind in ("qnan", "snan"):
            prefix = "sNaN" if self.kind == "snan" else "NaN"
            return f"{sign}{prefix}{self.coefficient if self.coefficient else ''}"
        return f"{sign}{self.coefficient}E{self.exponent:+d}"

    def value(self) -> Any:
        """Exact value of a finite operand."""
        return Fraction(self.coefficient) * Fraction(10) ** self.exponent


def _numeric_less(x: Operand, y: Operand) -> bool:
    """x < y for two non-NaN operands (§5.10 a)."""
    def key(o: Operand) -> tuple[int, Any]:
        if o.kind == "infinity":
            return (-1, 0) if o.negative else (1, 0)
        signed = -o.value() if o.negative else o.value()
        return (0, signed)
    kx, ky = key(x), key(y)
    if kx[0] != ky[0]:
        return kx[0] < ky[0]
    return kx[0] == 0 and kx[1] < ky[1]


def _same_datum(x: Operand, y: Operand) -> bool:
    if x.kind != y.kind:
        return False
    if x.kind == "infinity":
        return x.negative == y.negative
    return x.negative == y.negative and x.value() == y.value()


def total_order(x: Operand, y: Operand) -> bool:
    """IEEE 754-2019 §5.10 totalOrder(x, y) on canonical members of one format."""
    x_nan = x.kind in ("qnan", "snan")
    y_nan = y.kind in ("qnan", "snan")
    if not x_nan and not y_nan:
        if _numeric_less(x, y):
            return True  # a)
        if _numeric_less(y, x):
            return False  # b)
        # c) x = y numerically
        if x.kind == "finite" and x.value() == 0 and x.negative != y.negative:
            return x.negative  # c) 1), 2)
        if _same_datum(x, y):
            if x.negative:
                return x.exponent >= y.exponent  # c) 3) i)
            return x.exponent <= y.exponent  # c) 3) ii)
        raise AssertionError("equal operands that are not the same datum")
    if x_nan and not y_nan:
        return x.negative  # d) 1), 4)
    if y_nan and not x_nan:
        return not y.negative  # d) 2), 3)
    # d) 5): both NaNs
    if x.negative != y.negative:
        return x.negative  # i)
    if x.kind != y.kind:
        signaling_first = x.kind == "snan"
        return signaling_first if not x.negative else not signaling_first  # ii)
    # iii) implementation-defined: payload order, reversed for a negative sign
    if x.negative:
        return x.coefficient >= y.coefficient
    return x.coefficient <= y.coefficient


def compare(x: Operand, y: Operand) -> int:
    if x == y:
        return 0
    return -1 if total_order(x, y) else 1


def magnitude(o: Operand) -> Operand:
    return Operand(False, o.kind, o.coefficient, o.exponent)


def pool(format_name: str) -> list[Operand]:
    p, emin, emax = FORMATS[format_name]
    qmin, qmax = emin - p + 1, emax - p + 1
    full = 10**p - 1
    payload_max = 10 ** (p - 1) - 1
    values: list[Operand] = []
    for negative in (False, True):
        finite = [
            (0, qmin), (0, 0), (0, qmax),  # zeros of several exponents (one cohort)
            (1, 0), (10, -1), (100, -2), (10 ** (p - 1), -(p - 1)),  # cohort of one
            (12, 3), (120, 2), (1200, 1),  # cohort of 12000
            (1, qmin), (2, qmin), (10 ** (p - 1) - 1, qmin),  # subnormals
            (10 ** (p - 1), qmin), (full, qmin),  # smallest normals
            (5, -1), (full, -p), (full, qmax), (1, qmax),  # largest finite and others
        ]
        values += [Operand(negative, "finite", c, e) for c, e in finite]
        values.append(Operand(negative, "infinity"))
        for payload in (0, 1, 12, payload_max):
            values.append(Operand(negative, "qnan", payload))
            values.append(Operand(negative, "snan", payload))
    return values


SYMBOL = {-1: "<", 0: "=", 1: ">"}


def matrix(format_name: str, operands: list[Operand], op: str) -> str:
    """Row-major comparison of every ordered pair, one of `<`, `=`, `>` per pair."""
    cells = []
    for x, y in itertools.product(operands, repeat=2):
        lhs, rhs = (x, y) if op == "totalOrder" else (magnitude(x), magnitude(y))
        expected = compare(lhs, rhs)
        library = int(Decimal(lhs.text()).compare_total(Decimal(rhs.text())))
        if library != expected:
            raise AssertionError(
                f"{format_name} {op} {lhs.text()} {rhs.text()}: §5.10 model {expected}, libmpdec {library}"
            )
        cells.append(SYMBOL[expected])
    return "".join(cells)


def generate_formats() -> dict[str, Any]:
    formats: dict[str, Any] = {}
    for format_name in FORMATS:
        operands = pool(format_name)
        formats[format_name] = {
            "operands": [o.text() for o in operands],
            "totalOrder": matrix(format_name, operands, "totalOrder"),
            "totalOrderMag": matrix(format_name, operands, "totalOrderMag"),
        }
    return formats


def fixture() -> dict[str, Any]:
    return {
        "schemaVersion": 1,
        "standard": "IEEE 754-2019 §5.10",
        "generator": "tools/generate_decimal_total_order.py",
        "crossCheck": "CPython decimal.Decimal.compare_total (libmpdec); an oracle, not the specification",
        "nanPayloadOrder": "implementation-defined (§5.10 d) 5) iii)): unsigned payload order, reversed for a negative sign",
        "matrix": "row-major over operands x operands; `<` means totalOrder(x, y) and not totalOrder(y, x)",
        "formats": generate_formats(),
    }


def pair_count(data: dict[str, Any]) -> int:
    return sum(2 * len(entry["operands"]) ** 2 for entry in data["formats"].values())


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--write", action="store_true", help="rewrite the checked-in corpus")
    args = parser.parse_args(argv)
    data = fixture()
    text = json.dumps(data, indent=1) + "\n"
    if args.write:
        FIXTURE_PATH.write_text(text, encoding="utf-8")
    elif FIXTURE_PATH.read_text(encoding="utf-8") != text:
        print(f"{FIXTURE_PATH.relative_to(ROOT)} is stale; run with --write")
        return 1
    print(f"{pair_count(data)} totalOrder pairs")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
