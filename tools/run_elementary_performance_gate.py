#!/usr/bin/env python3
"""Compare shared 0.6.1/0.7.0 kernels with paired native measurements."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MANIFEST = ROOT / "testdata/elementary/performance_baseline.json"
DEFAULT_OUTPUT = ROOT / ".tmp/bench/elementary-baseline.json"
MARKER = "ELEMENTARY_BASELINE_JSON="
CHECKSUM_MARKER = "ELEMENTARY_BASELINE_CHECKSUM="


def load_manifest(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if value.get("schemaVersion") != 1:
        raise ValueError("unsupported elementary performance manifest")
    return value


def git_output(*arguments: str) -> str:
    result = subprocess.run(
        ["git", *arguments], cwd=ROOT, text=True, capture_output=True, check=False
    )
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip())
    return result.stdout.strip()


def verify_manifest(manifest: dict[str, Any]) -> None:
    baseline = manifest["baseline"]
    commit = git_output("rev-parse", "--verify", baseline["commit"])
    tree = git_output("rev-parse", f"{commit}^{{tree}}")
    if commit != baseline["commit"] or tree != baseline["tree"]:
        raise ValueError("elementary baseline commit or tree mismatch")
    if manifest.get("target") != "native":
        raise ValueError("elementary release performance target must be native")
    if manifest.get("pairedSamples") != 10:
        raise ValueError("elementary release gate requires ten paired samples")
    if manifest.get("practicalRegressionPct") != 3.0:
        raise ValueError("elementary release gate requires a three-percent threshold")
    if manifest.get("confidencePct") != 95.0:
        raise ValueError("elementary release gate requires 95% confidence")


def tracked_and_untracked_paths() -> list[Path]:
    result = subprocess.run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
        cwd=ROOT,
        stdout=subprocess.PIPE,
        check=True,
    )
    return [Path(item) for item in result.stdout.decode().split("\0") if item]


def copy_path(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    if source.is_symlink():
        destination.symlink_to(os.readlink(source))
    elif source.is_file():
        shutil.copy2(source, destination)


def copy_dependencies(destination: Path) -> None:
    source = ROOT / ".mooncakes"
    if source.is_dir():
        shutil.copytree(source, destination / ".mooncakes", symlinks=True)
    lock = ROOT / ".moon-lock"
    if lock.is_file():
        shutil.copy2(lock, destination / ".moon-lock")


def create_baseline(destination: Path, commit: str) -> None:
    archive = destination.parent / "baseline.tar"
    with archive.open("wb") as stream:
        result = subprocess.run(
            ["git", "archive", "--format=tar", commit],
            cwd=ROOT,
            stdout=stream,
            stderr=subprocess.PIPE,
            check=False,
        )
    if result.returncode:
        raise RuntimeError(result.stderr.decode(errors="replace").strip())
    destination.mkdir(parents=True)
    with tarfile.open(archive) as bundle:
        try:
            bundle.extractall(destination, filter="data")
        except TypeError:
            bundle.extractall(destination)
    archive.unlink()
    copy_dependencies(destination)


def create_candidate(destination: Path) -> None:
    destination.mkdir(parents=True)
    for relative in tracked_and_untracked_paths():
        source = ROOT / relative
        if source.exists() or source.is_symlink():
            copy_path(source, destination / relative)
    copy_dependencies(destination)


def inject_fixture(root: Path, manifest: dict[str, Any]) -> None:
    benchmark = manifest["benchmark"]
    package = root / "src/bin_float"
    for pattern in ("*_test.mbt", "*_wbtest.mbt", "*.mbt.md"):
        for path in package.glob(pattern):
            path.unlink()
    copy_path(ROOT / benchmark["fixture"], root / benchmark["destination"])


def parse_records(output: str, checksum: str) -> list[dict[str, Any]]:
    checksum_lines = [
        line.split(CHECKSUM_MARKER, 1)[1].strip()
        for line in output.splitlines()
        if CHECKSUM_MARKER in line
    ]
    if checksum_lines != [checksum]:
        raise ValueError("elementary benchmark fixture checksum mismatch")
    index = output.rfind(MARKER)
    if index < 0:
        raise ValueError("elementary benchmark output omitted its JSON marker")
    records, _ = json.JSONDecoder().raw_decode(output[index + len(MARKER) :].lstrip())
    if not isinstance(records, list) or not records:
        raise ValueError("elementary benchmark emitted no records")
    names: set[str] = set()
    for record in records:
        name = record.get("name")
        if not isinstance(name, str) or not name or name in names:
            raise ValueError("elementary benchmark names must be unique strings")
        names.add(name)
        if record.get("runs", 0) < 9:
            raise ValueError(f"{name}: benchmark produced fewer than nine runs")
        if float(record.get("median", 0.0)) <= 0.0:
            raise ValueError(f"{name}: benchmark median must be positive")
    return records


def run_snapshot(root: Path, manifest: dict[str, Any]) -> list[dict[str, Any]]:
    result = subprocess.run(
        manifest["benchmark"]["command"],
        cwd=root,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    if result.returncode:
        raise RuntimeError(result.stdout)
    return parse_records(result.stdout, manifest["benchmark"]["checksum"])


def medians(records: list[dict[str, Any]]) -> dict[str, float]:
    return {record["name"]: float(record["median"]) for record in records}


def collect_pairs(
    baseline: Path, candidate: Path, manifest: dict[str, Any]
) -> dict[str, dict[str, list[float]]]:
    samples: dict[str, dict[str, list[float]]] = {}
    expected_names: set[str] | None = None
    for pair_index in range(manifest["pairedSamples"]):
        order = (
            ("baseline", "candidate")
            if pair_index % 2 == 0
            else ("candidate", "baseline")
        )
        current: dict[str, dict[str, float]] = {}
        for variant in order:
            root = baseline if variant == "baseline" else candidate
            current[variant] = medians(run_snapshot(root, manifest))
        names = set(current["baseline"])
        if names != set(current["candidate"]):
            raise ValueError("baseline and candidate benchmark cells differ")
        if expected_names is None:
            expected_names = names
            samples = {
                name: {"baseline": [], "candidate": []} for name in sorted(names)
            }
        elif names != expected_names:
            raise ValueError("benchmark cells changed between paired samples")
        for name in names:
            samples[name]["baseline"].append(current["baseline"][name])
            samples[name]["candidate"].append(current["candidate"][name])
    return samples


def moon_array(values: list[float]) -> str:
    return "[" + ", ".join(repr(value) for value in values) + "]"


def write_maremark_gate(
    candidate: Path, samples: dict[str, dict[str, list[float]]]
) -> Path:
    lines = ["///|", 'test "immutable elementary baseline has no significant regression" {']
    for index, (name, pair) in enumerate(samples.items()):
        lines.extend(
            [
                f"  let comparison_{index} = confirmatory_regression(",
                f"    {moon_array(pair['baseline'])},",
                f"    {moon_array(pair['candidate'])},",
                f"    {20260715 + index}UL,",
                "  ).unwrap()",
                f"  if is_significant_regression(comparison_{index}) {{",
                f'    fail("significant performance regression: {name}")',
                "  }",
            ]
        )
    lines.extend(["}", ""])
    path = candidate / "src/bench/immutable_baseline_gate_wbtest.mbt"
    path.write_text("\n".join(lines), encoding="utf-8")
    return path


def run_maremark_gate(candidate: Path) -> None:
    result = subprocess.run(
        [
            "sh",
            "tools/run_moon_clean_exec.sh",
            "test",
            "src/bench/immutable_baseline_gate_wbtest.mbt",
            "--target",
            "native",
            "--deny-warn",
            "--no-parallelize",
        ],
        cwd=candidate,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    if result.returncode:
        raise RuntimeError(result.stdout)


def report(
    samples: dict[str, dict[str, list[float]]], manifest: dict[str, Any]
) -> dict[str, Any]:
    cells = []
    for name, pair in samples.items():
        ratios = [
            candidate / baseline
            for baseline, candidate in zip(pair["baseline"], pair["candidate"])
        ]
        cells.append(
            {
                "name": name,
                "baseline": pair["baseline"],
                "candidate": pair["candidate"],
                "pairedRatios": ratios,
            }
        )
    return {
        "schemaVersion": 1,
        "baseline": manifest["baseline"],
        "candidateRelease": manifest["candidateRelease"],
        "target": "native",
        "pairedSamples": manifest["pairedSamples"],
        "practicalRegressionPct": 3.0,
        "confidencePct": 95.0,
        "cells": cells,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--plan", action="store_true")
    args = parser.parse_args(argv)
    try:
        manifest = load_manifest(args.manifest)
        verify_manifest(manifest)
        if args.plan:
            print(json.dumps(manifest, indent=2))
            return 0
        with tempfile.TemporaryDirectory(prefix="floating-elementary-gate-") as directory:
            root = Path(directory)
            baseline = root / "baseline"
            candidate = root / "candidate"
            create_baseline(baseline, manifest["baseline"]["commit"])
            create_candidate(candidate)
            inject_fixture(baseline, manifest)
            inject_fixture(candidate, manifest)
            samples = collect_pairs(baseline, candidate, manifest)
            write_maremark_gate(candidate, samples)
            run_maremark_gate(candidate)
        payload = report(samples, manifest)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
        print(f"immutable elementary baseline: {len(payload['cells'])} cells passed")
        print(f"Maremark paired artifact: {args.output}")
        return 0
    except (OSError, RuntimeError, ValueError, KeyError, json.JSONDecodeError) as error:
        print(f"elementary performance gate failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
