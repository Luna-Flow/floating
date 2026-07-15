#!/usr/bin/env python3
"""Run the current independent GDA engine's quick native benchmark."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tools/fixtures/gda_performance_bench_wbtest.mbt"
DESTINATION = Path("src/decimal_gda/gda_performance_wbtest.mbt")
DEFAULT_OUTPUT = ROOT / ".tmp/bench/gda-quick-native.json"
CHECKSUM_MARKER = "GDA_PERFORMANCE_CHECKSUM="
JSON_MARKER = "GDA_PERFORMANCE_JSON="
FIXTURE_MARKER = "gda-quick-v1"
MINIMUM_RUNS = 3


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while block := stream.read(1024 * 1024):
            digest.update(block)
    return digest.hexdigest()


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


def create_candidate(destination: Path) -> None:
    destination.mkdir(parents=True)
    for relative in tracked_and_untracked_paths():
        source = ROOT / relative
        if source.exists() or source.is_symlink():
            copy_path(source, destination / relative)
    dependencies = ROOT / ".mooncakes"
    if dependencies.is_dir():
        shutil.copytree(dependencies, destination / ".mooncakes", symlinks=True)
    lock = ROOT / ".moon-lock"
    if lock.is_file():
        shutil.copy2(lock, destination / ".moon-lock")


def inject_fixture(destination: Path) -> None:
    copy_path(FIXTURE, destination / DESTINATION)
    package = destination / "src/decimal_gda/moon.pkg"
    package_text = package.read_text(encoding="utf-8")
    if '"moonbitlang/core/bench"' not in package_text:
        package_text += '\nimport {\n  "moonbitlang/core/bench",\n} for "wbtest"\n'
        package.write_text(package_text, encoding="utf-8")


def extract_records(output: str) -> list[dict[str, Any]]:
    checksums = [
        line.split(CHECKSUM_MARKER, 1)[1].strip()
        for line in output.splitlines()
        if CHECKSUM_MARKER in line
    ]
    if checksums != [FIXTURE_MARKER]:
        raise ValueError("GDA quick benchmark checksum mismatch")
    index = output.rfind(JSON_MARKER)
    if index < 0:
        raise ValueError("GDA quick benchmark omitted JSON output")
    records, _ = json.JSONDecoder().raw_decode(output[index + len(JSON_MARKER) :].lstrip())
    if not isinstance(records, list) or not records:
        raise ValueError("GDA quick benchmark emitted no records")
    names: set[str] = set()
    for record in records:
        if not isinstance(record, dict):
            raise ValueError("GDA quick benchmark record must be an object")
        name = record.get("name")
        if not isinstance(name, str) or not name or name in names:
            raise ValueError("GDA quick benchmark names must be unique")
        names.add(name)
        if record.get("runs", 0) < MINIMUM_RUNS:
            raise ValueError(f"{name}: fewer than three runs")
        for field in ("median", "median_abs_dev_pct"):
            value = record.get(field)
            if (
                isinstance(value, bool)
                or not isinstance(value, (int, float))
                or not math.isfinite(float(value))
                or float(value) < 0.0
            ):
                raise ValueError(f"{name}: invalid {field}")
        if float(record["median"]) <= 0.0:
            raise ValueError(f"{name}: median must be positive")
    return records


def operations_per_invocation(name: str) -> int:
    _, operation, digits_text = name.split("/")
    digits = int(digits_text)
    if operation == "context":
        return 1_048_576 if digits <= 18 else 131_072
    if operation == "parse":
        if digits == 1:
            return 262_144
        if digits <= 18:
            return 32_768
        return 4_096 if digits <= 34 else 1_024
    if operation in {"add", "sub"}:
        return 131_072 if digits <= 18 else 16_384 if digits <= 34 else 8_192
    if operation == "mul":
        return 131_072 if digits <= 18 else 32_768
    if operation == "exact-div":
        return 32_768 if digits <= 18 else 8_192 if digits <= 34 else 4_096
    if operation == "fma":
        return 65_536 if digits <= 18 else 32_768
    if operation == "sqrt":
        return 2_048 if digits <= 9 else 1_024
    if operation == "power":
        return 4_096 if digits <= 9 else 2_048
    if operation == "ln":
        return 32 if digits <= 9 else 16
    return 16 if digits <= 9 else 8


def normalize_records(records: list[dict[str, Any]]) -> list[dict[str, Any]]:
    normalized = []
    for record in records:
        operations = operations_per_invocation(record["name"])
        normalized.append(
            {
                **record,
                "operationsPerInvocation": operations,
                "medianPerOperationMicros": float(record["median"]) / operations,
            }
        )
    return normalized


def run_benchmark() -> list[dict[str, Any]]:
    with tempfile.TemporaryDirectory(prefix="floating-gda-quick-") as directory:
        candidate = Path(directory) / "candidate"
        create_candidate(candidate)
        inject_fixture(candidate)
        command = [
            "sh",
            "tools/run_moon_clean_exec.sh",
            "test",
            str(DESTINATION),
            "--release",
            "--include-skipped",
            "--no-parallelize",
            "--target",
            "native",
        ]
        result = subprocess.run(
            command,
            cwd=candidate,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
        )
        if result.returncode:
            raise RuntimeError(result.stdout)
        return extract_records(result.stdout)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args(argv)
    try:
        records = normalize_records(run_benchmark())
        version = subprocess.run(
            ["moon", "version", "--all"],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=True,
        ).stdout.splitlines()
        payload = {
            "schemaVersion": 1,
            "target": "native",
            "fixture": {
                "source": str(FIXTURE.relative_to(ROOT)),
                "sha256": sha256(FIXTURE),
                "marker": FIXTURE_MARKER,
            },
            "toolchain": [line.strip() for line in version if line.strip()],
            "runsPerCell": MINIMUM_RUNS,
            "cells": records,
        }
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
        print(f"GDA native quick benchmark: {len(records)} cells")
        print(f"benchmark artifact: {args.output}")
        return 0
    except (OSError, RuntimeError, ValueError, json.JSONDecodeError) as error:
        print(f"GDA quick benchmark failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
