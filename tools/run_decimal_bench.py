#!/usr/bin/env python3
"""Run reproducible Decimal coefficient and semantic benchmarks.

The runner intentionally builds two isolated source snapshots.  The baseline is
created with ``git archive`` and the candidate is assembled from the current
working tree (including non-ignored untracked files), so a dirty optimization
tree can be compared without changing the caller's checkout.  Measurements are
collected in AB/BA/AB order to reduce thermal and scheduler bias.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import platform
import shlex
import shutil
import statistics
import subprocess
import sys
import tarfile
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT_DIR = REPO_ROOT / ".tmp" / "decimal-bench"
DEFAULT_MANIFEST = REPO_ROOT / "testdata" / "decimal" / "performance_baseline.json"
MARKER = "DECIMAL_BENCH_JSON="
TARGETS = ("native", "wasm", "wasm-gc", "js")
MINIMUM_RUNS = 9
PROCESS_COUNT = 3
MAX_MAD_PCT = 5.0
MAX_ATTEMPTS = 3
MAX_REGRESSION_PCT = 5.0
SCHEMA_VERSION = 1


def _finite_nonnegative(record: dict[str, Any], field: str) -> float:
    value = record.get(field)
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError(f"{record.get('name')!r} has invalid {field!r}")
    value = float(value)
    if not math.isfinite(value) or value < 0:
        raise ValueError(f"{record.get('name')!r} has invalid {field!r}")
    return value


def validate_records(records: list[dict[str, Any]], minimum_runs: int = MINIMUM_RUNS) -> None:
    """Validate one marker payload and reject incomplete benchmark cells."""
    if not records:
        raise ValueError("benchmark output contains no records")
    names: set[str] = set()
    for record in records:
        name = record.get("name")
        if not isinstance(name, str) or not name:
            raise ValueError("every benchmark record must have a non-empty name")
        if name in names:
            raise ValueError(f"duplicate benchmark name: {name!r}")
        names.add(name)
        _finite_nonnegative(record, "median")
        _finite_nonnegative(record, "median_abs_dev_pct")
        runs = record.get("runs")
        if isinstance(runs, bool) or not isinstance(runs, int) or runs < minimum_runs:
            raise ValueError(f"{name!r} has fewer than {minimum_runs} valid runs")


def extract_checksum(output: str) -> str:
    marker = "DECIMAL_BENCH_CHECKSUM="
    values = [line.split(marker, 1)[1].strip() for line in output.splitlines() if marker in line]
    if len(values) != 1 or not values[0]:
        raise ValueError("benchmark output must contain exactly one checksum marker")
    return values[0]


def extract_records(output: str, marker: str = MARKER) -> list[dict[str, Any]]:
    """Extract the first JSON array following the benchmark marker."""
    index = output.rfind(marker)
    if index < 0:
        raise ValueError(f"benchmark output omitted marker {marker}")
    encoded = output[index + len(marker) :].lstrip()
    try:
        payload, _ = json.JSONDecoder().raw_decode(encoded)
    except json.JSONDecodeError as error:
        raise ValueError(f"invalid JSON after {marker}: {error.msg}") from error
    if not isinstance(payload, list) or not all(isinstance(item, dict) for item in payload):
        raise ValueError("benchmark marker must contain a JSON array of objects")
    return payload


def _signature(records: list[dict[str, Any]]) -> tuple[str, ...]:
    return tuple(sorted(str(item["name"]) for item in records))


def _mad_pct(values: Iterable[float]) -> float:
    values = list(values)
    if not values:
        raise ValueError("at least one value is required")
    median = statistics.median(values)
    if median == 0:
        return 0.0 if all(value == 0 for value in values) else math.inf
    return statistics.median(abs(value - median) for value in values) / median * 100


def _run_command(command: list[str], cwd: Path, expected_checksum: str | None = None) -> list[dict[str, Any]]:
    completed = subprocess.run(
        command,
        cwd=cwd,
        text=True,
        encoding="utf-8",
        errors="replace",
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    sys.stdout.write(completed.stdout)
    sys.stdout.flush()
    if completed.returncode:
        raise RuntimeError(f"benchmark command failed with exit code {completed.returncode}")
    if expected_checksum is not None and extract_checksum(completed.stdout) != expected_checksum:
        raise ValueError("benchmark fixture checksum does not match manifest")
    return extract_records(completed.stdout)


def _expand_command(template: list[str], target: str) -> list[str]:
    """Expand the documented ``{target}`` placeholder without using a shell."""
    return [part.replace("{target}", target) for part in template]


def _capture(command: list[str], cwd: Path = REPO_ROOT) -> tuple[int, str]:
    completed = subprocess.run(
        command,
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    return completed.returncode, completed.stdout.strip()


def _git_output(arguments: list[str]) -> str:
    code, output = _capture(["git", *arguments])
    if code:
        raise RuntimeError(f"git {' '.join(arguments)} failed: {output}")
    return output


def _source_paths() -> list[Path]:
    raw = subprocess.run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
        cwd=REPO_ROOT,
        stdout=subprocess.PIPE,
        check=True,
    ).stdout
    paths = [Path(item) for item in raw.decode().split("\0") if item]
    return [path for path in paths if path != Path(".git") and ".git" not in path.parts]


def _copy_path(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    if source.is_symlink():
        destination.symlink_to(os.readlink(source))
    elif source.is_file():
        shutil.copy2(source, destination)


def _copy_dependency_snapshot(destination: Path) -> str | None:
    dependency_dir = REPO_ROOT / ".mooncakes"
    if not dependency_dir.is_dir():
        return None
    target = destination / ".mooncakes"
    shutil.copytree(dependency_dir, target, symlinks=True)
    lock = REPO_ROOT / ".moon-lock"
    if lock.exists():
        shutil.copy2(lock, destination / ".moon-lock")
    return hash_tree(target)


def hash_tree(root: Path) -> str:
    """Hash paths, file modes, symlink targets and bytes deterministically."""
    digest = hashlib.sha256()
    if not root.exists():
        return digest.hexdigest()
    entries = sorted(path for path in root.rglob("*") if ".git" not in path.parts)
    for path in entries:
        relative = path.relative_to(root).as_posix().encode()
        stat = path.lstat()
        digest.update(relative + b"\0" + str(stat.st_mode & 0o7777).encode() + b"\0")
        if path.is_symlink():
            digest.update(b"L" + os.readlink(path).encode() + b"\0")
        elif path.is_file():
            digest.update(b"F\0")
            with path.open("rb") as stream:
                while block := stream.read(1024 * 1024):
                    digest.update(block)
        else:
            digest.update(b"D\0")
    return digest.hexdigest()


def _inject_shared_paths(destination: Path, shared_paths: list[dict[str, str]]) -> None:
    for entry in shared_paths:
        source_text = entry.get("source")
        destination_text = entry.get("destination")
        if not isinstance(source_text, str) or not isinstance(destination_text, str):
            raise ValueError("shared benchmark paths require source and destination")
        source = REPO_ROOT / source_text
        if not source.is_file():
            raise ValueError(f"shared benchmark fixture does not exist: {source_text}")
        _copy_path(source, destination / destination_text)


def create_baseline_snapshot(
    destination: Path, commit: str, shared_paths: list[dict[str, str]] | None = None
) -> str:
    destination.mkdir(parents=True, exist_ok=True)
    archive = destination.parent / "baseline.tar"
    with archive.open("wb") as stream:
        process = subprocess.run(
            ["git", "archive", "--format=tar", commit],
            cwd=REPO_ROOT,
            stdout=stream,
            stderr=subprocess.PIPE,
            check=False,
        )
    if process.returncode:
        raise RuntimeError(process.stderr.decode(errors="replace").strip())
    with tarfile.open(archive) as tar:
        try:
            tar.extractall(destination, filter="data")
        except TypeError:  # Python < 3.12 has no extraction filter argument.
            tar.extractall(destination)
    archive.unlink()
    _copy_dependency_snapshot(destination)
    _inject_shared_paths(destination, shared_paths or [])
    return hash_tree(destination)


def create_candidate_snapshot(destination: Path, shared_paths: list[dict[str, str]]) -> str:
    destination.mkdir(parents=True, exist_ok=True)
    for relative in _source_paths():
        source = REPO_ROOT / relative
        if source.exists() or source.is_symlink():
            _copy_path(source, destination / relative)
    _copy_dependency_snapshot(destination)
    _inject_shared_paths(destination, shared_paths)
    return hash_tree(destination)


def verify_manifest(manifest: dict[str, Any], repo: Path = REPO_ROOT) -> None:
    if manifest.get("schema_version") != SCHEMA_VERSION:
        raise ValueError("unsupported Decimal benchmark manifest schema")
    baseline = manifest.get("baseline")
    if not isinstance(baseline, dict):
        raise ValueError("manifest baseline must be an object")
    commit = baseline.get("commit")
    tree = baseline.get("tree")
    if not isinstance(commit, str) or not isinstance(tree, str):
        raise ValueError("manifest baseline requires commit and tree")
    actual_commit = _git_output(["rev-parse", "--verify", commit]) if repo == REPO_ROOT else ""
    if repo == REPO_ROOT and actual_commit != commit:
        raise ValueError(f"baseline commit {commit} is not available")
    actual_tree = _git_output(["rev-parse", f"{commit}^{{tree}}"])
    if actual_tree != tree:
        raise ValueError(f"baseline tree mismatch: manifest={tree}, git={actual_tree}")
    targets = manifest.get("targets")
    if tuple(targets or ()) != TARGETS:
        raise ValueError(f"manifest targets must be exactly {TARGETS}")
    toolchain = manifest.get("toolchain")
    if not isinstance(toolchain, dict) or not toolchain.get("moon") or not toolchain.get("moonc"):
        raise ValueError("manifest requires pinned moon and moonc versions")
    benchmark = manifest.get("benchmark")
    if not isinstance(benchmark, dict) or not isinstance(benchmark.get("command"), list):
        raise ValueError("manifest benchmark.command must be an array")
    if benchmark.get("minimum_runs") != MINIMUM_RUNS:
        raise ValueError("manifest must require nine benchmark runs")


def collect_metadata(target: str, manifest: dict[str, Any], baseline_hash: str, candidate_hash: str) -> dict[str, Any]:
    moon_code, moon_version = _capture(["moon", "version", "--all"])
    if moon_code:
        raise RuntimeError("unable to query MoonBit toolchain version")
    toolchain = manifest["toolchain"]
    version_lines = [line.strip() for line in moon_version.splitlines()]

    def has_version(expected: str) -> bool:
        return any(line == expected or line.startswith(expected + " ") for line in version_lines)

    if not has_version(toolchain["moon"]) or not has_version(toolchain["moonc"]):
        raise ValueError("MoonBit toolchain does not match the pinned baseline manifest")
    _, commit = _capture(["git", "rev-parse", "HEAD"])
    _, status = _capture(["git", "status", "--porcelain", "--untracked-files=normal"])
    return {
        "captured_at_utc": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "target": target,
        "baseline": manifest["baseline"],
        "candidate": {"commit": commit or None, "dirty": bool(status), "tree_hash": candidate_hash},
        "baseline_snapshot_hash": baseline_hash,
        "dependency_hash": hash_tree(REPO_ROOT / ".mooncakes"),
        "moon_version": moon_version,
        "platform": {"system": platform.system(), "release": platform.release(), "machine": platform.machine()},
        "minimum_runs": MINIMUM_RUNS,
        "independent_processes": PROCESS_COUNT,
        "schedule": "AB/BA/AB",
        "maximum_mad_pct": MAX_MAD_PCT,
        "max_attempts": MAX_ATTEMPTS,
        "max_regression_pct": MAX_REGRESSION_PCT,
        "benchmark_command": manifest["benchmark"]["command"],
        "benchmark_checksum": manifest["benchmark"].get("checksum"),
        "llvm": "not run by policy",
    }


def _paired_cells(baseline: list[dict[str, Any]], candidate: list[dict[str, Any]]) -> list[dict[str, Any]]:
    if _signature(baseline) != _signature(candidate):
        raise ValueError("baseline and candidate benchmark cells differ")
    left = {item["name"]: item for item in baseline}
    right = {item["name"]: item for item in candidate}
    cells: list[dict[str, Any]] = []
    for name in sorted(left):
        baseline_median = _finite_nonnegative(left[name], "median")
        candidate_median = _finite_nonnegative(right[name], "median")
        if baseline_median <= 0:
            raise ValueError(f"{name!r} baseline median must be positive")
        cells.append({
            "name": name,
            "baseline": baseline_median,
            "candidate": candidate_median,
            "ratio": candidate_median / baseline_median,
            "baseline_mad_pct": _finite_nonnegative(left[name], "median_abs_dev_pct"),
            "candidate_mad_pct": _finite_nonnegative(right[name], "median_abs_dev_pct"),
            "runs": {"baseline": left[name]["runs"], "candidate": right[name]["runs"]},
        })
    return cells


def run_target(
    target: str,
    baseline_root: Path,
    candidate_root: Path,
    command_template: list[str],
    minimum_runs: int = MINIMUM_RUNS,
    expected_checksum: str | None = None,
) -> dict[str, Any]:
    """Run AB/BA/AB and return paired cells plus process-level MAD."""
    rounds: list[tuple[str, str]] = [("baseline", "candidate"), ("candidate", "baseline"), ("baseline", "candidate")]
    by_variant: dict[str, list[list[dict[str, Any]]]] = {"baseline": [], "candidate": []}
    expected_signature: tuple[str, ...] | None = None
    for round_index, order in enumerate(rounds, 1):
        for attempt in range(1, MAX_ATTEMPTS + 1):
            current: dict[str, list[dict[str, Any]]] = {}
            try:
                for variant in order:
                    root = baseline_root if variant == "baseline" else candidate_root
                    records = _run_command(
                        _expand_command(command_template, target), root, expected_checksum
                    )
                    validate_records(records, minimum_runs)
                    current[variant] = records
                if _signature(current["baseline"]) != _signature(current["candidate"]):
                    raise ValueError("benchmark cells differ between baseline and candidate")
                if expected_signature is None:
                    expected_signature = _signature(current["baseline"])
                elif expected_signature != _signature(current["baseline"]):
                    raise ValueError("benchmark cells changed between independent processes")
                if any(item["median_abs_dev_pct"] > MAX_MAD_PCT for records in current.values() for item in records):
                    raise ValueError("within-process benchmark MAD exceeds five percent")
                break
            except (RuntimeError, ValueError) as error:
                if attempt == MAX_ATTEMPTS:
                    raise ValueError(f"{target} round {round_index} failed after retries: {error}") from error
                print(f"[decimal-bench] retrying {target} round {round_index}: {error}", flush=True)
        by_variant["baseline"].append(current["baseline"])
        by_variant["candidate"].append(current["candidate"])

    cells: list[dict[str, Any]] = []
    for name in expected_signature or ():
        baseline_values = [
            float({record["name"]: record for record in records}[name]["median"])
            for records in by_variant["baseline"]
        ]
        candidate_values = [
            float({record["name"]: record for record in records}[name]["median"])
            for records in by_variant["candidate"]
        ]
        ratios = [candidate / baseline for candidate, baseline in zip(candidate_values, baseline_values)]
        cells.append({
            "name": name,
            "baseline_median": statistics.median(baseline_values),
            "candidate_median": statistics.median(candidate_values),
            "ratio": statistics.median(ratios),
            "process_medians": {"baseline": baseline_values, "candidate": candidate_values},
            "process_mad_pct": {"baseline": _mad_pct(baseline_values), "candidate": _mad_pct(candidate_values)},
        })
    unstable = [
        f"{item['name']} {variant} process MAD {item['process_mad_pct'][variant]:.6g}% exceeds {MAX_MAD_PCT}%"
        for item in cells
        for variant in ("baseline", "candidate")
        if item["process_mad_pct"][variant] > MAX_MAD_PCT
    ]
    if unstable:
        raise ValueError("; ".join(unstable))
    return {"target": target, "cells": cells}


def render_markdown(metadata: dict[str, Any], result: dict[str, Any]) -> str:
    lines = [
        "# Decimal performance baseline",
        "",
        f"- Target: `{metadata['target']}`",
        f"- Baseline: `{metadata['baseline']['commit']}` (`{metadata['baseline']['tree']}`)",
        f"- Candidate tree hash: `{metadata['candidate']['tree_hash']}`",
        f"- MoonBit: `{metadata['moon_version']}`",
        f"- Schedule: `{metadata['schedule']}`; valid runs/cell: `{metadata['minimum_runs']}`",
        f"- Fixture checksum: `{metadata['benchmark_checksum']}`",
        "- LLVM: not run by policy",
        "",
        "Ratios are candidate / baseline medians; values above 1.05 are regressions.",
        "",
        "| Cell | Baseline (µs) | Candidate (µs) | Ratio | Baseline process MAD% | Candidate process MAD% |",
        "|---|---:|---:|---:|---:|---:|",
    ]
    for cell in result["cells"]:
        lines.append(
            f"| `{cell['name']}` | {cell['baseline_median']:.6g} | {cell['candidate_median']:.6g} | "
            f"{cell['ratio']:.6g}× | {cell['process_mad_pct']['baseline']:.4g} | "
            f"{cell['process_mad_pct']['candidate']:.4g} |"
        )
    return "\n".join(lines) + "\n"


def write_artifacts(output_dir: Path, metadata: dict[str, Any], result: dict[str, Any]) -> tuple[Path, Path]:
    output_dir.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    stem = f"decimal-bench-{stamp}-{metadata['target']}"
    raw_path = output_dir / f"{stem}.json"
    markdown_path = output_dir / f"{stem}.md"
    raw_path.write_text(json.dumps({"schema_version": SCHEMA_VERSION, "metadata": metadata, "result": result}, indent=2) + "\n", encoding="utf-8")
    markdown_path.write_text(render_markdown(metadata, result), encoding="utf-8")
    return raw_path, markdown_path


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run reproducible Decimal baseline/candidate benchmarks")
    parser.add_argument("--target", choices=TARGETS, default="native")
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--benchmark-command", nargs="+", help="command template; use {target} for backend")
    parser.add_argument("--keep-snapshots", action="store_true", help="retain isolated source snapshots")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
        if not isinstance(manifest, dict):
            raise ValueError("manifest must contain a JSON object")
        verify_manifest(manifest)
        command = args.benchmark_command or manifest["benchmark"]["command"]
        shared_paths = manifest["benchmark"].get("shared_paths", [])
        if not isinstance(shared_paths, list) or not all(isinstance(item, dict) for item in shared_paths):
            raise ValueError("benchmark.shared_paths must be an array of source/destination objects")
        baseline_commit = manifest["baseline"]["commit"]
        temp = tempfile.TemporaryDirectory(prefix="decimal-bench-")
        if args.keep_snapshots:
            snapshot_parent = args.output_dir.expanduser().resolve() / f"snapshots-{args.target}"
            snapshot_parent.mkdir(parents=True, exist_ok=True)
            temp.cleanup = lambda: None  # type: ignore[method-assign]
        else:
            snapshot_parent = Path(temp.name)
        baseline_root = snapshot_parent / "baseline"
        candidate_root = snapshot_parent / "candidate"
        baseline_hash = create_baseline_snapshot(baseline_root, baseline_commit, shared_paths)
        candidate_hash = create_candidate_snapshot(candidate_root, shared_paths)
        metadata = collect_metadata(args.target, manifest, baseline_hash, candidate_hash)
        result = run_target(
            args.target,
            baseline_root,
            candidate_root,
            [str(item) for item in command],
            int(manifest["benchmark"]["minimum_runs"]),
            str(manifest["benchmark"].get("checksum", "")) or None,
        )
        raw_path, markdown_path = write_artifacts(args.output_dir.expanduser().resolve(), metadata, result)
        regressions = [cell for cell in result["cells"] if cell["ratio"] > 1 + MAX_REGRESSION_PCT / 100]
        if regressions:
            names = ", ".join(cell["name"] for cell in regressions)
            raise ValueError(
                f"performance regression exceeds {MAX_REGRESSION_PCT}%: {names}; report: {raw_path}"
            )
    except (OSError, RuntimeError, ValueError, json.JSONDecodeError) as error:
        print(f"[decimal-bench] error: {error}", file=sys.stderr)
        return 1
    print(f"[decimal-bench] raw JSON: {raw_path}")
    print(f"[decimal-bench] Markdown: {markdown_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
