#!/usr/bin/env python3
"""Generate deterministic IEEE decimal boundary vectors as JSONL."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any, Iterator

ROOT = Path(__file__).resolve().parent.parent
PLAN_PATH = ROOT / "testdata/decimal/ieee/vector_plan.json"
FORMATS = ("decimal32", "decimal64", "decimal128")
DATA_SCALES = (
    "tiny",
    "small",
    "medium",
    "format-precision",
    "large",
    "huge",
    "sparse",
    "unbalanced-short",
    "unbalanced-long",
)
SHAPES = ("balanced", "sparse", "dense", "unbalanced")
PRECISION = {"decimal32": 7, "decimal64": 16, "decimal128": 34}
EMIN = {"decimal32": -95, "decimal64": -383, "decimal128": -6143}
EMAX = {"decimal32": 96, "decimal64": 384, "decimal128": 6144}


def load_plan(path: Path = PLAN_PATH) -> dict[str, Any]:
    plan = json.loads(path.read_text(encoding="utf-8"))
    if plan.get("schemaVersion") != 1 or plan.get("standard") != "IEEE 754-2019":
        raise ValueError("unsupported IEEE vector plan")
    if plan.get("targetCasesPerFamily", 0) < 100_000:
        raise ValueError("each IEEE vector family must target at least 100000 cases")
    if tuple(plan.get("formats", [])) != FORMATS:
        raise ValueError("IEEE vector plan format order changed")
    if tuple(plan.get("dataScales", [])) != DATA_SCALES:
        raise ValueError("IEEE vector plan data-scale order changed")
    if tuple(plan.get("shapes", [])) != SHAPES:
        raise ValueError("IEEE vector plan shape order changed")
    families = plan.get("families")
    if not isinstance(families, list) or len(families) < 10 or len(set(families)) != len(families):
        raise ValueError("IEEE vector plan families are incomplete")
    return plan


def _next(state: int) -> int:
    return (state * 6364136223846793005 + 1442695040888963407) & ((1 << 64) - 1)


def _random_digits(state: int, digits: int) -> tuple[int, str]:
    result = []
    for _ in range(digits):
        state = _next(state)
        result.append(str(state % 10))
    return state, "".join(result)


def _scale_digits(format_name: str, scale: str) -> int:
    precision = PRECISION[format_name]
    return {
        "tiny": 1,
        "small": 3,
        "medium": 9,
        "format-precision": precision,
        "large": 64,
        "huge": 512,
        "sparse": 128,
        "unbalanced-short": 8,
        "unbalanced-long": 256,
    }[scale]


def _boundary_value(format_name: str, boundary: str, state: int, scale: str) -> tuple[int, str]:
    precision = PRECISION[format_name]
    emin = EMIN[format_name]
    emax = EMAX[format_name]
    etiny = emin - precision + 1
    if boundary == "zero":
        return state, "0"
    if boundary == "signed-zero":
        return state, "-0" if state & 1 else "0"
    if boundary == "one":
        return state, "1"
    if boundary == "max-finite":
        return state, f"{('9' * precision)}E{emax - precision + 1:+d}"
    if boundary == "min-normal":
        return state, f"1E{emin:+d}"
    if boundary == "min-subnormal":
        return state, f"1E{etiny:+d}"
    if boundary == "max-subnormal":
        return state, f"{('9' * precision)}E{etiny:+d}"
    if boundary == "qnan":
        return state, "NaN"
    if boundary == "snan":
        return state, "sNaN"
    if boundary == "infinity":
        return state, "-Infinity" if state & 1 else "Infinity"
    if boundary == "halfway":
        return state, f"{('5' + '0' * (precision - 1))}E{-precision:+d}"
    if boundary == "large-exponent":
        return state, f"1E{(emax if state & 1 else emin):+d}"
    if boundary == "large-coefficient":
        state, digits = _random_digits(state, _scale_digits(format_name, scale))
        return state, f"{digits}E{(emax - precision + 1):+d}"
    state, digits = _random_digits(state, _scale_digits(format_name, scale))
    exponent = emin + int(state % (emax - emin + 1))
    return state, f"{digits}E{exponent:+d}"


def _case_operations(family: str, state: int) -> tuple[int, str, int]:
    operations = {
        "mandatory-decimal": ("add", "subtract", "multiply", "divide", "sqrt", "quantize", "remainder"),
        "exp-ln-log10": ("exp", "ln", "log10"),
        "sqrt": ("sqrt",),
        "integer-power": ("pown",),
        "pow-powr": ("pow", "powr"),
        "trigonometric": ("sin", "cos", "tan"),
        "inverse-trigonometric": ("asin", "acos", "atan"),
        "hyperbolic": ("sinh", "cosh", "tanh"),
        "inverse-hyperbolic": ("asinh", "acosh", "atanh"),
        "expm1-log1p-hypot-cbrt": ("expm1", "log1p", "hypot", "cbrt"),
    }[family]
    state = _next(state)
    return state, operations[state % len(operations)], len(operations)


def _coefficient_digits(value: str) -> int:
    mantissa = value.lstrip("-+").split("E", 1)[0].split("e", 1)[0]
    digits = [char for char in mantissa if char.isdigit()]
    return len(digits)


def generate(family: str, count: int, seed: int) -> Iterator[dict[str, Any]]:
    plan = load_plan()
    if family not in plan["families"]:
        raise ValueError(f"unknown IEEE vector family: {family}")
    state = seed ^ sum(ord(char) for char in family)
    boundaries = plan["boundaryClasses"]
    scales = plan["dataScales"]
    shapes = plan["shapes"]
    for index in range(count):
        state = _next(state)
        format_name = FORMATS[index % len(FORMATS)]
        boundary = boundaries[(index + state) % len(boundaries)]
        scale = scales[(index * 5 + state) % len(scales)]
        shape = shapes[(index * 7 + state) % len(shapes)]
        state, operation, _ = _case_operations(family, state)
        state, lhs = _boundary_value(format_name, boundary, state, scale)
        operands = [lhs]
        if operation in {"add", "subtract", "multiply", "divide", "remainder", "quantize", "pow", "powr", "pown", "hypot"}:
            rhs_boundary = boundaries[(index * 3 + state) % len(boundaries)]
            rhs_scale = "unbalanced-long" if shape == "unbalanced" else scale
            state, rhs = _boundary_value(format_name, rhs_boundary, state, rhs_scale)
            operands.append(rhs if operation not in {"pown", "hypot"} else (str(int(state % 33) - 16) if operation == "pown" else rhs))
        if family == "expm1-log1p-hypot-cbrt" and operation == "hypot" and len(operands) < 2:
            state, rhs = _boundary_value(format_name, "one", state, scale)
            operands.append(rhs)
        yield {
            "id": f"{family}-{index:06d}",
            "family": family,
            "format": format_name,
            "operation": operation,
            "operands": operands,
            "rounding": plan["roundings"][index % len(plan["roundings"])],
            "tininess": plan["tininess"][index % len(plan["tininess"])],
            "boundary": boundary,
            "dataScale": scale,
            "shape": shape,
            "coefficientDigits": max((_coefficient_digits(item) for item in operands), default=0),
            "oracle": "static-example-or-external-adapter",
        }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Generate deterministic IEEE decimal JSONL vectors")
    parser.add_argument("--family", action="append")
    parser.add_argument("--count", type=int, default=100_000)
    parser.add_argument("--seed", type=int, default=None)
    parser.add_argument("--output", type=Path, default=None)
    args = parser.parse_args(argv)
    plan = load_plan()
    families = args.family or plan["families"]
    if args.count <= 0:
        raise SystemExit("--count must be positive")
    seed = plan["seed"] if args.seed is None else args.seed
    stream = (row for family in families for row in generate(family, args.count, seed))
    if args.output is None:
        for row in stream:
            print(json.dumps(row, separators=(",", ":")))
    else:
        with args.output.open("w", encoding="utf-8") as handle:
            for row in stream:
                handle.write(json.dumps(row, separators=(",", ":")) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
