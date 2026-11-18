"""Greedy minimization of failing random differential cases.

A failing case is shrunk by trying simpler variants of its precision, context,
operands and literals; a variant is kept when the library still disagrees with
the oracle. The oracle is asked again for every variant (the MPFR generator in
`eval` mode, or `generate_libmpdec_random.evaluate`), so a minimized row is
always a consistent oracle row, never a hand-edited one.
"""

from __future__ import annotations

import argparse
import dataclasses
import json
import re
import tempfile
from pathlib import Path
from typing import Iterator

import generate_libmpdec_random as decimal_oracle
import random_differential as tool

MAX_ROUNDS = 400
BINARY_FIELDS = 13
HEX_VALUE = re.compile(r"^(-?)0x([0-9a-f]+)p(-?\d+)$")


# ----------------------------------------------------------------- binary ---


def shrink_precisions(precision: int) -> list[int]:
    candidates = [2, 3, 4, 5, 6, 8, 11, 16, 24, 32, 53, precision // 2, precision - 3, precision - 2, precision - 1]
    return sorted({c for c in candidates if 2 <= c < precision})


def shrink_hex(token: str) -> list[str]:
    match = HEX_VALUE.match(token)
    if match is None:
        return []
    sign, mantissa, exponent = match.group(1), int(match.group(2), 16), int(match.group(3))
    candidates: list[str] = []
    if sign:
        candidates.append(f"0x{mantissa:x}p{exponent}")
    bits = mantissa.bit_length()
    for keep in (1, 2, 3, 4, 8, bits // 2, bits - 8, bits - 4, bits - 1):
        if 1 <= keep < bits:
            shifted = mantissa >> (bits - keep)
            candidates.append(f"{sign}0x{shifted:x}p{exponent + bits - keep}")
    cleared = mantissa & ~((1 << max(bits // 2, 1)) - 1)
    if cleared and cleared != mantissa:
        candidates.append(f"{sign}0x{cleared:x}p{exponent}")
    if mantissa > 1:
        candidates.append(f"{sign}0x1p{exponent + bits - 1}")
    for target in (0, exponent // 2, exponent // 4):
        if target != exponent:
            candidates.append(f"{sign}0x{mantissa:x}p{target}")
    return [c for c in dict.fromkeys(candidates) if c != token]


def shrink_literal(literal: str) -> list[str]:
    match = re.match(r"^([+-]?)([0-9.]*)([eE]([+-]?\d+))?$", literal)
    if match is None:
        return []
    sign, mantissa, _, exponent = match.groups()
    candidates: list[str] = []
    if sign:
        candidates.append(literal[1:])
    figures = mantissa.replace(".", "")
    for keep in (1, 2, 3, 5, 10, len(figures) // 2, len(figures) - 1):
        if 1 <= keep < len(figures):
            candidates.append(f"{sign}{figures[:keep]}" + (f"e{exponent}" if exponent else ""))
    if exponent:
        value = int(exponent)
        for target in (0, value // 2, value // 10):
            if target != value:
                candidates.append(f"{sign}{mantissa}e{target}")
    return [c for c in dict.fromkeys(candidates) if c != literal]


def binary_candidates(tokens: list[str]) -> Iterator[list[str]]:
    op = tokens[1]
    if tokens[2] != "n":
        yield tokens[:2] + ["n"] + tokens[3:]
    for precision in shrink_precisions(int(tokens[3])):
        yield tokens[:3] + [str(precision)] + tokens[4:]
    if tokens[4] != "-":
        yield tokens[:4] + ["-", "-", "-"] + tokens[7:]
        if tokens[6] == "b":
            yield tokens[:6] + ["a"] + tokens[7:]
    if op == "strtofr":
        for literal in shrink_literal(tokens[7]):
            yield tokens[:7] + [literal] + tokens[8:]
    else:
        for index in (7, 8, 9):
            for value in shrink_hex(tokens[index]):
                yield tokens[:index] + [value] + tokens[index + 1:]
    n = int(tokens[10])
    for smaller in (n // 2, n - 1):
        if 0 < smaller < n and op in ("getstr", "rootn", "pown"):
            yield tokens[:10] + [str(smaller)] + tokens[11:]


def evaluate_binary(rows: list[list[str]]) -> list[str]:
    text = "\n".join(" ".join(row[:11] + ["?", "?"]) for row in rows) + "\n"
    result = tool.run_command([str(tool.GENERATOR_BINARY), "eval"], stdin=text)
    if result.returncode != 0:
        raise tool.ToolError("MPFR eval failed:\n" + result.stderr)
    return result.stdout.splitlines()


def failing_ids(target: str, kind: str, path: Path) -> set[str]:
    backend = "mpfr" if kind == "binary" else "gda"
    result = tool.run_command([*tool.conformance_cli(target), "--backend", backend, "--json", str(path)])
    if result.returncode not in (0, 1):
        raise tool.ToolError(result.stderr + result.stdout)
    payload = json.loads(result.stdout)
    ids = payload["failedIds"] if backend == "mpfr" else payload["execution"]["failedIds"]
    return set(ids)


def minimize_binary(row: str, target: str) -> list[str]:
    tokens = row.split()
    for _ in range(MAX_ROUNDS):
        candidates = list(binary_candidates(tokens))
        if not candidates:
            break
        labelled = []
        for index, candidate in enumerate(candidates):
            candidate = candidate[:]
            candidate[0] = f"{tokens[0]}.c{index}"
            labelled.append(candidate)
        rows = evaluate_binary(labelled)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "candidates.txt"
            path.write_text("# mpfr-random-v1 candidates\n" + "\n".join(rows) + "\n", encoding="utf-8")
            failures = failing_ids(target, "binary", path)
        chosen = next((r for r in rows if r.split()[0] in failures), None)
        if chosen is None:
            break
        new_tokens = chosen.split()
        new_tokens[0] = tokens[0]
        tokens = new_tokens
    return tokens


# ---------------------------------------------------------------- decimal ---


@dataclasses.dataclass
class DecimalCase:
    case: decimal_oracle.Case

    def candidates(self) -> Iterator[decimal_oracle.Case]:
        case = self.case
        context = case.context
        if context.rounding != "half_even":
            yield dataclasses.replace(case, context=dataclasses.replace(context, rounding="half_even"))
        if context.clamp:
            yield dataclasses.replace(case, context=dataclasses.replace(context, clamp=0))
        for precision in sorted({1, 2, 3, 4, 5, 7, 9, 16, context.precision // 2, context.precision - 1}):
            if 1 <= precision < context.precision:
                yield dataclasses.replace(case, context=dataclasses.replace(context, precision=precision))
        for emax in sorted({0, 1, 9, 99, 999, context.emax // 2, context.emax // 10}):
            if 0 <= emax < context.emax:
                yield dataclasses.replace(case, context=dataclasses.replace(context, emax=emax))
        for emin in sorted({0, -1, -9, -99, -999, context.emin // 2, context.emin // 10}, reverse=True):
            if context.emin < emin <= 0:
                yield dataclasses.replace(case, context=dataclasses.replace(context, emin=emin))
        for index, operand in enumerate(case.operands):
            for value in shrink_decimal(operand):
                operands = list(case.operands)
                operands[index] = value
                yield dataclasses.replace(case, operands=tuple(operands))


def shrink_decimal(text: str) -> list[str]:
    match = re.match(r"^([+-]?)(\d*)\.?(\d*)(?:[eE]([+-]?\d+))?$", text)
    if match is None:
        return []
    sign, whole, fraction, exponent = match.groups()
    figures = (whole + fraction).lstrip("0") or "0"
    scale = (int(exponent) if exponent else 0) - len(fraction)
    candidates: list[str] = []
    if sign:
        candidates.append(text.lstrip("+-"))
    for keep in (1, 2, 3, 5, 9, len(figures) // 2, len(figures) - 1):
        if 1 <= keep < len(figures):
            candidates.append(f"{sign}{figures[:keep]}E{scale + len(figures) - keep:+d}")
    for target in (0, scale // 2, scale // 10):
        if target != scale:
            candidates.append(f"{sign}{figures}E{target:+d}")
    candidates.append(f"{sign}1E{scale + len(figures) - 1:+d}")
    return [c for c in dict.fromkeys(candidates) if c != text]


def decimal_text(cases: list[decimal_oracle.Case]) -> str:
    lines = decimal_oracle.header("candidates", 0, 0, len(cases))
    for case in cases:
        lines.extend(decimal_oracle.format_row(decimal_oracle.evaluate(case)))
    return "\n".join(lines) + "\n"


def minimize_decimal(case: decimal_oracle.Case, target: str) -> decimal_oracle.Case:
    for _ in range(MAX_ROUNDS):
        candidates = [
            dataclasses.replace(candidate, case_id=f"{case.case_id}.c{index}")
            for index, candidate in enumerate(DecimalCase(case).candidates())
        ]
        if not candidates:
            break
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "candidates.decTest"
            path.write_text(decimal_text(candidates), encoding="utf-8")
            failures = failing_ids(target, "decimal", path)
        chosen = next((c for c in candidates if c.case_id in failures), None)
        if chosen is None:
            break
        case = dataclasses.replace(chosen, case_id=case.case_id)
    return case


# ------------------------------------------------------------------- main ---


def main(args: argparse.Namespace) -> int:
    cases = tool.expand_ids(args.ids)
    binary_out: list[str] = []
    decimal_out: list[str] = []
    for kind, seed, family, index in cases:
        if kind == "binary":
            tool.build_generator()
            result = tool.run_command([str(tool.GENERATOR_BINARY), family, str(seed), str(index), "1"])
            row = next(line for line in result.stdout.splitlines() if not line.startswith("#"))
            with tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / "row.txt"
                path.write_text("# mpfr-random-v1 minimize\n" + row + "\n", encoding="utf-8")
                if not failing_ids(args.target, "binary", path):
                    print(f"{row.split()[0]}: passes, nothing to minimize")
                    continue
            minimal = minimize_binary(row, args.target)
            binary_out.append(f"# minimized from {row.split()[0]}")
            binary_out.append(" ".join(minimal))
            print("minimized:", " ".join(minimal)[:400])
        else:
            name = family.removeprefix(tool.DECIMAL_PREFIX)
            case = decimal_oracle.generate_case(name, seed, index)
            with tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / "row.decTest"
                path.write_text(decimal_text([case]), encoding="utf-8")
                if not failing_ids(args.target, "decimal", path):
                    print(f"{case.case_id}: passes, nothing to minimize")
                    continue
            minimal_case = minimize_decimal(case, args.target)
            row = decimal_oracle.evaluate(minimal_case)
            decimal_out.append(f"-- minimized from {case.case_id}")
            decimal_out.extend(decimal_oracle.format_row(row))
            print("minimized:", " | ".join(decimal_oracle.format_row(row)))
    if args.output:
        output = Path(args.output)
        lines = binary_out or decimal_out
        if lines:
            with output.open("a", encoding="utf-8") as stream:
                stream.write("\n".join(lines) + "\n")
    return 0
