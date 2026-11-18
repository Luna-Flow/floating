#!/usr/bin/env python3
"""Seeded random differential testing of `floating` against MPFR and libmpdec.

    random_differential.py run      generate rows, execute them, record JSONL
    random_differential.py replay   re-run cases named by id (or id..id)
    random_differential.py minimize shrink failing ids into regression fixtures
    random_differential.py smoke    run the committed fixtures (no oracle needed)
    random_differential.py plan     print what `run` would execute

The oracles are GNU MPFR (binary, `tools/generate_mpfr_random_oracle.c`) and
libmpdec through Python's `decimal` module (decimal,
`tools/generate_libmpdec_random.py`). Neither is the specification: a
disagreement is a lead that is triaged against IEEE 754-2019 / the General
Decimal Arithmetic text before anyone calls it a bug.

Python only generates, schedules and aggregates; the arithmetic under test runs
in MoonBit (`src/differential`, built on the mare_mark harness) and the
reference arithmetic runs in MPFR / libmpdec.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import dataclasses
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from collections import Counter
from pathlib import Path

import generate_libmpdec_random as decimal_oracle

REPO_ROOT = Path(__file__).resolve().parent.parent
RUN_ROOT = REPO_ROOT / ".tmp/random-diff"
BUILD_ROOT = REPO_ROOT / "_build/random-diff"
C_SOURCE = REPO_ROOT / "tools/generate_mpfr_random_oracle.c"
GENERATOR_BINARY = RUN_ROOT / "bin/generate_mpfr_random_oracle"
BINARY_FAMILIES = (
    "add",
    "sub",
    "mul",
    "div",
    "sqrt",
    "fma",
    "strtofr",
    "getstr",
    "shortest",
    "elem",
    "elem2",
)
DECIMAL_PREFIX = "dec-"
DECIMAL_FAMILIES = tuple(DECIMAL_PREFIX + name for name in decimal_oracle.FAMILIES)
ALL_FAMILIES = BINARY_FAMILIES + DECIMAL_FAMILIES
# `dec-*wide` samples contexts beyond the decNumber elementary limit, where the
# library answers Invalid_context by design; they are opt-in.
DEFAULT_FAMILIES = tuple(f for f in ALL_FAMILIES if not f.endswith("wide"))
TARGETS = ("native", "wasm", "js", "wasm-gc", "llvm")
HARNESS_TARGETS = ("native", "wasm", "js", "llvm")
DEFAULT_COUNT = 100_000
DEFAULT_SHARD = 100_000
DEFAULT_BATCH = 1000
FIXTURES = {
    "binary": REPO_ROOT / "testdata/bin_float/mpfr-4.2.2-random.txt",
    "binary-regression": REPO_ROOT / "testdata/bin_float/random-regressions.txt",
    "decimal": REPO_ROOT / "testdata/decimal/random/libmpdec-random.decTest",
    "decimal-regression": REPO_ROOT / "testdata/decimal/random/random-regressions.decTest",
}

class ToolError(RuntimeError):
    pass


def is_binary(family: str) -> bool:
    return family in BINARY_FAMILIES


def run_command(
    command: list[str], *, stdin: str | None = None, env: dict[str, str] | None = None
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        cwd=REPO_ROOT,
        input=stdin,
        text=True,
        capture_output=True,
        env=env,
    )


# ------------------------------------------------------------------ build ---


def find_mpfr_prefix(explicit: str | None) -> Path:
    candidates = [explicit, os.environ.get("MPFR_PREFIX"), "/opt/homebrew", "/usr/local", "/usr"]
    for candidate in candidates:
        if candidate and (Path(candidate) / "include/mpfr.h").is_file():
            return Path(candidate)
    raise ToolError("mpfr.h not found; set MPFR_PREFIX or pass --mpfr-prefix")


def build_generator(mpfr_prefix: str | None = None, force: bool = False) -> Path:
    if GENERATOR_BINARY.is_file() and not force:
        if GENERATOR_BINARY.stat().st_mtime >= C_SOURCE.stat().st_mtime:
            return GENERATOR_BINARY
    prefix = find_mpfr_prefix(mpfr_prefix)
    GENERATOR_BINARY.parent.mkdir(parents=True, exist_ok=True)
    result = run_command(
        [
            os.environ.get("CC", "cc"),
            "-O2",
            f"-I{prefix}/include",
            f"-L{prefix}/lib",
            "-o",
            str(GENERATOR_BINARY),
            str(C_SOURCE),
            "-lmpfr",
            "-lgmp",
        ]
    )
    if result.returncode != 0:
        raise ToolError("cannot build the MPFR generator:\n" + result.stderr)
    return GENERATOR_BINARY


def artifact_path(target: str) -> Path:
    base = BUILD_ROOT / target / target / "release/build/differential"
    suffix = {"native": "exe", "wasm": "wasm", "js": "js", "llvm": "exe"}[target]
    return base / f"differential.{suffix}"


def build_harness(target: str) -> Path:
    if target not in HARNESS_TARGETS:
        raise ToolError(f"the mare_mark harness is built for {', '.join(HARNESS_TARGETS)}, not {target}")
    environment = dict(os.environ)
    environment["CODEX_MOON_TARGET_DIR"] = str(BUILD_ROOT / target)
    result = run_command(
        ["sh", "tools/run_moon_clean_exec.sh", "build", "--release", "--target", target, "src/differential"],
        env=environment,
    )
    path = artifact_path(target)
    if result.returncode != 0 or not path.is_file():
        raise ToolError(f"cannot build the harness for {target}:\n{result.stdout}{result.stderr}")
    return path


def conformance_cli(target: str) -> list[str]:
    """The shared `floating-conformance` executable (sync); used for wasm-gc."""
    environment = dict(os.environ)
    environment["CODEX_MOON_TARGET_DIR"] = str(BUILD_ROOT / f"cli-{target}")
    result = run_command(
        ["sh", "tools/run_moon_clean_exec.sh", "build", "--release", "--target", target, "src/cli"],
        env=environment,
    )
    suffix = {"native": "exe", "wasm": "wasm", "wasm-gc": "wasm", "js": "js", "llvm": "exe"}[target]
    path = BUILD_ROOT / f"cli-{target}" / target / f"release/build/cli/cli.{suffix}"
    if result.returncode != 0 or not path.is_file():
        raise ToolError(f"cannot build the conformance CLI for {target}:\n{result.stdout}{result.stderr}")
    return launcher(target, path)


def launcher(target: str, path: Path) -> list[str]:
    if target in ("wasm", "wasm-gc"):
        moonrun = shutil.which("moonrun") or str(Path.home() / ".moon/bin/moonrun")
        return [moonrun, str(path), "--"]
    if target == "js":
        return ["node", str(path)]
    return [str(path)]


# -------------------------------------------------------------- generation ---


def generate_rows(family: str, seed: int, start: int, count: int, path: Path) -> None:
    """Writes the rows of `family`; decimal families are named `dec-<name>`."""
    if is_binary(family):
        result = run_command([str(GENERATOR_BINARY), family, str(seed), str(start), str(count)])
        if result.returncode != 0:
            raise ToolError(f"MPFR generator failed for {family}:\n{result.stderr}")
        path.write_text(result.stdout, encoding="utf-8")
    else:
        with path.open("w", encoding="utf-8") as stream:
            for line in decimal_oracle.generate(family.removeprefix(DECIMAL_PREFIX), seed, start, count):
                stream.write(line + "\n")


def parse_case_id(text: str) -> tuple[str, int, str, int]:
    """`<seed>.<family>.<index>` or `d<seed>.<family>.<index>`."""
    prefix, family, index = text.split(".")
    decimal = prefix.startswith("d")
    seed = int(prefix.removeprefix("d"))
    if decimal:
        family = DECIMAL_PREFIX + family
    if decimal and family not in DECIMAL_FAMILIES:
        raise ToolError(f"unknown decimal family in {text}")
    if not decimal and family not in BINARY_FAMILIES:
        raise ToolError(f"unknown binary family in {text}")
    return ("decimal" if decimal else "binary", seed, family, int(index))


def expand_ids(items: list[str]) -> list[tuple[str, int, str, int]]:
    cases: list[tuple[str, int, str, int]] = []
    for item in items:
        if ".." in item:
            first, last = item.split("..")
            kind, seed, family, low = parse_case_id(first)
            high = parse_case_id(last)[3]
            cases.extend((kind, seed, family, index) for index in range(low, high + 1))
        else:
            cases.append(parse_case_id(item))
    return cases


# ---------------------------------------------------------------- running ---


@dataclasses.dataclass
class ShardResult:
    family: str
    target: str
    seed: int
    start: int
    count: int
    operations: dict[str, int]
    validations: int
    invalid: int
    failed_batches: list[str]
    failures: list[dict[str, object]]
    seconds: float
    records: str


def operation_counts(family: str, path: Path) -> Counter[str]:
    counts: Counter[str] = Counter()
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith(("#", "--")):
            continue
        tokens = line.split()
        if is_binary(family):
            counts[tokens[1]] += 1
        elif len(tokens) > 1 and tokens[0].startswith("d") and "->" in tokens:
            counts[tokens[1]] += 1
    return counts


def harness_command(
    target: str,
    executable: Path,
    rows: Path,
    seed: int,
    batch: int,
    run_id: str,
) -> list[str]:
    arguments = [
        "--rows",
        str(rows),
        "--batch",
        str(batch),
        "--seed",
        str(seed % 2_000_000_000),
        "--run-id",
        run_id,
        "--target",
        target,
        "--replay-command",
        "python3",
        "--replay-argument",
        "tools/random_differential.py",
        "--replay-argument",
        "replay",
    ]
    return launcher(target, executable) + arguments


def run_sync_shard(
    family: str,
    target: str,
    cli: list[str],
    rows: Path,
    seed: int,
    start: int,
    count: int,
    operations: dict[str, int],
    started: float,
    keep: bool,
) -> ShardResult:
    """Wasm-GC has no mare_mark runtime: run the synchronous CLI, record no JSONL."""
    backend = "mpfr" if is_binary(family) else "gda"
    result = run_command([*cli, "--backend", backend, "--json", str(rows)])
    if not keep:
        rows.unlink(missing_ok=True)
    if result.returncode not in (0, 1):
        raise ToolError(f"wasm-gc run failed for {family}.{seed}.{start}:\n{result.stderr}{result.stdout[-2000:]}")
    payload = json.loads(result.stdout)
    failed_ids = payload["failedIds"] if backend == "mpfr" else payload["execution"]["failedIds"]
    failures = [{"reason": f"case {case_id}", "minimal_input": case_id, "shrink_path": [], "seed": str(seed)} for case_id in failed_ids]
    return ShardResult(
        family,
        target,
        seed,
        start,
        count,
        operations,
        1,
        1 if failed_ids else 0,
        [f"{failed_ids[0]}..{failed_ids[-1]}"] if failed_ids else [],
        failures,
        time.monotonic() - started,
        "",
    )


def run_shard(
    family: str,
    target: str,
    executable: Path,
    seed: int,
    start: int,
    count: int,
    batch: int,
    work: Path,
    keep: bool,
) -> ShardResult:
    started = time.monotonic()
    rows = work / f"{family}.{seed}.{start}.{'rows' if is_binary(family) else 'decTest'}"
    generate_rows(family, seed, start, count, rows)
    operations = dict(operation_counts(family, rows))
    run_id = f"{family}.{seed}.{start}.{target}"
    if target == "wasm-gc":
        return run_sync_shard(family, target, executable, rows, seed, start, count, operations, started, keep)
    result = run_command(harness_command(target, executable, rows, seed, batch, run_id))
    if not keep:
        rows.unlink(missing_ok=True)
    if result.returncode not in (0, 1):
        raise ToolError(f"harness failed for {run_id} ({result.returncode}):\n{result.stderr}{result.stdout[-2000:]}")
    validations = invalid = 0
    failed_batches: list[str] = []
    failures: list[dict[str, object]] = []
    for line in result.stdout.splitlines():
        if not line.startswith("{"):
            continue
        event = json.loads(line)
        if event["type"] == "validation":
            validations += 1
            if event["status"] != "valid":
                invalid += 1
                failed_batches.append(f"{event['operands'][0]}..{event['operands'][1]}")
        elif event["type"] == "validation_failure":
            failures.append(
                {
                    "reason": event.get("reason", ""),
                    "minimal_input": event.get("minimal_input", ""),
                    "shrink_path": event.get("shrink_path", []),
                    "seed": event.get("seed", ""),
                }
            )
    return ShardResult(
        family,
        target,
        seed,
        start,
        count,
        operations,
        validations,
        invalid,
        failed_batches,
        failures,
        time.monotonic() - started,
        result.stdout,
    )


def cmd_run(args: argparse.Namespace) -> int:
    families = args.family or list(DEFAULT_FAMILIES)
    for family in families:
        if family not in ALL_FAMILIES:
            raise ToolError(f"unknown family {family}")
    targets = args.target or ["native"]
    if any(is_binary(family) for family in families):
        build_generator(args.mpfr_prefix)
    executables = {
        target: (conformance_cli(target) if target == "wasm-gc" else build_harness(target)) for target in targets
    }
    run_dir = Path(args.out) if args.out else RUN_ROOT / (args.name or time.strftime("run-%Y%m%d-%H%M%S"))
    run_dir.mkdir(parents=True, exist_ok=True)
    work = run_dir / "rows"
    work.mkdir(exist_ok=True)
    jobs: list[tuple[str, str, int, int]] = []
    for target in targets:
        for family in families:
            for start in range(0, args.count, args.shard):
                jobs.append((family, target, start, min(args.shard, args.count - start)))
    records = {target: run_dir / f"records-{target}.jsonl" for target in targets if target != "wasm-gc"}
    lock = threading.Lock()
    results: list[ShardResult] = []
    print(f"{len(jobs)} shards, {args.count} cases per family, seed {args.seed}, targets {','.join(targets)}", flush=True)

    def work_item(job: tuple[str, str, int, int]) -> ShardResult:
        family, target, start, count = job
        shard = run_shard(family, target, executables[target], args.seed, start, count, args.batch, work, args.keep_rows)
        with lock:
            if target in records:
                with records[target].open("a", encoding="utf-8") as stream:
                    stream.write(shard.records)
            results.append(shard)
            flag = "FAIL" if shard.invalid else "ok"
            print(
                f"[{len(results)}/{len(jobs)}] {target:6} {family:10} {shard.start:>9}+{shard.count:<7} "
                f"{flag} {shard.seconds:6.1f}s",
                flush=True,
            )
        return shard

    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        list(pool.map(work_item, jobs))
    summary = summarize(results, args.seed, targets)
    (run_dir / "summary.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print_summary(summary)
    print(f"records and summary: {run_dir}")
    return 1 if summary["failedBatches"] else 0


def summarize(results: list[ShardResult], seed: int, targets: list[str]) -> dict[str, object]:
    per_target: dict[str, dict[str, Counter[str]]] = {}
    failed: list[dict[str, object]] = []
    for shard in results:
        table = per_target.setdefault(shard.target, {})
        for operation, count in shard.operations.items():
            table.setdefault(shard.family, Counter())[operation] += count
        for batch in shard.failed_batches:
            failed.append({"target": shard.target, "family": shard.family, "batch": batch})
    detail = [
        dict(
            kind="failure",
            reason=failure["reason"],
            minimal_input=failure["minimal_input"],
            shrink_path=failure["shrink_path"],
        )
        for shard in results
        for failure in shard.failures
    ]
    totals = {
        target: {family: sum(counter.values()) for family, counter in table.items()}
        for target, table in per_target.items()
    }
    operations = {
        target: {family: dict(sorted(counter.items())) for family, counter in table.items()}
        for target, table in per_target.items()
    }
    return {
        "schemaVersion": 1,
        "seed": seed,
        "targets": targets,
        "casesPerTargetAndFamily": totals,
        "casesPerOperation": operations,
        "totalCases": {target: sum(values.values()) for target, values in totals.items()},
        "batches": {
            "validated": sum(shard.validations for shard in results),
            "invalid": sum(shard.invalid for shard in results),
        },
        "failedBatches": failed,
        "failures": detail,
        "seconds": round(sum(shard.seconds for shard in results), 1),
    }


def print_summary(summary: dict[str, object]) -> None:
    for target, values in summary["casesPerTargetAndFamily"].items():  # type: ignore[union-attr]
        print(f"{target}: {sum(values.values()):,} cases")
        for family, count in sorted(values.items()):
            print(f"    {family:12} {count:>12,}")
    batches = summary["batches"]
    print(f"batches validated {batches['validated']}, invalid {batches['invalid']}")  # type: ignore[index]
    for failure in summary["failures"]:  # type: ignore[union-attr]
        print("FAILURE:", failure["reason"])


def cmd_plan(args: argparse.Namespace) -> int:
    families = args.family or list(DEFAULT_FAMILIES)
    shards = (args.count + args.shard - 1) // args.shard
    print(
        json.dumps(
            {
                "families": families,
                "targets": args.target or ["native"],
                "casesPerFamily": args.count,
                "shardsPerFamily": shards,
                "batch": args.batch,
                "seed": args.seed,
            },
            indent=2,
        )
    )
    return 0


# ------------------------------------------------------------------ replay ---


def rows_for_cases(cases: list[tuple[str, int, str, int]], work: Path) -> list[tuple[str, Path]]:
    files: list[tuple[str, Path]] = []
    for index, (kind, seed, family, number) in enumerate(cases):
        path = work / f"replay-{index}.rows"
        if kind == "binary":
            build_generator()
        generate_rows(family, seed, number, 1, path)
        files.append((kind, path))
    return files


def merge_rows(files: list[tuple[str, Path]], work: Path) -> list[tuple[str, Path]]:
    merged: dict[str, list[str]] = {"binary": [], "decimal": []}
    for kind, path in files:
        merged[kind].extend(
            line
            for line in path.read_text(encoding="utf-8").splitlines()
            if line and not line.startswith(("#", "--"))
        )
    outputs: list[tuple[str, Path]] = []
    for kind, lines in merged.items():
        if not lines:
            continue
        path = work / f"replay-{kind}.rows"
        header = "# mpfr-random-v1 replay" if kind == "binary" else "-- libmpdec-random-v1 replay\nversion: 2.62\nextended: 1"
        path.write_text(header + "\n" + "\n".join(lines) + "\n", encoding="utf-8")
        outputs.append((kind, path))
    return outputs


def execute_rows(target: str, kind: str, rows: Path) -> subprocess.CompletedProcess[str]:
    backend = "mpfr" if kind == "binary" else "gda"
    cli = conformance_cli(target)
    return run_command([*cli, "--backend", backend, str(rows)])


def cmd_replay(args: argparse.Namespace) -> int:
    cases = expand_ids(args.ids)
    status = 0
    with tempfile.TemporaryDirectory() as directory:
        work = Path(directory)
        merged = merge_rows(rows_for_cases(cases, work), work)
        for kind, path in merged:
            result = execute_rows(args.target, kind, path)
            sys.stdout.write(result.stdout)
            sys.stderr.write(result.stderr)
            status = max(status, result.returncode)
    return status


# ------------------------------------------------------------------- smoke ---

FIXTURE_SEED = 20261118
FIXTURE_COUNT = 50
XFAIL_MARKERS = ("# xfail", "-- xfail")


def xfail_ids(path: Path) -> dict[str, str]:
    """Rows annotated as known failures: `# xfail #N note` before the row."""
    known: dict[str, str] = {}
    pending: str | None = None
    for line in path.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if stripped.startswith(XFAIL_MARKERS):
            pending = stripped.split("xfail", 1)[1].strip()
            continue
        if not stripped or stripped.startswith(("#", "--")):
            continue
        first = stripped.split()[0]
        if first.endswith(":"):  # a decTest directive
            continue
        if pending is not None:
            known[first] = pending
            pending = None
    return known


def fixture_report(name: str, path: Path, cli: list[str]) -> tuple[bool, str]:
    backend = "mpfr" if name.startswith("binary") else "gda"
    result = run_command([*cli, "--backend", backend, "--json", str(path)])
    if result.returncode not in (0, 1):
        return False, f"{name}: runner failed\n{result.stderr}{result.stdout}"
    payload = json.loads(result.stdout)
    if backend == "mpfr":
        total, failed_ids = payload["totalCases"], set(payload["failedIds"])
    else:
        execution = payload["execution"]
        total, failed_ids = execution["executableCases"], set(execution["failedIds"])
        if payload["totalCases"] != total:
            return False, f"{name}: {payload['totalCases'] - total} cases are not executable"
    known = xfail_ids(path)
    unexpected = sorted(failed_ids - set(known))
    fixed = sorted(set(known) - failed_ids)
    summary = f"{name}: {total - len(failed_ids)}/{total} passed"
    if known:
        summary += f", {len(set(known) & failed_ids)} known failures (xfail)"
    summary += f" ({path.relative_to(REPO_ROOT)})"
    problems = []
    if unexpected:
        problems.append("unexpected failures: " + ", ".join(unexpected[:10]))
    if fixed:
        problems.append("known failures that now pass (remove the xfail marker): " + ", ".join(fixed[:10]))
    if problems:
        return False, summary + "\n    " + "\n    ".join(problems)
    return True, summary


def cmd_smoke(args: argparse.Namespace) -> int:
    cli = conformance_cli(args.target)
    status = 0
    for name, path in FIXTURES.items():
        if not path.is_file():
            if name.endswith("regression"):
                continue
            print(f"{name}: no fixture at {path.relative_to(REPO_ROOT)}")
            status = 1
            continue
        ok, message = fixture_report(name, path, cli)
        print(message)
        status = status or (0 if ok else 1)
    return status


def cmd_fixtures(args: argparse.Namespace) -> int:
    """Regenerates the committed seeded samples (a fixed-seed prefix of each family)."""
    build_generator(args.mpfr_prefix)
    with tempfile.TemporaryDirectory() as directory:
        work = Path(directory)
        mpfr_version, gmp_version = library_versions()
        header = (
            f"# mpfr-random-v1 mpfr={mpfr_version} gmp={gmp_version} seed={FIXTURE_SEED} "
            f"families={','.join(BINARY_FAMILIES)} cases-per-family={args.count}"
        )
        lines = [header, "# id op rounding precision emin emax tininess a b c n expected flags"]
        for family in BINARY_FAMILIES:
            rows = work / f"{family}.rows"
            generate_rows(family, FIXTURE_SEED, 0, args.count, rows)
            lines.extend(
                line for line in rows.read_text(encoding="utf-8").splitlines() if not line.startswith("#")
            )
        FIXTURES["binary"].write_text("\n".join(lines) + "\n", encoding="utf-8")
        decimal_lines = [
            f"-- libmpdec-random-v1 libmpdec={decimal_oracle.decimal.__libmpdec_version__} seed={FIXTURE_SEED} "
            f"families={','.join(decimal_oracle.FAMILIES)} cases-per-family={args.count}",
            "-- Expected results and conditions: Python decimal (libmpdec). The oracle",
            "-- is not the specification; see doc/manual/verification.md.",
            "version: 2.62",
            "extended: 1",
        ]
        for family in decimal_oracle.FAMILIES:
            if family.endswith("wide"):
                continue
            for index in range(args.count):
                decimal_lines.extend(
                    decimal_oracle.format_row(decimal_oracle.evaluate(decimal_oracle.generate_case(family, FIXTURE_SEED, index)))
                )
        FIXTURES["decimal"].write_text("\n".join(decimal_lines) + "\n", encoding="utf-8")
    for name in ("binary", "decimal"):
        print(f"{FIXTURES[name].relative_to(REPO_ROOT)}: {FIXTURES[name].stat().st_size:,} bytes")
    return 0


def library_versions() -> tuple[str, str]:
    """MPFR and GMP versions, read from the header the generator writes."""
    header = run_command([str(GENERATOR_BINARY), "add", "1", "0", "0"]).stdout.splitlines()[0]
    return header.split("mpfr=")[1].split()[0], header.split("gmp=")[1].split()[0]


# --------------------------------------------------------------- minimize ---


def minimize_cases(args: argparse.Namespace) -> int:
    import random_differential_minimize

    return random_differential_minimize.main(args)


def cmd_minimize(args: argparse.Namespace) -> int:
    return minimize_cases(args)


# ------------------------------------------------------------------- main ---


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)

    def common(sub: argparse.ArgumentParser) -> None:
        sub.add_argument("--family", action="append", choices=ALL_FAMILIES, help="family to run (repeatable; default: all)")
        sub.add_argument("--count", type=int, default=DEFAULT_COUNT, help="cases per family")
        sub.add_argument("--seed", type=int, default=20261118)
        sub.add_argument("--target", action="append", choices=TARGETS)
        sub.add_argument("--batch", type=int, default=DEFAULT_BATCH, help="cases validated together")
        sub.add_argument("--shard", type=int, default=DEFAULT_SHARD, help="cases generated per file")

    run = commands.add_parser("run", help="generate, execute and record")
    common(run)
    run.add_argument("--jobs", type=int, default=max(1, min(6, (os.cpu_count() or 2) - 2)))
    run.add_argument("--out", help="run directory (default .tmp/random-diff/run-<time>)")
    run.add_argument("--name", help="run directory name below .tmp/random-diff")
    run.add_argument("--mpfr-prefix", help="MPFR/GMP install prefix (default /opt/homebrew)")
    run.add_argument("--keep-rows", action="store_true", help="keep the generated rows")
    run.set_defaults(handler=cmd_run)

    plan = commands.add_parser("plan", help="print the run plan")
    common(plan)
    plan.set_defaults(handler=cmd_plan)

    replay = commands.add_parser("replay", help="re-run cases by id or id..id")
    replay.add_argument("--target", default="native", choices=TARGETS)
    replay.add_argument("ids", nargs="+")
    replay.set_defaults(handler=cmd_replay)

    smoke = commands.add_parser("smoke", help="run the committed fixtures")
    smoke.add_argument("--target", default="native", choices=TARGETS)
    smoke.set_defaults(handler=cmd_smoke)

    fixtures = commands.add_parser("fixtures", help="regenerate the committed seeded samples")
    fixtures.add_argument("--count", type=int, default=FIXTURE_COUNT, help="rows per family")
    fixtures.add_argument("--mpfr-prefix")
    fixtures.set_defaults(handler=cmd_fixtures)

    minimize = commands.add_parser("minimize", help="shrink failing cases into fixtures")
    minimize.add_argument("--target", default="native", choices=TARGETS)
    minimize.add_argument("--output", help="fixture file to append to")
    minimize.add_argument("ids", nargs="+")
    minimize.set_defaults(handler=cmd_minimize)
    return parser


def main(argv: list[str] | None = None) -> int:
    arguments = build_parser().parse_args(argv)
    try:
        return arguments.handler(arguments)
    except ToolError as error:
        print(error, file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
