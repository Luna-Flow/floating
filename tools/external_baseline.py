#!/usr/bin/env python3
"""External performance baseline: floating against MPFR and libmpdec (issue #20).

One seeded generator writes the operands to a file that both sides read: the C
harness (tools/external_baseline.c, MPFR for binary and libmpdec for `decimal_gda`)
and the floating benchmarks (tooling/src/bench/external, run by Maremark on native in
release mode).  The runner alternates the two sides in seeded AB/BA order over
several rounds, collects raw JSONL, and reduces it to median ns per operation
with two-level bootstrap intervals and floating/reference ratios.

Pure functions (generation, planning, statistics, reduction, rendering) are
separated from the process execution at the bottom of the file.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import platform
import random
import shutil
import subprocess
import sys
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Callable, Iterable, Sequence

REPO_ROOT = Path(__file__).resolve().parents[1]
C_SOURCE = REPO_ROOT / "tools" / "external_baseline.c"
DEFAULT_OUT = REPO_ROOT / ".tmp" / "external"
SUMMARY_DIR = REPO_ROOT / "testdata" / "external_baseline"
EVENT_MARKER = "MAREMARK_JSONL="

SCHEMA = "external-baseline-v1"
INPUT_SEED = 20261118
OPERANDS_PER_CASE = 8

BINARY_OPS: tuple[str, ...] = ("add", "mul", "div", "sqrt", "exp", "ln", "sin")
DECIMAL_OPS: tuple[str, ...] = ("add", "mul", "div", "sqrt", "exp", "ln")
BINARY_PRECISIONS: tuple[int, ...] = (53, 128, 512, 2048, 8192)
DECIMAL_DIGITS: tuple[int, ...] = (16, 34, 100, 1000)
# The "null" operation runs floating's timed loop without arithmetic: it
# measures what the harness itself costs per pass, so it can be read off.
OVERHEAD_CASES: tuple[tuple[str, int], ...] = (("binary", 53), ("decimal_gda", 16))

REFERENCE_TOOL = {"binary": "mpfr", "decimal_gda": "libmpdec"}


# ---------------------------------------------------------------------------
# Cases and protocol
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class Case:
    kind: str  # "binary" or "decimal_gda"
    op: str
    size: int  # bits or decimal digits

    @property
    def id(self) -> str:
        return f"{self.kind}/{self.op}/{self.size}"

    @staticmethod
    def parse(text: str) -> "Case":
        kind, op, size = text.split("/")
        return Case(kind, op, int(size))


def benchmark_cases(
    binary_precisions: Sequence[int] = BINARY_PRECISIONS,
    decimal_digits: Sequence[int] = DECIMAL_DIGITS,
    ops: Sequence[str] | None = None,
) -> list[Case]:
    """The measured cases, binary first, then decimal; `ops` filters by name."""
    wanted = None if ops is None else set(ops)
    cases = [
        Case("binary", op, bits)
        for op in BINARY_OPS
        for bits in binary_precisions
        if wanted is None or op in wanted
    ]
    cases += [
        Case("decimal_gda", op, digits)
        for op in DECIMAL_OPS
        for digits in decimal_digits
        if wanted is None or op in wanted
    ]
    return cases


def overhead_cases(cases: Sequence[Case]) -> list[Case]:
    kinds = {case.kind for case in cases}
    return [Case(kind, "null", size) for kind, size in OVERHEAD_CASES if kind in kinds]


@dataclass(frozen=True)
class Protocol:
    """The Maremark protocol, handed unchanged to both sides."""

    warmup_iterations: int
    warmup_time_us: float
    target_batch_time_us: float
    min_batch_iterations: int
    max_batch_iterations: int
    max_sample_time_us: float
    exploratory: int
    confirmatory: int
    rounds: int
    resamples: int


PRESETS: dict[str, Protocol] = {
    # Reported numbers: 7 AB/BA rounds of 12 confirmatory blocks of ~20 ms.
    "standard": Protocol(3, 5000.0, 20000.0, 1, 1000000, 500000.0, 3, 12, 7, 2000),
    # A smoke run: enough to exercise every path, not to publish.
    "quick": Protocol(1, 1000.0, 3000.0, 1, 1000000, 100000.0, 1, 4, 2, 200),
}


def c_protocol_args(protocol: Protocol) -> list[str]:
    return [
        "--warmup-iterations", str(protocol.warmup_iterations),
        "--warmup-time-us", repr(protocol.warmup_time_us),
        "--target-batch-us", repr(protocol.target_batch_time_us),
        "--min-batch-iterations", str(protocol.min_batch_iterations),
        "--max-batch-iterations", str(protocol.max_batch_iterations),
        "--max-sample-us", repr(protocol.max_sample_time_us),
        "--exploratory", str(protocol.exploratory),
        "--confirmatory", str(protocol.confirmatory),
    ]  # fmt: skip


def moon_protocol_env(protocol: Protocol) -> dict[str, str]:
    return {
        "EXTBENCH_WARMUP_ITERATIONS": str(protocol.warmup_iterations),
        "EXTBENCH_WARMUP_US": repr(protocol.warmup_time_us),
        "EXTBENCH_TARGET_BATCH_US": repr(protocol.target_batch_time_us),
        "EXTBENCH_MIN_BATCH": str(protocol.min_batch_iterations),
        "EXTBENCH_MAX_BATCH": str(protocol.max_batch_iterations),
        "EXTBENCH_MAX_SAMPLE_US": repr(protocol.max_sample_time_us),
        "EXTBENCH_EXPLORATORY": str(protocol.exploratory),
        "EXTBENCH_CONFIRMATORY": str(protocol.confirmatory),
    }


# ---------------------------------------------------------------------------
# Input generation (pure)
# ---------------------------------------------------------------------------

# Binary: exponent q of the leading bit of an operand (value in [2^q, 2^(q+1))),
# and whether the operand may be negative.  Decimal: the same with powers of ten.
_BINARY_RANGE: dict[str, tuple[int, int, bool]] = {
    "add": (-8, 8, True),
    "mul": (-8, 8, True),
    "div": (-8, 8, True),
    "sqrt": (-8, 8, False),
    "exp": (-2, 1, True),  # |x| in [0.25, 4)
    "ln": (-3, 3, False),
    "sin": (-2, 1, True),  # |x| in [0.25, 4)
    "null": (-8, 8, True),
}
_DECIMAL_RANGE: dict[str, tuple[int, int, bool]] = {
    "add": (-2, 2, True),
    "mul": (-2, 2, True),
    "div": (-2, 2, True),
    "sqrt": (-1, 2, False),
    "exp": (-1, 0, True),  # |x| in [0.1, 10)
    "ln": (-1, 2, False),
    "null": (-2, 2, True),
}
_BINARY_ARITY = {"add": 2, "mul": 2, "div": 2, "null": 2}
_DECIMAL_ARITY = {"add": 2, "mul": 2, "div": 2, "null": 2}


@dataclass(frozen=True)
class Row:
    kind: str
    op: str
    size: int
    index: int
    a: str
    b: str | None


def binary_operand(rng: random.Random, size: int, low: int, high: int, signed: bool) -> str:
    """An exact `size`-bit operand `±0x<mantissa>p<exp>` with leading-bit exponent in [low, high]."""
    mantissa = rng.getrandbits(size - 1) | (1 << (size - 1))
    leading = rng.randint(low, high)
    negative = signed and rng.random() < 0.5
    return f"{'-' if negative else ''}0x{mantissa:x}p{leading - (size - 1)}"


def decimal_operand(rng: random.Random, size: int, low: int, high: int, signed: bool) -> str:
    """An exact `size`-digit operand `±<coefficient>E<exp>` with decimal magnitude exponent in [low, high]."""
    coefficient = rng.randrange(10 ** (size - 1), 10**size)
    leading = rng.randint(low, high)
    negative = signed and rng.random() < 0.5
    return f"{'-' if negative else ''}{coefficient}E{leading - (size - 1)}"


def generate_rows(seed: int, count: int, cases: Iterable[Case]) -> list[Row]:
    """`count` operand rows per case; every case has its own seeded stream."""
    rows: list[Row] = []
    for case in cases:
        rng = random.Random(f"external-baseline:{seed}:{case.id}")
        if case.kind == "binary":
            low, high, signed = _BINARY_RANGE[case.op]
            operand, arity = binary_operand, _BINARY_ARITY.get(case.op, 1)
        else:
            low, high, signed = _DECIMAL_RANGE[case.op]
            operand, arity = decimal_operand, _DECIMAL_ARITY.get(case.op, 1)
        for index in range(count):
            a = operand(rng, case.size, low, high, signed)
            b = operand(rng, case.size, low, high, signed) if arity == 2 else None
            if case.op == "div" and b is not None and b.lstrip("-").startswith("0x0p"):
                raise AssertionError("zero divisor")  # unreachable: leading bit is set
            rows.append(Row(case.kind, case.op, case.size, index, a, b))
    return rows


def format_inputs(rows: Sequence[Row], seed: int, count: int) -> str:
    header = f"# external-baseline inputs v1 seed={seed} operands-per-case={count}\n"
    lines = [
        " ".join(
            [row.kind, row.op, str(row.size), str(row.index), row.a]
            + ([row.b] if row.b is not None else [])
        )
        for row in rows
    ]
    return header + "\n".join(lines) + "\n"


# ---------------------------------------------------------------------------
# Round planning (pure)
# ---------------------------------------------------------------------------

TOOLS = ("reference", "floating")


@dataclass(frozen=True)
class RoundPlan:
    index: int
    first: str  # which side runs first in this round
    case_order: tuple[str, ...]


def plan_rounds(seed: int, rounds: int, case_ids: Sequence[str]) -> list[RoundPlan]:
    """Seeded AB/BA: the first side alternates every round, case order is shuffled.

    The same shuffled case order is used by both sides within a round, so a
    drifting machine state shifts a case on both sides alike; across rounds
    each side runs first as often as second.
    """
    coin = random.Random(f"external-baseline-order:{seed}").randrange(2)
    plans = []
    for index in range(rounds):
        order = list(case_ids)
        random.Random(f"external-baseline-order:{seed}:{index}").shuffle(order)
        plans.append(RoundPlan(index, TOOLS[(index + coin) % 2], tuple(order)))
    return plans


# ---------------------------------------------------------------------------
# Statistics (pure)
# ---------------------------------------------------------------------------


def median(values: Sequence[float]) -> float:
    ordered = sorted(values)
    n = len(ordered)
    if n == 0:
        raise ValueError("median of no values")
    mid = n // 2
    return ordered[mid] if n % 2 else (ordered[mid - 1] + ordered[mid]) / 2.0


def percentile(sorted_values: Sequence[float], fraction: float) -> float:
    """Linear-interpolated percentile of an already sorted sequence."""
    if not sorted_values:
        raise ValueError("percentile of no values")
    position = fraction * (len(sorted_values) - 1)
    low = math.floor(position)
    high = math.ceil(position)
    weight = position - low
    return sorted_values[low] * (1.0 - weight) + sorted_values[high] * weight


def mad_pct(values: Sequence[float]) -> float:
    """Median absolute deviation as a percentage of the median."""
    centre = median(values)
    return 100.0 * median([abs(v - centre) for v in values]) / centre


# Samples of one cell on one side: round index -> ns/op of each confirmatory block.
Samples = dict[int, list[float]]


def pooled(samples: Samples, rounds: Sequence[int] | None = None) -> list[float]:
    keys = sorted(samples) if rounds is None else rounds
    return [value for key in keys for value in samples[key]]


def _resample(rng: random.Random, samples: Samples, chosen_rounds: Sequence[int]) -> list[float]:
    """Two-level bootstrap draw: the chosen rounds, then blocks within each."""
    values: list[float] = []
    for key in chosen_rounds:
        block = samples[key]
        values.extend(rng.choices(block, k=len(block)))
    return values


def bootstrap_median_ci(
    samples: Samples, seed: str, resamples: int, level: float = 0.95
) -> tuple[float, float]:
    """Seeded two-level percentile bootstrap interval of the pooled median."""
    rng = random.Random(seed)
    keys = sorted(samples)
    medians = sorted(
        median(_resample(rng, samples, rng.choices(keys, k=len(keys)))) for _ in range(resamples)
    )
    tail = (1.0 - level) / 2.0
    return percentile(medians, tail), percentile(medians, 1.0 - tail)


def bootstrap_ratio_ci(
    numerator: Samples,
    denominator: Samples,
    seed: str,
    resamples: int,
    level: float = 0.95,
) -> tuple[float, float]:
    """Interval of median(numerator) / median(denominator), paired by round.

    A replicate draws rounds with replacement once, for both sides, so slow
    round-to-round drift cancels in the ratio; blocks are resampled
    independently within each chosen round on each side.
    """
    common = sorted(set(numerator) & set(denominator))
    if not common:
        raise ValueError("no round has both sides")
    rng = random.Random(seed)
    ratios = []
    for _ in range(resamples):
        chosen = rng.choices(common, k=len(common))
        top = median(_resample(rng, numerator, chosen))
        bottom = median(_resample(rng, denominator, chosen))
        ratios.append(top / bottom)
    ratios.sort()
    tail = (1.0 - level) / 2.0
    return percentile(ratios, tail), percentile(ratios, 1.0 - tail)


@dataclass(frozen=True)
class CellStats:
    median_ns: float
    ci_low_ns: float
    ci_high_ns: float
    mad_pct: float
    round_spread_pct: float  # (max - min of round medians) / pooled median
    rounds: int
    blocks: int
    iterations: int  # calibrated batch size of the first round (passes per block)


def summarize(samples: Samples, seed: str, resamples: int, iterations: int) -> CellStats:
    values = pooled(samples)
    centre = median(values)
    round_medians = [median(block) for block in samples.values()]
    low, high = bootstrap_median_ci(samples, seed, resamples)
    return CellStats(
        median_ns=centre,
        ci_low_ns=low,
        ci_high_ns=high,
        mad_pct=mad_pct(values),
        round_spread_pct=100.0 * (max(round_medians) - min(round_medians)) / centre,
        rounds=len(samples),
        blocks=len(values),
        iterations=iterations,
    )


NOISY_CI_PCT = 5.0  # half-width of the median CI as a share of the median
NOISY_SPREAD_PCT = 10.0  # spread between round medians as a share of the median


def is_noisy(stats: CellStats) -> bool:
    half_width = (stats.ci_high_ns - stats.ci_low_ns) / 2.0
    return (
        100.0 * half_width / stats.median_ns > NOISY_CI_PCT
        or stats.round_spread_pct > NOISY_SPREAD_PCT
    )


# ---------------------------------------------------------------------------
# JSONL reduction (pure)
# ---------------------------------------------------------------------------


@dataclass
class Collected:
    """Raw observations of both sides, keyed by case id."""

    reference: dict[str, Samples] = field(default_factory=dict)
    floating: dict[str, Samples] = field(default_factory=dict)
    reference_iterations: dict[str, int] = field(default_factory=dict)
    floating_iterations: dict[str, int] = field(default_factory=dict)
    floating_validation: dict[str, tuple[int, int]] = field(default_factory=dict)  # passed, failed
    operands: int = OPERANDS_PER_CASE


def parse_jsonl(text: str, marker: str = "") -> list[dict[str, object]]:
    events = []
    for line in text.splitlines():
        if marker:
            index = line.find(marker)
            if index < 0:
                continue
            line = line[index + len(marker) :]
        line = line.strip()
        if not line.startswith("{"):
            continue
        events.append(json.loads(line))
    return events


def add_reference_events(collected: Collected, round_index: int, events: Iterable[dict[str, object]]) -> None:
    """C harness lines: ns/op of every confirmatory block."""
    for event in events:
        case = str(event["case"])
        if event["type"] == "calibration":
            collected.reference_iterations.setdefault(case, int(event["iterations"]))  # type: ignore[call-overload]
        elif event["type"] == "observation" and event["phase"] == "confirmatory":
            per_op = float(event["elapsed_us"]) * 1000.0 / (  # type: ignore[arg-type]
                int(event["iterations"]) * int(event["ops_per_iteration"])  # type: ignore[call-overload]
            )
            collected.reference.setdefault(case, {}).setdefault(round_index, []).append(per_op)


def _floating_case_id(event: dict[str, object]) -> str | None:
    """`kind/op/size` of a Maremark event of the floating side, from its case and scale text."""
    parts = str(event.get("case", "")).split("/")  # external/<kind>/<op>
    digits = "".join(ch for ch in str(event.get("scale", "")) if ch.isdigit())
    if len(parts) != 3 or parts[0] != "external" or not digits:
        return None
    return f"{parts[1]}/{parts[2]}/{digits}"


def add_floating_events(
    collected: Collected, round_index: int, events: Iterable[dict[str, object]]
) -> None:
    """Maremark lines.

    An observation's `elapsed_us` is the time of one iteration (one pass over
    the operand set), so ns per operation is `elapsed_us * 1000 / operands`.
    """
    for event in events:
        kind = event.get("type")
        case = _floating_case_id(event)
        if case is None:
            continue
        if kind == "observation":
            if event.get("valid") is False:
                raise ValueError(f"invalid floating observation in {case}")
            collected.floating_iterations.setdefault(case, int(event["iterations"]))  # type: ignore[call-overload]
            if event.get("phase") == "confirmatory":
                per_op = float(event["elapsed_us"]) * 1000.0 / collected.operands  # type: ignore[arg-type]
                collected.floating.setdefault(case, {}).setdefault(round_index, []).append(per_op)
        elif kind == "validation":
            passed, total = collected.floating_validation.get(case, (0, 0))
            collected.floating_validation[case] = (passed + (event.get("status") == "valid"), total + 1)


# ---------------------------------------------------------------------------
# Results (pure)
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class RatioStats:
    ratio: float
    ci_low: float
    ci_high: float


@dataclass(frozen=True)
class CaseResult:
    case: str
    kind: str
    op: str
    size: int
    reference_tool: str
    reference: CellStats
    floating: CellStats
    ratio: RatioStats
    noisy: bool


def reduce_results(collected: Collected, protocol: Protocol, seed: int) -> list[CaseResult]:
    results: list[CaseResult] = []
    for case_id in sorted(collected.floating, key=_case_sort_key):
        kind, op, size_text = case_id.split("/")
        if op == "null" or case_id not in collected.reference:
            continue
        floating_samples = collected.floating[case_id]
        reference_samples = collected.reference[case_id]
        tag = f"{seed}:{case_id}"
        floating = summarize(
            floating_samples, f"{tag}:floating", protocol.resamples,
            collected.floating_iterations.get(case_id, 0),
        )  # fmt: skip
        reference = summarize(
            reference_samples, f"{tag}:reference", protocol.resamples,
            collected.reference_iterations.get(case_id, 0),
        )  # fmt: skip
        low, high = bootstrap_ratio_ci(
            floating_samples, reference_samples, f"{tag}:ratio", protocol.resamples
        )
        results.append(
            CaseResult(
                case=case_id,
                kind=kind,
                op=op,
                size=int(size_text),
                reference_tool=REFERENCE_TOOL[kind],
                reference=reference,
                floating=floating,
                ratio=RatioStats(floating.median_ns / reference.median_ns, low, high),
                noisy=is_noisy(floating) or is_noisy(reference),
            )
        )
    return results


def overhead_results(collected: Collected, protocol: Protocol, seed: int) -> list[dict[str, object]]:
    rows = []
    for case_id, samples in sorted(collected.floating.items()):
        if case_id.split("/")[1] != "null":
            continue
        stats = summarize(samples, f"{seed}:{case_id}:floating", protocol.resamples, 0)
        rows.append({"case": case_id, "ns_per_op": stats.median_ns, "ci": [stats.ci_low_ns, stats.ci_high_ns]})
    return rows


def _case_sort_key(case_id: str) -> tuple[int, int, int]:
    kind, op, size = case_id.split("/")
    ops = BINARY_OPS if kind == "binary" else DECIMAL_OPS
    return (0 if kind == "binary" else 1, ops.index(op) if op in ops else len(ops), int(size))


# ---------------------------------------------------------------------------
# Rendering (pure)
# ---------------------------------------------------------------------------


def format_ns(value: float) -> str:
    """Median time with a unit that keeps three or four significant digits."""
    if value >= 1e9:
        return f"{value / 1e9:.3g} s"
    if value >= 1e6:
        return f"{value / 1e6:.3g} ms"
    if value >= 1e3:
        return f"{value / 1e3:.3g} us"
    return f"{value:.3g} ns"


def format_ratio(value: float) -> str:
    return f"{value:.2f}" if value < 100 else f"{value:.0f}"


def _table(kind: str, results: Sequence[CaseResult], cell: Callable[[CaseResult], str]) -> list[str]:
    selected = [r for r in results if r.kind == kind]
    sizes = sorted({r.size for r in selected})
    ops = sorted({r.op for r in selected}, key=lambda op: (BINARY_OPS if kind == "binary" else DECIMAL_OPS).index(op))
    unit = "bits" if kind == "binary" else "digits"
    lines = ["| op | " + " | ".join(f"{size} {unit}" for size in sizes) + " |"]
    lines.append("| --- | " + " | ".join("---:" for _ in sizes) + " |")
    by_key = {(r.op, r.size): r for r in selected}
    for op in ops:
        cells = [cell(by_key[(op, size)]) if (op, size) in by_key else "n/a" for size in sizes]
        lines.append(f"| {op} | " + " | ".join(cells) + " |")
    return lines


def _ratio_cell(result: CaseResult) -> str:
    mark = "\\*" if result.noisy else ""
    return (
        f"{format_ratio(result.ratio.ratio)}{mark}"
        f" [{format_ratio(result.ratio.ci_low)}, {format_ratio(result.ratio.ci_high)}]"
    )


def render_markdown(
    results: Sequence[CaseResult], overhead: Sequence[dict[str, object]] = ()
) -> str:
    """Ratio and absolute-time tables, one pair per domain, and the harness overhead."""
    out: list[str] = []
    titles = {
        "binary": ("Binary: floating `bin_float` against MPFR", "MPFR"),
        "decimal_gda": ("Decimal GDA: floating `decimal_gda` against libmpdec", "libmpdec"),
    }
    for kind, (title, library) in titles.items():
        if not any(r.kind == kind for r in results):
            continue
        out += [f"### {title}", ""]
        out += [f"Ratio floating / {library} (median time, 95% bootstrap interval; above 1 means floating is slower)", ""]
        out += _table(kind, results, _ratio_cell)
        out += ["", f"Median ns per operation, {library}", ""]
        out += _table(kind, results, lambda r: format_ns(r.reference.median_ns))
        out += ["", "Median ns per operation, floating", ""]
        out += _table(kind, results, lambda r: format_ns(r.floating.median_ns))
        out += [""]
    if overhead:
        out += ["### Harness overhead of the floating side", ""]
        out += ["| case | ns per operation (loop and result store only) |", "| --- | ---: |"]
        for row in overhead:
            low, high = row["ci"]  # type: ignore[misc]
            out.append(f"| `{row['case']}` | {format_ns(float(row['ns_per_op']))} [{format_ns(low)}, {format_ns(high)}] |")  # type: ignore[arg-type]
        out += [""]
    noisy = [r.case for r in results if r.noisy]
    if noisy:
        out += [
            "Cells marked with an asterisk exceeded a dispersion threshold "
            f"(CI half-width over {NOISY_CI_PCT:.0f}% of the median, or round medians spread by over "
            f"{NOISY_SPREAD_PCT:.0f}%): " + ", ".join(f"`{case}`" for case in noisy) + ".",
            "",
        ]
    return "\n".join(out)


def summary_document(
    results: Sequence[CaseResult],
    overhead: Sequence[dict[str, object]],
    meta: dict[str, object],
    protocol: Protocol,
) -> dict[str, object]:
    return {
        "schema": SCHEMA,
        "meta": meta,
        "protocol": asdict(protocol),
        "overhead_floating_ns_per_pass_op": list(overhead),
        "cases": [asdict(r) for r in results],
    }


@dataclass(frozen=True)
class Change:
    case: str
    old: float
    new: float
    verdict: str  # "slower", "faster" or "same"

    @property
    def change_pct(self) -> float:
        return 100.0 * (self.new / self.old - 1.0)


def compare_summaries(old: dict[str, object], new: dict[str, object]) -> list[Change]:
    """Compare the floating/reference ratios of two summaries, case by case.

    A case is "slower" (floating lost ground to the library) only when the 95%
    interval of the new ratio lies entirely above that of the old one, and
    "faster" when it lies entirely below; overlapping intervals are "same".
    """
    old_cases = {c["case"]: c["ratio"] for c in old["cases"]}  # type: ignore[index, union-attr]
    changes = []
    for case in new["cases"]:  # type: ignore[union-attr]
        before = old_cases.get(case["case"])
        if before is None:
            continue
        after = case["ratio"]
        if after["ci_low"] > before["ci_high"]:
            verdict = "slower"
        elif after["ci_high"] < before["ci_low"]:
            verdict = "faster"
        else:
            verdict = "same"
        changes.append(Change(case["case"], before["ratio"], after["ratio"], verdict))
    return changes


def render_changes(changes: Sequence[Change]) -> str:
    lines = ["| case | old ratio | new ratio | change | verdict |", "| --- | ---: | ---: | ---: | --- |"]
    for change in changes:
        lines.append(
            f"| `{change.case}` | {format_ratio(change.old)} | {format_ratio(change.new)} "
            f"| {change.change_pct:+.1f}% | {change.verdict} |"
        )
    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------------------
# Execution (impure)
# ---------------------------------------------------------------------------


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def capture(command: Sequence[str], **kwargs: object) -> str:
    try:
        completed = subprocess.run(
            list(command), text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False, **kwargs  # type: ignore[call-overload]
        )
    except OSError as error:
        return f"unavailable: {error}"
    return completed.stdout.strip()


QUIET_CPU_PCT = 150.0  # other processes may use at most 1.5 cores before a timed side starts
QUIET_POLLS = 3
QUIET_POLL_SECONDS = 5.0
QUIET_MAX_WAIT_SECONDS = 3600.0


def foreign_cpu_pct(process_rows: Iterable[tuple[int, int, float]], root: int) -> float:
    """Total %CPU of the processes that are not `root` or one of its descendants.

    Rows are `(pid, ppid, pcpu)`.  The gate uses it to tell whether something
    else is competing for the cores while a side is timed.
    """
    rows = list(process_rows)
    children: dict[int, list[int]] = {}
    for pid, ppid, _ in rows:
        children.setdefault(ppid, []).append(pid)
    own = {root}
    stack = [root]
    while stack:
        for child in children.get(stack.pop(), []):
            if child not in own:
                own.add(child)
                stack.append(child)
    return sum(pcpu for pid, _, pcpu in rows if pid not in own)


def sample_foreign_cpu() -> float:
    text = capture(["ps", "-Ao", "pid=,ppid=,pcpu="])
    rows = []
    for line in text.splitlines():
        parts = line.split()
        if len(parts) == 3:
            try:
                rows.append((int(parts[0]), int(parts[1]), float(parts[2])))
            except ValueError:
                continue
    return foreign_cpu_pct(rows, os.getpid())


def wait_until_quiet() -> float:
    """Block until other processes use little CPU for several polls; return the last sample.

    Gives up after QUIET_MAX_WAIT_SECONDS and measures anyway, with the busy
    sample recorded so the report can say so.
    """
    started = time.monotonic()
    quiet = 0
    sample = sample_foreign_cpu()
    while True:
        quiet = quiet + 1 if sample < QUIET_CPU_PCT else 0
        if quiet >= QUIET_POLLS or time.monotonic() - started > QUIET_MAX_WAIT_SECONDS:
            return sample
        time.sleep(QUIET_POLL_SECONDS)
        sample = sample_foreign_cpu()


def moon_environment() -> dict[str, str]:
    """The environment for moon: the stale /tmp/qed-moon-latest shadow is stripped from PATH."""
    env = dict(os.environ)
    entries = [p for p in env.get("PATH", "").split(os.pathsep) if "qed-moon-latest" not in p]
    env["PATH"] = os.pathsep.join(entries)
    return env


def moon_cc_flags() -> str:
    """The C compiler flags moon uses for the native release build of the floating side."""
    text = capture(
        ["moon", "test", "tooling/src/bench/external", "--release", "--include-skipped", "--target", "native", "--dry-run"],
        env=moon_environment(), cwd=REPO_ROOT,
    )  # fmt: skip
    for line in text.splitlines():
        if line.startswith("/usr/bin/cc") and " -c " in line and "external.internal_test.c" in line:
            flags = [t.strip("'") for t in line.split() if t.strip("'").startswith(("-O", "-f", "-W", "-D"))]
            return " ".join(flags)
    return "unknown"


def machine_description(c_info: dict[str, object], cc: str) -> dict[str, object]:
    system = platform.system()
    if system == "Darwin":
        cpu = capture(["sysctl", "-n", "machdep.cpu.brand_string"])
        memory = capture(["sysctl", "-n", "hw.memsize"])
        os_text = capture(["sw_vers", "-productVersion"])
        power = capture(["pmset", "-g", "batt"]).splitlines()[:1]
        perf = capture(["sysctl", "-n", "hw.perflevel0.logicalcpu", "hw.perflevel1.logicalcpu"]).split()
    else:
        cpu = next(
            (line.split(":", 1)[1].strip() for line in Path("/proc/cpuinfo").read_text().splitlines() if line.startswith("model name")),
            "unknown",
        ) if Path("/proc/cpuinfo").exists() else "unknown"
        memory = "unknown"
        os_text = platform.release()
        power = []
        perf = []
    env = moon_environment()
    moon = capture(["moon", "version"], env=env)
    moonc = capture(["moonc", "-v"], env=env)
    return {
        "cpu": cpu,
        "logical_cpus": os.cpu_count(),
        "performance_cores_efficiency_cores": perf,
        "memory_bytes": memory,
        "os": f"{system} {os_text}",
        "kernel": platform.release(),
        "power": power,
        "load_average_start": os.getloadavg(),
        "python": platform.python_version(),
        "cc": capture([cc, "--version"]).splitlines()[0] if shutil.which(cc) else "unavailable",
        "moon": moon.splitlines()[0] if moon else "unknown",
        "moonc": moonc.splitlines()[0] if moonc else "unknown",
        "libraries": c_info,
        "moon_native_cc_flags": moon_cc_flags(),
        "git_revision": capture(["git", "rev-parse", "HEAD"], cwd=REPO_ROOT),
        "git_dirty": bool(capture(["git", "status", "--porcelain", "--untracked-files=no"], cwd=REPO_ROOT)),
        "timestamp_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }


def build_harness(out_dir: Path, prefix: Path, cc: str, cflags: str) -> Path:
    binary = out_dir / "extbench"
    out_dir.mkdir(parents=True, exist_ok=True)
    flags = cflags.split()
    command = [
        cc, *flags, "-std=c11", "-Wall", "-Wextra",
        f"-DEXTBENCH_CFLAGS=\"{cflags}\"",
        f"-I{prefix / 'include'}", str(C_SOURCE), "-o", str(binary),
        f"-L{prefix / 'lib'}", f"-Wl,-rpath,{prefix / 'lib'}",
        "-lmpfr", "-lgmp", "-lmpdec",
    ]  # fmt: skip
    completed = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False)
    if completed.returncode != 0:
        raise RuntimeError(f"C harness build failed:\n{completed.stdout}")
    return binary


def moon_command(release: bool = True) -> list[str]:
    command = [
        "sh", "tools/run_moon_clean_exec.sh", "test", "tooling/src/bench/external",
        "--include-skipped", "--no-parallelize", "--target", "native",
        "--filter", "external baseline floating",
    ]  # fmt: skip
    if release:
        command.insert(4, "--release")
    return command


def run_floating(inputs: Path, reference: Path | None, cases: Sequence[str], protocol: Protocol, seed: int, round_index: int) -> str:
    env = moon_environment()
    env.update(moon_protocol_env(protocol))
    env["EXTBENCH_INPUTS"] = str(inputs)
    env["EXTBENCH_CASES"] = ",".join(cases)
    env["EXTBENCH_SEED"] = str(seed)
    env["EXTBENCH_ROUND"] = str(round_index)
    if reference is not None:
        env["EXTBENCH_REFERENCE"] = str(reference)
    completed = subprocess.run(
        moon_command(), cwd=REPO_ROOT, env=env, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False,
    )  # fmt: skip
    if completed.returncode != 0:
        raise RuntimeError(f"floating benchmark failed (round {round_index}):\n{completed.stdout[-4000:]}")
    return completed.stdout


def run_reference(binary: Path, inputs: Path, out: Path, cases: Sequence[str], protocol: Protocol, round_index: int) -> None:
    command = [str(binary), "time", "--inputs", str(inputs), "--out", str(out),
               "--cases", ",".join(cases), "--round", str(round_index), *c_protocol_args(protocol)]  # fmt: skip
    completed = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False)
    if completed.returncode != 0:
        raise RuntimeError(f"C harness failed (round {round_index}):\n{completed.stdout}")


def selected_cases(args: argparse.Namespace) -> list[Case]:
    return benchmark_cases(args.binary_precisions, args.decimal_digits, args.ops)


def prepare_inputs(args: argparse.Namespace, out_dir: Path) -> tuple[Path, list[Case]]:
    cases = selected_cases(args)
    rows = generate_rows(args.input_seed, OPERANDS_PER_CASE, cases + overhead_cases(cases))
    inputs = out_dir / "inputs.txt"
    inputs.write_text(format_inputs(rows, args.input_seed, OPERANDS_PER_CASE), encoding="utf-8")
    return inputs, cases


def command_gen(args: argparse.Namespace) -> int:
    out_dir = args.out
    out_dir.mkdir(parents=True, exist_ok=True)
    inputs, cases = prepare_inputs(args, out_dir)
    print(f"{len(cases)} cases, {OPERANDS_PER_CASE} operand sets each: {inputs} sha256={sha256_file(inputs)[:16]}")
    return 0


def command_run(args: argparse.Namespace) -> int:
    protocol = PRESETS[args.preset]
    if args.rounds is not None:
        protocol = Protocol(**{**asdict(protocol), "rounds": args.rounds})
    out_dir: Path = args.out
    out_dir.mkdir(parents=True, exist_ok=True)
    if not args.resume:
        for stale in out_dir.glob("round-*"):
            shutil.rmtree(stale)
    binary = build_harness(out_dir, args.prefix, args.cc, args.cflags)
    info = json.loads(capture([str(binary), "info"]))
    inputs, cases = prepare_inputs(args, out_dir)
    case_ids = [c.id for c in cases]
    overhead_ids = [c.id for c in overhead_cases(cases)]
    # Reference results (MPFR / libmpdec) are the oracle the floating side is validated against.
    reference = out_dir / "reference.txt"
    completed = subprocess.run(
        [str(binary), "reference", "--inputs", str(inputs), "--out", str(reference)],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False,
    )  # fmt: skip
    if completed.returncode != 0:
        raise RuntimeError(f"reference run failed:\n{completed.stdout}")
    meta = machine_description(info, args.cc)
    meta.update({
        "input_seed": args.input_seed,
        "order_seed": args.seed,
        "inputs_sha256": sha256_file(inputs),
        "reference_sha256": sha256_file(reference),
        "operands_per_case": OPERANDS_PER_CASE,
        "preset": args.preset,
        "c_flags": args.cflags,
    })  # fmt: skip
    (out_dir / "machine.json").write_text(json.dumps(meta, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    collected = Collected()
    plans = plan_rounds(args.seed, protocol.rounds, case_ids + overhead_ids)
    contention: list[dict[str, object]] = []
    for plan in plans:
        round_dir = out_dir / f"round-{plan.index}"
        round_dir.mkdir(exist_ok=True)
        c_order = [case for case in plan.case_order if case in case_ids]
        for side in (plan.first, "floating" if plan.first == "reference" else "reference"):
            started = time.monotonic()
            if not args.no_gate and not args.resume:
                before = wait_until_quiet()
                if before >= QUIET_CPU_PCT:
                    print(f"WARNING: machine still busy ({before:.0f}% other CPU) before round {plan.index} {side}")
            else:
                before = -1.0
            if side == "reference":
                path = round_dir / "reference.jsonl"
                if not (args.resume and path.exists()):
                    run_reference(binary, inputs, path, c_order, protocol, plan.index)
                add_reference_events(collected, plan.index, parse_jsonl(path.read_text(encoding="utf-8")))
            else:
                log = round_dir / "floating.log"
                jsonl = round_dir / "floating.jsonl"
                if not (args.resume and jsonl.exists() and log.exists()):
                    output = run_floating(inputs, reference, list(plan.case_order), protocol, args.seed, plan.index)
                    log.write_text(output, encoding="utf-8")
                    events = parse_jsonl(output, EVENT_MARKER)
                    jsonl.write_text("".join(json.dumps(e, sort_keys=True) + "\n" for e in events), encoding="utf-8")
                add_floating_events(collected, plan.index, parse_jsonl(jsonl.read_text(encoding="utf-8")))
                failed = [line for line in log.read_text(encoding="utf-8").splitlines() if line.startswith("EXTBENCH_FAILED=")]
                if failed and failed[-1] != "EXTBENCH_FAILED=0":
                    print(f"WARNING: floating output differs from the reference in round {plan.index}: see {log}")
            contention.append({"round": plan.index, "side": side, "other_cpu_pct_before": before, "other_cpu_pct_after": sample_foreign_cpu()})
            print(f"round {plan.index} {side}: {time.monotonic() - started:.0f} s, other CPU {contention[-1]['other_cpu_pct_after']:.0f}%", flush=True)
    meta["contention"] = contention
    meta["load_average_end"] = os.getloadavg()
    if platform.system() == "Darwin":
        meta["power_end"] = capture(["pmset", "-g", "batt"]).splitlines()[:1]
    (out_dir / "machine.json").write_text(json.dumps(meta, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return finish(collected, protocol, args.seed, meta, out_dir)


# ---------------------------------------------------------------------------
# Quick check (floating side only, against the stored reference medians)
# ---------------------------------------------------------------------------

STORED_SUMMARY = SUMMARY_DIR / "summary-0.10.2.json"
QUICK_TARGET_RATIO = 10.0


def stored_medians(summary: dict[str, object]) -> dict[str, tuple[float, float]]:
    """`case id -> (reference median ns, floating median ns)` of a published summary."""
    medians: dict[str, tuple[float, float]] = {}
    for entry in summary["cases"]:  # type: ignore[attr-defined]
        medians[str(entry["case"])] = (
            float(entry["reference"]["median_ns"]),
            float(entry["floating"]["median_ns"]),
        )
    return medians


def quick_rows(
    floating: dict[str, float], stored: dict[str, tuple[float, float]], target: float
) -> list[list[str]]:
    """Table rows `case, floating ns, reference ns, ratio, ratio of the stored run, flag`."""
    rows = []
    for case_id in sorted(floating, key=_case_sort_key):
        if case_id not in stored:
            continue
        reference_ns, stored_floating_ns = stored[case_id]
        ratio = floating[case_id] / reference_ns
        before = stored_floating_ns / reference_ns
        rows.append([
            case_id, format_ns(floating[case_id]), format_ns(reference_ns),
            f"{ratio:.1f}", f"{before:.1f}", ">" + f"{target:g}x" if ratio > target else "ok",
        ])  # fmt: skip
    return rows


def render_quick(rows: Sequence[Sequence[str]]) -> str:
    header = ["case", "floating", "reference (stored)", "ratio", "ratio (stored run)", f"vs {QUICK_TARGET_RATIO:g}x"]
    table = [header, *rows]
    widths = [max(len(row[i]) for row in table) for i in range(len(header))]
    return "\n".join(
        "  ".join(cell.ljust(widths[i]) if i == 0 else cell.rjust(widths[i]) for i, cell in enumerate(row))
        for row in table
    )


def floating_medians(collected: Collected) -> dict[str, float]:
    return {
        case: median(pooled(samples))
        for case, samples in collected.floating.items()
        if not case.split("/")[1] == "null"
    }


def command_quick(args: argparse.Namespace) -> int:
    """Floating side only: a few rounds, the reference medians come from a stored summary.

    The MPFR and libmpdec medians do not change between runs, so this skips the C
    harness and the quiet-machine gate. The numbers are for finding gaps and for
    paired comparisons of two builds, not for publishing: the machine state of
    the stored run differs from today's.
    """
    protocol = PRESETS["quick"]
    protocol = Protocol(**{**asdict(protocol), "rounds": args.rounds})
    stored = stored_medians(json.loads(args.stored.read_text(encoding="utf-8")))
    out_dir: Path = args.out
    out_dir.mkdir(parents=True, exist_ok=True)
    inputs, cases = prepare_inputs(args, out_dir)
    case_ids = [c.id for c in cases]
    collected = Collected()
    for round_index in range(protocol.rounds):
        output = run_floating(inputs, None, case_ids, protocol, args.seed, round_index)
        (out_dir / f"quick-round-{round_index}.log").write_text(output, encoding="utf-8")
        add_floating_events(collected, round_index, parse_jsonl(output, EVENT_MARKER))
        print(f"round {round_index} done", flush=True)
    rows = quick_rows(floating_medians(collected), stored, args.target)
    print(render_quick(rows))
    if args.json is not None:
        args.json.write_text(json.dumps({row[0]: row[1:] for row in rows}, indent=1) + "\n", encoding="utf-8")
    return 0


def finish(collected: Collected, protocol: Protocol, seed: int, meta: dict[str, object], out_dir: Path) -> int:
    results = reduce_results(collected, protocol, seed)
    overhead = overhead_results(collected, protocol, seed)
    document = summary_document(results, overhead, meta, protocol)
    validation = {case: list(counts) for case, counts in sorted(collected.floating_validation.items())}
    document["validation_valid_total_per_case_all_rounds"] = validation
    invalid = [case for case, (valid, total) in collected.floating_validation.items() if valid != total]
    document["validation_failed_cases"] = sorted(invalid)
    if invalid:
        print("WARNING: floating differs from the MPFR/libmpdec reference in: " + ", ".join(sorted(invalid)))
    (out_dir / "results.json").write_text(json.dumps(document, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    markdown = render_markdown(results, overhead)
    (out_dir / "results.md").write_text(markdown, encoding="utf-8")
    print(markdown)
    print(f"summary: {out_dir / 'results.json'}")
    return 0


def command_report(args: argparse.Namespace) -> int:
    """Re-reduce the raw rounds of an earlier run without measuring again."""
    out_dir: Path = args.out
    meta = json.loads((out_dir / "machine.json").read_text(encoding="utf-8"))
    preset = PRESETS[meta["preset"]]
    protocol = Protocol(**{**asdict(preset), "rounds": len(list(out_dir.glob("round-*")))})
    collected = Collected()
    for round_dir in sorted(out_dir.glob("round-*"), key=lambda p: int(p.name.split("-")[1])):
        index = int(round_dir.name.split("-")[1])
        add_reference_events(collected, index, parse_jsonl((round_dir / "reference.jsonl").read_text(encoding="utf-8")))
        add_floating_events(collected, index, parse_jsonl((round_dir / "floating.jsonl").read_text(encoding="utf-8")))
    return finish(collected, protocol, int(meta["order_seed"]), meta, out_dir)


def module_version() -> str:
    for line in (REPO_ROOT / "library" / "moon.mod").read_text(encoding="utf-8").splitlines():
        if line.startswith("version"):
            return line.split("=", 1)[1].strip().strip('"')
    raise RuntimeError("moon.mod declares no version")


def command_publish(args: argparse.Namespace) -> int:
    """Copy the summary of a run into testdata/ (raw JSONL stays in .tmp).

    One `summary-<version>.json` is kept per release, so the ratios can be
    tracked from release to release with `compare`; `summary.md` is the latest.
    The name follows `--version`, or the version of `library/moon.mod`: name the
    measured release explicitly when the manifest already carries the next one.
    The stored measurement of the latest published release (`STORED_SUMMARY`) keeps
    its name and content.
    """
    SUMMARY_DIR.mkdir(parents=True, exist_ok=True)
    document = json.loads((args.out / "results.json").read_text(encoding="utf-8"))
    raw = sorted(args.out.glob("round-*/*.jsonl")) + sorted(args.out.glob("round-*/*.log"))
    document["raw_sha256"] = {str(path.relative_to(args.out)): sha256_file(path) for path in raw}
    document["raw_bytes"] = sum(path.stat().st_size for path in raw)
    target = SUMMARY_DIR / f"summary-{args.version or module_version()}.json"
    target.write_text(json.dumps(document, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    (SUMMARY_DIR / "summary.md").write_text((args.out / "results.md").read_text(encoding="utf-8"), encoding="utf-8")
    print(f"published {target}")
    return 0


def command_compare(args: argparse.Namespace) -> int:
    """Print how the ratios of NEW moved against OLD."""
    old = json.loads(args.old.read_text(encoding="utf-8"))
    new = json.loads(args.new.read_text(encoding="utf-8"))
    changes = compare_summaries(old, new)
    print(render_changes(changes), end="")
    slower = [c.case for c in changes if c.verdict == "slower"]
    if slower:
        print("slower than the library by more than the intervals: " + ", ".join(slower))
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    def common(p: argparse.ArgumentParser) -> None:
        p.add_argument("--out", type=Path, default=DEFAULT_OUT, help="working directory for inputs and raw rounds")
        p.add_argument("--input-seed", type=int, default=INPUT_SEED)
        p.add_argument("--binary-precisions", type=int, nargs="+", default=list(BINARY_PRECISIONS))
        p.add_argument("--decimal-gda-digits", "--decimal-digits", dest="decimal_digits", type=int, nargs="+", default=list(DECIMAL_DIGITS))
        p.add_argument("--ops", nargs="+", default=None, help="restrict to these operation names")

    gen = sub.add_parser("gen", help="write the shared operand file")
    common(gen)
    gen.set_defaults(func=command_gen)

    run = sub.add_parser("run", help="build, validate, measure both sides, reduce")
    common(run)
    run.add_argument("--preset", choices=sorted(PRESETS), default="standard")
    run.add_argument("--rounds", type=int, default=None, help="override the preset's number of AB/BA rounds")
    run.add_argument("--seed", type=int, default=INPUT_SEED, help="seed of the round order and of the bootstrap")
    run.add_argument("--prefix", type=Path, default=Path(os.environ.get("EXTBENCH_PREFIX", "/opt/homebrew")),
                     help="prefix holding include/ and lib/ of MPFR, GMP and mpdecimal")  # fmt: skip
    run.add_argument("--no-gate", action="store_true", help="do not wait for a quiet machine before each timed side")
    run.add_argument("--resume", action="store_true", help="reuse finished sides of an interrupted run in --out")
    run.add_argument("--cc", default=os.environ.get("CC", "cc"))
    run.add_argument("--cflags", default=os.environ.get("EXTBENCH_CFLAGS", "-O2"))
    run.set_defaults(func=command_run)

    quick = sub.add_parser("quick", help="floating side only, against the stored reference medians")
    common(quick)
    quick.add_argument("--rounds", type=int, default=2)
    quick.add_argument("--seed", type=int, default=INPUT_SEED)
    quick.add_argument("--stored", type=Path, default=STORED_SUMMARY, help="published summary giving the reference medians")
    quick.add_argument("--target", type=float, default=QUICK_TARGET_RATIO, help="ratio above which a cell is flagged")
    quick.add_argument("--json", type=Path, default=None, help="also write the rows as JSON")
    quick.set_defaults(func=command_quick)

    report = sub.add_parser("report", help="reduce the raw rounds of an earlier run again")
    report.add_argument("--out", type=Path, default=DEFAULT_OUT)
    report.set_defaults(func=command_report)

    publish = sub.add_parser("publish", help="copy the summary of a run into testdata/external_baseline")
    publish.add_argument("--out", type=Path, default=DEFAULT_OUT)
    publish.add_argument("--version", help="release the run measures (default: the version of library/moon.mod)")
    publish.set_defaults(func=command_publish)

    compare = sub.add_parser("compare", help="compare the ratios of two published summaries")
    compare.add_argument("old", type=Path)
    compare.add_argument("new", type=Path)
    compare.set_defaults(func=command_compare)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main())
