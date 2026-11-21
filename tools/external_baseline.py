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
import re
import shutil
import subprocess
import sys
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any, Callable, Iterable, Sequence

import external_stats as stats

REPO_ROOT = Path(__file__).resolve().parents[1]
C_SOURCE = REPO_ROOT / "tools" / "external_baseline.c"
DEFAULT_OUT = REPO_ROOT / ".tmp" / "external"
SUMMARY_DIR = REPO_ROOT / "testdata" / "external_baseline"
EVENT_MARKER = "MAREMARK_JSONL="

SCHEMA_V1 = "external-baseline-v1"
SCHEMA = "external-baseline-v2"
INPUT_SEED = 20261118
OPERANDS_PER_CASE = 8

BINARY_OPS: tuple[str, ...] = ("add", "mul", "div", "sqrt", "exp", "ln", "sin")
DECIMAL_OPS: tuple[str, ...] = ("add", "mul", "div", "sqrt", "exp", "ln")
BINARY_PRECISIONS: tuple[int, ...] = (53, 128, 512, 2048, 8192)
DECIMAL_DIGITS: tuple[int, ...] = (16, 34, 100, 1000)
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
}
_DECIMAL_RANGE: dict[str, tuple[int, int, bool]] = {
    "add": (-2, 2, True),
    "mul": (-2, 2, True),
    "div": (-2, 2, True),
    "sqrt": (-1, 2, False),
    "exp": (-1, 0, True),  # |x| in [0.1, 10)
    "ln": (-1, 2, False),
}
_BINARY_ARITY = {"add": 2, "mul": 2, "div": 2}
_DECIMAL_ARITY = {"add": 2, "mul": 2, "div": 2}


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
    # Pairs of a case block and its null block, per case id and round (confirmatory blocks only).
    reference_pairs: dict[str, stats.Pairs] = field(default_factory=dict)
    floating_pairs: dict[str, stats.Pairs] = field(default_factory=dict)
    operands: int = OPERANDS_PER_CASE
    # What the floating side said about its validation, per round ((state, detail)), and the
    # number of distinct operand sets per case; both empty when not known (a report from old samples).
    validation_status: dict[int, tuple[str, str]] = field(default_factory=dict)
    distinct_operands: dict[str, int] = field(default_factory=dict)


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


VALIDATED = "validated"
VALIDATION_FAILED = "failed"
NOT_VALIDATED = "not_validated"
VALIDATION_UNKNOWN = "unknown"


def floating_validation_status(log: str) -> tuple[str, str]:
    """What the floating side's own output says about its validation: `(state, detail)`.

    The benchmark prints `EXTBENCH_FAILED=<n>` only when every case was compared
    with a reference result, and `EXTBENCH_NOT_VALIDATED=<cases>` when some case
    had no reference (the library's own result stood in). A run without a
    reference is therefore never `validated`; a log with neither line (the run
    stopped early or the line was lost) is `unknown`, not `validated`.
    """
    lines = log.splitlines()
    not_validated = [line for line in lines if line.startswith("EXTBENCH_NOT_VALIDATED=")]
    if not_validated:
        return NOT_VALIDATED, not_validated[-1].split("=", 1)[1]
    failed = [line for line in lines if line.startswith("EXTBENCH_FAILED=")]
    if not failed:
        return VALIDATION_UNKNOWN, "no EXTBENCH_FAILED line"
    count = failed[-1].split("=", 1)[1]
    return (VALIDATED, "0") if count == "0" else (VALIDATION_FAILED, count)


def distinct_operand_counts(rows: Iterable[Row]) -> dict[str, int]:
    """Distinct operand sets per case id. The operand set of a case is the same in
    every round and every block, so the number of checks a case makes is this
    number, not the number of rounds or blocks."""
    seen: dict[str, set[tuple[str, str | None]]] = {}
    for row in rows:
        seen.setdefault(f"{row.kind}/{row.op}/{row.size}", set()).add((row.a, row.b))
    return {case: len(operands) for case, operands in seen.items()}


def validation_paragraph(validation: dict[str, object]) -> list[str]:
    """The sentences of the rendered page about what was checked and against what."""
    status = str(validation.get("status", VALIDATION_UNKNOWN))
    out: list[str] = []
    if status == VALIDATED:
        out.append(
            "Validation: every result of the floating side was compared, as canonical text (sign, "
            "significand and exponent; for decimal the coefficient with its trailing zeros), with the MPFR or "
            "libmpdec result for the same operands; the sign of zero, the decimal cohort, infinities and NaN are "
            "compared, and no reader of the library stands between the reference and the comparison."
        )
    elif status == NOT_VALIDATED:
        out.append("**NOT VALIDATED: no reference result was given for some cases (" + str(validation.get("detail", "")) + "); the results are the library compared with itself.**")
    elif status == VALIDATION_FAILED:
        out.append(f"**VALIDATION FAILED: {validation.get('detail', '?')} results differ from the reference.**")
    else:
        out.append(f"**Validation unknown: {validation.get('detail', 'the output carries no verdict')}.**")
    distinct = validation.get("distinct_operands_per_case")
    if isinstance(distinct, dict) and distinct:
        low, high = min(distinct.values()), max(distinct.values())
        span = f"{low}" if low == high else f"{low} to {high}"
        out.append(
            f"Each case checks {span} distinct operand sets. The same operands are timed in every round and block, "
            "so the rounds are repeats of one check, not further checks."
        )
    return out


def add_reference_events(collected: Collected, round_index: int, events: Iterable[dict[str, object]]) -> None:
    """C harness lines: ns/op of every confirmatory block.

    Each block of the harness is a pair, a `case` line and a `null` line with
    the same block number; the case lines alone give the raw samples, both
    together the pairs.
    """
    halves: dict[tuple[str, int], dict[str, float]] = {}
    null_first: dict[tuple[str, int], bool] = {}
    for event in events:
        case = str(event["case"])
        variant = str(event.get("variant", "case"))
        if event["type"] == "calibration":
            if variant == "case":
                collected.reference_iterations.setdefault(case, int(event["iterations"]))  # type: ignore[call-overload]
        elif event["type"] == "observation" and event["phase"] == "confirmatory":
            per_op = float(event["elapsed_us"]) * 1000.0 / (  # type: ignore[arg-type]
                int(event["iterations"]) * int(event["ops_per_iteration"])  # type: ignore[call-overload]
            )
            if variant == "case":
                collected.reference.setdefault(case, {}).setdefault(round_index, []).append(per_op)
            if "block" in event:
                key = (case, int(event["block"]))  # type: ignore[call-overload]
                halves.setdefault(key, {})[variant] = per_op
                if "null_first" in event:
                    null_first[key] = bool(event["null_first"])
    for key in sorted(halves, key=lambda k: (k[0], k[1])):
        half = halves[key]
        if "case" in half and "null" in half:
            collected.reference_pairs.setdefault(key[0], {}).setdefault(round_index, []).append(
                stats.Pair(half["case"], half["null"], null_first.get(key, False))
            )


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
    Each case runs two implementations, `floating` and its `null`, block by
    block; the order of the lines of one block says which ran first.
    """
    halves: dict[tuple[str, int], dict[str, float]] = {}
    first: dict[tuple[str, int], str] = {}
    for event in events:
        kind = event.get("type")
        case = _floating_case_id(event)
        if case is None:
            continue
        implementation = str(event.get("implementation", "floating"))
        if kind == "observation":
            if event.get("valid") is False:
                raise ValueError(f"invalid floating observation in {case}")
            if implementation == "floating":
                collected.floating_iterations.setdefault(case, int(event["iterations"]))  # type: ignore[call-overload]
            if event.get("phase") == "confirmatory":
                per_op = float(event["elapsed_us"]) * 1000.0 / collected.operands  # type: ignore[arg-type]
                if implementation == "floating":
                    collected.floating.setdefault(case, {}).setdefault(round_index, []).append(per_op)
                if "block_id" in event:
                    key = (case, int(event["block_id"]))  # type: ignore[call-overload]
                    halves.setdefault(key, {})[implementation] = per_op
                    first.setdefault(key, implementation)
        elif kind == "validation":
            passed, total = collected.floating_validation.get(case, (0, 0))
            collected.floating_validation[case] = (passed + (event.get("status") == "valid"), total + 1)
    for key in sorted(halves, key=lambda k: (k[0], k[1])):
        half = halves[key]
        if "floating" in half and "null" in half:
            collected.floating_pairs.setdefault(key[0], {}).setdefault(round_index, []).append(
                stats.Pair(half["floating"], half["null"], first[key] == "null")
            )


# ---------------------------------------------------------------------------
# Results (pure)
# ---------------------------------------------------------------------------

SCHEMA_SAMPLES = "external-baseline-samples-v1"
NULL_DEFINITION = "the case loop without the library call, v1"
DEFAULT_CONFIGURATION = "native"


@dataclass(frozen=True)
class RatioStats:
    ratio: float
    ci_low: float
    ci_high: float


@dataclass(frozen=True)
class NetStats:
    """Net time of one side: the median of the pair differences and its interval."""

    net_ns: float
    ci_low_ns: float
    ci_high_ns: float
    pairs: int
    drift_pct: float
    order_pct: float
    warm_pct: float


@dataclass(frozen=True)
class SideResult:
    raw: CellStats  # the case blocks alone, as in the 0.11.0 method
    null: CellStats  # the null blocks of the pairs
    net: NetStats


@dataclass(frozen=True)
class CaseResult:
    case: str
    kind: str
    op: str
    size: int
    reference_tool: str
    reference: SideResult
    floating: SideResult
    ratio_raw: RatioStats
    ratio_net: RatioStats
    status: str  # stats.MET, stats.TOLERATED, stats.NOT_MET, stats.UNRESOLVED, or stats.NOT_APPLICABLE where the criterion is not defined
    raw_status: str  # the verdict of the raw ratio's upper end; the verdict of an unresolved case
    borderline: bool
    reason: str
    drift: bool
    order: bool
    warm: bool
    noisy: bool


def pair_samples(pairs: stats.Pairs, null: bool) -> Samples:
    """The case blocks (or the null blocks) of the pairs, per round."""
    return {key: [pair.null_ns if null else pair.case_ns for pair in block] for key, block in pairs.items()}


def _side_result(
    pairs: stats.Pairs, iterations: int, seed: int, configuration: str, case_id: str, side: str, protocol: Protocol
) -> tuple[SideResult, stats.SideNet]:
    net = stats.side_net(pairs, seed, configuration, case_id, side, protocol.resamples)
    result = SideResult(
        raw=summarize(
            pair_samples(pairs, False), stats.derive_seed(seed, configuration, case_id, side, "raw"), protocol.resamples, iterations
        ),
        null=summarize(
            pair_samples(pairs, True), stats.derive_seed(seed, configuration, case_id, side, "null"), protocol.resamples, iterations
        ),
        net=NetStats(net.net_ns, net.ci_low_ns, net.ci_high_ns, net.pairs, net.drift_pct, net.order_pct, net.warm_pct),
    )
    return result, net


def reduce_results(
    collected: Collected,
    protocol: Protocol,
    seed: int,
    rules: stats.Rules = stats.Rules(),
    configuration: str = DEFAULT_CONFIGURATION,
    criterion_applies: bool = True,
) -> list[CaseResult]:
    results: list[CaseResult] = []
    for case_id in sorted(collected.floating, key=_case_sort_key):
        kind, op, size_text = case_id.split("/")
        if case_id not in collected.reference:
            continue
        if case_id not in collected.floating_pairs or case_id not in collected.reference_pairs:
            raise ValueError(f"{case_id} has no pairs of case and null blocks (rounds of an older harness?)")
        floating, floating_net = _side_result(
            collected.floating_pairs[case_id], collected.floating_iterations.get(case_id, 0), seed, configuration, case_id, "floating", protocol
        )
        reference, reference_net = _side_result(
            collected.reference_pairs[case_id], collected.reference_iterations.get(case_id, 0), seed, configuration, case_id, "reference", protocol
        )
        low, high = bootstrap_ratio_ci(
            collected.floating[case_id],
            collected.reference[case_id],
            stats.derive_seed(seed, configuration, case_id, "both", "raw-ratio"),
            protocol.resamples,
        )
        raw = RatioStats(floating.raw.median_ns / reference.raw.median_ns, low, high)
        verdict = stats.judge(floating_net, reference_net, high, rules, criterion_applies)
        results.append(
            CaseResult(
                case=case_id,
                kind=kind,
                op=op,
                size=int(size_text),
                reference_tool=REFERENCE_TOOL[kind],
                reference=reference,
                floating=floating,
                ratio_raw=raw,
                ratio_net=RatioStats(verdict.ratio, verdict.ci_low, verdict.ci_high),
                status=verdict.status,
                raw_status=verdict.raw_status,
                borderline=verdict.borderline,
                reason=verdict.reason,
                drift=verdict.drift,
                order=verdict.order,
                warm=verdict.warm,
                noisy=is_noisy(floating.raw) or is_noisy(reference.raw),
            )
        )
    return results


def _case_sort_key(case_id: str) -> tuple[int, int, int]:
    kind, op, size = case_id.split("/")
    ops = BINARY_OPS if kind == "binary" else DECIMAL_OPS
    return (0 if kind == "binary" else 1, ops.index(op) if op in ops else len(ops), int(size))


# ---------------------------------------------------------------------------
# Samples (pure): everything a summary is computed from
# ---------------------------------------------------------------------------


def samples_document(collected: Collected) -> dict[str, object]:
    """The pairs of every case, per side and round: `[case ns, null ns, null ran first]`.

    The raw medians, the net times, the intervals and the verdicts of a summary
    are functions of this document and of the protocol, so any summary can be
    recomputed from it (`recompute`).
    """
    cases: dict[str, object] = {}
    for case_id in sorted(collected.floating_pairs, key=_case_sort_key):
        if case_id not in collected.reference_pairs:
            continue
        entry: dict[str, object] = {}
        for side, pairs, iterations in (
            ("floating", collected.floating_pairs[case_id], collected.floating_iterations),
            ("reference", collected.reference_pairs[case_id], collected.reference_iterations),
        ):
            entry[side] = {
                "iterations": iterations.get(case_id, 0),
                "rounds": {
                    str(key): [[pair.case_ns, pair.null_ns, int(pair.null_first)] for pair in block]
                    for key, block in sorted(pairs.items())
                },
            }
        cases[case_id] = entry
    return {"schema": SCHEMA_SAMPLES, "operands": collected.operands, "cases": cases}


def load_samples(document: dict[str, object]) -> Collected:
    """The inverse of `samples_document`."""
    if document.get("schema") != SCHEMA_SAMPLES:
        raise ValueError(f"not a samples document: {document.get('schema')!r}")
    collected = Collected(operands=int(document["operands"]))  # type: ignore[call-overload]
    for case_id, entry in document["cases"].items():  # type: ignore[attr-defined]
        for side in ("floating", "reference"):
            data = entry[side]
            pairs: stats.Pairs = {
                int(key): [stats.Pair(float(a), float(b), bool(c)) for a, b, c in block]
                for key, block in data["rounds"].items()
            }
            if side == "floating":
                collected.floating_pairs[case_id] = pairs
                collected.floating[case_id] = pair_samples(pairs, False)
                collected.floating_iterations[case_id] = int(data["iterations"])
            else:
                collected.reference_pairs[case_id] = pairs
                collected.reference[case_id] = pair_samples(pairs, False)
                collected.reference_iterations[case_id] = int(data["iterations"])
    return collected


def protocol_from_summary(document: dict[str, object]) -> tuple[Protocol, stats.Rules, int, str, bool]:
    """Protocol, rules, bootstrap seed, configuration and criterion flag of a v2 summary, to recompute it from its samples."""
    recorded = dict(document["protocol"])  # type: ignore[call-overload]
    protocol = Protocol(**{name: recorded[name] for name in Protocol.__dataclass_fields__})
    rules = stats.Rules(
        target=float(recorded["target_ratio"]),
        limit=float(recorded.get("limit_ratio", recorded["target_ratio"])),
        width_bound=float(recorded["width_bound"]),
        drift_pct=float(recorded["drift_pct"]),
        order_pct=float(recorded["order_pct"]),
        warm_pct=float(recorded["warm_pct"]),
        level=float(recorded["level"]),
    )
    return (
        protocol,
        rules,
        int(document["meta"]["order_seed"]),  # type: ignore[index]
        str(recorded["floating_configuration"]),
        bool(recorded["criterion_applies"]),
    )


def recompute(samples: dict[str, object], summary: dict[str, object]) -> list[CaseResult]:
    """The results of a published summary, recomputed from its samples document."""
    protocol, rules, seed, configuration, applies = protocol_from_summary(summary)
    return reduce_results(load_samples(samples), protocol, seed, rules, configuration, applies)


# ---------------------------------------------------------------------------
# Summary document (pure)
# ---------------------------------------------------------------------------


# The cases of the calibration experiment of the warm-up (design page): a fast case, a mid-size case, an
# elementary function and a decimal case.
WARMUP_CASES: tuple[str, ...] = ("binary/add/53", "binary/mul/512", "binary/ln/2048", "decimal_gda/add/34")
TARGETS: tuple[str, ...] = ("native", "wasm", "js")  # the `moon --target` values the floating side can be built for


JUDGED_REFERENCE = "reference"  # the net ratio of the floating side to the native reference process (MPFR, libmpdec)
JUDGED_NONE = "none"  # no criterion: the status of every case is not_applicable
JUDGED_KINDS: tuple[str, ...] = (JUDGED_REFERENCE, JUDGED_NONE)


@dataclass(frozen=True)
class Criterion:
    """What is judged for a configuration and against which bound."""

    judged: str
    target_ratio: float  # met: the upper end of the interval is at most this
    limit_ratio: float  # tolerated: above the target and at most this; equal to the target when there is no tolerated band

    def __post_init__(self) -> None:
        if self.judged not in JUDGED_KINDS:
            raise ValueError(f"criterion judges {self.judged!r}: one of {', '.join(JUDGED_KINDS)}")
        if not self.target_ratio > 0.0:
            raise ValueError("the target ratio must be positive")
        if self.limit_ratio < self.target_ratio:
            raise ValueError("the limit ratio must be at least the target ratio")

    @property
    def applies(self) -> bool:
        return self.judged != JUDGED_NONE


# The one table of the criterion of every configuration (bounds as data). Maintainer, 2026-11-21: the native
# configurations meet the target when the upper end of the interval of the net ratio to the native reference is at
# most 3; `wasm` and `js` are expected within 5 and at most 10 (met up to 5, tolerated up to 10, not met above).
# Their ratio to `native-portable` stays a diagnostic with no verdict (design page). A row with `JUDGED_NONE` makes
# the status of every case `not_applicable`; no configuration has one today.
CRITERIA: dict[str, Criterion] = {
    "native": Criterion(JUDGED_REFERENCE, 3.0, 3.0),
    "native-portable": Criterion(JUDGED_REFERENCE, 3.0, 3.0),
    "wasm": Criterion(JUDGED_REFERENCE, 5.0, 10.0),
    "js": Criterion(JUDGED_REFERENCE, 5.0, 10.0),
}


def valid_target(name: str) -> str:
    if name not in TARGETS:
        raise ValueError(f"target {name!r}: one of {', '.join(TARGETS)} (wasm-gc is not supported: the module initialiser of the async dependency is rejected by the runtime)")
    return name


def criterion_for(configuration: str, target: str) -> Criterion:
    """The criterion of a configuration: its row of `CRITERIA`, else the row of its target (a custom name measured on `wasm` is judged like `wasm`)."""
    if configuration in CRITERIA:
        return CRITERIA[configuration]
    return CRITERIA[default_configuration(target)]


def default_configuration(target: str) -> str:
    """`native` for the native target, the target's name otherwise (`native-portable` is named explicitly)."""
    return DEFAULT_CONFIGURATION if valid_target(target) == "native" else target


def valid_configuration(name: str) -> str:
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]*", name):
        raise ValueError(f"configuration name {name!r}: lower-case letters, digits and hyphens only")
    return name


def summary_document(
    results: Sequence[CaseResult],
    meta: dict[str, object],
    protocol: Protocol,
    configuration: str = DEFAULT_CONFIGURATION,
    rules: stats.Rules = stats.Rules(),
    target: str = "native",
    criterion: Criterion | None = None,
) -> dict[str, object]:
    criterion = criterion or criterion_for(configuration, target)
    rules = stats.Rules(**{**asdict(rules), "target": criterion.target_ratio, "limit": criterion.limit_ratio})
    method: dict[str, object] = {
        "method": stats.METHOD_VERSION,
        "pairs_per_round": protocol.confirmatory,
        "target_ratio": rules.target,
        "limit_ratio": rules.tolerated_limit,
        "width_bound": rules.width_bound,
        "drift_pct": rules.drift_pct,
        "order_pct": rules.order_pct,
        "warm_pct": rules.warm_pct,
        "level": rules.level,
        "target": valid_target(target),
        "criterion_applies": criterion.applies,
        "criterion_judged": criterion.judged,
        "null_definition": NULL_DEFINITION,
        "floating_configuration": valid_configuration(configuration),
    }
    return {
        "schema": SCHEMA,
        "meta": meta,
        "protocol": {**asdict(protocol), **method},
        "cases": [asdict(r) for r in results],
    }


def summary_configuration(summary: dict[str, object]) -> str:
    """The configuration of the floating side a summary measured (`native` for a v1 summary)."""
    if summary.get("schema") == SCHEMA_V1:
        return DEFAULT_CONFIGURATION
    return str(summary["protocol"]["floating_configuration"])  # type: ignore[index]


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
    if math.isinf(value):
        return "inf"
    return f"{value:.2f}" if value < 100 else f"{value:.0f}"


def _table(kind: str, results: Sequence[Any], cell: Callable[[Any], str]) -> list[str]:
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


def _interval(ratio: RatioStats) -> str:
    return f"{format_ratio(ratio.ratio)} [{format_ratio(ratio.ci_low)}, {format_ratio(ratio.ci_high)}]"


def net_cell(result: CaseResult) -> str:
    """Net ratio with its interval and the verdict; an unresolved case shows its raw verdict instead."""
    flags = (" d" if result.drift else "") + (" o" if result.order else "") + (" w" if result.warm else "")
    if result.status == stats.NOT_APPLICABLE:
        return f"{_interval(result.ratio_net)}{flags}"
    if result.status == stats.UNRESOLVED:
        raw = {stats.MET: "met", stats.TOLERATED: "tolerated"}.get(result.raw_status, "not met")
        return f"unresolved, raw {format_ratio(result.ratio_raw.ratio)} {raw}{flags}"
    mark = {stats.MET: " met", stats.TOLERATED: " tolerated"}.get(result.status, "")
    if result.borderline:
        mark += " \\*"
    return f"{_interval(result.ratio_net)}{mark}{flags}"


def raw_cell(result: CaseResult) -> str:
    return _interval(result.ratio_raw) + ("\\*" if result.noisy else "")


def render_markdown(results: Sequence[CaseResult], protocol: dict[str, object] | None = None, validation: dict[str, object] | None = None) -> str:
    """Net ratio, raw ratio, net times and null times, one set of tables per domain."""
    target = float(protocol["target_ratio"]) if protocol else stats.TARGET_RATIO  # type: ignore[arg-type]
    limit = float(protocol.get("limit_ratio", target)) if protocol else target  # type: ignore[arg-type]
    applies = bool(protocol["criterion_applies"]) if protocol else True
    runtime = str(protocol["target"]) if protocol else "native"
    out: list[str] = []
    titles = {
        "binary": ("Binary: floating `binary` against MPFR", "MPFR"),
        "decimal_gda": ("Decimal GDA: floating `decimal_gda` against libmpdec", "libmpdec"),
    }
    met = sum(1 for r in results if r.status == stats.MET)
    tolerated = sum(1 for r in results if r.status == stats.TOLERATED)
    not_met = sum(1 for r in results if r.status == stats.NOT_MET)
    unresolved = [r for r in results if r.status == stats.UNRESOLVED]
    raw_within = sum(1 for r in unresolved if r.raw_status in (stats.MET, stats.TOLERATED))
    if applies:
        counts = (
            f"{met} of {len(results)} cases meet the target (the upper end of the interval of the net ratio is at most {target:g})"
            + (f", {tolerated} are tolerated (above {target:g} and at most {limit:g}), {not_met} are not met (above {limit:g})" if limit > target else f", {not_met} are not met")
            + f"; {len(unresolved)} are unresolved"
            + (f" ({raw_within} of them within the {'limit' if limit > target else 'target'} on the raw ratio)" if unresolved else "")
        )
        out += [f"**{counts}.**", ""]
    else:
        out += [
            f"The target of {target:g} is defined for the native configurations. For this configuration the tables "
            "report ratios and set no target: there is no verdict, no count of cases within a target.",
            "",
        ]
    if validation is not None:
        out += validation_paragraph(validation) + [""]
    for kind, (title, library) in titles.items():
        if not any(r.kind == kind for r in results):
            continue
        out += [f"### {title}", ""]
        if applies:
            out += [
                f"Net ratio floating / {library}: the net time of `floating` over the net time of {library}, each "
                "the median of the differences between a case block and its null block, with the 95% bootstrap "
                f"interval and the verdict (\"met\": the upper end is at most {target:g}"
                + (f"; \"tolerated\": above {target:g} and at most {limit:g}" if limit > target else "")
                + "). Above 1 means floating is slower."
                + (
                    f" `floating` runs on `{runtime}` and the reference process is native, so this is the ratio of this "
                    f"library on that runtime to the native {library}; the ratio to the same case on `native-portable` "
                    "(below the tables of the run, when published) is a diagnostic of the cost of the runtime and has no verdict."
                    if runtime != "native"
                    else ""
                ),
                "",
            ]
        else:
            out += [
                f"Net ratio of `floating` on this runtime to the native {library}: the net time of `floating` here over "
                f"the net time of the native {library} process measured in the same run, with the 95% bootstrap interval "
                "and no verdict. It compares different runtimes, because the reference is native; the ratio to the "
                "same case on `native-portable` (below the tables of the run, when published) attributes a difference "
                "to the runtime. Above 1 means floating is slower.",
                "",
            ]
        out += _table(kind, results, net_cell)
        out += ["", f"Raw ratio floating / {library} (median over median of the case blocks, as in 0.11.0; 95% bootstrap interval)", ""]
        out += _table(kind, results, raw_cell)
        out += ["", f"Net time per operation, {library}", ""]
        out += _table(kind, results, lambda r: format_ns(r.reference.net.net_ns))
        out += ["", "Net time per operation, floating", ""]
        out += _table(kind, results, lambda r: format_ns(r.floating.net.net_ns))
        out += ["", f"Null time per operation (the loop without the library call), {library}", ""]
        out += _table(kind, results, lambda r: format_ns(r.reference.null.median_ns))
        out += ["", "Null time per operation, floating", ""]
        out += _table(kind, results, lambda r: format_ns(r.floating.null.median_ns))
        out += [""]
    notes: list[str] = []
    if unresolved:
        notes.append(
            "Unresolved cases (reason): "
            + ", ".join(f"`{r.case}` ({r.reason})" for r in unresolved)
            + ". Their raw ratio decides the criterion and is shown; they are not counted as met or tolerated."
        )
    drifting = [r.case for r in results if r.drift]
    ordered = [r.case for r in results if r.order]
    warming = [r.case for r in results if r.warm]
    if warming:
        notes.append("`w`: the net time of the first third of the pairs of each round differs from that of the last third by more than the warm-up threshold: " + ", ".join(f"`{c}`" for c in warming) + ".")
    if drifting:
        notes.append("`d`: the null time moved between rounds by more than the drift threshold: " + ", ".join(f"`{c}`" for c in drifting) + ".")
    if ordered:
        notes.append("`o`: the net time depends on which block of a pair ran first by more than the order threshold: " + ", ".join(f"`{c}`" for c in ordered) + ".")
    if any(r.borderline for r in results):
        notes.append("An asterisk after a net ratio: the interval contains " + ("the target or the limit." if limit > target else "the target."))
    noisy = [r.case for r in results if r.noisy]
    if noisy:
        notes.append(
            "An asterisk after a raw ratio: the cell exceeded a dispersion threshold "
            f"(CI half-width over {NOISY_CI_PCT:.0f}% of the median, or round medians spread by over "
            f"{NOISY_SPREAD_PCT:.0f}%): " + ", ".join(f"`{case}`" for case in noisy) + "."
        )
    for note in notes:
        out += [note, ""]
    return "\n".join(out)


# ---------------------------------------------------------------------------
# Comparison (pure)
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class Change:
    case: str
    old: float
    new: float
    verdict: str  # "slower", "faster" or "same"
    basis: str = "raw"  # "net" when both summaries have a resolved net ratio, else "raw"

    @property
    def change_pct(self) -> float:
        return 100.0 * (self.new / self.old - 1.0)


def _ratio_of(summary: dict[str, object], case: dict[str, object]) -> tuple[dict[str, float], str]:
    """The ratio entry of a case and its basis: net for a resolved v2 case, raw otherwise."""
    if summary.get("schema") == SCHEMA_V1:
        return case["ratio"], "raw"  # type: ignore[return-value]
    if case["status"] != stats.UNRESOLVED:
        return case["ratio_net"], "net"  # type: ignore[return-value]
    return case["ratio_raw"], "raw"  # type: ignore[return-value]


def compare_summaries(old: dict[str, object], new: dict[str, object]) -> list[Change]:
    """Compare the floating/reference ratios of two summaries, case by case.

    The net ratios are compared when both cases are resolved v2 results, the
    raw ratios otherwise. A case is "slower" (floating lost ground to the
    library) only when the 95% interval of the new ratio lies entirely above
    that of the old one, and "faster" when it lies entirely below; overlapping
    intervals are "same".
    """
    old_cases = {c["case"]: c for c in old["cases"]}  # type: ignore[attr-defined]
    changes = []
    for case in new["cases"]:  # type: ignore[attr-defined]
        previous = old_cases.get(case["case"])
        if previous is None:
            continue
        before, old_basis = _ratio_of(old, previous)
        after, new_basis = _ratio_of(new, case)
        if old_basis != new_basis:  # mixed: fall back to the raw ratios on both sides
            before = previous["ratio"] if old.get("schema") == SCHEMA_V1 else previous["ratio_raw"]
            after = case["ratio"] if new.get("schema") == SCHEMA_V1 else case["ratio_raw"]
            basis = "raw"
        else:
            basis = new_basis
        if after["ci_low"] > before["ci_high"]:
            verdict = "slower"
        elif after["ci_high"] < before["ci_low"]:
            verdict = "faster"
        else:
            verdict = "same"
        changes.append(Change(case["case"], before["ratio"], after["ratio"], verdict, basis))
    return changes


def render_changes(changes: Sequence[Change]) -> str:
    lines = ["| case | old ratio | new ratio | change | verdict | ratio |", "| --- | ---: | ---: | ---: | --- | --- |"]
    for change in changes:
        lines.append(
            f"| `{change.case}` | {format_ratio(change.old)} | {format_ratio(change.new)} "
            f"| {change.change_pct:+.1f}% | {change.verdict} | {change.basis} |"
        )
    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------------------
# The comparison table of a release (pure)
# ---------------------------------------------------------------------------

TABLE_COLUMNS: tuple[str, ...] = (
    "configuration", "case", "package", "size", "op", "reference_ns", "floating_ns", "old_ratio", "old_basis",
    "new_ratio", "new_ci_low", "new_ci_high", "new_basis", "verdict", "quotient", "new_raw_ratio", "old_raw_ratio", "quotient_raw",
)  # fmt: skip
PACKAGES = {"binary": "binary", "decimal_gda": "decimal_gda"}
TABLE_TOLERATED = "tolerated"  # the status of a case above the target and within the limit (a summary of the two-bound criterion)
TABLE_STATUSES: tuple[str, ...] = (stats.MET, TABLE_TOLERATED, stats.NOT_MET, stats.UNRESOLVED, stats.NOT_APPLICABLE)


@dataclass(frozen=True)
class TableRow:
    """One case of a new summary beside the same case of an old one."""

    case: str
    kind: str
    op: str
    size: int
    reference_ns: float  # the net time of the reference side (v2), its median (v1)
    floating_ns: float
    old_ratio: float | None  # None when the old summary has no such case
    old_basis: str  # "raw" (v1, and v2 cases that were unresolved) or "net"
    new_ratio: float
    new_ci_low: float
    new_ci_high: float
    new_basis: str  # "net", or "raw" for an unresolved case, whose raw ratio is shown instead
    verdict: str  # a status of `stats`; an unresolved case adds its raw verdict
    status: str
    new_raw_ratio: float | None = None  # the ratio of medians of the new summary (every case of a v2 summary has it)
    old_raw_ratio: float | None = None  # the ratio of medians of the old summary

    @property
    def quotient_raw(self) -> float | None:
        """New raw ratio over old raw ratio: the same quantity on both sides (medians, the floor in both times). Empty when either is missing."""
        if self.new_raw_ratio is None or self.old_raw_ratio is None or self.old_raw_ratio <= 0.0:
            return None
        return self.new_raw_ratio / self.old_raw_ratio

    @property
    def quotient(self) -> float | None:
        """New over old: below 1 is faster. Not a like-for-like quotient when the bases differ (see the page)."""
        return None if self.old_ratio is None or self.old_ratio <= 0.0 else self.new_ratio / self.old_ratio


@dataclass(frozen=True)
class TableSection:
    """The table of one new summary: its configuration, its bounds, its rows and the counts of statuses."""

    configuration: str
    target: float | None
    limit: float | None
    rows: tuple[TableRow, ...]

    @property
    def counts(self) -> dict[str, int]:
        return {status: sum(1 for row in self.rows if row.status == status) for status in TABLE_STATUSES}


def _case_key(case_id: str) -> tuple[int, int, int, str]:
    """Package, precision, operation: the order of the table."""
    kind, op, size = case_id.split("/")
    ops = BINARY_OPS if kind == "binary" else DECIMAL_OPS
    return (list(PACKAGES).index(kind) if kind in PACKAGES else len(PACKAGES), int(size), ops.index(op) if op in ops else len(ops), case_id)


def _raw_ratio(summary: dict[str, object], case: dict[str, Any]) -> float | None:
    """The ratio of medians of a case: `ratio` in a v1 summary, `ratio_raw` in a v2 one."""
    entry = case.get("ratio") if summary.get("schema") == SCHEMA_V1 else case.get("ratio_raw")
    return None if entry is None else float(entry["ratio"])


def _old_ratio(old: dict[str, object] | None, case_id: str) -> tuple[float | None, str, float | None]:
    """The ratio of a case in the old summary, its basis, and its ratio of medians."""
    if old is None:
        return None, "raw", None
    entry = next((c for c in old["cases"] if c["case"] == case_id), None)  # type: ignore[attr-defined]
    if entry is None:
        return None, "raw", None
    ratio, basis = _ratio_of(old, entry)
    return float(ratio["ratio"]), basis, _raw_ratio(old, entry)


def table_section(old: dict[str, object] | None, new: dict[str, object]) -> TableSection:
    """The rows of a v1 or v2 summary `new` (v2 normally) beside the ratio of the same case in `old` (v1 or v2)."""
    v1 = new.get("schema") == SCHEMA_V1
    protocol = {} if v1 else dict(new["protocol"])  # type: ignore[call-overload]
    target = float(protocol["target_ratio"]) if "target_ratio" in protocol else None
    limit = float(protocol.get("limit_ratio", protocol["target_ratio"])) if "target_ratio" in protocol else None
    rows: list[TableRow] = []
    new_cases: list[dict[str, Any]] = list(new["cases"])  # type: ignore[call-overload]
    for case in sorted(new_cases, key=lambda c: _case_key(c["case"])):
        kind, op, size = case["case"].split("/")
        old_ratio, old_basis, old_raw = _old_ratio(old, case["case"])
        if v1:
            reference_ns, floating_ns = float(case["reference"]["median_ns"]), float(case["floating"]["median_ns"])
            ratio, basis, status, verdict = case["ratio"], "raw", stats.NOT_APPLICABLE, stats.NOT_APPLICABLE
        else:
            reference_ns, floating_ns = float(case["reference"]["net"]["net_ns"]), float(case["floating"]["net"]["net_ns"])
            status = str(case["status"])
            if status == stats.UNRESOLVED:
                ratio, basis = case["ratio_raw"], "raw"
                verdict = f"{status} (raw {case['raw_status']})"
            else:
                ratio, basis, verdict = case["ratio_net"], "net", status
        rows.append(
            TableRow(case["case"], kind, op, int(size), reference_ns, floating_ns, old_ratio, old_basis,
                     float(ratio["ratio"]), float(ratio["ci_low"]), float(ratio["ci_high"]), basis, verdict, status, _raw_ratio(new, case), old_raw)
        )  # fmt: skip
    return TableSection(summary_configuration(new), target, limit, tuple(rows))


def _cell_ratio(row: TableRow) -> str:
    return f"{format_ratio(row.new_ratio)} [{format_ratio(row.new_ci_low)}, {format_ratio(row.new_ci_high)}]" + (" (raw)" if row.new_basis == "raw" else "")


def render_table_markdown(sections: Sequence[TableSection], old_name: str = "the old summary") -> str:
    """One table per configuration with a line of counts; the quantities are explained in the text before the tables."""
    out = [
        f"The old ratio is the ratio of the median time of floating to that of the reference in {old_name}; a ratio marked (raw) "
        "is a ratio of medians, the loop floor of the timing harness is in both times. The new ratio is the net ratio "
        "(the floor subtracted on both sides) with its 95% interval, and the verdict is made on it. The two are not the same "
        "quantity, so the quotient new / old is indicative, above all for the small cases whose time is mostly floor. "
        "The column raw new / old divides the raw ratio of the new summary by the raw ratio of the old one: the same quantity "
        "on both sides (medians, the floor in both times), so it is the like-for-like change since the old release; it is empty "
        "when either raw ratio is missing. A new ratio marked (raw) is the raw ratio of an unresolved case. Below 1, a quotient "
        "says floating got faster.",
        "",
    ]
    for section in sections:
        counts = section.counts
        if section.target is None:
            bounds = "no bounds (a v1 summary has no verdict)"
        elif section.limit is not None and section.limit > section.target:
            bounds = f"target {section.target:g}, limit {section.limit:g}"
        else:
            bounds = f"target {section.target:g}"
        shown = [f"{counts[status]} {status.replace('_', ' ')}" for status in TABLE_STATUSES if counts[status] or status in (stats.MET, stats.NOT_MET)]
        summary_line = f"{len(section.rows)} cases, no verdict." if section.target is None else ", ".join(shown) + f" of {len(section.rows)} cases."
        out += [f"### Configuration `{section.configuration}` ({bounds})", "", f"**{summary_line}**", ""]
        out += ["| case | reference | floating | old ratio | new ratio | verdict | new / old | raw new / old |", "| --- | ---: | ---: | ---: | --- | --- | ---: | ---: |"]
        for row in section.rows:
            old = "n/a" if row.old_ratio is None else f"{format_ratio(row.old_ratio)}" + (" (raw)" if row.old_basis == "raw" else "")
            quotient = "n/a" if row.quotient is None else f"{row.quotient:.2f}"
            raw_quotient = "n/a" if row.quotient_raw is None else f"{row.quotient_raw:.2f}"
            out.append(f"| `{row.case}` | {format_ns(row.reference_ns)} | {format_ns(row.floating_ns)} | {old} | {_cell_ratio(row)} | {row.verdict} | {quotient} | {raw_quotient} |")
        out.append("")
    return "\n".join(out)


def render_table_csv(sections: Sequence[TableSection]) -> str:
    """All configurations in one CSV with the column `configuration`; numbers are plain floats (nanoseconds, ratios), empty when absent."""
    import csv
    import io

    buffer = io.StringIO()
    writer = csv.writer(buffer, lineterminator="\n")
    writer.writerow(TABLE_COLUMNS)

    def number(value: float | None) -> str:
        return "" if value is None else repr(float(value))

    for section in sections:
        for row in section.rows:
            writer.writerow(
                [section.configuration, row.case, PACKAGES.get(row.kind, row.kind), row.size, row.op, number(row.reference_ns), number(row.floating_ns),
                 number(row.old_ratio), row.old_basis if row.old_ratio is not None else "", number(row.new_ratio), number(row.new_ci_low),
                 number(row.new_ci_high), row.new_basis, row.verdict, number(row.quotient), number(row.new_raw_ratio), number(row.old_raw_ratio),
                 number(row.quotient_raw)]
            )  # fmt: skip
    return buffer.getvalue()


# ---------------------------------------------------------------------------
# The same case in two configurations (pure)
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class RelativeRow:
    case: str
    kind: str
    op: str
    size: int
    ratio: RatioStats


def relative_rows(
    samples_a: dict[str, object], summary_a: dict[str, object], samples_b: dict[str, object], summary_b: dict[str, object]
) -> list[RelativeRow]:
    """Net time of the floating side of A over that of B, case by case, from two samples documents.

    Meant for a runtime (A: wasm, js) against `native-portable` (B). Both runs
    must have read the same operand file and used the same protocol; each side
    is resampled with its own configuration in the seed, so the draws of A and
    B are independent. The result has an interval and no verdict.
    """
    meta_a, meta_b = summary_a["meta"], summary_b["meta"]
    if meta_a["inputs_sha256"] != meta_b["inputs_sha256"]:  # type: ignore[index]
        raise ValueError("the two summaries read different operand files")
    protocol_a, _, seed_a, configuration_a, _ = protocol_from_summary(summary_a)
    protocol_b, _, seed_b, configuration_b, _ = protocol_from_summary(summary_b)
    if protocol_a != protocol_b:
        raise ValueError("the two summaries were measured with different protocols")
    if configuration_a == configuration_b:
        raise ValueError("the two summaries are of the same configuration")
    collected_a, collected_b = load_samples(samples_a), load_samples(samples_b)
    rows = []
    for case_id in sorted(set(collected_a.floating_pairs) & set(collected_b.floating_pairs), key=_case_sort_key):
        net_a = stats.side_net(collected_a.floating_pairs[case_id], seed_a, configuration_a, case_id, "floating", protocol_a.resamples)
        net_b = stats.side_net(collected_b.floating_pairs[case_id], seed_b, configuration_b, case_id, "floating", protocol_b.resamples)
        between = stats.ratio_between(net_a, net_b)
        kind, op, size = case_id.split("/")
        rows.append(RelativeRow(case_id, kind, op, int(size), RatioStats(between.ratio, between.ci_low, between.ci_high)))
    return rows


def render_relative(rows: Sequence[RelativeRow], configuration: str, other: str) -> str:
    """The tables of the ratio of `configuration` to `other`, one per domain, with no verdict."""
    out = [
        f"#### Ratio of `{configuration}` to `{other}`",
        "",
        f"Net time of `floating` in the configuration `{configuration}` over the net time of the same case in `{other}`, "
        "with the 95% bootstrap interval of independent resampling of the two configurations. The same code path runs in "
        "both (the portable one), so a ratio above 1 attributes the difference to the runtime. It is a diagnostic of the cost "
        "of the runtime: there is no verdict.",
        "",
    ]
    for kind, title in (("binary", "Binary"), ("decimal_gda", "Decimal GDA")):
        if not any(r.kind == kind for r in rows):
            continue
        out += [f"{title}", ""]
        out += _table(kind, rows, lambda r: _interval(r.ratio))
        out += [""]
    return "\n".join(out)


def choose_warmup(drift_by_warmup: dict[int, list[float]], limit_pct: float = 2.0) -> int | None:
    """The smallest warm-up (microseconds) whose runs all have a warm-up drift of at most `limit_pct` percent.

    `drift_by_warmup[w]` holds `external_stats.warm_pct` of every run (case and
    repeat) that used a warm-up of `w`. The rule is fixed before the experiment
    (see the design page); `None` when no warm-up reaches the limit.
    """
    for warmup in sorted(drift_by_warmup):
        if drift_by_warmup[warmup] and all(value <= limit_pct for value in drift_by_warmup[warmup]):
            return warmup
    return None


# ---------------------------------------------------------------------------
# Published files (pure naming)
# ---------------------------------------------------------------------------


def summary_name(version: str, configuration: str) -> str:
    return f"summary-{version}-{valid_configuration(configuration)}.json"


def samples_name(version: str, configuration: str) -> str:
    return f"samples-{version}-{valid_configuration(configuration)}.json.gz"


def tables_name(configuration: str) -> str:
    return f"summary-{valid_configuration(configuration)}.md"


def page_markers(configuration: str) -> tuple[str, str]:
    """The comment lines that delimit the generated tables of a configuration in the manual page."""
    name = valid_configuration(configuration)
    return (f"<!-- external-baseline:{name}:start -->", f"<!-- external-baseline:{name}:end -->")


def replace_page_tables(page: str, configuration: str, tables: str) -> str:
    """The manual page with the generated tables of one configuration replaced."""
    start, end = page_markers(configuration)
    if page.count(start) != 1 or page.count(end) != 1:
        raise ValueError(f"the page needs exactly one {start} and one {end}")
    head, rest = page.split(start)
    _, tail = rest.split(end)
    return f"{head}{start}\n\n{tables.strip()}\n\n{end}{tail}"


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


def thermal_state() -> str:
    """The speed-limit line of `pmset -g therm` (Darwin), empty when the system reports none."""
    if platform.system() != "Darwin":
        return ""
    for line in capture(["pmset", "-g", "therm"]).splitlines():
        if "speed_limit" in line.lower():
            return line.strip()
    return ""


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


def moon_command(release: bool = True, target: str = "native") -> list[str]:
    command = [
        "sh", "tools/run_moon_clean_exec.sh", "test", "tooling/src/bench/external",
        "--include-skipped", "--no-parallelize", "--target", valid_target(target),
        "--filter", "external baseline floating",
    ]  # fmt: skip
    if release:
        command.insert(4, "--release")
    return command


def runtime_versions(target: str) -> dict[str, str]:
    """Versions of the runtime that runs the floating side, for `meta`: `moonrun` for wasm, node and V8 for js, nothing for native."""
    if valid_target(target) == "wasm":
        moonrun = shutil.which("moonrun") or str(Path.home() / ".moon" / "bin" / "moonrun")
        return {"moonrun": capture([moonrun, "--version"])}
    if target == "js":
        return {
            "node": capture(["node", "--version"]),
            "v8": capture(["node", "-p", "process.versions.v8"]),
        }
    return {}


def parse_environment(items: Sequence[str]) -> dict[str, str]:
    """`KEY=VALUE` arguments of `--moon-env`; a key is given once."""
    environment: dict[str, str] = {}
    for item in items:
        key, separator, value = item.partition("=")
        if not separator or not key or key in environment:
            raise ValueError(f"--moon-env wants KEY=VALUE, each key once: {item!r}")
        environment[key] = value
    return environment


def run_floating(inputs: Path, reference: Path | None, cases: Sequence[str], protocol: Protocol, seed: int, round_index: int,
                 extra_environment: dict[str, str] | None = None, target: str = "native") -> str:  # fmt: skip
    env = moon_environment()
    env.update(extra_environment or {})
    env.update(moon_protocol_env(protocol))
    env["EXTBENCH_INPUTS"] = str(inputs)
    env["EXTBENCH_CASES"] = ",".join(cases)
    env["EXTBENCH_SEED"] = str(seed)
    env["EXTBENCH_ROUND"] = str(round_index)
    if reference is not None:
        env["EXTBENCH_REFERENCE"] = str(reference)
    completed = subprocess.run(
        moon_command(target=target), cwd=REPO_ROOT, env=env, text=True,
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
    rows = generate_rows(args.input_seed, OPERANDS_PER_CASE, cases)
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
    target = valid_target(args.target)
    configuration = valid_configuration(args.configuration or default_configuration(target))
    environment = parse_environment(args.moon_env)
    if args.rounds is not None:
        protocol = Protocol(**{**asdict(protocol), "rounds": args.rounds})
    if args.warmup_us is not None:
        protocol = Protocol(**{**asdict(protocol), "warmup_time_us": args.warmup_us})
    out_dir: Path = args.out
    out_dir.mkdir(parents=True, exist_ok=True)
    if not args.resume:
        for stale in out_dir.glob("round-*"):
            shutil.rmtree(stale)
    binary = build_harness(out_dir, args.prefix, args.cc, args.cflags)
    info = json.loads(capture([str(binary), "info"]))
    inputs, cases = prepare_inputs(args, out_dir)
    case_ids = [c.id for c in cases]
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
        "floating_configuration": configuration,
        "floating_environment": environment,
        "target": target,
        "runtime": runtime_versions(target),
    })  # fmt: skip
    (out_dir / "machine.json").write_text(json.dumps(meta, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    collected = Collected()
    collected.distinct_operands = distinct_operand_counts(generate_rows(args.input_seed, OPERANDS_PER_CASE, cases))
    plans = plan_rounds(args.seed, protocol.rounds, case_ids)
    contention: list[dict[str, object]] = []
    for plan in plans:
        round_dir = out_dir / f"round-{plan.index}"
        round_dir.mkdir(exist_ok=True)
        c_order = list(plan.case_order)
        for side in (plan.first, "floating" if plan.first == "reference" else "reference"):
            started = time.monotonic()
            therm_before = thermal_state()
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
                    output = run_floating(inputs, reference, list(plan.case_order), protocol, args.seed, plan.index, environment, target)
                    log.write_text(output, encoding="utf-8")
                    events = parse_jsonl(output, EVENT_MARKER)
                    jsonl.write_text("".join(json.dumps(e, sort_keys=True) + "\n" for e in events), encoding="utf-8")
                add_floating_events(collected, plan.index, parse_jsonl(jsonl.read_text(encoding="utf-8")))
                state, detail = floating_validation_status(log.read_text(encoding="utf-8"))
                collected.validation_status[plan.index] = (state, detail)
                if state != VALIDATED:
                    print(f"WARNING: floating output of round {plan.index} is {state.upper()} ({detail}): see {log}")
            contention.append({"round": plan.index, "side": side, "other_cpu_pct_before": before, "other_cpu_pct_after": sample_foreign_cpu(),
                               "thermal_before": therm_before, "thermal_after": thermal_state()})  # fmt: skip
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

STORED_SUMMARY = SUMMARY_DIR / "summary-0.11.0.json"
QUICK_TARGET_RATIO = 10.0


def stored_medians(summary: dict[str, object]) -> dict[str, tuple[float, float]]:
    """`case id -> (reference median ns, floating median ns)` of a published summary."""
    medians: dict[str, tuple[float, float]] = {}
    v1 = summary.get("schema") == SCHEMA_V1
    for entry in summary["cases"]:  # type: ignore[attr-defined]
        reference = entry["reference"] if v1 else entry["reference"]["raw"]
        floating = entry["floating"] if v1 else entry["floating"]["raw"]
        medians[str(entry["case"])] = (float(reference["median_ns"]), float(floating["median_ns"]))
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
    return {case: median(pooled(samples)) for case, samples in collected.floating.items()}


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
        output = run_floating(inputs, None, case_ids, protocol, args.seed, round_index, parse_environment(args.moon_env), valid_target(args.target))
        (out_dir / f"quick-round-{round_index}.log").write_text(output, encoding="utf-8")
        state, detail = floating_validation_status(output)
        if state != NOT_VALIDATED:
            print(f"WARNING: a quick run passes no reference file, yet the output says {state} ({detail})")
        add_floating_events(collected, round_index, parse_jsonl(output, EVENT_MARKER))
        print(f"round {round_index} done", flush=True)
    rows = quick_rows(floating_medians(collected), stored, args.flag_above)
    print(render_quick(rows))
    print("NOT VALIDATED: a quick run has no reference results; the floating results are compared with themselves.")
    if args.json is not None:
        args.json.write_text(json.dumps({row[0]: row[1:] for row in rows}, indent=1) + "\n", encoding="utf-8")
    return 0


def validation_document(collected: Collected) -> dict[str, object]:
    """The validation facts of a run: the worst state over the rounds and the distinct operand counts."""
    order = [VALIDATION_FAILED, NOT_VALIDATED, VALIDATION_UNKNOWN, VALIDATED]
    states = {round_index: pair for round_index, pair in collected.validation_status.items()}
    if not states:
        status, detail = VALIDATION_UNKNOWN, "no floating output was read (a report from stored samples)"
    else:
        status, detail = min(states.values(), key=lambda pair: order.index(pair[0]))
    return {
        "status": status,
        "detail": detail,
        "rounds": {str(k): list(v) for k, v in sorted(states.items())},
        "distinct_operands_per_case": dict(sorted(collected.distinct_operands.items())),
    }


def finish(collected: Collected, protocol: Protocol, seed: int, meta: dict[str, object], out_dir: Path) -> int:
    configuration = str(meta.get("floating_configuration", DEFAULT_CONFIGURATION))
    target = str(meta.get("target", "native"))
    criterion = criterion_for(configuration, target)
    rules = stats.Rules(target=criterion.target_ratio, limit=criterion.limit_ratio)
    results = reduce_results(collected, protocol, seed, rules, configuration, criterion.applies)
    document = summary_document(results, meta, protocol, configuration, rules, target, criterion)
    validation = {case: list(counts) for case, counts in sorted(collected.floating_validation.items())}
    document["validation_valid_total_per_case_all_rounds"] = validation
    invalid = [case for case, (valid, total) in collected.floating_validation.items() if valid != total]
    document["validation_failed_cases"] = sorted(invalid)
    validation = validation_document(collected)
    document["validation"] = validation
    if invalid:
        print("WARNING: floating differs from the MPFR/libmpdec reference in: " + ", ".join(sorted(invalid)))
    (out_dir / "results.json").write_text(json.dumps(document, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    (out_dir / "samples.json").write_text(json.dumps(samples_document(collected), sort_keys=True) + "\n", encoding="utf-8")
    markdown = render_markdown(results, document["protocol"], validation)  # type: ignore[arg-type]
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


def write_gzip(path: Path, text: str) -> None:
    """Deterministic gzip (no timestamp, no file name): the same samples give the same bytes."""
    import gzip

    with path.open("wb") as handle:
        with gzip.GzipFile(filename="", mode="wb", fileobj=handle, mtime=0) as archive:
            archive.write(text.encode("utf-8"))


def command_publish(args: argparse.Namespace) -> int:
    """Copy the summary and the samples of a run into testdata/ (raw JSONL stays in .tmp).

    One `summary-<version>-<configuration>.json` and one
    `samples-<version>-<configuration>.json.gz` are kept per release and per
    configuration of the floating side (`native` by default), so the ratios can
    be tracked from release to release with `compare`, and every number of a
    summary recomputed from its samples (`recompute`); `summary-<configuration>.md`
    is the latest tables of that configuration, and the generated tables of the
    manual page for it are replaced (`page`). The name follows `--version`, or
    the version of `library/moon.mod`: name the measured release explicitly when
    the manifest already carries the next one. The summaries of earlier
    releases (`summary-0.10.2.json`, `summary-0.11.0.json`, schema v1) keep their
    names and content.
    """
    SUMMARY_DIR.mkdir(parents=True, exist_ok=True)
    document = json.loads((args.out / "results.json").read_text(encoding="utf-8"))
    configuration = summary_configuration(document)
    version = args.version or module_version()
    raw = sorted(args.out.glob("round-*/*.jsonl")) + sorted(args.out.glob("round-*/*.log"))
    document["raw_sha256"] = {str(path.relative_to(args.out)): sha256_file(path) for path in raw}
    document["raw_bytes"] = sum(path.stat().st_size for path in raw)
    target = SUMMARY_DIR / summary_name(version, configuration)
    target.write_text(json.dumps(document, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    write_gzip(SUMMARY_DIR / samples_name(version, configuration), (args.out / "samples.json").read_text(encoding="utf-8"))
    (SUMMARY_DIR / tables_name(configuration)).write_text((args.out / "results.md").read_text(encoding="utf-8"), encoding="utf-8")
    print(f"published {target}")
    return update_page(configuration)


def version_key(version: str) -> tuple[tuple[int, ...], int, tuple[tuple[int, str], ...]]:
    """A sortable key of a release name such as `0.12.0` or `0.12.0-rc.1`: numbers compare as numbers and a pre-release sorts below its release."""
    base, _, pre = version.partition("-")
    numbers = tuple(int(part) for part in base.split(".") if part.isdigit())
    parts = tuple((int(part), "") if part.isdigit() else (-1, part) for part in re.split(r"[.-]", pre)) if pre else ()
    return (numbers, 0 if pre else 1, parts)


def published_summaries(configuration: str) -> dict[str, Path]:
    """`version -> path` of the published schema v2 summaries of a configuration."""
    pattern = re.compile(rf"summary-(.+)-{re.escape(valid_configuration(configuration))}\.json")
    found = {}
    for path in SUMMARY_DIR.glob("summary-*.json"):
        match = pattern.fullmatch(path.name)
        if match:
            found[match.group(1)] = path
    return found


def page_tables(configuration: str) -> str:
    """The generated tables of a configuration: those of its run, and, for a runtime, its ratio to `native-portable`.

    The relative tables are computed from the two published samples files of
    the same version; when the `native-portable` files are not published the
    section says so instead.
    """
    tables = (SUMMARY_DIR / tables_name(configuration)).read_text(encoding="utf-8")
    summaries = published_summaries(configuration)
    if not summaries:
        return tables
    version = max(summaries, key=version_key)
    summary = json.loads(summaries[version].read_text(encoding="utf-8"))
    if summary["protocol"]["target"] == "native":
        return tables
    other = "native-portable"
    other_summary_path = SUMMARY_DIR / summary_name(version, other)
    other_samples_path = SUMMARY_DIR / samples_name(version, other)
    own_samples_path = SUMMARY_DIR / samples_name(version, configuration)
    if not (other_summary_path.is_file() and other_samples_path.is_file() and own_samples_path.is_file()):
        return tables + f"\nThe ratio to `{other}` is not shown: the `{other}` summary and samples of {version} are not published.\n"
    import gzip

    rows = relative_rows(
        json.loads(gzip.decompress(own_samples_path.read_bytes()).decode("utf-8")),
        summary,
        json.loads(gzip.decompress(other_samples_path.read_bytes()).decode("utf-8")),
        json.loads(other_summary_path.read_text(encoding="utf-8")),
    )
    return tables.rstrip("\n") + "\n\n" + render_relative(rows, configuration, other)


def update_page(configuration: str) -> int:
    """Replace the generated tables of `configuration` in the manual page, when the page has its markers."""
    page_path = REPO_ROOT / "doc" / "manual" / "performance" / "bench" / "external.md"
    page = page_path.read_text(encoding="utf-8")
    start, end = page_markers(configuration)
    if start not in page:
        print(f"the manual page has no {start}: tables not updated")
        return 0
    page_path.write_text(replace_page_tables(page, configuration, page_tables(configuration)), encoding="utf-8")
    print(f"updated the tables of configuration {configuration} in {page_path.relative_to(REPO_ROOT)}")
    return 0


def command_page(args: argparse.Namespace) -> int:
    """Regenerate the tables of one configuration in the manual page from the published `summary-<configuration>.md`."""
    return update_page(valid_configuration(args.configuration))


def command_recompute(args: argparse.Namespace) -> int:
    """Recompute a published summary from its samples and say whether every stored number agrees."""
    import gzip

    summary = json.loads(args.summary.read_text(encoding="utf-8"))
    samples = json.loads(gzip.decompress(args.samples.read_bytes()).decode("utf-8"))
    results = recompute(samples, summary)
    stored = {entry["case"]: entry for entry in summary["cases"]}
    differing = [r.case for r in results if json.loads(json.dumps(asdict(r))) != stored.get(r.case)]
    print(f"{len(results) - len(differing)} of {len(results)} cases agree with the summary")
    if differing:
        print("differ: " + ", ".join(differing))
    return 1 if differing or len(results) != len(stored) else 0


def command_warmup(args: argparse.Namespace) -> int:
    """The calibration experiment of the warm-up of a runtime (floating side only, no reference, nothing published).

    For every warm-up time, every repeat and every case: one process that
    warms up for that long, calibrates, then times `--blocks` pairs of
    confirmatory blocks; the table is `external_stats.warm_pct` of each run, and
    the rule of the design page picks the smallest warm-up whose runs all stay
    within `--limit` percent. Run it once per runtime, in the bench window,
    before any cell is measured.
    """
    target = valid_target(args.target)
    out_dir: Path = args.out
    out_dir.mkdir(parents=True, exist_ok=True)
    cases = [Case.parse(text) for text in args.cases]
    inputs = out_dir / "inputs.txt"
    inputs.write_text(format_inputs(generate_rows(args.input_seed, OPERANDS_PER_CASE, cases), args.input_seed, OPERANDS_PER_CASE), encoding="utf-8")
    case_ids = [c.id for c in cases]
    environment = parse_environment(args.moon_env)
    base = PRESETS["standard"]
    drift: dict[int, list[float]] = {}
    table: list[dict[str, object]] = []
    for warmup_us in args.warmups_us:
        protocol = Protocol(**{**asdict(base), "warmup_time_us": float(warmup_us), "exploratory": 0, "confirmatory": args.blocks, "rounds": 1})
        for repeat in range(args.repeats):
            output = run_floating(inputs, None, case_ids, protocol, args.seed, repeat, environment, target)
            collected = Collected()
            add_floating_events(collected, repeat, parse_jsonl(output, EVENT_MARKER))
            for case_id in case_ids:
                value = stats.warm_pct(collected.floating_pairs[case_id])
                drift.setdefault(int(warmup_us), []).append(value)
                table.append({"warmup_us": warmup_us, "repeat": repeat, "case": case_id, "warm_pct": value})
                print(f"warm-up {warmup_us:>9.0f} us  repeat {repeat}  {case_id:<22} warm {value:6.2f}%", flush=True)
    chosen = choose_warmup(drift, args.limit)
    print(f"smallest warm-up within {args.limit:g}%: {chosen if chosen is not None else 'none'} us")
    document = {"target": target, "runtime": runtime_versions(target), "limit_pct": args.limit, "chosen_us": chosen, "rows": table}
    (out_dir / f"warmup-{target}.json").write_text(json.dumps(document, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return 0


def command_compare(args: argparse.Namespace) -> int:
    """Print how the ratios of NEW moved against OLD."""
    old = json.loads(args.old.read_text(encoding="utf-8"))
    new = json.loads(args.new.read_text(encoding="utf-8"))
    if summary_configuration(old) != summary_configuration(new):
        print(f"configurations differ: {summary_configuration(old)} (old) against {summary_configuration(new)} (new)")
    changes = compare_summaries(old, new)
    print(render_changes(changes), end="")
    slower = [c.case for c in changes if c.verdict == "slower"]
    if slower:
        print("slower than the library by more than the intervals: " + ", ".join(slower))
    return 0


def command_table(args: argparse.Namespace) -> int:
    """One table per new summary beside an old summary, as Markdown (stdout or `--markdown`) and CSV (`--csv`)."""
    old = json.loads(args.old.read_text(encoding="utf-8"))
    sections = [table_section(old, json.loads(path.read_text(encoding="utf-8"))) for path in args.new]
    markdown = render_table_markdown(sections, args.old.name)
    if args.markdown:
        args.markdown.write_text(markdown, encoding="utf-8")
    else:
        print(markdown, end="")
    if args.csv:
        args.csv.write_text(render_table_csv(sections), encoding="utf-8")
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
    run.add_argument("--target", choices=list(TARGETS), default="native",
                     help="the `moon --target` the floating side is built and run for; the reference side is always the native C process")  # fmt: skip
    run.add_argument("--configuration", default=None,
                     help="name of the build configuration of the floating side, recorded in the summary and in the names of the published files (native, native-portable, wasm, js; default: native for the native target, the target's name otherwise)")  # fmt: skip
    run.add_argument("--warmup-us", type=float, default=None,
                     help="override the preset's warm-up time in microseconds (a runtime's value is fixed by the calibration experiment of the design page)")  # fmt: skip
    run.add_argument("--moon-env", action="append", default=[], metavar="KEY=VALUE",
                     help="environment variable for the moon process that builds and runs the floating side (how a configuration is selected is defined by the kernel work); repeatable")  # fmt: skip
    run.set_defaults(func=command_run)

    quick = sub.add_parser("quick", help="floating side only, against the stored reference medians")
    common(quick)
    quick.add_argument("--rounds", type=int, default=2)
    quick.add_argument("--seed", type=int, default=INPUT_SEED)
    quick.add_argument("--stored", type=Path, default=STORED_SUMMARY, help="published summary giving the reference medians")
    quick.add_argument("--flag-above", type=float, default=QUICK_TARGET_RATIO, help="ratio above which a cell is flagged")
    quick.add_argument("--json", type=Path, default=None, help="also write the rows as JSON")
    quick.add_argument("--moon-env", action="append", default=[], metavar="KEY=VALUE", help="environment variable for the moon process; repeatable")
    quick.add_argument("--target", choices=list(TARGETS), default="native")
    quick.set_defaults(func=command_quick)

    report = sub.add_parser("report", help="reduce the raw rounds of an earlier run again")
    report.add_argument("--out", type=Path, default=DEFAULT_OUT)
    report.set_defaults(func=command_report)

    publish = sub.add_parser("publish", help="copy the summary of a run into testdata/external_baseline")
    publish.add_argument("--out", type=Path, default=DEFAULT_OUT)
    publish.add_argument("--version", help="release the run measures (default: the version of library/moon.mod)")
    publish.set_defaults(func=command_publish)

    page = sub.add_parser("page", help="regenerate the tables of one configuration in the manual page")
    page.add_argument("--configuration", default=DEFAULT_CONFIGURATION)
    page.set_defaults(func=command_page)

    recomputed = sub.add_parser("recompute", help="recompute a published summary from its samples")
    recomputed.add_argument("summary", type=Path)
    recomputed.add_argument("samples", type=Path)
    recomputed.set_defaults(func=command_recompute)

    warmup = sub.add_parser("warmup", help="the calibration experiment of the warm-up of a runtime (floating side only)")
    warmup.add_argument("--out", type=Path, default=DEFAULT_OUT, help="working directory for the inputs and the result")
    warmup.add_argument("--input-seed", type=int, default=INPUT_SEED)
    warmup.add_argument("--cases", nargs="+", default=list(WARMUP_CASES), help="cases of the experiment (kind/op/size)")
    warmup.add_argument("--target", choices=list(TARGETS), required=True)
    warmup.add_argument("--warmups-us", type=float, nargs="+", default=[5000.0, 50000.0, 200000.0, 1000000.0, 3000000.0])
    warmup.add_argument("--repeats", type=int, default=3)
    warmup.add_argument("--blocks", type=int, default=60, help="confirmatory pairs per run")
    warmup.add_argument("--limit", type=float, default=2.0, help="warm-up drift (percent) every run must stay within")
    warmup.add_argument("--seed", type=int, default=INPUT_SEED)
    warmup.add_argument("--moon-env", action="append", default=[], metavar="KEY=VALUE")
    warmup.set_defaults(func=command_warmup)

    compare = sub.add_parser("compare", help="compare the ratios of two published summaries")
    compare.add_argument("old", type=Path)
    compare.add_argument("new", type=Path)
    compare.set_defaults(func=command_compare)

    table = sub.add_parser("table", help="a table of the new summaries beside an old one (Markdown, CSV), one section per configuration")
    table.add_argument("old", type=Path, help="the summary to compare with (schema v1 or v2), e.g. testdata/external_baseline/summary-0.11.0.json")
    table.add_argument("new", type=Path, nargs="+", help="the summaries of the new run, one per configuration")
    table.add_argument("--markdown", type=Path, default=None, help="write the Markdown here instead of standard output")
    table.add_argument("--csv", type=Path, default=None, help="also write all sections as one CSV")
    table.set_defaults(func=command_table)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main())
