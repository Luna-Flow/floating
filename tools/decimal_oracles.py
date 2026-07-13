"""Optional external decimal oracle adapters with independent flag handling."""

from __future__ import annotations

import decimal
import json
import os
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent
ORACLE_MANIFEST = ROOT / "testdata/decimal/ieee/oracle_manifest.json"
STATIC_EXAMPLES = ROOT / "testdata/decimal/ieee/oracle_static_examples.json"


@dataclass(frozen=True)
class OracleResult:
    value: str | None
    bits: str | None
    flags: frozenset[str]
    source: str


def load_manifest(path: Path = ORACLE_MANIFEST) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError("oracle manifest must be an object")
    return value


def validate_manifest(path: Path = ORACLE_MANIFEST) -> int:
    manifest = load_manifest(path)
    if manifest.get("schemaVersion") != 1 or manifest.get("standard") != "IEEE 754-2019":
        raise ValueError("unsupported oracle manifest")
    if manifest.get("flagPolicy") != "derive independently from IEEE special-case and exact-rounding rules":
        raise ValueError("oracle manifest must separate flags from value oracles")
    routes = manifest.get("routes")
    if not isinstance(routes, list) or not routes:
        raise ValueError("oracle manifest has no routes")
    seen: set[str] = set()
    for route in routes:
        if not isinstance(route, dict):
            raise ValueError("malformed oracle route")
        family = route.get("family")
        if not isinstance(family, str) or not family or family in seen:
            raise ValueError(f"duplicate or malformed oracle family: {family!r}")
        seen.add(family)
        for key in ("primary", "secondary"):
            if not isinstance(route.get(key), str) or not route[key]:
                raise ValueError(f"{family}: missing {key} oracle")
    commands = manifest.get("externalCommands")
    if not isinstance(commands, dict) or set(commands) != {"intel-rdfp", "arb", "mpfr"}:
        raise ValueError("external oracle command mapping is incomplete")
    return len(routes)


def validate_static_examples(context_factory: Any, path: Path = STATIC_EXAMPLES) -> int:
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("schemaVersion") != 1 or data.get("standard") != "IEEE 754-2019":
        raise ValueError("unsupported static oracle examples")
    if data.get("rounding") != "nearest-even" or data.get("tininess") not in {
        "before-rounding",
        "after-rounding",
    }:
        raise ValueError("static oracle examples must declare rounding and tininess")
    examples = data.get("examples")
    if not isinstance(examples, list) or not examples:
        raise ValueError("static oracle examples are empty")
    seen: set[str] = set()
    for example in examples:
        if not isinstance(example, dict) or not isinstance(example.get("id"), str):
            raise ValueError("malformed static oracle example")
        if example["id"] in seen:
            raise ValueError(f"duplicate static oracle example: {example['id']}")
        seen.add(example["id"])
        operands = example.get("operands")
        flags = example.get("flags")
        if not isinstance(operands, list) or not operands or not all(isinstance(item, str) for item in operands):
            raise ValueError(f"{example['id']}: malformed operands")
        if not isinstance(flags, list) or not all(isinstance(item, str) for item in flags):
            raise ValueError(f"{example['id']}: malformed flags")
        primary = example.get("primary")
        if not isinstance(primary, str) or not primary:
            raise ValueError(f"{example['id']}: missing primary oracle")
        operation = example.get("operation")
        if primary == "libmpdec-allcr1":
            if operation not in {"exp", "ln", "log10"} or len(operands) != 1:
                raise ValueError(f"{example['id']}: invalid libmpdec unary example")
            result = libmpdec_unary(operation, operands[0], example["format"], context_factory)
            if result.value != example["result"] or result.flags != frozenset(flags):
                raise ValueError(
                    f"{example['id']}: libmpdec result/flags drift "
                    f"({result.value!r}, {sorted(result.flags)!r})"
                )
        elif primary == "exact-gmp-rational":
            if operation != "pown" or len(operands) != 2:
                raise ValueError(f"{example['id']}: invalid exact power example")
            base = decimal.Decimal(operands[0])
            exponent = int(operands[1])
            actual = base**exponent
            if str(actual) != example["result"] or flags:
                raise ValueError(f"{example['id']}: exact power result/flags drift")
        elif primary == "clause-derived-special-case":
            values = [decimal.Decimal(item) for item in operands]
            derived = context_flags(operation, values, example["format"], context_factory)
            if derived != frozenset(flags):
                raise ValueError(f"{example['id']}: special-case flags drift")
    return len(examples)


def _command_from_env(name: str) -> list[str] | None:
    value = os.environ.get(name, "").strip()
    if not value:
        return None
    command = value.split()
    if not command:
        return None
    if shutil.which(command[0]) is None and not Path(command[0]).is_file():
        return None
    return command


def probe() -> dict[str, dict[str, Any]]:
    libmpdec_version = getattr(decimal, "__libmpdec_version__", None)
    return {
        "intel-rdfp": {
            "available": _command_from_env("DECIMAL_RDFP_ORACLE") is not None,
            "commandEnv": "DECIMAL_RDFP_ORACLE",
        },
        "libmpdec-allcr1": {
            "available": libmpdec_version is not None,
            "version": libmpdec_version,
            "rounding": "nearest-even",
            "allcr": 1,
        },
        "arb": {
            "available": _command_from_env("DECIMAL_ARB_ORACLE") is not None,
            "commandEnv": "DECIMAL_ARB_ORACLE",
        },
        "mpfr": {
            "available": _command_from_env("DECIMAL_MPFR_ORACLE") is not None,
            "commandEnv": "DECIMAL_MPFR_ORACLE",
        },
        "exact-gmp-rational": {
            "available": True,
            "implementation": "Python arbitrary-precision integer/rational arithmetic",
        },
    }


def special_case_flags(operation: str, operands: list[decimal.Decimal]) -> frozenset[str]:
    flags: set[str] = set()
    if any(value.is_snan() for value in operands):
        flags.add("InvalidOperation")
    if operation in {"divide", "remainder"} and len(operands) >= 2:
        lhs, rhs = operands[:2]
        if rhs.is_zero() and not lhs.is_nan() and not lhs.is_infinite():
            flags.add("DivisionByZero" if operation == "divide" else "InvalidOperation")
    if operation in {"sqrt", "ln", "log10", "log", "powr"} and operands:
        if operands[0].is_finite() and operands[0] < 0:
            flags.add("InvalidOperation")
    return frozenset(flags)


def context_flags(
    operation: str,
    operands: list[decimal.Decimal],
    format_name: str,
    context_factory: Any,
) -> frozenset[str]:
    context = context_factory(format_name)
    with decimal.localcontext(context) as active:
        active.clear_flags()
        for signal in active.traps:
            active.traps[signal] = False
        if operation == "add":
            active.add(*operands[:2])
        elif operation == "subtract":
            active.subtract(*operands[:2])
        elif operation == "multiply":
            active.multiply(*operands[:2])
        elif operation == "divide":
            active.divide(*operands[:2])
        elif operation == "sqrt":
            active.sqrt(operands[0])
        elif operation == "remainder":
            active.remainder(*operands[:2])
        else:
            raise ValueError(f"context flag operation is unsupported: {operation}")
        flags = {signal.__name__ for signal, raised in active.flags.items() if raised}
    return frozenset(flags) | special_case_flags(operation, operands)


def libmpdec_unary(
    operation: str,
    operand: str,
    format_name: str,
    context_factory: Any,
) -> OracleResult:
    context = context_factory(format_name)
    with decimal.localcontext(context) as active:
        active.clear_flags()
        for signal in active.traps:
            active.traps[signal] = False
        value = decimal.Decimal(operand)
        if operation == "exp":
            actual = active.exp(value)
        elif operation == "ln":
            actual = active.ln(value)
        elif operation == "log10":
            actual = active.log10(value)
        else:
            raise ValueError(f"libmpdec unary operation is unsupported: {operation}")
        flags = {signal.__name__ for signal, raised in active.flags.items() if raised}
    flags.update(special_case_flags(operation, [value]))
    return OracleResult(str(actual), None, frozenset(flags), f"libmpdec-{decimal.__libmpdec_version__}-allcr1")


def external_json_line(command: list[str], request: dict[str, Any]) -> OracleResult:
    process = subprocess.run(
        command,
        input=json.dumps(request) + "\n",
        text=True,
        capture_output=True,
        check=False,
    )
    if process.returncode:
        raise RuntimeError(f"oracle command failed ({process.returncode}): {process.stderr.strip()}")
    try:
        response = json.loads(process.stdout.strip())
    except json.JSONDecodeError as error:
        raise RuntimeError(f"oracle command returned invalid JSON: {process.stdout!r}") from error
    if not isinstance(response, dict):
        raise RuntimeError("oracle response must be an object")
    flags = response.get("flags", [])
    if not isinstance(flags, list) or not all(isinstance(item, str) for item in flags):
        raise RuntimeError("oracle response flags must be a string array")
    return OracleResult(
        response.get("value"),
        response.get("bits"),
        frozenset(flags),
        str(response.get("source", command[0])),
    )
