#!/usr/bin/env python3
"""Validate the checked-in IEEE decimal corpus and static oracle examples.

The authoritative corpus combines IEEE encoding formulas, exact
integer/rational arithmetic, and committed MPFR-directed elementary
enclosures. A small pinned decTest excerpt is supplementary diagnostics only;
no external implementation archive is required to run the gate.
"""

from __future__ import annotations

import argparse
import decimal
import json
import re
import subprocess
import time
from decimal import Context, Decimal, localcontext
from pathlib import Path
from typing import Any

import decimal_oracles
import generate_decimal_elementary_oracle
import generate_ieee_decimal_vectors
from conformance_ui import SummaryRow, print_summary

ROOT = Path(__file__).resolve().parent.parent
FIXTURE_ROOT = ROOT / "testdata/decimal/ieee"
MANIFEST_PATH = FIXTURE_ROOT / "manifest.json"
MATRIX_PATH = FIXTURE_ROOT / "conformance_matrix.json"
STANDARD_EXCERPT_PATH = FIXTURE_ROOT / "dectest_ieee_excerpt.json"
ELEMENTARY_ORACLE_PATH = FIXTURE_ROOT / "elementary_mpfr_oracle.json"
ELEMENTARY_INTERVAL_PATH = FIXTURE_ROOT / "mpfr-4.2.2-elementary-interval.txt"
SUPPORTED_TARGETS = ("native", "wasm", "wasm-gc", "js")
DEFAULT_OUTPUT = ROOT / ".tmp/decimal-ieee-conformance"
MOON_TEST_SUMMARY = re.compile(
    r"Total tests:\s*(?P<total>\d+),\s*passed:\s*(?P<passed>\d+),\s*failed:\s*(?P<failed>\d+)\."
)
FORMAT_BITS = {"decimal32": 32, "decimal64": 64, "decimal128": 128}
FORMAT_PRECISION = {"decimal32": 7, "decimal64": 16, "decimal128": 34}
FORMAT_EXPONENT = {"decimal32": 6, "decimal64": 8, "decimal128": 12}
FORMAT_COEFFICIENT = {"decimal32": 20, "decimal64": 50, "decimal128": 110}
FORMAT_BID_EXPONENT = {"decimal32": 8, "decimal64": 10, "decimal128": 14}
FORMAT_BID_SMALL_COEFFICIENT = {"decimal32": 23, "decimal64": 53, "decimal128": 113}
FORMAT_BIAS = {"decimal32": 101, "decimal64": 398, "decimal128": 6176}
FORMAT_EMIN = {"decimal32": -95, "decimal64": -383, "decimal128": -6143}
FORMAT_EMAX = {"decimal32": 96, "decimal64": 384, "decimal128": 6144}

FLAG_TYPES = {
    "Clamped": decimal.Clamped,
    "Inexact": decimal.Inexact,
    "InvalidOperation": decimal.InvalidOperation,
    "Overflow": decimal.Overflow,
    "Rounded": decimal.Rounded,
    "Subnormal": decimal.Subnormal,
    "Underflow": decimal.Underflow,
    "DivisionByZero": decimal.DivisionByZero,
}
SIGNAL_VARIANTS = {
    "Clamped": "Clamped",
    "Inexact": "Inexact",
    "InvalidOperation": "InvalidOperation",
    "Overflow": "Overflow",
    "Rounded": "Rounded",
    "Subnormal": "Subnormal",
    "Underflow": "Underflow",
    "DivisionByZero": "DivisionByZero",
}


class CorpusError(ValueError):
    pass


def load_json(path: Path) -> dict[str, Any]:
    import json

    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise CorpusError(f"fixture must be an object: {path}")
    return value


def dpd_encode(lhs: int, mid: int, rhs: int) -> int:
    if not all(0 <= digit <= 9 for digit in (lhs, mid, rhs)):
        raise ValueError("DPD digit out of range")
    a, b, c, d = (lhs >> 3) & 1, (lhs >> 2) & 1, (lhs >> 1) & 1, lhs & 1
    e, f, g, h = (mid >> 3) & 1, (mid >> 2) & 1, (mid >> 1) & 1, mid & 1
    i, j, k, m = (rhs >> 3) & 1, (rhs >> 2) & 1, (rhs >> 1) & 1, rhs & 1
    p = b or (a and j) or (a and f and i)
    q = c or (a and k) or (a and g and i)
    r = d
    s = (f and (not a or not i)) or (not a and e and j) or (e and i)
    t = g or (not a and e and k) or (a and i)
    u = h
    v = a or e or i
    w = a or (e and i) or (not e and j)
    x = e or (a and i) or (not a and k)
    y = m
    return (
        (int(p) << 9) | (int(q) << 8) | (r << 7) | (int(s) << 6)
        | (int(t) << 5) | (u << 4) | (int(v) << 3) | (int(w) << 2)
        | (int(x) << 1) | y
    )


def dpd_decode(code: int) -> tuple[int, int, int]:
    if not 0 <= code < 1024:
        raise ValueError("DPD code out of range")
    p, q, r, s, t, u, v, w, x, y = ((code >> shift) & 1 for shift in range(9, -1, -1))
    a = int((v and w) and (not s or t or not x))
    b = int(p and (not v or not w or (s and not t and x)))
    c = int(q and (not v or not w or (s and not t and x)))
    d = r
    e = int(v and ((not w and x) or (not t and x) or (s and x)))
    f = int((s and (not v or not x)) or (p and not s and t and v and w and x))
    g = int((t and (not v or not x)) or (q and not s and t and w))
    h = u
    i = int(v and ((not w and not x) or (w and x and (s or t))))
    j = int((not v and w) or (s and v and not w and x) or (p and w and (not x or (not s and not t))))
    k = int((not v and x) or (t and not w and x) or (q and v and w and (not x or (not s and not t))))
    return ((a << 3) | (b << 2) | (c << 1) | d, (e << 3) | (f << 2) | (g << 1) | h, (i << 3) | (j << 2) | (k << 1) | y)


def decimal_context(format_name: str) -> Context:
    precision = FORMAT_PRECISION[format_name]
    return Context(
        prec=precision,
        Emin=FORMAT_EMIN[format_name],
        Emax=FORMAT_EMAX[format_name],
        clamp=1,
    )


def _hex_bits(bits: str, format_name: str) -> int:
    digits = FORMAT_BITS[format_name] // 4
    if not isinstance(bits, str) or len(bits.removeprefix("#")) != digits:
        raise CorpusError(f"invalid {format_name} interchange width")
    body = bits.removeprefix("#")
    try:
        return int(body, 16)
    except ValueError as error:
        raise CorpusError(f"invalid interchange bits: {bits}") from error


def _format_bits(value: int, format_name: str) -> str:
    return f"{value:0{FORMAT_BITS[format_name] // 4}X}"


def _dpd_digits_to_string(bits: int, groups: int) -> str:
    return "".join("%d%d%d" % dpd_decode((bits >> ((groups - i - 1) * 10)) & 0x3FF) for i in range(groups))


def _encode_dpd_case(case: dict[str, Any], format_name: str) -> int:
    total = FORMAT_BITS[format_name]
    exp_bits = FORMAT_EXPONENT[format_name]
    coeff_bits = FORMAT_COEFFICIENT[format_name]
    bias = FORMAT_BIAS[format_name]
    precision = FORMAT_PRECISION[format_name]
    sign = int(bool(case.get("negative", False))) << (total - 1)
    prefix_shift = coeff_bits + exp_bits
    kind = case.get("class")
    if kind == "infinity":
        return sign | (0b11110 << prefix_shift)
    if kind in {"qnan", "snan"}:
        payload = str(case.get("payload", "0"))
        payload = payload[-(precision - 1) :].rjust(precision - 1, "0")
        payload_bits = 0
        for offset in range(0, len(payload), 3):
            payload_bits = (payload_bits << 10) | dpd_encode(*(int(digit) for digit in payload[offset : offset + 3]))
        signal = int(kind == "snan") << (exp_bits - 1)
        return sign | (0b11111 << prefix_shift) | (signal << coeff_bits) | payload_bits
    coefficient = str(case.get("coefficient", "0")).rjust(precision, "0")[-precision:]
    msd = int(coefficient[0])
    exponent = int(case["exponent"]) + bias
    exp_msb = exponent >> exp_bits
    combination = (0b11000 | (exp_msb << 1) | (msd - 8)) if msd >= 8 else ((exp_msb << 3) | msd)
    continuation = coefficient[1:]
    coefficient_bits_value = 0
    for offset in range(0, len(continuation), 3):
        coefficient_bits_value = (coefficient_bits_value << 10) | dpd_encode(*(int(digit) for digit in continuation[offset : offset + 3]))
    return sign | (combination << prefix_shift) | ((exponent % (1 << exp_bits)) << coeff_bits) | coefficient_bits_value


def _decode_interchange_case(case: dict[str, Any], format_name: str, encoding: str) -> tuple[dict[str, Any], str]:
    bits = _hex_bits(case.get("bits", ""), format_name)
    total = FORMAT_BITS[format_name]
    precision = FORMAT_PRECISION[format_name]
    bias = FORMAT_BIAS[format_name]
    sign = bool((bits >> (total - 1)) & 1)
    exp_bits = FORMAT_EXPONENT[format_name]
    coeff_bits = FORMAT_COEFFICIENT[format_name]
    prefix_shift = coeff_bits + exp_bits
    combination = (bits >> prefix_shift) & 0x1F
    if combination == 0b11110:
        value = {"class": "infinity", "negative": sign}
        canonical = _encode_dpd_case(value, format_name) if encoding == "DPD" else (int(sign) << (total - 1)) | (0b11110 << prefix_shift)
        return value, _format_bits(canonical, format_name)
    if combination == 0b11111:
        signaling = bool((bits >> (coeff_bits + exp_bits - 1)) & 1)
        if encoding == "DPD":
            payload = str(int(_dpd_digits_to_string(bits & ((1 << coeff_bits) - 1), coeff_bits // 10)))
            payload = payload.lstrip("0") or "0"
        else:
            payload_value = bits & ((1 << coeff_bits) - 1)
            payload = str(payload_value) if payload_value < 10 ** (precision - 1) else "0"
        value = {"class": "snan" if signaling else "qnan", "negative": sign, "payload": payload}
        canonical = _encode_dpd_case(value, format_name) if encoding == "DPD" else _encode_bid_case(value, format_name)
        return value, _format_bits(canonical, format_name)
    if encoding == "DPD":
        exp_msb, msd = (((combination >> 1) & 0b11), 8 + (combination & 1)) if (combination & 0b11000) == 0b11000 else (((combination >> 3) & 0b11), combination & 0b111)
        continuation = _dpd_digits_to_string(bits & ((1 << coeff_bits) - 1), coeff_bits // 10)
        coefficient = int(str(msd) + continuation)
        exponent = ((exp_msb << exp_bits) | ((bits >> coeff_bits) & ((1 << exp_bits) - 1))) - bias
        value = {"class": "finite", "coefficient": str(coefficient), "exponent": exponent, "negative": sign}
        canonical = _encode_dpd_case(value, format_name)
    else:
        small_bits = FORMAT_BID_SMALL_COEFFICIENT[format_name]
        large_bits = small_bits - 2
        steering = (bits >> (total - 3)) & 0b11
        if steering == 0b11:
            encoded_exponent = (bits >> large_bits) & ((1 << FORMAT_BID_EXPONENT[format_name]) - 1)
            coefficient = (bits & ((1 << large_bits) - 1)) + (1 << small_bits)
        else:
            encoded_exponent = (bits >> small_bits) & ((1 << FORMAT_BID_EXPONENT[format_name]) - 1)
            coefficient = bits & ((1 << small_bits) - 1)
        canonical_coefficient = coefficient if coefficient < 10**precision else 0
        value = {"class": "finite", "coefficient": str(canonical_coefficient), "exponent": encoded_exponent - bias, "negative": sign}
        canonical = _encode_bid_case(value, format_name)
    return value, _format_bits(canonical, format_name)


def _encode_bid_case(case: dict[str, Any], format_name: str) -> int:
    total = FORMAT_BITS[format_name]
    coeff_bits = FORMAT_COEFFICIENT[format_name]
    exp_bits = FORMAT_EXPONENT[format_name]
    bias = FORMAT_BIAS[format_name]
    precision = FORMAT_PRECISION[format_name]
    sign = int(bool(case.get("negative", False))) << (total - 1)
    prefix_shift = coeff_bits + exp_bits
    kind = case.get("class")
    if kind == "infinity":
        return sign | (0b11110 << prefix_shift)
    if kind in {"qnan", "snan"}:
        payload = int(case.get("payload", "0"))
        payload = payload if payload < 10 ** (precision - 1) else 0
        signal = int(kind == "snan") << (exp_bits - 1)
        return sign | (0b11111 << prefix_shift) | (signal << coeff_bits) | payload
    coefficient = int(case.get("coefficient", "0"))
    exponent = int(case["exponent"]) + bias
    small_bits = FORMAT_BID_SMALL_COEFFICIENT[format_name]
    if coefficient < (1 << small_bits):
        return sign | (exponent << small_bits) | coefficient
    large_bits = small_bits - 2
    return sign | (0b11 << (total - 3)) | (exponent << large_bits) | (coefficient % (1 << large_bits))


def _validate_case(case: dict[str, Any], format_name: str, encoding: str) -> None:
    if not isinstance(case, dict) or not isinstance(case.get("id"), str):
        raise CorpusError(f"malformed interchange case in {format_name}/{encoding}")
    actual, canonical = _decode_interchange_case(case, format_name, encoding)
    for key, expected in actual.items():
        if case.get(key) != expected:
            raise CorpusError(f"{case['id']}: decoded {key}={expected!r}, fixture has {case.get(key)!r}")
    if case.get("canonical") != canonical:
        raise CorpusError(f"{case['id']}: canonical bits mismatch")


def _raised_flags(active: Context) -> set[str]:
    return {signal.__name__ for signal, raised in active.flags.items() if raised and signal.__name__ in FLAG_TYPES}


def check_conformance_matrix(path: Path = MATRIX_PATH) -> tuple[int, int]:
    matrix = load_json(path)
    if matrix.get("schemaVersion") != 1 or matrix.get("standard") != "IEEE 754-2019":
        raise CorpusError("unsupported IEEE conformance matrix")
    statuses = matrix.get("statuses")
    if not isinstance(statuses, list) or not statuses or not all(isinstance(item, str) for item in statuses):
        raise CorpusError("conformance matrix statuses must be a non-empty string array")
    known_statuses = set(statuses)
    seen: set[str] = set()
    counts = []
    for section in ("required", "recommended"):
        rows = matrix.get(section)
        if not isinstance(rows, list) or not rows:
            raise CorpusError(f"conformance matrix section {section!r} is empty")
        counts.append(len(rows))
        for row in rows:
            if not isinstance(row, dict) or not isinstance(row.get("operation"), str):
                raise CorpusError(f"malformed conformance matrix row in {section}")
            operation = row["operation"]
            if operation in seen:
                raise CorpusError(f"duplicate conformance matrix operation: {operation}")
            seen.add(operation)
            if not isinstance(row.get("api"), str) or not row["api"]:
                raise CorpusError(f"{operation}: missing API mapping")
            if row.get("status") not in known_statuses:
                raise CorpusError(f"{operation}: unknown conformance status")
    return counts[0], counts[1]


def _moon_string(value: str) -> str:
    import json

    return json.dumps(value)


def render_moon_fixture_test() -> str:
    rows: list[tuple[str, dict[str, Any], str, str]] = []
    for entry in load_json(MANIFEST_PATH)["fixtures"]:
        fixture = load_json(FIXTURE_ROOT / entry["path"])
        for row in fixture["operations"]:
            rows.append((entry["format"], row, entry["encoding"], entry["path"]))
    excerpt = load_json(STANDARD_EXCERPT_PATH)
    for row in excerpt["cases"]:
        rows.append((row["format"], row, "decTest", row["file"]))
    all_signals = ", ".join(f"DecimalSignal::{name}" for name in SIGNAL_VARIANTS.values())
    source = [
        "fn assert_ieee_fixture_flags(id : String, actual : DecimalFlags, expected : Array[DecimalSignal]) -> Unit raise {",
        f"  let all = [{all_signals}]",
        "  for signal in all {",
        "    assert_eq(actual.contains(signal), expected.contains(signal), msg=id + \" flag\")",
        "  }",
        "}",
        "",
    ]
    for format_name, row, encoding, path in rows:
        operation = row["op"]
        name = f"IEEE fixture {format_name} {encoding} {row['id']}".replace('"', "'")
        ctx = f"DecimalContext::{format_name}()"
        lhs = f"Decimal::from_string({_moon_string(str(row['lhs']))}).unwrap()"
        rhs = f"Decimal::from_string({_moon_string(str(row['rhs']))}).unwrap()" if "rhs" in row else None
        if operation == "add":
            call = f"lhs.add_ctx({rhs}, ctx)"
        elif operation == "subtract":
            call = f"lhs.sub_ctx({rhs}, ctx)"
        elif operation == "multiply":
            call = f"lhs.mul_ctx({rhs}, ctx)"
        elif operation == "divide":
            call = f"lhs.div_ctx({rhs}, ctx)"
        elif operation == "fma":
            third = f"Decimal::from_string({_moon_string(str(row['third']))}).unwrap()"
            call = f"lhs.fma_ctx({rhs}, {third}, ctx)"
        elif operation == "sqrt":
            call = "lhs.sqrt_ctx(ctx)"
        elif operation == "quantize":
            call = f"lhs.quantize({rhs}, ctx)"
        elif operation == "remainder":
            call = f"lhs.remainder_ctx({rhs}, ctx)"
        elif operation == "compare":
            call = f"lhs.compare_ctx({rhs}, ctx)"
        else:
            raise CorpusError(f"unsupported operation in {path}: {operation}")
        expected = ", ".join(f"DecimalSignal::{SIGNAL_VARIANTS[item]}" for item in row["flags"])
        source.extend([
            f"test {_moon_string(name)} {{",
            f"  let ctx = {ctx}",
            f"  let lhs = {lhs}",
            f"  let (actual, flags) = {call}",
            f"  assert_eq(actual.to_string(), {_moon_string(str(row['result']))}, msg={_moon_string(str(row['id']))})",
            f"  assert_ieee_fixture_flags({_moon_string(str(row['id']))}, flags, [{expected}])",
            "}",
            "",
        ])
    rounding_variants = {
        "half_even": "HalfEven",
        "half_up": "HalfUp",
        "half_down": "HalfDown",
        "down": "Down",
        "ceiling": "Ceiling",
        "floor": "Floor",
        "up": "Up",
        "zero_five_up": "ZeroFiveUp",
    }
    format_parameters = {
        "decimal32": (7, -95, 96),
        "decimal64": (16, -383, 384),
        "decimal128": (34, -6143, 6144),
    }
    for row in load_json(ELEMENTARY_ORACLE_PATH)["rows"]:
        operation = row["operation"]
        precision, e_min, e_max = format_parameters[row["format"]]
        ctx = (
            "DecimalContext::new("
            f"precision={precision}, e_min={e_min}, e_max={e_max}, clamp=true, "
            f"decimal_rounding=DecimalRoundingMode::{rounding_variants[row['rounding']]})"
        )
        rhs = (
            f"Decimal::from_string({_moon_string(row['right'])}).unwrap()"
            if "right" in row
            else None
        )
        unary = {
            "exp": "try_exp_ctx",
            "exp2": "try_exp2_ctx",
            "exp10": "try_exp10_ctx",
            "expm1": "try_expm1_ctx",
            "ln": "try_ln_ctx",
            "log2": "try_log2_ctx",
            "log10": "try_log10_ctx",
            "log1p": "try_log1p_ctx",
            "sin": "try_sin_ctx",
            "cos": "try_cos_ctx",
            "tan": "try_tan_ctx",
            "sinpi": "try_sinpi_ctx",
            "cospi": "try_cospi_ctx",
            "tanpi": "try_tanpi_ctx",
            "asin": "try_asin_ctx",
            "acos": "try_acos_ctx",
            "atan": "try_atan_ctx",
            "sinh": "try_sinh_ctx",
            "cosh": "try_cosh_ctx",
            "tanh": "try_tanh_ctx",
            "asinh": "try_asinh_ctx",
            "acosh": "try_acosh_ctx",
            "atanh": "try_atanh_ctx",
        }
        if operation == "sqrt":
            call = "lhs.sqrt_ctx(ctx)"
        elif operation == "rootn":
            call = f"lhs.try_rootn_ctx({row['integer']}, ctx).unwrap()"
        elif operation == "pown":
            call = f"lhs.try_pown_ctx({row['integer']}, ctx).unwrap()"
        elif operation == "pow":
            call = f"lhs.try_power_ctx({rhs}, ctx).unwrap()"
        elif operation == "hypot":
            call = f"lhs.try_hypot_ctx({rhs}, ctx).unwrap()"
        elif operation == "atan2":
            call = f"lhs.try_atan2_ctx({rhs}, ctx).unwrap()"
        elif operation in unary:
            call = f"lhs.{unary[operation]}(ctx).unwrap()"
        else:
            raise CorpusError(f"unsupported Decimal elementary oracle operation: {operation}")
        expected_flags = ", ".join(
            f"DecimalSignal::{SIGNAL_VARIANTS[item]}" for item in row["flags"]
        )
        source.extend(
            [
                f"test {_moon_string('IEEE elementary oracle ' + row['id'])} {{",
                f"  let ctx = {ctx}",
                f"  let lhs = Decimal::from_string({_moon_string(row['left'])}).unwrap()",
                f"  let (actual, flags) = {call}",
                f"  let expected = Decimal::from_string({_moon_string(row['result'])}).unwrap()",
                f"  assert_eq(actual.compare(expected), 0, msg={_moon_string(row['id'])})",
                f"  assert_ieee_fixture_flags({_moon_string(row['id'])}, flags, [{expected_flags}])",
                "}",
                "",
            ]
        )
    return "\n".join(source)


def check_elementary_oracle() -> int:
    fixture = load_json(ELEMENTARY_ORACLE_PATH)
    if fixture.get("schemaVersion") != 1:
        raise CorpusError("unsupported Decimal elementary oracle schema")
    intervals = generate_decimal_elementary_oracle.parse_intervals(
        ELEMENTARY_INTERVAL_PATH
    )
    expected_rows = generate_decimal_elementary_oracle.generate_rows(intervals)
    if fixture.get("rows") != expected_rows:
        raise CorpusError("Decimal elementary oracle does not match certified endpoints")
    return len(expected_rows)


def check_declets(path: Path) -> int:
    fixture = load_json(path)
    if fixture.get("codes") != {"start": 0, "stop": 1024, "step": 1}:
        raise CorpusError("DPD fixture must cover all 1024 declets")
    redundant = 0
    for code in range(1024):
        digits = dpd_decode(code)
        if dpd_encode(*digits) != code:
            redundant += 1
    if redundant != fixture.get("expectedRedundantCodes"):
        raise CorpusError("invalid DPD declet inventory")
    return 1024


def check_encoding_bridge() -> int:
    checked = 0
    for entry in load_json(MANIFEST_PATH)["fixtures"]:
        if entry["encoding"] != "DPD":
            continue
        format_name = str(entry["format"])
        fixture = load_json(FIXTURE_ROOT / entry["path"])
        for case in fixture["cases"]:
            value, _ = _decode_interchange_case(case, format_name, "DPD")
            bid_bits = _format_bits(_encode_bid_case(value, format_name), format_name)
            bridged, _ = _decode_interchange_case(
                {"bits": bid_bits}, format_name, "BID"
            )
            if value != bridged:
                raise CorpusError(f"{case['id']}: DPD/BID encoding bridge drift")
            checked += 1
    return checked


def check_fixture(path: Path, entry: dict[str, Any]) -> tuple[int, int]:
    fixture = load_json(path)
    if fixture.get("format") != entry.get("format") or fixture.get("encoding") != entry.get("encoding"):
        raise CorpusError(f"manifest/fixture mismatch: {path}")
    if fixture.get("schemaVersion") != 1:
        raise CorpusError(f"unsupported fixture schema: {path}")
    format_name = str(entry["format"])
    encoding = str(entry["encoding"])
    cases = fixture.get("cases")
    operations = fixture.get("operations")
    if not isinstance(cases, list) or not isinstance(operations, list):
        raise CorpusError(f"malformed fixture: {path}")
    case_ids: set[str] = set()
    for case in cases:
        _validate_case(case, format_name, encoding)
        if case["id"] in case_ids:
            raise CorpusError(f"duplicate interchange case id: {case['id']}")
        case_ids.add(case["id"])
    context = decimal_context(format_name)
    operation_ids: set[str] = set()
    for row in operations:
        if not isinstance(row, dict) or not isinstance(row.get("id"), str):
            raise CorpusError(f"malformed operation row: {path}")
        if row["id"] in operation_ids:
            raise CorpusError(f"duplicate operation id: {row['id']}")
        operation_ids.add(row["id"])
        if not isinstance(row.get("flags"), list) or not all(isinstance(item, str) for item in row["flags"]):
            raise CorpusError(f"{row['id']}: flags must be an array of names")
        unknown_flags = set(row["flags"]) - set(FLAG_TYPES)
        if unknown_flags:
            raise CorpusError(f"{row['id']}: unknown flags {sorted(unknown_flags)}")
        with localcontext(context) as active:
            active.clear_flags()
            lhs = Decimal(str(row["lhs"]))
            rhs = Decimal(str(row["rhs"])) if "rhs" in row else None
            op = row.get("op")
            if op == "add":
                actual = active.add(lhs, rhs)
            elif op == "subtract":
                actual = active.subtract(lhs, rhs)
            elif op == "multiply":
                actual = active.multiply(lhs, rhs)
            elif op == "divide":
                actual = active.divide(lhs, rhs)
            elif op == "fma":
                actual = active.fma(lhs, rhs, Decimal(str(row["third"])))
            elif op == "sqrt":
                actual = active.sqrt(lhs)
            elif op == "quantize":
                actual = active.quantize(lhs, rhs)
            elif op == "compare":
                actual = active.compare(lhs, rhs)
            else:
                raise CorpusError(f"unsupported operation: {op}")
            if str(actual) != row["result"]:
                raise CorpusError(f"{row['id']}: expected {row['result']}, got {actual}")
            expected_flags = set(row["flags"])
            actual_flags = _raised_flags(active)
            if actual_flags != expected_flags:
                raise CorpusError(
                    f"{row['id']}: expected flags {sorted(expected_flags)}, got {sorted(actual_flags)}"
                )
    return len(cases), len(operations)


def check_standard_excerpt(path: Path = STANDARD_EXCERPT_PATH) -> int:
    excerpt = load_json(path)
    if excerpt.get("schemaVersion") != 1 or excerpt.get("standard") != "IEEE 754-2019":
        raise CorpusError("unsupported decTest IEEE excerpt")
    source = excerpt.get("source")
    if not isinstance(source, dict) or source.get("kind") != "GDA decTest concrete-format excerpt":
        raise CorpusError("decTest IEEE excerpt is missing source provenance")
    files = source.get("files")
    if not isinstance(files, list) or not files or not all(isinstance(item, str) for item in files):
        raise CorpusError("decTest IEEE excerpt source files are malformed")
    cases = excerpt.get("cases")
    if not isinstance(cases, list) or not cases:
        raise CorpusError("decTest IEEE excerpt is empty")
    seen: set[str] = set()
    for row in cases:
        if not isinstance(row, dict) or not isinstance(row.get("id"), str):
            raise CorpusError("malformed decTest IEEE excerpt row")
        identifier = row["id"]
        if identifier in seen:
            raise CorpusError(f"duplicate decTest IEEE excerpt id: {identifier}")
        seen.add(identifier)
        format_name = row.get("format")
        if format_name not in FORMAT_BITS:
            raise CorpusError(f"{identifier}: unsupported excerpt format")
        if row.get("file") not in files:
            raise CorpusError(f"{identifier}: source file is not recorded")
        operation = row.get("op")
        if operation not in {"add", "subtract", "multiply", "divide", "fma", "quantize", "remainder"}:
            raise CorpusError(f"{identifier}: unsupported excerpt operation {operation!r}")
        if not isinstance(row.get("flags"), list) or not all(
            isinstance(item, str) and item in FLAG_TYPES for item in row["flags"]
        ):
            raise CorpusError(f"{identifier}: malformed excerpt flags")
        context = decimal_context(format_name)
        with localcontext(context) as active:
            active.clear_flags()
            lhs = Decimal(str(row["lhs"]))
            rhs = Decimal(str(row["rhs"])) if "rhs" in row else None
            if operation == "add":
                actual = active.add(lhs, rhs)
            elif operation == "subtract":
                actual = active.subtract(lhs, rhs)
            elif operation == "multiply":
                actual = active.multiply(lhs, rhs)
            elif operation == "divide":
                actual = active.divide(lhs, rhs)
            elif operation == "fma":
                actual = active.fma(lhs, rhs, Decimal(str(row["third"])))
            elif operation == "quantize":
                actual = active.quantize(lhs, rhs)
            else:
                actual = active.remainder(lhs, rhs)
            if str(actual) != row["result"]:
                raise CorpusError(f"{identifier}: expected {row['result']}, got {actual}")
            actual_flags = _raised_flags(active)
            if actual_flags != set(row["flags"]):
                raise CorpusError(
                    f"{identifier}: expected flags {sorted(row['flags'])}, got {sorted(actual_flags)}"
                )
    return len(cases)


def collect_corpus_checks() -> dict[str, Any]:
    required, recommended = check_conformance_matrix()
    oracle_routes = decimal_oracles.validate_manifest()
    static_examples = decimal_oracles.validate_static_examples(decimal_context)
    vector_plan = generate_ieee_decimal_vectors.load_plan()
    manifest = load_json(MANIFEST_PATH)
    if manifest.get("schemaVersion") != 2 or manifest.get("standard") != "IEEE 754-2019":
        raise CorpusError("unsupported IEEE manifest")
    for key, expected in (
        ("oracleManifest", "oracle_manifest.json"),
        ("staticOracleExamples", "oracle_static_examples.json"),
        ("elementaryOracle", "elementary_mpfr_oracle.json"),
        ("elementaryOracleIntervals", "mpfr-4.2.2-elementary-interval.txt"),
        ("vectorPlan", "vector_plan.json"),
    ):
        if manifest.get(key) != expected or not (FIXTURE_ROOT / expected).is_file():
            raise CorpusError(f"IEEE manifest is missing {key}")
    entries = manifest.get("fixtures")
    if not isinstance(entries, list) or len(entries) != 6:
        raise CorpusError("manifest must list six interchange fixtures")
    cases = operations = 0
    for entry in entries:
        checked_cases, checked_operations = check_fixture(FIXTURE_ROOT / entry["path"], entry)
        cases += checked_cases
        operations += checked_operations
    declets = check_declets(FIXTURE_ROOT / manifest["exhaustive"]["path"])
    bridge = check_encoding_bridge()
    elementary = check_elementary_oracle()
    return {
        "requiredOperations": required,
        "recommendedOperations": recommended,
        "oracleRoutes": oracle_routes,
        "staticExamples": static_examples,
        "vectorPlan": vector_plan,
        "cases": cases,
        "operations": operations,
        "declets": declets,
        "encodingBridge": bridge,
        "elementaryOracle": elementary,
    }


def check_corpus() -> tuple[int, int, int]:
    checks = collect_corpus_checks()
    return checks["cases"], checks["operations"], checks["declets"]


def _target_result(target: str, result: subprocess.CompletedProcess[str]) -> dict[str, Any]:
    output = f"{result.stdout}\n{result.stderr}"
    match = list(MOON_TEST_SUMMARY.finditer(output))[-1:]
    if match:
        summary = match[0].groupdict()
        total = int(summary["total"])
        passed = int(summary["passed"])
        failed = int(summary["failed"])
    elif result.returncode == 0:
        raise CorpusError(f"MoonBit test output had no summary for target {target}")
    else:
        total, passed, failed = 1, 0, 1
    if result.returncode != 0 and failed == 0:
        total += 1
        failed = 1
    return {
        "target": target,
        "totalCases": total,
        "passedCases": passed,
        "failedCases": failed,
        "exitCode": result.returncode,
    }


def selected_targets(targets: list[str]) -> list[str]:
    requested = targets or ["native"]
    invalid = set(requested) - set(SUPPORTED_TARGETS)
    if invalid:
        raise CorpusError(f"unsupported target(s): {sorted(invalid)}")
    if len(set(requested)) != len(requested):
        raise CorpusError("targets may only be specified once")
    return requested


def run_targets(targets: list[str], fixture: str = "") -> list[dict[str, Any]]:
    requested = selected_targets(targets)
    generated_path = ROOT / "src/decimal/ieee_corpus_generated_wbtest.mbt"
    if generated_path.exists():
        raise CorpusError(f"generated IEEE fixture already exists: {generated_path}")
    results: list[dict[str, Any]] = []
    try:
        generated_path.write_text(render_moon_fixture_test(), encoding="utf-8")
        for target in requested:
            result = subprocess.run(
                ["moon", "test", "src/decimal", "--target", target, "--no-parallelize"],
                cwd=ROOT,
                check=False,
                capture_output=True,
                text=True,
            )
            results.append(_target_result(target, result))
    finally:
        generated_path.unlink(missing_ok=True)
    return results


def _plan(targets: list[str]) -> dict[str, Any]:
    manifest = load_json(MANIFEST_PATH)
    vector_plan = generate_ieee_decimal_vectors.load_plan()
    fixture_cases = 0
    fixture_operations = 0
    for entry in manifest.get("fixtures", []):
        fixture = load_json(FIXTURE_ROOT / entry["path"])
        fixture_cases += len(fixture.get("cases", []))
        fixture_operations += len(fixture.get("operations", []))
    excerpt = load_json(STANDARD_EXCERPT_PATH)
    return {
        "schemaVersion": 1,
        "runner": "ieee-decimal-oracles",
        "corpus": "checked-in",
        "targets": targets or ["native"],
        "checks": {
            "interchangeCases": fixture_cases,
            "authoritativeOperations": fixture_operations,
            "decTestExcerptRows": len(excerpt.get("cases", [])),
            "dpdDeclets": 1024,
            "staticOracleExamples": len(load_json(decimal_oracles.STATIC_EXAMPLES).get("examples", [])),
            "certifiedElementaryOracle": len(load_json(ELEMENTARY_ORACLE_PATH).get("rows", [])),
        },
        "vectorPlan": {
            "families": len(vector_plan["families"]),
            "targetCasesPerFamily": vector_plan["targetCasesPerFamily"],
        },
        "availableOracles": [
            name for name, details in decimal_oracles.probe().items() if details.get("available")
        ],
    }


def _report(
    checks: dict[str, Any],
    excerpt_cases: int,
    targets: list[dict[str, Any]],
    capabilities: dict[str, dict[str, Any]],
    elapsed: float,
) -> dict[str, Any]:
    rows = [
        {"name": "interchange cases", "passedCases": checks["cases"], "totalCases": checks["cases"], "failedCases": 0},
        {"name": "authoritative operations", "passedCases": checks["operations"], "totalCases": checks["operations"], "failedCases": 0},
        {"name": "decTest excerpt", "passedCases": excerpt_cases, "totalCases": excerpt_cases, "failedCases": 0},
        {"name": "DPD declets", "passedCases": checks["declets"], "totalCases": checks["declets"], "failedCases": 0},
        {"name": "DPD/BID bridge", "passedCases": checks["encodingBridge"], "totalCases": checks["encodingBridge"], "failedCases": 0},
        {"name": "static Oracle examples", "passedCases": checks["staticExamples"], "totalCases": checks["staticExamples"], "failedCases": 0},
        {"name": "certified elementary Oracle", "passedCases": checks["elementaryOracle"], "totalCases": checks["elementaryOracle"], "failedCases": 0},
    ]
    rows.extend(
        {
            "name": f"public API · {target['target']}",
            "passedCases": target["passedCases"],
            "totalCases": target["totalCases"],
            "failedCases": target["failedCases"],
        }
        for target in targets
    )
    summary = {
        "totalCases": sum(row["totalCases"] for row in rows),
        "passedCases": sum(row["passedCases"] for row in rows),
        "failedCases": sum(row["failedCases"] for row in rows),
        "failedIds": [target["target"] for target in targets if target["failedCases"]],
        "elapsedSeconds": round(elapsed, 3),
    }
    return {
        "schemaVersion": 1,
        "runner": "ieee-decimal-oracles",
        "standard": "IEEE 754-2019",
        "checks": checks,
        "excerptCases": excerpt_cases,
        "targets": targets,
        "oracles": capabilities,
        "summary": summary,
    }


def _print_report(report: dict[str, Any]) -> None:
    rows = [
        SummaryRow(
            row["name"],
            row["passedCases"],
            row["totalCases"],
            row["failedCases"],
        )
        for row in [
            {
                "name": "interchange cases",
                "passedCases": report["checks"]["cases"],
                "totalCases": report["checks"]["cases"],
                "failedCases": 0,
            },
            {
                "name": "authoritative operations",
                "passedCases": report["checks"]["operations"],
                "totalCases": report["checks"]["operations"],
                "failedCases": 0,
            },
            {
                "name": "decTest excerpt",
                "passedCases": report["excerptCases"],
                "totalCases": report["excerptCases"],
                "failedCases": 0,
            },
            {
                "name": "DPD declets",
                "passedCases": report["checks"]["declets"],
                "totalCases": report["checks"]["declets"],
                "failedCases": 0,
            },
            {
                "name": "DPD/BID bridge",
                "passedCases": report["checks"]["encodingBridge"],
                "totalCases": report["checks"]["encodingBridge"],
                "failedCases": 0,
            },
            {
                "name": "static Oracle examples",
                "passedCases": report["checks"]["staticExamples"],
                "totalCases": report["checks"]["staticExamples"],
                "failedCases": 0,
            },
            {
                "name": "certified elementary Oracle",
                "passedCases": report["checks"]["elementaryOracle"],
                "totalCases": report["checks"]["elementaryOracle"],
                "failedCases": 0,
            },
        ]
        + [
            {
                "name": f"public API · {target['target']}",
                "passedCases": target["passedCases"],
                "totalCases": target["totalCases"],
                "failedCases": target["failedCases"],
            }
            for target in report["targets"]
        ]
    ]
    summary = report["summary"]
    print_summary(
        "DECIMAL · IEEE 754",
        "checked-in interchange corpus · independent Oracle routes",
        rows,
        summary["passedCases"],
        summary["totalCases"],
        summary["failedCases"],
        summary["elapsedSeconds"],
        summary["failedIds"],
    )


def fetch_main(argv: list[str] | None = None) -> int:
    if argv:
        print("IEEE Decimal uses checked-in fixtures; fetch accepts no arguments", flush=True)
        return 2
    print("IEEE Decimal fixtures are checked in; nothing to fetch")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Run IEEE decimal Oracle conformance")
    parser.add_argument("--run-target", "--target", dest="targets", action="append", default=[])
    parser.add_argument("--jobs", type=int, default=1)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--smoke", action="store_true")
    parser.add_argument("--plan", action="store_true")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)
    try:
        if args.jobs <= 0:
            raise ValueError("--jobs must be positive")
        targets = selected_targets(args.targets)
        if args.plan:
            plan = _plan(targets)
            print(json.dumps(plan, indent=2))
            return 0
        started = time.monotonic()
        checks = collect_corpus_checks()
        excerpt_cases = check_standard_excerpt()
        capabilities = decimal_oracles.probe()
        target_results = run_targets(targets)
        report = _report(checks, excerpt_cases, target_results, capabilities, time.monotonic() - started)
        args.output.resolve().mkdir(parents=True, exist_ok=True)
        report_path = args.output.resolve() / "summary.json"
        report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        if args.json:
            print(json.dumps(report, indent=2))
        else:
            _print_report(report)
            print(f"summary: {report_path.relative_to(ROOT)}")
        return 0 if report["summary"]["failedCases"] == 0 else 1
    except (CorpusError, OSError, ValueError, decimal.DecimalException) as error:
        print(f"error: {error}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
