#!/usr/bin/env python3
"""Run and summarize the BinCoeff and BinFloat white-box benchmarks."""

from __future__ import annotations

import argparse
import json
import math
import platform
import shlex
import statistics
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT_DIR = REPO_ROOT / ".tmp" / "bin-coeff-bench"
BENCHMARK_FILES = {
    "bin_coeff": "src/internal/coeff_bench_wbtest.mbt",
    "bin_float": "src/bin_float/bin_float_bench_wbtest.mbt",
}
BIN_FLOAT_RELEASE_FILTER = "BinFloat contextual arithmetic baseline"
MARKERS = {
    "BIN_COEFF_BENCH_JSON=": "bin_coeff",
    "BIN_FLOAT_BENCH_JSON=": "bin_float",
}
MINIMUM_RUNS = 9
REQUIRED_PROCESS_COUNT = 3
MAXIMUM_MAD_PCT = 5.0
MAX_PROCESS_ATTEMPTS = 3


def extract_marked_payloads(line: str) -> list[tuple[str, list[dict[str, Any]]]]:
    extracted: list[tuple[str, list[dict[str, Any]]]] = []
    decoder = json.JSONDecoder()
    for marker, suite in MARKERS.items():
        marker_index = line.find(marker)
        if marker_index < 0:
            continue
        encoded = line[marker_index + len(marker) :].lstrip()
        try:
            payload, _ = decoder.raw_decode(encoded)
        except json.JSONDecodeError as error:
            raise ValueError(f"invalid JSON after {marker}: {error.msg}") from error
        if not isinstance(payload, list):
            raise ValueError(f"payload after {marker} must be a JSON array")
        if not all(isinstance(record, dict) for record in payload):
            raise ValueError(f"payload after {marker} must contain JSON objects")
        extracted.append((suite, payload))
    return extracted


def parse_benchmark_name(name: str) -> tuple[str, str, int, str]:
    parts = name.split("/")
    if len(parts) != 4 or any(not part for part in parts):
        raise ValueError(
            f"benchmark name must have impl/op/bits/shape form: {name!r}"
        )
    implementation, operation, bits_text, shape = parts
    try:
        bits = int(bits_text)
    except ValueError as error:
        raise ValueError(f"benchmark bits must be an integer: {name!r}") from error
    if bits <= 0:
        raise ValueError(f"benchmark bits must be positive: {name!r}")
    return implementation, operation, bits, shape


def _finite_number(record: dict[str, Any], field: str) -> float:
    value = record.get(field)
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError(f"{record.get('name')!r} has invalid {field!r}")
    converted = float(value)
    if not math.isfinite(converted) or converted < 0.0:
        raise ValueError(f"{record.get('name')!r} has invalid {field!r}")
    return converted


def validate_benchmark_records(
    records: list[dict[str, Any]], minimum_runs: int = MINIMUM_RUNS
) -> None:
    names: set[str] = set()
    for record in records:
        name = record.get("name")
        if not isinstance(name, str):
            raise ValueError("every benchmark record must have a string name")
        parse_benchmark_name(name)
        if name in names:
            raise ValueError(f"duplicate benchmark name: {name!r}")
        names.add(name)
        _finite_number(record, "median")
        _finite_number(record, "median_abs_dev_pct")
        runs = record.get("runs")
        if isinstance(runs, bool) or not isinstance(runs, int):
            raise ValueError(f"{name!r} has invalid 'runs'")
        if runs < minimum_runs:
            raise ValueError(
                f"{name!r} has {runs} runs; at least {minimum_runs} are required"
            )


def unstable_benchmark_records(
    results: dict[str, list[dict[str, Any]]], maximum_mad_pct: float = MAXIMUM_MAD_PCT
) -> list[str]:
    unstable: list[str] = []
    for suite, records in sorted(results.items()):
        validate_benchmark_records(records)
        for record in records:
            mad_pct = _finite_number(record, "median_abs_dev_pct")
            if mad_pct > maximum_mad_pct:
                unstable.append(
                    f"{suite}:{record['name']} MAD {mad_pct:.6g}% exceeds "
                    f"{maximum_mad_pct:.6g}%"
                )
    return unstable


def _benchmark_signature(
    results: dict[str, list[dict[str, Any]]]
) -> dict[str, tuple[str, ...]]:
    return {
        suite: tuple(sorted(str(record["name"]) for record in records))
        for suite, records in sorted(results.items())
    }


def _median_abs_deviation_pct(values: list[float]) -> float:
    median = statistics.median(values)
    if median == 0.0:
        return 0.0 if all(value == 0.0 for value in values) else math.inf
    return statistics.median(abs(value - median) for value in values) / median * 100.0


def aggregate_process_results(
    process_results: list[dict[str, list[dict[str, Any]]]],
) -> dict[str, list[dict[str, Any]]]:
    if not process_results:
        raise ValueError("at least one benchmark process is required")
    expected_signature = _benchmark_signature(process_results[0])
    for results in process_results:
        if _benchmark_signature(results) != expected_signature:
            raise ValueError("benchmark cells changed between independent processes")

    aggregate: dict[str, list[dict[str, Any]]] = {}
    for suite, names in expected_signature.items():
        by_name = [
            {str(record["name"]): record for record in results[suite]}
            for results in process_results
        ]
        records: list[dict[str, Any]] = []
        for name in names:
            samples = [indexed[name] for indexed in by_name]
            medians = [_finite_number(sample, "median") for sample in samples]
            mad_pcts = [
                _finite_number(sample, "median_abs_dev_pct") for sample in samples
            ]
            record = dict(samples[0])
            record["median"] = statistics.median(medians)
            record["median_abs_dev_pct"] = max(mad_pcts)
            record["process_count"] = len(samples)
            record["process_medians"] = medians
            record["process_median_abs_dev_pct"] = _median_abs_deviation_pct(medians)
            record["process_mad_pcts"] = mad_pcts
            records.append(record)
        aggregate[suite] = records
    return aggregate


def run_release_benchmarks(
    commands: dict[str, list[str]],
    process_count: int = REQUIRED_PROCESS_COUNT,
    max_attempts: int = MAX_PROCESS_ATTEMPTS,
) -> dict[str, list[dict[str, Any]]]:
    if process_count != REQUIRED_PROCESS_COUNT:
        raise ValueError(
            f"release benchmark requires exactly {REQUIRED_PROCESS_COUNT} independent processes"
        )
    if max_attempts < 1:
        raise ValueError("max_attempts must be positive")

    accepted: list[dict[str, list[dict[str, Any]]]] = []
    expected_signature: dict[str, tuple[str, ...]] | None = None
    for process_index in range(process_count):
        for attempt in range(1, max_attempts + 1):
            print(
                "[bin-coeff-bench] process "
                f"{process_index + 1}/{process_count}, attempt {attempt}/{max_attempts}",
                flush=True,
            )
            results = run_benchmark_suites(commands)
            signature = _benchmark_signature(results)
            if expected_signature is None:
                expected_signature = signature
            elif signature != expected_signature:
                raise ValueError("benchmark cells changed between independent processes")
            unstable = unstable_benchmark_records(results)
            if not unstable:
                accepted.append(results)
                break
            print(
                "[bin-coeff-bench] discarded unstable process: " + "; ".join(unstable),
                flush=True,
            )
        else:
            raise ValueError(
                "benchmark process "
                f"{process_index + 1} remained unstable after {max_attempts} attempts"
            )
    return aggregate_process_results(accepted)


def _pair_implementations(
    records: list[dict[str, Any]],
    candidate_implementation: str,
    baseline_implementation: str,
    candidate_field: str,
    baseline_field: str,
    minimum_runs: int,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    validate_benchmark_records(records, minimum_runs)
    indexed: dict[tuple[str, int, str], dict[str, dict[str, Any]]] = {}
    for record in records:
        implementation, operation, bits, shape = parse_benchmark_name(record["name"])
        indexed.setdefault((operation, bits, shape), {})[implementation] = record

    pairs: list[dict[str, Any]] = []
    paired_names: set[str] = set()
    for (operation, bits, shape), implementations in indexed.items():
        candidate = implementations.get(candidate_implementation)
        baseline = implementations.get(baseline_implementation)
        if candidate is None or baseline is None:
            continue
        ratio = paired_median_ratio(candidate, baseline)
        pairs.append(
            {
                "operation": operation,
                "bits": bits,
                "shape": shape,
                candidate_field: candidate,
                baseline_field: baseline,
                "median_ratio": ratio,
            }
        )
        paired_names.update((candidate["name"], baseline["name"]))

    pairs.sort(key=lambda pair: (pair["operation"], pair["bits"], pair["shape"]))
    unpaired = [record for record in records if record["name"] not in paired_names]
    unpaired.sort(key=_record_sort_key)
    return pairs, unpaired


def paired_median_ratio(candidate: dict[str, Any], baseline: dict[str, Any]) -> float:
    candidate_medians = candidate.get("process_medians")
    baseline_medians = baseline.get("process_medians")
    if candidate_medians is None and baseline_medians is None:
        baseline_median = _finite_number(baseline, "median")
        if baseline_median == 0.0:
            raise ValueError(
                f"{baseline['name']!r} has a zero median; ratio is undefined"
            )
        return _finite_number(candidate, "median") / baseline_median
    if not isinstance(candidate_medians, list) or not isinstance(baseline_medians, list):
        raise ValueError("paired process medians must be present for both implementations")
    if len(candidate_medians) != len(baseline_medians) or not candidate_medians:
        raise ValueError("paired process medians must have the same nonzero length")
    ratios: list[float] = []
    for candidate_median, baseline_median in zip(candidate_medians, baseline_medians):
        if isinstance(candidate_median, bool) or not isinstance(
            candidate_median, (int, float)
        ):
            raise ValueError(f"{candidate['name']!r} has invalid process median")
        if isinstance(baseline_median, bool) or not isinstance(
            baseline_median, (int, float)
        ):
            raise ValueError(f"{baseline['name']!r} has invalid process median")
        candidate_value = float(candidate_median)
        baseline_value = float(baseline_median)
        if not math.isfinite(candidate_value) or candidate_value < 0.0:
            raise ValueError(f"{candidate['name']!r} has invalid process median")
        if not math.isfinite(baseline_value) or baseline_value <= 0.0:
            raise ValueError(
                f"{baseline['name']!r} has a zero or invalid process median; ratio is undefined"
            )
        ratios.append(candidate_value / baseline_value)
    return statistics.median(ratios)


def pair_coeff_vs_bigint(
    records: list[dict[str, Any]], minimum_runs: int = MINIMUM_RUNS
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    return _pair_implementations(
        records,
        "coeff",
        "bigint",
        "coeff",
        "bigint",
        minimum_runs,
    )


def pair_binfloat_vs_legacy(
    records: list[dict[str, Any]], minimum_runs: int = MINIMUM_RUNS
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    return _pair_implementations(
        records,
        "binfloat",
        "legacy",
        "binfloat",
        "legacy",
        minimum_runs,
    )


def _record_sort_key(record: dict[str, Any]) -> tuple[str, str, int, str]:
    implementation, operation, bits, shape = parse_benchmark_name(record["name"])
    return implementation, operation, bits, shape


def benchmark_command(target: str) -> list[str]:
    return benchmark_commands(target)["bin_coeff"]


def benchmark_commands(target: str) -> dict[str, list[str]]:
    def command_for(source: str) -> list[str]:
        return [
            "sh",
            "tools/run_moon_clean_exec.sh",
            "test",
            source,
            "--release",
            "--include-skipped",
            "--no-parallelize",
            "--target",
            target,
        ]

    bin_float = command_for(BENCHMARK_FILES["bin_float"])
    bin_float.extend(["-f", BIN_FLOAT_RELEASE_FILTER])
    return {
        "bin_coeff": command_for(BENCHMARK_FILES["bin_coeff"]),
        "bin_float": bin_float,
    }


def run_benchmark_suites(
    commands: dict[str, list[str]],
) -> dict[str, list[dict[str, Any]]]:
    if set(commands) != set(MARKERS.values()):
        raise ValueError("benchmark commands must contain exactly the known suites")
    results: dict[str, list[dict[str, Any]]] = {}
    for suite in sorted(commands):
        suite_results = run_benchmarks(commands[suite], required_suites=(suite,))
        results[suite] = suite_results[suite]
    return results


def run_benchmarks(
    command: list[str], required_suites: tuple[str, ...] = tuple(MARKERS.values())
) -> dict[str, list[dict[str, Any]]]:
    results = {suite: [] for suite in MARKERS.values()}
    parse_errors: list[str] = []
    process = subprocess.Popen(
        command,
        cwd=REPO_ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
        bufsize=1,
    )
    assert process.stdout is not None
    try:
        for line in process.stdout:
            sys.stdout.write(line)
            sys.stdout.flush()
            try:
                payloads = extract_marked_payloads(line)
            except ValueError as error:
                parse_errors.append(str(error))
                continue
            for suite, payload in payloads:
                results[suite].extend(payload)
    except KeyboardInterrupt:
        process.terminate()
        process.wait()
        raise
    return_code = process.wait()
    if return_code != 0:
        raise RuntimeError(f"benchmark command failed with exit code {return_code}")
    if parse_errors:
        raise ValueError("; ".join(parse_errors))
    missing = [suite for suite in required_suites if not results[suite]]
    if missing:
        raise ValueError("benchmark output omitted markers for: " + ", ".join(missing))
    return results


def _capture(command: list[str]) -> tuple[int, str]:
    completed = subprocess.run(
        command,
        cwd=REPO_ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    return completed.returncode, completed.stdout.strip()


def collect_metadata(
    target: str, commands: dict[str, list[str]]
) -> dict[str, Any]:
    git_code, git_commit = _capture(["git", "rev-parse", "--verify", "HEAD"])
    status_code, git_status = _capture(
        ["git", "status", "--porcelain", "--untracked-files=normal"]
    )
    moon_code, moon_version = _capture(["moon", "--version"])
    return {
        "captured_at_utc": datetime.now(timezone.utc)
        .isoformat()
        .replace("+00:00", "Z"),
        "target": target,
        "git": {
            "commit": git_commit if git_code == 0 else None,
            "dirty": bool(git_status) if status_code == 0 else None,
        },
        "moon_version": moon_version if moon_code == 0 else None,
        "platform": {
            "system": platform.system(),
            "release": platform.release(),
            "machine": platform.machine(),
        },
        "minimum_runs": MINIMUM_RUNS,
        "independent_processes": REQUIRED_PROCESS_COUNT,
        "maximum_mad_pct": MAXIMUM_MAD_PCT,
        "max_process_attempts": MAX_PROCESS_ATTEMPTS,
        "commands": commands,
    }


def _markdown_cell(value: Any) -> str:
    return str(value).replace("\\", "\\\\").replace("|", "\\|").replace("\n", " ")


def _metric(value: Any) -> str:
    return f"{float(value):.6g}"


def render_markdown(
    metadata: dict[str, Any], results: dict[str, list[dict[str, Any]]]
) -> str:
    coeff_pairs, unpaired_coeff = pair_coeff_vs_bigint(results["bin_coeff"])
    binfloat_pairs, unpaired_binfloat = pair_binfloat_vs_legacy(
        results["bin_float"]
    )
    standalone = [
        ("bin_coeff", record) for record in unpaired_coeff
    ] + [("bin_float", record) for record in unpaired_binfloat]
    standalone.sort(key=lambda item: (item[0], *_record_sort_key(item[1])))

    git = metadata["git"]
    platform_data = metadata["platform"]
    dirty = "unknown" if git["dirty"] is None else str(git["dirty"]).lower()
    lines = [
        "# Binary coefficient benchmark report",
        "",
        f"- UTC: `{_markdown_cell(metadata['captured_at_utc'])}`",
        f"- Target: `{_markdown_cell(metadata['target'])}`",
        f"- Git commit: `{_markdown_cell(git['commit'] or 'unknown')}`",
        f"- Git dirty: `{dirty}`",
        f"- MoonBit: `{_markdown_cell(metadata['moon_version'] or 'unknown')}`",
        "- Platform: `"
        + _markdown_cell(
            f"{platform_data['system']} {platform_data['release']} "
            f"({platform_data['machine']})"
        )
        + "`",
        f"- Minimum runs per benchmark: `{metadata['minimum_runs']}`",
        f"- Independent processes: `{metadata['independent_processes']}`",
        f"- Maximum accepted within-process MAD: `{metadata['maximum_mad_pct']:.6g}%`",
        *[
            f"- {suite} command: `{_markdown_cell(shlex.join(command))}`"
            for suite, command in sorted(metadata["commands"].items())
        ],
        "",
        "Median values are microseconds per benchmark closure (µs). Ratios are "
        "the median of same-process `candidate / baseline` pairs; values below 1 "
        "mean the candidate is faster.",
        "",
        "## Coeff vs BigInt",
        "",
    ]
    if coeff_pairs:
        lines.extend(
            [
                "| Operation | Bits | Shape | Coeff median (µs) | BigInt median (µs) | Median ratio | Coeff MAD% | BigInt MAD% | Runs (Coeff/BigInt) |",
                "|---|---:|---|---:|---:|---:|---:|---:|---:|",
            ]
        )
        for pair in coeff_pairs:
            coefficient = pair["coeff"]
            bigint = pair["bigint"]
            lines.append(
                "| "
                + " | ".join(
                    (
                        _markdown_cell(pair["operation"]),
                        str(pair["bits"]),
                        _markdown_cell(pair["shape"]),
                        _metric(coefficient["median"]),
                        _metric(bigint["median"]),
                        f"{pair['median_ratio']:.4f}×",
                        _metric(coefficient["median_abs_dev_pct"]),
                        _metric(bigint["median_abs_dev_pct"]),
                        f"{coefficient['runs']}/{bigint['runs']}",
                    )
                )
                + " |"
            )
        positive_ratios = [
            pair["median_ratio"]
            for pair in coeff_pairs
            if pair["median_ratio"] > 0
        ]
        if positive_ratios:
            geometric_mean = math.exp(
                sum(math.log(ratio) for ratio in positive_ratios)
                / len(positive_ratios)
            )
            lines.extend(
                [
                    "",
                    f"Geometric mean median ratio: **{geometric_mean:.4f}×**.",
                ]
            )
    else:
        lines.append("No coefficient benchmarks had a matching BigInt baseline.")

    lines.extend(["", "## BinFloat vs Legacy BigInt", ""])
    if binfloat_pairs:
        lines.extend(
            [
                "| Operation | Bits | Shape | BinFloat median (µs) | Legacy median (µs) | Median ratio | BinFloat MAD% | Legacy MAD% | Runs (BinFloat/Legacy) |",
                "|---|---:|---|---:|---:|---:|---:|---:|---:|",
            ]
        )
        for pair in binfloat_pairs:
            candidate = pair["binfloat"]
            legacy = pair["legacy"]
            lines.append(
                "| "
                + " | ".join(
                    (
                        _markdown_cell(pair["operation"]),
                        str(pair["bits"]),
                        _markdown_cell(pair["shape"]),
                        _metric(candidate["median"]),
                        _metric(legacy["median"]),
                        f"{pair['median_ratio']:.4f}×",
                        _metric(candidate["median_abs_dev_pct"]),
                        _metric(legacy["median_abs_dev_pct"]),
                        f"{candidate['runs']}/{legacy['runs']}",
                    )
                )
                + " |"
            )
        positive_ratios = [
            pair["median_ratio"]
            for pair in binfloat_pairs
            if pair["median_ratio"] > 0
        ]
        if positive_ratios:
            geometric_mean = math.exp(
                sum(math.log(ratio) for ratio in positive_ratios)
                / len(positive_ratios)
            )
            lines.extend(
                [
                    "",
                    f"Geometric mean median ratio: **{geometric_mean:.4f}×**.",
                ]
            )
    else:
        lines.append("No BinFloat benchmarks had a matching legacy baseline.")

    lines.extend(["", "## Standalone measurements", ""])
    if standalone:
        lines.extend(
            [
                "| Suite | Implementation | Operation | Bits | Shape | Median (µs) | MAD% | Runs |",
                "|---|---|---|---:|---|---:|---:|---:|",
            ]
        )
        for suite, record in standalone:
            implementation, operation, bits, shape = parse_benchmark_name(
                record["name"]
            )
            lines.append(
                "| "
                + " | ".join(
                    (
                        suite,
                        _markdown_cell(implementation),
                        _markdown_cell(operation),
                        str(bits),
                        _markdown_cell(shape),
                        _metric(record["median"]),
                        _metric(record["median_abs_dev_pct"]),
                        str(record["runs"]),
                    )
                )
                + " |"
            )
    else:
        lines.append("No standalone measurements were reported.")
    lines.append("")
    return "\n".join(lines)


def write_artifacts(
    output_dir: Path,
    metadata: dict[str, Any],
    results: dict[str, list[dict[str, Any]]],
) -> tuple[Path, Path]:
    output_dir.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    stem = f"bin-coeff-bench-{stamp}-{metadata['target']}"
    raw_path = output_dir / f"{stem}.json"
    summary_path = output_dir / f"{stem}.md"
    raw_path.write_text(
        json.dumps(
            {"schema_version": 2, "metadata": metadata, "results": results},
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    summary_path.write_text(render_markdown(metadata, results), encoding="utf-8")
    return raw_path, summary_path


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run release white-box benchmarks and summarize coefficient ratios."
    )
    parser.add_argument(
        "--target",
        choices=("native", "llvm", "wasm", "wasm-gc", "js"),
        default="native",
        help="MoonBit backend target (default: native)",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=DEFAULT_OUTPUT_DIR,
        help=f"artifact directory (default: {DEFAULT_OUTPUT_DIR})",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    commands = benchmark_commands(args.target)
    for suite, command in sorted(commands.items()):
        print(f"[bin-coeff-bench] running {suite}: {shlex.join(command)}", flush=True)
    try:
        metadata = collect_metadata(args.target, commands)
        results = run_release_benchmarks(commands)
        for suite, records in results.items():
            validate_benchmark_records(records)
            print(
                f"[bin-coeff-bench] validated {len(records)} {suite} records",
                flush=True,
            )
        output_dir = args.output_dir.expanduser().resolve()
        raw_path, summary_path = write_artifacts(output_dir, metadata, results)
    except (OSError, RuntimeError, ValueError) as error:
        print(f"[bin-coeff-bench] error: {error}", file=sys.stderr)
        return 1
    print(f"[bin-coeff-bench] raw JSON: {raw_path}")
    print(f"[bin-coeff-bench] Markdown: {summary_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
