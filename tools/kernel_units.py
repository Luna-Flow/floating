"""Incremental verification of the kernel test stages (level 1: one unit per stage and state).

The seven kernel stages of `just gate binary` (the product routes and the oracles under three
states of the limb tier, and the oracle tables) take about 220 s and always ran in full. The
package under test, `library/src/internal/binary_kernel`, is a leaf of the module: it imports only
`moonbitlang/core/...`, so nothing of the repository outside its own files is compiled into its
test executable. A unit is therefore keyed by the content of those files, not by a fingerprint
of compiled code:

* the content of every file under the package (sources, tests, row tables, the native stub,
  `moon.pkg`) and of the module files (`library/moon.mod`, `moon.work`);
* the command line of the stage, which holds the state (`LUNA_FLOATING_LIMBS=c`,
  `LUNA_FLOATING_PORTABLE=1`);
* for a `moon test` stage the compile and link command lines that `moon ... --dry-run` prints
  (flags, `-g -O0`, the files named), and the toolchain digest of the ledger (`moon`, `moonc`, the
  C compiler, the runtime, the environment the stubs read);
* for the oracle tables `tools/kernel_oracle.py` (it imports only the standard library) and the
  Python version;
* the verifier digest (the `tools/` modules the process imported).

The key is of file content, which is coarser than code: a comment-only edit of the package changes
it, and that is allowed (a false rerun costs seconds, a false reuse is a wrong claim).

The leaf property is checked, not assumed: if `moon.pkg` imports anything that is not under
`moonbitlang/core/`, `leaf_problem` says so and no unit is reused.

A reused unit is reported as reused with the commit it ran on; never as a pass. A unit is
sampled with probability `rate` each (the 2 % of the TestFloat units is `max(1, ceil(2 % of n))`,
which with seven units would rerun one stage every time): with seven units and rate 2 % a run
samples a stage once in about seven runs, and the seed is printed so that the draw can be
repeated. A sampled stage that fails although its key is recorded as passing is a defect of the
system (exit status 70), not a verification failure.

The functions are pure unless their name says they touch files or processes.
"""

from __future__ import annotations

import dataclasses
import os
import random
import re
import subprocess
import sys
from collections.abc import Callable, Mapping, Sequence
from pathlib import Path
from typing import Any

import check_imports
import code_fingerprint as cf
import incremental as inc

KERNEL_PACKAGE = "library/src/internal/binary_kernel"
KERNEL_STAGE_PREFIX = "BINARY: kernel"
CORE_PREFIX = "moonbitlang/core/"
MODULE_FILES = ("library/moon.mod", "moon.work")
# Between `verify.py` and `moon` every `moon test` stage goes through this wrapper (it chooses the
# target directory, clears lock files and execs moon): a change to it changes what runs.
MOON_WRAPPER = "tools/run_moon_clean_exec.sh"
AMBIENT_PREFIXES = ("MOON", "CODEX_MOON", "LUNA_")
DEFAULT_RATE = 0.02
KEY_VERSION = "kernel-units-v1"


@dataclasses.dataclass(frozen=True)
class KernelUnit:
    """One stage under one state: its name, command and the extra files its key covers."""

    name: str
    command: tuple[str, ...]
    kind: str  # "moon" (a `moon test` command) or "python"
    extra_files: tuple[str, ...] = ()


def kernel_units(stages: Sequence[tuple[str, tuple[str, ...]]]) -> list[KernelUnit]:
    """The kernel stages of a plan `(name, command)`, in order."""
    units = []
    for name, command in stages:
        if not name.startswith(KERNEL_STAGE_PREFIX):
            continue
        if "tools/kernel_oracle.py" in command:
            units.append(KernelUnit(name, tuple(command), "python", ("tools/kernel_oracle.py",)))
        else:
            units.append(KernelUnit(name, tuple(command), "moon", (MOON_WRAPPER,)))
    return units


def leaf_problem(imports: Sequence[str]) -> str | None:
    """Why the package is not a leaf (an import outside `moonbitlang/core/`), or None."""
    outside = sorted(i for i in imports if not i.startswith(CORE_PREFIX))
    if outside:
        return f"{KERNEL_PACKAGE}/moon.pkg imports {outside}: not a leaf of the module, its units run"
    return None


def python_unit_problem(path: Path) -> str | None:
    """Why a Python unit is not keyed by its own file alone: it imports something that is not in the
    standard library (the program it runs would then depend on other files), or None."""
    import ast

    try:
        tree = ast.parse(path.read_text(encoding="utf-8"))
    except (OSError, SyntaxError) as error:
        return f"{path.name} cannot be read: {error}"
    outside: set[str] = set()
    for node in ast.walk(tree):
        names: list[str] = []
        if isinstance(node, ast.Import):
            names = [alias.name for alias in node.names]
        elif isinstance(node, ast.ImportFrom):
            names = [("." * node.level) + (node.module or "")]
        for name in names:
            top = name.split(".")[0]
            if name.startswith(".") or top not in sys.stdlib_module_names:
                outside.add(name)
    if outside:
        return f"{path.name} imports {sorted(outside)} outside the standard library: its unit runs"
    return None


def ambient_environment(environ: Mapping[str, str]) -> str:
    """The variables of the environment that `moon`, its wrapper or the stubs read by prefix
    (`MOON*`, `CODEX_MOON*`, `LUNA_*`), as text for the key."""
    return "\n".join(f"{k}={v}" for k, v in sorted(environ.items()) if k.startswith(AMBIENT_PREFIXES))


def package_files(repo_root: Path) -> list[Path]:
    """Every file of the package and the module files that exist, sorted."""
    files = [p for p in (repo_root / KERNEL_PACKAGE).rglob("*") if p.is_file() and "_build" not in p.parts]
    files += [repo_root / m for m in MODULE_FILES if (repo_root / m).is_file()]
    return sorted(files)


def content_digest(repo_root: Path, files: Sequence[Path]) -> str:
    return cf.hash_tree(list(files), repo_root)


def unit_key(
    unit: KernelUnit,
    package_digest: str,
    extra_digest: str,
    compile_commands: str,
    toolchain: str,
    verifier: str,
    python_version: str,
    ambient: str = "",
) -> tuple[str, dict[str, str]]:
    """The key of a unit and its components (the ledger keeps both)."""
    parts = {
        "version": KEY_VERSION,
        "unit": unit.name,
        "command": " ".join(unit.command),
        "package": package_digest,
        "extra": extra_digest,
        "compile": inc.digest(compile_commands),
        "toolchain": toolchain,
        "verifier": verifier,
        "python": python_version if unit.kind == "python" else "",
        "ambient": inc.digest(ambient),
    }
    return inc.digest(*(f"{k}={v}" for k, v in sorted(parts.items()))), parts


def decide_units(keys: Mapping[str, str], ledger_has: Callable[[str], bool], rng: random.Random, rate: float) -> dict[str, str]:
    """`unit -> "run" | "reuse" | "sample"`. A unit whose key is not in the ledger runs; a recorded
    one is reused except with probability `rate` each (drawn in the order of `keys`)."""
    out: dict[str, str] = {}
    for name, key in keys.items():
        if not ledger_has(key):
            out[name] = "run"
        else:
            out[name] = "sample" if rng.random() < rate else "reuse"
    return out


@dataclasses.dataclass
class KernelTally:
    ran: int = 0
    reused: int = 0
    sampled: int = 0
    failed: int = 0
    unrecorded: int = 0  # passed, but not recorded (the files changed during the run, or the unit is not keyed)
    disabled: str = ""


def summary_line(tally: KernelTally, seed: int, rate: float, commits: Mapping[str, int]) -> str:
    """The report line of the kernel units: ran, reused (from which commits), sampled with the
    rule, failed; never a total that mixes them."""
    if tally.disabled:
        return f"kernel units: not reusable ({tally.disabled}); ran {tally.ran}, failed {tally.failed}"
    sources = ", ".join(f"{n} from {c[:10]}" for c, n in sorted(commits.items()))
    return (
        f"kernel units: ran {tally.ran}, reused {tally.reused}" + (f" [{sources}]" if sources else "")
        + f", sampled {tally.sampled} (each reusable stage with probability {rate:g}, seed {seed}), failed {tally.failed}"
        + (f", not recorded {tally.unrecorded}" if tally.unrecorded else "")
    )


# ---------------------------------------------------------------------------------------
# Files, processes and the ledger
# ---------------------------------------------------------------------------------------


def package_imports(repo_root: Path) -> list[str]:
    return check_imports.imports_of(repo_root / KERNEL_PACKAGE / "moon.pkg")


def dry_run_commands(command: Sequence[str], repo_root: Path, run: Callable[..., str] | None = None) -> str:
    """The commands `moon` would run for a `moon test` stage (its `--dry-run` output), paths made
    relative; empty when moon cannot print them (the unit then runs)."""
    execute = run or _run
    output = execute([*command, "--dry-run"], cwd=repo_root)
    lines = [l.replace(str(repo_root), "<repo>") for l in output.splitlines() if l.strip()]
    return "\n".join(lines)


def _run(command: Sequence[str], cwd: Path) -> str:
    result = subprocess.run(list(command), cwd=cwd, capture_output=True, text=True)
    return result.stdout + result.stderr if result.returncode == 0 else ""


@dataclasses.dataclass
class Plan:
    """What `verify` knows about the kernel units before it runs the stages."""

    units: list[KernelUnit]
    keys: dict[str, str]
    parts: dict[str, dict[str, str]]
    actions: dict[str, str]
    disabled: str
    ledger: inc.Ledger
    seed: int
    rate: float
    commit: str
    dirty: bool
    repo_root: Path = Path(".")
    package_digest: str = ""
    extra_digests: dict[str, str] = dataclasses.field(default_factory=dict)
    unit_disabled: dict[str, str] = dataclasses.field(default_factory=dict)  # unit -> why it always runs


def make_plan(
    stages: Sequence[tuple[str, tuple[str, ...]]],
    repo_root: Path,
    ledger: inc.Ledger,
    seed: int,
    rate: float = DEFAULT_RATE,
    environ: Mapping[str, str] | None = None,
    run: Callable[..., str] | None = None,
) -> Plan:
    """Compute the key of every kernel unit and decide run, reuse or sample (file system and
    processes: the dry runs, the toolchain, git). An error while forming keys disables reuse."""
    units = kernel_units([(n, tuple(c)) for n, c in stages])
    commit, dirty = inc.git_head(repo_root)
    base = Plan(units, {}, {}, {u.name: "run" for u in units}, "", ledger, seed, rate, commit, dirty, repo_root)
    if not units:
        return base
    try:
        problem = leaf_problem(package_imports(repo_root))
        if problem:
            base.disabled = problem
            return base
        toolchain = cf.toolchain_digest(
            cf.collect_toolchain(repo_root, Path.home() / ".moon", cf.run_command, environ=dict(environ or {}) or None)
        )
        verifier = inc.verifier_digest(repo_root)
        package = content_digest(repo_root, package_files(repo_root))
        base.package_digest = package
        ambient = ambient_environment(os.environ if environ is None else environ)
        for unit in units:
            extra = content_digest(repo_root, [repo_root / f for f in unit.extra_files])
            base.extra_digests[unit.name] = extra
            if unit.kind == "python":
                problem = python_unit_problem(repo_root / unit.extra_files[0])
                if problem:
                    base.unit_disabled[unit.name] = problem
            compile_commands = dry_run_commands(unit.command, repo_root, run) if unit.kind == "moon" else ""
            if unit.kind == "moon" and not compile_commands:
                base.disabled = f"moon could not print the build of '{unit.name}'"
                return base
            key, parts = unit_key(unit, package, extra, compile_commands, toolchain, verifier, sys.version, ambient)
            base.keys[unit.name] = key
            base.parts[unit.name] = parts
    except (OSError, ValueError, KeyError) as error:
        base.disabled = f"no key can be formed: {error}"
        base.keys.clear()
        return base
    base.actions = decide_units(base.keys, lambda k: ledger.result(k) is not None, random.Random(seed), rate)
    for name in base.unit_disabled:
        base.actions[name] = "run"
    return base


def files_unchanged(plan: Plan, unit: KernelUnit) -> bool:
    """Whether the files of the key are what they were when the plan was made (a stage runs for
    minutes; an edit meanwhile would make the result belong to other content)."""
    repo_root = plan.repo_root
    if content_digest(repo_root, package_files(repo_root)) != plan.package_digest:
        return False
    return content_digest(repo_root, [repo_root / f for f in unit.extra_files]) == plan.extra_digests.get(unit.name)


def record_pass(plan: Plan, unit: KernelUnit, seconds: float, clock: Callable[[], str] | None = None) -> bool:
    """Append the passing run of a unit (only the runner writes the ledger, only for a pass, only
    when the files are still those of the key). Returns whether it was recorded."""
    import socket
    import time

    if unit.name in plan.unit_disabled or not files_unchanged(plan, unit):
        return False
    plan.ledger.append(
        [
            {
                "kind": "result",
                "key": plan.keys[unit.name],
                "unit": unit.name,
                "parts": plan.parts[unit.name],
                "result": {"passed": True, "seconds": round(seconds, 1)},
                "commit": plan.commit + ("+dirty" if plan.dirty else ""),
                "dirty": plan.dirty,
                "date": (clock or (lambda: time.strftime("%Y-%m-%dT%H:%M:%S%z")))(),
                "host": socket.gethostname(),
                "log": "",
            }
        ]
    )
    return True


def recorded_commit(plan: Plan, unit: KernelUnit) -> str:
    record: dict[str, Any] | None = plan.ledger.result(plan.keys[unit.name])
    return str(record["commit"]) if record else ""
