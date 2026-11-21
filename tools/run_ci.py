#!/usr/bin/env python3

import argparse
import os
import signal
import subprocess
import sys
import threading
import time
from dataclasses import dataclass, replace
from pathlib import Path

from ci_schedule import Outcome, execute
from conformance_ui import Console, Progress, format_duration
from conformance_runtime import BackendName


REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_JOBS = max(1, min(8, os.cpu_count() or 1))
INTERVAL_PHASES = (
    "sets",
    "relations",
    "observations",
    "cancellation",
    "arithmetic",
    "elementary-core",
    "exponential-logarithmic",
    "general-power",
    "trigonometric",
    "hyperbolic",
    "inverse-trigonometric",
    "atan2",
    "fma",
    "integer-power",
    "extrema",
    "integer-functions",
    "multiplicative-reverse",
    "algebraic-reverse",
    "trigonometric-reverse",
    "power-reverse-1",
    "power-reverse-2",
    "atan2-reverse",
)
SUPPORTED_TARGETS = ("native", "wasm", "wasm-gc", "js")


@dataclass(frozen=True)
class Stage:
    name: str
    command: tuple[str, ...]
    # Stages of one lane run in order; lanes run concurrently (`ci_schedule`).
    # `after` is a stage of another lane that must have passed first.
    lane: str = "main"
    after: str | None = None


KERNEL_PRODUCT_ROUTES_TEST = (
    "sh",
    "tools/run_moon_clean_exec.sh",
    "test",
    "library/src/internal/bin_kernel/coeff_ntt_route_native_wbtest.mbt",
    "--include-skipped",
    "--target",
    "native",
    "--deny-warn",
    "--frozen",
)


def conformance_command(backend: BackendName, jobs: int) -> tuple[str, ...]:
    base = [
        sys.executable,
        "tools/conformance.py",
        "run",
        "--backend",
        backend.value,
    ]
    if backend != BackendName.DECIMAL:
        base.extend(("--jobs", str(jobs)))
    if backend == BackendName.BINARY:
        base.extend(("--level", "1", "--tininess", "after", "--tininess", "before"))
    if backend == BackendName.INTERVAL:
        phases = tuple(item for phase in INTERVAL_PHASES for item in ("--phase", phase))
        base.extend((*phases, "--strict-supported"))
    if backend == BackendName.DECIMAL:
        base.extend(
            (
                "--run-target",
                "native",
                "--run-target",
                "wasm",
                "--run-target",
                "wasm-gc",
                "--run-target",
                "js",
            )
        )
    return tuple(base)


# Since moon 0.1.20261028 `moon install` without a source installs a binary
# package; dependencies are fetched by an unfrozen build command instead. The
# command is the native check with `--deny-warn`: it fetches, and it is the
# only front-end pass over the native sources before the test build (which
# repeats the warning check on the same sources), so no separate native CHECK
# stage follows. The later stages stay `--frozen`.
DEPENDENCY_STAGE = Stage(
    "DEPENDENCIES: fetch",
    ("sh", "tools/run_moon_clean_exec.sh", "check", "--target", "native", "--deny-warn"),
)


# The native test stage is the longest of the quick gate and grows with every
# white-box test that keeps an old implementation next to the new one. Above
# this many seconds the gate prints a warning (it does not fail) that names the
# tool listing the slowest test files. The maintainer decides later whether the
# threshold becomes a failure.
NATIVE_TEST_STAGE_NAME = "TEST: native"
NATIVE_TEST_WARN_SECONDS = 150.0

# Front-end check of the other targets with `--deny-warn`: a change to a
# target-specific file (`*_wasm_gc.mbt`, `bin_coeff_js.mbt`, per-target
# thresholds) must not wait for the nightly run. Native keeps its own
# `--deny-warn` check in the dependency stage. Every `moon check` run from the
# repository root covers both workspace modules (library and `tooling`).
OTHER_TARGETS_STAGE_NAME = "CHECK: other targets"

# Builds the zip of each module (`moon -C library package --frozen`, then `tooling`;
# about 2 s each with the dependencies fetched) and checks its contents
# (tools/check_package_contents.py). It runs in the "moon" lane because
# `moon package` uses the target directory of the workspace root.
PACKAGE_STAGE_NAME = "PACKAGE: published contents"

DOCS_STAGE_NAME = "DOCS: manual quality and examples"
DOCS_EXAMPLES_STAGE_NAME = "DOCS: manual examples"
# Every checked-in row file and generated table has only legal contexts (`tools/context_rules.py`).
CONTEXTS_STAGE_NAME = "CONTEXTS: corpus"

# The targets whose unit tests the quick gate runs besides native. Empty: the pull-request
# job is at the maintainer's budget, and these targets are tested by the nightly workflow
# (`unit-tests` in `.github/workflows/nightly.yml`). To test js in the quick gate, change
# this one line to `("js",)`.
QUICK_TEST_TARGETS: tuple[str, ...] = ()

# Quick gate lanes (see `ci_schedule`). Stages of the "moon" lane share the
# default target directory `_build`, and `run_moon_clean_exec.sh` clears the
# lock files of that directory, so they stay in order in one lane. The
# "conformance" lane builds `tooling/src/cli` (module `Luna-Flow/floating-tools`) into `_build/conformance/cli` (its own
# target directory) and starts after the manual examples, the only stage that
# writes throwaway packages under `src`, so that no moon command in the other
# lane sees them. The "python" lane never calls moon.
QUICK_LANES: dict[str, tuple[str, str | None]] = {
    "DEPENDENCIES: fetch": ("moon", None),
    OTHER_TARGETS_STAGE_NAME: ("moon", None),
    PACKAGE_STAGE_NAME: ("moon", None),
    DOCS_EXAMPLES_STAGE_NAME: ("moon", None),
    "FORMAT: MoonBit sources": ("moon", None),
    "TEST: native": ("moon", None),
    "TEST: js": ("moon", None),
    "TEST: wasm": ("moon", None),
    "TEST: wasm-gc": ("moon", None),
    "SMOKE: IEEE 754": ("moon", None),
    "IMPORTS: package independence": ("python", None),
    CONTEXTS_STAGE_NAME: ("python", None),
    "DOCS: manual quality": ("python", None),
    "TEST: Python tooling": ("python", None),
    "SMOKE: DecimalGDA": ("conformance", DOCS_EXAMPLES_STAGE_NAME),
    "SMOKE: Binary": ("conformance", None),
    "SMOKE: Random differential": ("conformance", None),
    "SMOKE: Interval": ("conformance", None),
}


def assign_lanes(stages: list[Stage]) -> list[Stage]:
    """Quick-gate plan: the stages in lane order with their lanes set."""
    unknown = [stage.name for stage in stages if stage.name not in QUICK_LANES]
    if unknown:
        raise ValueError(f"stages without a lane: {', '.join(unknown)}")
    placed = [
        replace(stage, lane=QUICK_LANES[stage.name][0], after=QUICK_LANES[stage.name][1])
        for stage in stages
    ]
    order = {name: index for index, name in enumerate(("moon", "python", "conformance"))}
    position = {name: index for index, name in enumerate(QUICK_LANES)}
    return sorted(placed, key=lambda stage: (order[stage.lane], position[stage.name]))


def stages_for(scope: str, jobs: int) -> list[Stage]:
    suites = {
        "decimal": Stage(
            "DECIMAL: IEEE 754",
            conformance_command(BackendName.DECIMAL, 1),
        ),
        "decimal_gda": [
            Stage(
                "DECIMAL_GDA: package tests",
                (
                    "sh",
                    "tools/run_moon_clean_exec.sh",
                    "test",
                    "-p",
                    "Luna-Flow/floating/decimal_gda",
                    "--target",
                    "native",
                    "--deny-warn",
                    "--frozen",
                    "--no-parallelize",
                ),
            ),
            Stage(
                "DECIMAL_GDA: frontend tests",
                (
                    "sh",
                    "tools/run_moon_clean_exec.sh",
                    "test",
                    "-p",
                    "Luna-Flow/floating-tools/frontend/gda_expr",
                    "--target",
                    "native",
                    "--deny-warn",
                    "--frozen",
                    "--no-parallelize",
                ),
            ),
            Stage(
                "DECIMAL_GDA: official decTest",
                conformance_command(BackendName.DECIMAL_GDA, jobs),
            ),
            Stage(
                "DECIMAL_GDA: official0 decTest",
                (*conformance_command(BackendName.DECIMAL_GDA, jobs), "--corpus", "official0"),
            ),
        ],
        "binary": [
            Stage(
                "BINARY: TestFloat + MPFR",
                conformance_command(BackendName.BINARY, jobs),
            ),
            # The full list of the product routes of the native kernel (136 products at
            # 4,096 to 15,360 limbs, about 15 s): marked `#skip` so a plain `moon test`
            # runs only its subset, and run here with `--include-skipped` in the three
            # states of the row implementation (assembly or C rows, C rows, portable loops).
            *(
                Stage(f"BINARY: kernel product routes ({state})", (*prefix, *KERNEL_PRODUCT_ROUTES_TEST))
                for state, prefix in (
                    ("default", ()),
                    ("C rows", ("env", "LUNA_FLOATING_LIMBS=c")),
                    ("portable loops", ("env", "LUNA_FLOATING_PORTABLE=1")),
                )
            ),
        ],
        "interval": [
            Stage(
                "INTERVAL: IEEE 1788",
                conformance_command(BackendName.INTERVAL, jobs),
            ),
            # The long runs of the reverse trigonometric reference test (4,200
            # cases, about 40 s) and of the pow_rev1 and pow_rev2 reference tests (2,100
            # cases each) and of the atan2 reverse reference test (3,000 cases): marked `#skip` so a plain `moon test` runs only its sample,
            # and run here with `--include-skipped`.
            Stage(
                "INTERVAL: reverse trigonometric reference",
                (
                    "sh",
                    "tools/run_moon_clean_exec.sh",
                    "test",
                    "library/src/ball_float/trig_reverse_reference_wbtest.mbt",
                    "library/src/ball_float/pow_reverse_reference_wbtest.mbt",
                    "library/src/ball_float/pow_reverse2_reference_wbtest.mbt",
                    "library/src/ball_float/atan2_reverse_reference_wbtest.mbt",
                    "--include-skipped",
                    "--target",
                    "native",
                    "--deny-warn",
                    "--frozen",
                ),
            ),
        ],
        "elementary": [
            Stage(
                "ELEMENTARY: correctness and candidate workload",
                (
                    "sh",
                    "tools/run_moon_clean_exec.sh",
                    "test",
                    "-p",
                    "Luna-Flow/floating-tools/bench/bin_float",
                    "--target",
                    "native",
                    "--deny-warn",
                    "--frozen",
                    "--no-parallelize",
                ),
            ),
            Stage(
                "ELEMENTARY: immutable baseline mare_mark gate",
                (sys.executable, "tools/run_elementary_performance_gate.py"),
            ),
            Stage(
                "ELEMENTARY: candidate mare_mark workload",
                (sys.executable, "tools/benchmark.py", "elementary"),
            ),
        ],
    }
    if scope not in {"all", "quick"}:
        selected = suites[scope]
        stages = selected if isinstance(selected, list) else [selected]
        return [DEPENDENCY_STAGE, *stages]
    common_repository_stages = [
        DEPENDENCY_STAGE,
        Stage(
            "IMPORTS: package independence",
            (sys.executable, "tools/check_imports.py"),
        ),
        Stage(
            CONTEXTS_STAGE_NAME,
            (sys.executable, "tools/check_corpus_contexts.py"),
        ),
        Stage(
            "FORMAT: MoonBit sources",
            ("sh", "tools/run_moon_clean_exec.sh", "fmt", "--check"),
        ),
        Stage(
            PACKAGE_STAGE_NAME,
            (sys.executable, "tools/check_package_contents.py", "--module", "all"),
        ),
        Stage(
            DOCS_STAGE_NAME,
            (sys.executable, "tools/run_docs.py", "--skip-package-tests"),
        ),
    ]
    if scope == "quick":
        repository_stages = [
            stage
            for stage in common_repository_stages
            if stage.name != DOCS_STAGE_NAME
        ]
        return assign_lanes([
            *repository_stages,
            Stage(
                OTHER_TARGETS_STAGE_NAME,
                (
                    "sh",
                    "tools/run_moon_clean_exec.sh",
                    "check",
                    "--deny-warn",
                    "--frozen",
                    "--target",
                    ",".join(target for target in SUPPORTED_TARGETS if target != "native"),
                ),
            ),
            Stage(
                "DOCS: manual quality",
                (sys.executable, "tools/run_docs.py", "--quality-only"),
            ),
            Stage(
                DOCS_EXAMPLES_STAGE_NAME,
                (
                    sys.executable,
                    "tools/run_docs.py",
                    "--examples-only",
                    "--skip-package-tests",
                ),
            ),
            Stage(
                "TEST: native",
                (
                    "sh",
                    "tools/run_moon_clean_exec.sh",
                    "test",
                    "--target",
                    "native",
                    "--deny-warn",
                    "--frozen",
                    "--jobs",
                    str(jobs),
                ),
            ),
            *[
                Stage(
                    f"TEST: {target}",
                    (
                        "sh",
                        "tools/run_moon_clean_exec.sh",
                        "test",
                        "--target",
                        target,
                        "--deny-warn",
                        "--frozen",
                        "--jobs",
                        str(jobs),
                    ),
                )
                for target in QUICK_TEST_TARGETS
            ],
            Stage(
                "SMOKE: IEEE 754",
                (
                    sys.executable,
                    "tools/conformance.py",
                    "smoke",
                    "--backend",
                    "decimal",
                ),
            ),
            Stage(
                "TEST: Python tooling",
                # `unittest discover -s tools -p "*_test.py"` with a guard: the stage
                # fails if a test writes into the real repository (#417).
                (sys.executable, "tools/run_python_tests.py"),
            ),
            Stage(
                "SMOKE: DecimalGDA",
                (
                    sys.executable,
                    "tools/conformance.py",
                    "smoke",
                    "--backend",
                    "decimal_gda",
                ),
            ),
            Stage(
                "SMOKE: Binary",
                (
                    sys.executable,
                    "tools/conformance.py",
                    "smoke",
                    "--backend",
                    "binary",
                ),
            ),
            Stage(
                "SMOKE: Random differential",
                (sys.executable, "tools/random_differential.py", "smoke"),
            ),
            Stage(
                "SMOKE: Interval",
                (
                    sys.executable,
                    "tools/conformance.py",
                    "smoke",
                    "--backend",
                    "interval",
                    "--strict-supported",
                ),
            ),
        ])
    repository_stages = [
        *common_repository_stages,
        *[
            Stage(
                f"CHECK: {target}",
                (
                    "sh",
                    "tools/run_moon_clean_exec.sh",
                    "check",
                    "--target",
                    target,
                    "--deny-warn",
                    "--frozen",
                ),
            )
            for target in SUPPORTED_TARGETS
            if target != "native"  # checked, with --deny-warn, by the dependency stage
        ],
    ]
    return [
        *repository_stages,
        Stage("INFO: generated interfaces", ("sh", "tools/run_moon_clean_exec.sh", "info")),
        *[
            Stage(
                f"TEST: {target}",
                (
                    "sh",
                    "tools/run_moon_clean_exec.sh",
                    "test",
                    "--target",
                    target,
                    "--deny-warn",
                    "--frozen",
                    "--jobs",
                    str(jobs),
                ),
            )
            for target in SUPPORTED_TARGETS
        ],
        suites["decimal"],
        *suites["decimal_gda"],
        *suites["binary"],
        *suites["interval"],
    ]


class Children:
    """The stage processes that are running, so a failure can stop them."""

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._running: set[subprocess.Popen[str]] = set()

    def add(self, process: "subprocess.Popen[str]") -> None:
        with self._lock:
            self._running.add(process)

    def discard(self, process: "subprocess.Popen[str]") -> None:
        with self._lock:
            self._running.discard(process)

    def terminate(self) -> None:
        with self._lock:
            running = [process for process in self._running if process.poll() is None]
        for process in running:
            try:
                os.killpg(process.pid, signal.SIGTERM)  # each stage is its own group
            except (ProcessLookupError, PermissionError):
                pass


def run_captured(stage: Stage, children: Children) -> Outcome:
    started = time.monotonic()
    process = subprocess.Popen(
        stage.command,
        cwd=REPO_ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        errors="replace",
        start_new_session=True,
    )
    children.add(process)
    try:
        output, _ = process.communicate()
    finally:
        children.discard(process)
    return Outcome(process.returncode, output, time.monotonic() - started)


def slow_stage_warning(stage: Stage, seconds: float) -> str | None:
    """The warning for a native test stage over the threshold, else None."""
    if stage.name != NATIVE_TEST_STAGE_NAME or seconds <= NATIVE_TEST_WARN_SECONDS:
        return None
    return (
        f"WARNING  {stage.name} took {format_duration(seconds)}, over the "
        f"{format_duration(NATIVE_TEST_WARN_SECONDS)} budget. List the slowest test "
        "files with: python3 tools/native_test_timing.py --top 20 "
        "(run it in a heavy slot), then slim the largest."
    )


def run_parallel(stages: list[Stage], console: Console) -> int:
    children = Children()
    started = time.monotonic()

    def report(stage: Stage, outcome: Outcome) -> None:
        # Called under the scheduler's lock: the output of a stage is written in
        # one piece, preceded by its name, so concurrent stages do not interleave.
        if outcome.output.strip():
            print(f"--- output of {stage.name} (lane {stage.lane})", file=console.stream)
            print(outcome.output.rstrip("\n"), file=console.stream, flush=True)
        console.status(
            outcome.returncode == 0,
            stage.name,
            f"{format_duration(outcome.seconds)}, lane {stage.lane}",
        )
        warning = slow_stage_warning(stage, outcome.seconds)
        if warning:
            print(warning, file=console.stream, flush=True)

    code, failed = execute(
        stages,
        lambda stage: run_captured(stage, children),  # type: ignore[arg-type]
        report,  # type: ignore[arg-type]
        cancel=children.terminate,
    )
    elapsed = format_duration(time.monotonic() - started)
    if failed is not None:
        console.status(False, "repository gate", f"{failed}, {elapsed}")
        return code or 1
    console.status(True, "repository gate", elapsed)
    return 0


def run(scope: str, jobs: int, dry_run: bool = False) -> int:
    stages = stages_for(scope, jobs)
    console = Console()
    console.heading("LUNAFLOW CI", f"scope={scope}, workers={jobs}")
    if dry_run:
        for stage in stages:
            print(f"{stage.name}: [{stage.lane}] " + " ".join(stage.command))
        return 0
    if len({stage.lane for stage in stages}) > 1:
        return run_parallel(stages, console)
    progress = Progress("repository gate", len(stages), console)
    started = time.monotonic()
    completed = 0
    for stage in stages:
        progress.update(completed, stage.name)
        progress.pause()
        stage_started = time.monotonic()
        result = subprocess.run(stage.command, cwd=REPO_ROOT)
        elapsed = format_duration(time.monotonic() - stage_started)
        if result.returncode != 0:
            progress.finish(False, f"{stage.name}, {elapsed}")
            return result.returncode
        console.status(True, stage.name, elapsed)
        warning = slow_stage_warning(stage, time.monotonic() - stage_started)
        if warning:
            print(warning, file=console.stream, flush=True)
        completed += 1
        progress.update(completed, stage.name)
    progress.finish(True, format_duration(time.monotonic() - started))
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Run LunaFlow repository CI gates")
    parser.add_argument(
        "scope",
        choices=(
            "all",
            "quick",
            "decimal",
            "decimal_gda",
            "binary",
            "interval",
            "elementary",
        ),
    )
    parser.add_argument("jobs", nargs="?", type=int, default=DEFAULT_JOBS)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)
    if args.jobs <= 0:
        parser.error("jobs must be positive")
    return run(args.scope, args.jobs, args.dry_run)


if __name__ == "__main__":
    raise SystemExit(main())
