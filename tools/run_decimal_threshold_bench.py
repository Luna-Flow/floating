#!/usr/bin/env python3
"""Calibrate Decimal coefficient algorithm crossovers.

The default mode binary-searches forced algorithm pairs. ``--model`` runs a
regular padding-band grid with ABBA/BAAB paired samples and fits a conservative
bootstrap isotonic change point. Use ``--shape`` to keep dense, sparse, and
unbalanced operand models separate.
"""

from __future__ import annotations

import argparse
import json
import math
import platform
import shutil
import statistics
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

from benchmark_common import capture_command, utc_now_iso, utc_stamp, write_json
from decimal_dispatch_model import DispatchObservation, fit_dispatch_model


ROOT = Path(__file__).resolve().parents[1]
MARKER = "DECIMAL_THRESHOLD_JSON="
ALGORITHMS = {
    "schoolbook": ("dec_coeff_mul_schoolbook(left, right)", "mul"),
    "karatsuba": ("dec_coeff_mul_karatsuba(left, right)", "mul"),
    "toom3": ("dec_coeff_mul_toom3(left, right)", "mul"),
    "ntt": ("dec_coeff_mul_ntt(left, right)", "mul"),
    "square-schoolbook": ("dec_coeff_square_schoolbook(value)", "square"),
    "square-karatsuba": ("dec_coeff_square_karatsuba(value)", "square"),
    "square-toom3": ("dec_coeff_mul_toom3(value, value)", "square"),
    "square-ntt": ("dec_coeff_square_ntt(value)", "square"),
    "knuth": ("dec_coeff_div_rem_knuth_repr(numerator, denominator)", "div"),
    "burnikel-ziegler": (
        "dec_coeff_div_rem_burnikel_ziegler(numerator, denominator)",
        "div",
    ),
    "newton": ("dec_coeff_div_rem_newton(numerator, denominator)", "div"),
}

SHAPES = ("dense", "sparse", "unbalanced")


@dataclass(frozen=True)
class Transition:
    name: str
    baseline: str
    candidate: str
    low: int
    high: int
    step: int
    shape: str = "dense"


@dataclass(frozen=True)
class BenchmarkRecord:
    median: float
    mad_pct: float
    runs: int


TRANSITIONS = (
    Transition("mul-schoolbook-karatsuba", "schoolbook", "karatsuba", 16, 256, 8),
    Transition("square-schoolbook-karatsuba", "square-schoolbook", "square-karatsuba", 16, 128, 8),
    Transition("mul-karatsuba-toom3", "karatsuba", "toom3", 256, 4096, 128),
    Transition("square-karatsuba-toom3", "square-karatsuba", "square-toom3", 256, 4096, 128),
    Transition("mul-toom3-ntt", "toom3", "ntt", 1024, 8192, 256),
    Transition("mul-toom3-ntt-8k", "toom3", "ntt", 1024, 1792, 64),
    Transition("mul-toom3-ntt-16k", "toom3", "ntt", 2048, 3584, 128),
    Transition("mul-toom3-ntt-32k", "toom3", "ntt", 3840, 7168, 256),
    Transition("mul-toom3-ntt-64k", "toom3", "ntt", 7424, 14080, 512),
    Transition("square-toom3-ntt", "square-toom3", "square-ntt", 1024, 8192, 256),
    Transition("square-karatsuba-ntt-4k", "square-karatsuba", "square-ntt", 512, 896, 64),
    Transition("square-karatsuba-ntt-8k", "square-karatsuba", "square-ntt", 912, 1104, 64),
    Transition("square-toom3-ntt-8k", "square-toom3", "square-ntt", 1152, 1792, 128),
    Transition("square-toom3-ntt-16k", "square-toom3", "square-ntt", 1824, 3488, 128),
    Transition("square-toom3-ntt-32k", "square-toom3", "square-ntt", 3648, 6976, 256),
    Transition("square-toom3-ntt-64k", "square-toom3", "square-ntt", 7296, 14208, 256),
    Transition("div-knuth-bz", "knuth", "burnikel-ziegler", 512, 4096, 128),
    Transition("div-knuth-bz-1k", "knuth", "burnikel-ziegler", 576, 1024, 64),
    Transition("div-knuth-bz-2k", "knuth", "burnikel-ziegler", 1088, 2048, 64),
    Transition("div-knuth-bz-4k", "knuth", "burnikel-ziegler", 2112, 4032, 128),
    Transition("div-knuth-bz-8k", "knuth", "burnikel-ziegler", 4224, 8064, 256),
    Transition("div-knuth-bz-16k", "knuth", "burnikel-ziegler", 8448, 16384, 256),
    Transition("div-bz-newton", "burnikel-ziegler", "newton", 2048, 8192, 256),
)


def dense_source(limbs: int, order: tuple[str, str]) -> str:
    return probe_source(limbs, order, "dense")


def _sparse_pattern_source() -> str:
    return '''
fn dec_coeff_test_sparse_pattern(length : Int, salt : Int) -> DecCoeff {
  let limbs = Array::make(length, 0U)
  limbs[0] = (salt + 1).reinterpret_as_uint()
  if length > 2 {
    limbs[length / 2] = (salt + 3).reinterpret_as_uint()
  }
  limbs[length - 1] = (dec_coeff_base - 1 - salt).reinterpret_as_uint()
  dec_coeff_from_unit_accumulator(limbs, limbs.length())
}
'''


def _operand_setup(operation: str, limbs: int, shape: str) -> tuple[str, str, str]:
    if shape not in SHAPES:
        raise ValueError(f"unsupported operand shape: {shape}")
    if operation == "square" and shape == "unbalanced":
        raise ValueError("square does not have an unbalanced operand shape")
    right_limbs = limbs * 3 if shape == "unbalanced" else limbs
    pattern = (
        "dec_coeff_test_sparse_pattern"
        if shape == "sparse"
        else "dec_coeff_test_dense_pattern"
    )
    if operation == "mul":
        setup = f"""  let left = {pattern}({limbs}, 17)
  let right = {pattern}({right_limbs}, 31)
"""
        return setup, "left", "right"
    if operation == "square":
        return f"  let value = {pattern}({limbs}, 17)\n", "value", "value"
    setup = f"""  let denominator = {pattern}({limbs}, 17)
  let quotient = {pattern}({right_limbs}, 31)
  let numerator = dec_coeff_magnitude_add_unit(
    dec_coeff_multiply_repr(denominator, quotient),
    1,
  )
"""
    return setup, "numerator", "denominator"


def probe_source(
    limbs: int, order: tuple[str, str], shape: str = "dense", sample_count: int = 9
) -> str:
    if sample_count < 9:
        raise ValueError("benchmark cells require at least nine samples")
    first, second = order
    first_expr, operation = ALGORITHMS[first]
    second_expr, second_operation = ALGORITHMS[second]
    if operation != second_operation:
        raise ValueError("algorithms in one probe must have the same operation")
    if shape == "sparse":
        prelude = _sparse_pattern_source()
    else:
        prelude = ""
    setup, _, _ = _operand_setup(operation, limbs, shape)
    if operation == "mul":
        first_call = first_expr
        second_call = second_expr
    elif operation == "square":
        first_call = first_expr
        second_call = second_expr
    else:
        first_call = first_expr
        second_call = second_expr
    return f'''{prelude}
///|
#skip("threshold calibration")
test "decimal threshold probe" {{
{setup}
  let bencher = @bench.Bench()
  bencher.bench(name="{first}", count={sample_count}, fn() {{
    bencher.keep({first_call})
  }})
  bencher.bench(name="{second}", count={sample_count}, fn() {{
    bencher.keep({second_call})
  }})
  println("{MARKER}" + bencher.dump_summaries())
}}
'''


def dense_grid_source(
    transition: Transition,
    sizes: list[int],
    reverse_order: bool,
) -> str:
    return grid_source(transition, sizes, reverse_order, transition.shape)


def grid_source(
    transition: Transition,
    sizes: list[int],
    reverse_order: bool,
    shape: str = "dense",
    sample_count: int = 9,
) -> str:
    if sample_count < 9:
        raise ValueError("benchmark cells require at least nine samples")
    baseline_expr, operation = ALGORITHMS[transition.baseline]
    candidate_expr, candidate_operation = ALGORITHMS[transition.candidate]
    if operation != candidate_operation:
        raise ValueError("algorithms in one grid must have the same operation")
    cases: list[str] = []
    if shape == "sparse":
        prelude = _sparse_pattern_source()
    else:
        prelude = ""
    for limbs in sizes:
        setup, _, _ = _operand_setup(operation, limbs, shape)
        setup = "\n".join(
            f"    {line}" if line else line for line in setup.rstrip("\n").split("\n")
        )
        order = (
            [
                (transition.candidate, candidate_expr, 0),
                (transition.baseline, baseline_expr, 0),
                (transition.baseline, baseline_expr, 1),
                (transition.candidate, candidate_expr, 1),
            ]
            if reverse_order
            else [
                (transition.baseline, baseline_expr, 0),
                (transition.candidate, candidate_expr, 0),
                (transition.candidate, candidate_expr, 1),
                (transition.baseline, baseline_expr, 1),
            ]
        )
        benchmarks = "\n".join(
            f'''    bencher.bench(name="{algorithm}/{limbs}/{replicate}", count={sample_count}, fn() {{
      bencher.keep({expression})
    }})'''
            for algorithm, expression, replicate in order
        )
        cases.append(f"""  {{
{setup}
{benchmarks}
  }}""")
    return f'''{prelude}
///|
#skip("dispatch model calibration")
test "decimal dispatch model grid" {{
  let bencher = @bench.Bench()
{chr(10).join(cases)}
  println("{MARKER}" + bencher.dump_summaries())
}}
'''


def extract_benchmark_records(output: str) -> dict[str, BenchmarkRecord]:
    marker_index = output.rfind(MARKER)
    if marker_index < 0:
        raise RuntimeError(f"benchmark omitted {MARKER}")
    payload = json.JSONDecoder().raw_decode(output[marker_index + len(MARKER) :].lstrip())[0]
    if not isinstance(payload, list):
        raise RuntimeError("threshold benchmark payload is not an array")
    result: dict[str, BenchmarkRecord] = {}
    for record in payload:
        if not isinstance(record, dict) or not isinstance(record.get("name"), str):
            raise RuntimeError("invalid threshold benchmark record")
        median = record.get("median")
        if not isinstance(median, (int, float)) or median <= 0:
            raise RuntimeError("threshold benchmark median must be positive")
        mad_pct = record.get("median_abs_dev_pct")
        runs = record.get("runs")
        if not isinstance(mad_pct, (int, float)) or mad_pct < 0:
            raise RuntimeError("threshold benchmark MAD must be non-negative")
        if isinstance(runs, bool) or not isinstance(runs, int) or runs < 9:
            raise RuntimeError("threshold benchmark requires nine runs")
        result[record["name"]] = BenchmarkRecord(
            float(median), float(mad_pct), runs
        )
    return result


def extract_records(output: str) -> dict[str, float]:
    return {
        name: record.median
        for name, record in extract_benchmark_records(output).items()
    }


def make_snapshot(parent: Path) -> Path:
    destination = parent / "repo"
    ignored = shutil.ignore_patterns(
        ".git",
        "_build",
        "target",
        ".tmp",
        ".moon",
        ".mooncakes",
        "node_modules",
    )
    shutil.copytree(ROOT, destination, ignore=ignored, symlinks=True)
    mooncakes = ROOT / ".mooncakes"
    if mooncakes.is_dir():
        (destination / ".mooncakes").symlink_to(mooncakes, target_is_directory=True)
    lock = ROOT / ".moon-lock"
    if lock.exists():
        shutil.copy2(lock, destination / ".moon-lock")
    return destination


def run_probe(
    snapshot: Path,
    transition: Transition,
    limbs: int,
    process: int,
    shape: str | None = None,
) -> float:
    order = (
        (transition.baseline, transition.candidate)
        if process % 2 == 0
        else (transition.candidate, transition.baseline)
    )
    source = snapshot / "src/decimal/decimal_threshold_probe_wbtest.mbt"
    source.write_text(
        probe_source(limbs, order, transition.shape if shape is None else shape),
        encoding="utf-8",
    )
    command = [
        "sh",
        "tools/run_moon_clean_exec.sh",
        "test",
        "src/decimal/decimal_threshold_probe_wbtest.mbt",
        "--release",
        "--include-skipped",
        "--no-parallelize",
        "--target",
        "native",
    ]
    completed = subprocess.run(
        command,
        cwd=snapshot,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    if completed.returncode:
        raise RuntimeError(completed.stdout)
    records = extract_records(completed.stdout)
    baseline = records[transition.baseline]
    candidate = records[transition.candidate]
    return candidate / baseline


def rotated_sizes(sizes: list[int], process: int) -> list[int]:
    if not sizes:
        raise ValueError("size grid must not be empty")
    offset = process % len(sizes)
    rotated = sizes[offset:] + sizes[:offset]
    return list(reversed(rotated)) if process % 2 else rotated


def run_grid_process(
    snapshot: Path,
    transition: Transition,
    sizes: list[int],
    process: int,
    target: str,
    sample_count: int = 9,
    shape: str | None = None,
) -> tuple[dict[int, float], float]:
    source = snapshot / "src/decimal/decimal_threshold_probe_wbtest.mbt"
    source.write_text(
        grid_source(
            transition,
            rotated_sizes(sizes, process),
            reverse_order=process % 2 == 1,
            shape=transition.shape if shape is None else shape,
            sample_count=sample_count,
        ),
        encoding="utf-8",
    )
    command = [
        "sh",
        "tools/run_moon_clean_exec.sh",
        "test",
        "src/decimal/decimal_threshold_probe_wbtest.mbt",
        "--release",
        "--include-skipped",
        "--no-parallelize",
        "--target",
        target,
    ]
    completed = subprocess.run(
        command,
        cwd=snapshot,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    if completed.returncode:
        raise RuntimeError(completed.stdout)
    records = extract_benchmark_records(completed.stdout)
    ratios: dict[int, float] = {}
    maximum_mad = 0.0
    for size in sizes:
        baseline_first = records[f"{transition.baseline}/{size}/0"]
        baseline_second = records[f"{transition.baseline}/{size}/1"]
        candidate_first = records[f"{transition.candidate}/{size}/0"]
        candidate_second = records[f"{transition.candidate}/{size}/1"]
        baseline = math.sqrt(baseline_first.median * baseline_second.median)
        candidate = math.sqrt(candidate_first.median * candidate_second.median)
        ratios[size] = candidate / baseline
        maximum_mad = max(
            maximum_mad,
            baseline_first.mad_pct,
            baseline_second.mad_pct,
            candidate_first.mad_pct,
            candidate_second.mad_pct,
        )
    return ratios, maximum_mad


def candidate_wins(ratio: float, margin: float) -> bool:
    return ratio <= 1.0 - margin


def bisect_transition(
    transition: Transition,
    probe: Callable[[int], float],
    margin: float,
) -> tuple[int, int, dict[int, float]]:
    measurements: dict[int, float] = {}

    def measure(point: int) -> float:
        if point not in measurements:
            measurements[point] = probe(point)
        return measurements[point]

    low = transition.low
    high = transition.high
    if candidate_wins(measure(low), margin):
        candidate = low
        rejected = low - transition.step
        while candidate + transition.step <= high:
            if candidate_wins(measure(candidate), margin) and candidate_wins(
                measure(candidate + transition.step), margin
            ):
                return candidate, rejected, measurements
            rejected = candidate
            candidate += transition.step
        raise RuntimeError(
            f"{transition.name}: no two consecutive candidate wins in bracket; "
            f"ratios={measurements}"
        )
    if not candidate_wins(measure(high), margin):
        raise RuntimeError(
            f"{transition.name}: candidate does not win at upper bracket; "
            f"ratios={measurements}"
        )
    while high - low > transition.step:
        midpoint = low + ((high - low) // (2 * transition.step)) * transition.step
        midpoint = max(low + transition.step, min(high - transition.step, midpoint))
        if candidate_wins(measure(midpoint), margin):
            high = midpoint
        else:
            low = midpoint
    candidate = high
    while candidate + transition.step <= transition.high:
        if candidate_wins(measure(candidate), margin) and candidate_wins(
            measure(candidate + transition.step), margin
        ):
            return candidate, low, measurements
        low = candidate
        candidate += transition.step
    raise RuntimeError(
        f"{transition.name}: no two consecutive candidate wins in bracket"
    )


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--transition", choices=[item.name for item in TRANSITIONS])
    parser.add_argument("--margin", type=float, default=0.03)
    parser.add_argument("--processes", type=int)
    parser.add_argument("--model", action="store_true")
    parser.add_argument("--model-low", type=int)
    parser.add_argument("--model-high", type=int)
    parser.add_argument("--model-step", type=int)
    parser.add_argument("--bootstrap-samples", type=int, default=5000)
    parser.add_argument("--seed", type=int, default=20260713)
    parser.add_argument("--alpha", type=float, default=0.05)
    parser.add_argument("--maximum-mad-pct", type=float, default=5.0)
    parser.add_argument("--max-attempts", type=int, default=3)
    parser.add_argument("--samples", type=int, default=9)
    parser.add_argument("--target", choices=("native", "wasm", "wasm-gc", "js"), default="native")
    parser.add_argument("--shape", choices=SHAPES, default="dense")
    parser.add_argument("--output", type=Path)
    return parser.parse_args(argv)


def _capture(command: list[str]) -> str:
    completed = capture_command(command, ROOT)
    return completed.output if completed.returncode == 0 else "unavailable"


def model_grid(transition: Transition, args: argparse.Namespace) -> list[int]:
    low = args.model_low if args.model_low is not None else transition.low
    high = args.model_high if args.model_high is not None else transition.high
    step = args.model_step if args.model_step is not None else transition.step
    if low <= 0 or high <= low or step <= 0 or (high - low) % step != 0:
        raise ValueError("model grid must be a positive regular inclusive range")
    sizes = list(range(low, high + 1, step))
    shape = getattr(args, "shape", "dense")
    operation = ALGORITHMS[transition.baseline][1]
    if operation == "square" and shape == "unbalanced":
        raise ValueError("square does not have an unbalanced operand shape")
    if shape not in SHAPES:
        raise ValueError(f"unsupported operand shape: {shape}")
    capacities = {_padding_capacity(transition, size, shape) for size in sizes}
    if len(capacities) > 1:
        raise ValueError(
            f"model grid crosses padding band(s): {sorted(capacities)}; "
            "choose one regular grid per band"
        )
    return sizes


def _next_power_of_two(value: int) -> int:
    capacity = 1
    while capacity < value:
        capacity <<= 1
    return capacity


def _padding_capacity(transition: Transition, limbs: int, shape: str) -> int | None:
    operation = ALGORITHMS[transition.baseline][1]
    if operation == "square" and shape == "unbalanced":
        raise ValueError("square does not have an unbalanced operand shape")
    if transition.baseline in {"ntt", "square-ntt"} or transition.candidate in {
        "ntt",
        "square-ntt",
    }:
        right_limbs = limbs * 3 if shape == "unbalanced" else limbs
        left_digits = (limbs * 9 + 3) // 4
        right_digits = (right_limbs * 9 + 3) // 4
        return _next_power_of_two(left_digits + right_digits - 1)
    if transition.baseline == "burnikel-ziegler" or transition.candidate == "burnikel-ziegler":
        return _next_power_of_two(limbs)
    return None


def run_model(
    snapshot: Path,
    transition: Transition,
    args: argparse.Namespace,
) -> dict[str, object]:
    sizes = model_grid(transition, args)
    process_count = args.processes if args.processes is not None else 5
    if process_count < 5:
        raise ValueError("dispatch modeling requires at least five processes")
    if args.max_attempts < 1 or args.maximum_mad_pct <= 0 or args.samples < 9:
        raise ValueError("model retry, MAD limits, and samples must be valid")
    by_size: dict[int, list[float]] = {size: [] for size in sizes}
    accepted_mads: list[float] = []
    for process in range(process_count):
        for attempt in range(1, args.max_attempts + 1):
            print(
                f"[decimal-model] {transition.name}: process "
                f"{process + 1}/{process_count}, attempt {attempt}/{args.max_attempts}",
                flush=True,
            )
            ratios, maximum_mad = run_grid_process(
                snapshot,
                transition,
                sizes,
                process,
                args.target,
                args.samples,
                args.shape,
            )
            if maximum_mad <= args.maximum_mad_pct:
                for size, ratio in ratios.items():
                    by_size[size].append(ratio)
                accepted_mads.append(maximum_mad)
                break
            print(
                f"[decimal-model] rejected process MAD {maximum_mad:.4g}%",
                flush=True,
            )
        else:
            raise RuntimeError(
                f"process {process + 1} remained unstable after retries"
            )
    observations = [
        DispatchObservation(size, tuple(by_size[size]))
        for size in sizes
    ]
    model = fit_dispatch_model(
        observations,
        margin=args.margin,
        alpha=args.alpha,
        bootstrap_samples=args.bootstrap_samples,
        seed=args.seed,
    )
    return {
        "schema_version": 1,
        "captured_at_utc": utc_now_iso(),
        "transition": {
            "name": transition.name,
            "baseline": transition.baseline,
            "candidate": transition.candidate,
            "shape": args.shape,
            "padding_capacity": _padding_capacity(transition, sizes[0], args.shape),
        },
        "environment": {
            "target": args.target,
            "platform": platform.platform(),
            "machine": platform.machine(),
            "moon": _capture(["moon", "version", "--all"]),
            "git_commit": _capture(["git", "rev-parse", "HEAD"]),
            "working_tree_dirty": bool(
                _capture(["git", "status", "--porcelain", "--untracked-files=normal"])
            ),
            "schedule": "ABBA/BAAB with rotated size order",
            "samples_per_cell": args.samples,
            "maximum_within_process_mad_pct": args.maximum_mad_pct,
            "accepted_process_max_mad_pct": accepted_mads,
        },
        "model": model,
    }


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    if args.margin <= 0 or args.margin >= 1:
        raise SystemExit("margin must be in (0,1)")
    if args.processes is not None and args.processes < 1:
        raise SystemExit("processes must be positive")
    if args.model and args.transition is None:
        raise SystemExit("--model requires --transition")
    transitions = [item for item in TRANSITIONS if args.transition is None or item.name == args.transition]
    with tempfile.TemporaryDirectory(prefix="decimal-threshold-") as temporary:
        snapshot = make_snapshot(Path(temporary))
        if args.model:
            try:
                report = run_model(snapshot, transitions[0], args)
            except (OSError, RuntimeError, ValueError) as error:
                print(f"[decimal-model] error: {error}")
                return 1
            stamp = utc_stamp("%Y%m%dT%H%M%SZ")
            output = args.output or (
                ROOT
                / ".tmp"
                / "decimal-dispatch-model"
                / f"{transitions[0].name}-{stamp}.json"
            )
            write_json(output, report)
            threshold = report["model"]["threshold"]
            print(
                json.dumps(
                    {
                        "transition": transitions[0].name,
                        "threshold": threshold,
                        "report": str(output),
                    },
                    sort_keys=True,
                )
            )
            return 0
        process_count = args.processes if args.processes is not None else 3
        for transition in transitions:
            def probe(limbs: int, transition: Transition = transition) -> float:
                ratios = []
                for process in range(process_count):
                    print(
                        f"[decimal-threshold] {transition.name}: "
                        f"{limbs} limbs, process {process + 1}/{process_count}",
                        flush=True,
                    )
                    ratios.append(run_probe(snapshot, transition, limbs, process, args.shape))
                return statistics.median(ratios)

            high, low, measurements = bisect_transition(transition, probe, args.margin)
            print(json.dumps({
                "transition": transition.name,
                "baseline": transition.baseline,
                "candidate": transition.candidate,
                "candidate_threshold": high,
                "last_baseline_point": low,
                "step": transition.step,
                "ratios": {str(point): ratio for point, ratio in sorted(measurements.items())},
                "processes": process_count,
                "margin": args.margin,
            }, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
