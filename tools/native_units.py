#!/usr/bin/env python3
"""The `TEST: native` stage of the quick gate as incremental verification units.

The stage used to be one `moon test --target native` of every package. It is now this program,
which runs the same tests but skips the packages whose tests cannot have changed since a recorded
passing run, and says so. A *unit* is one package of the six that carry the time (`HEAVY`), or the
rest of the packages in one or two coarse units (the keyed ones, the ones that are not keyed).

The key of a unit holds, and the ledger keeps, these parts:

* `closure`: the content of every file of every package of the unit and of every package they
  import inside the two modules (the closure is computed from the `moon.pkg` files, never listed
  by hand; test and white-box test imports count), and of the module files (`library/moon.mod`,
  `tooling/moon.mod`, `moon.work`). The key is of file content, which is coarser than code: a
  comment edit reruns the packages above it. That is allowed (a false rerun costs seconds, a false
  reuse is a wrong claim);
* `command`: the `moon test` command line without the list of packages and without `--jobs`;
* `compile`: what `moon test -p <the packages of the unit> ... --dry-run` prints (the compiler
  and C compiler command lines, the files named);
* `toolchain`, `verifier` (the `tools/` modules this process imported), `wrapper` (the shell
  wrapper every moon call goes through), `ambient` (the `MOON*`, `CODEX_MOON*`, `LUNA_*`
  environment variables: the native stubs and thresholds read `LUNA_FLOATING_*`).

A unit is keyed only when every package of its closure imports nothing but the standard packages
that cannot touch files, the environment or the clock (`PURE_IMPORTS`) and the two pure modules the
library depends on; a package whose closure imports anything else (the benchmark harness, `x/fs`,
`async`) is not keyed and always runs, and the report says so. Anything that cannot be read
disables reuse for the whole stage, which then runs as it did before.

The packages that have to run share one `moon test -p ...` invocation (moon runs them in
parallel); a pass records every unit of the invocation, a failure records nothing. The units that
were drawn for the sampled rerun (probability `rate` each, the seed is printed) run in a second
invocation: a failure there is a defect of the system (exit status 70), not of the change.
Reused units are reported as `REUSED` with the commit they ran on, never as passed.

Usage: python3 tools/native_units.py [--jobs N] [--no-reuse] [--sample-rate R] [--sample-seed S]
       [--ledger FILE] [--plan-only] [--dry-run]
The functions are pure unless their name says they touch files or processes.
"""

from __future__ import annotations

import argparse
import dataclasses
import os
import random
import subprocess
import sys
import time
from collections.abc import Callable, Mapping, Sequence
from pathlib import Path

import check_imports
import code_fingerprint as cf
import incremental as inc
import kernel_units as ku

REPO_ROOT = Path(__file__).resolve().parent.parent
LIBRARY = "Luna-Flow/floating"
TOOLING = "Luna-Flow/floating-tools"
SOURCE_ROOTS = ((LIBRARY, "library/src"), (TOOLING, "tooling/src"))
MODULE_FILES = ("library/moon.mod", "tooling/moon.mod", "moon.work")
WRAPPER = ku.MOON_WRAPPER
KEY_VERSION = "native-units-v1"
STAGE = "TEST: native"
DEFAULT_RATE = ku.DEFAULT_RATE
# The packages that carry the time of the stage (measured, `.tmp/plan-0.12/x-incr-ci-package-times.md`):
# 99 % of the 128 s of per-package time. Each is its own unit.
HEAVY = tuple(
    f"{LIBRARY}/{name}" for name in ("interval", "decimal_gda", "decimal", "internal/bin_kernel", "bin_float", "internal/decimal_kernel")
)
# Imports a keyed package may have besides the packages of the two modules: they read no file,
# no environment variable and no clock.
PURE_IMPORTS = frozenset(
    {
        "moonbitlang/core/bigint",
        "moonbitlang/core/debug",
        "moonbitlang/core/string",
        "moonbitlang/core/math",
        "moonbitlang/core/ref",
        "Luna-Flow/arithmetic",
        "Luna-Flow/luna-generic",
    }
)


@dataclasses.dataclass(frozen=True)
class Package:
    id: str
    directory: str  # relative to the repository root
    imports: tuple[str, ...]


@dataclasses.dataclass(frozen=True)
class Unit:
    name: str
    members: tuple[str, ...]  # package ids, sorted
    keyed: bool  # False: always runs
    why_not: str = ""


# ---------------------------------------------------------------------------------------
# Pure parts
# ---------------------------------------------------------------------------------------


def package_id(module: str, relative: str) -> str:
    return module if relative in ("", ".") else f"{module}/{relative}"


def internal_package(path: str) -> bool:
    """Whether an import path names a package of the library or the tools module."""
    return any(path == module or path.startswith(module + "/") for module in (LIBRARY, TOOLING))


def closure(start: str, packages: Mapping[str, Package]) -> set[str]:
    """The package and everything it imports inside the two modules. Raises `KeyError` for an
    import of a package that does not exist."""
    seen: set[str] = set()
    todo = [start]
    while todo:
        current = todo.pop()
        if current in seen:
            continue
        if current not in packages:
            raise KeyError(f"the package {current} is imported but has no moon.pkg")
        seen.add(current)
        todo.extend(i for i in packages[current].imports if internal_package(i))
    return seen


def impure_imports(members: Sequence[str], packages: Mapping[str, Package]) -> list[str]:
    """Imports in the closure of the members that are neither internal nor in `PURE_IMPORTS`."""
    found: set[str] = set()
    for member in members:
        for pid in closure(member, packages):
            found.update(i for i in packages[pid].imports if not internal_package(i) and i not in PURE_IMPORTS)
    return sorted(found)


def make_units(packages: Mapping[str, Package], heavy: Sequence[str] = HEAVY) -> list[Unit]:
    """The six heavy packages, then the other packages in one unit that is keyed (all pure) and
    one that is not (they import something outside the pure set). Raises KeyError for a heavy
    package that does not exist or a broken import."""
    units: list[Unit] = []
    for pid in heavy:
        if pid not in packages:
            raise KeyError(f"heavy package {pid} does not exist")
        bad = impure_imports([pid], packages)
        units.append(Unit(pid, (pid,), not bad, f"imports {bad}" if bad else ""))
    pure: list[str] = []
    impure: list[str] = []
    for pid in sorted(set(packages) - set(heavy)):
        (impure if impure_imports([pid], packages) else pure).append(pid)
    if pure:
        units.append(Unit("rest", tuple(pure), True))
    if impure:
        units.append(Unit("rest (not keyed)", tuple(impure), False, "the closure imports packages outside the pure set"))
    return units


def unit_files(unit: Unit, packages: Mapping[str, Package]) -> list[str]:
    """Directories whose content the unit's key covers: its closure, sorted."""
    directories: set[str] = set()
    for member in unit.members:
        directories.update(packages[pid].directory for pid in closure(member, packages))
    return sorted(directories)


def test_command(prefix: Sequence[str], members: Sequence[str], jobs: int | None = None) -> tuple[str, ...]:
    """`moon test -p <members> ...` through the wrapper; `prefix` is `("--target", "native", ...)`."""
    command = ["sh", WRAPPER, "test", "-p", *members, *prefix]
    if jobs is not None:
        command += ["--jobs", str(jobs)]
    return tuple(command)


NATIVE_ARGUMENTS = ("--target", "native", "--deny-warn", "--frozen")


def whole_command(jobs: int) -> tuple[str, ...]:
    """The stage as it was before the units: every package in one `moon test`."""
    return ("sh", WRAPPER, "test", *NATIVE_ARGUMENTS, "--jobs", str(jobs))


def unit_key(
    unit: Unit,
    closure_digest: str,
    compile_commands: str,
    module_digest: str,
    wrapper_digest: str,
    toolchain: str,
    verifier: str,
    ambient: str,
) -> tuple[str, dict[str, str]]:
    parts = {
        "version": KEY_VERSION,
        "unit": unit.name,
        "members": inc.digest(*unit.members),
        "command": " ".join(NATIVE_ARGUMENTS),
        "closure": closure_digest,
        "modules": module_digest,
        "compile": inc.digest(compile_commands),
        "wrapper": wrapper_digest,
        "toolchain": toolchain,
        "verifier": verifier,
        "ambient": inc.digest(ambient),
    }
    return inc.digest(*(f"{k}={v}" for k, v in sorted(parts.items()))), parts


def to_run(units: Sequence[Unit], actions: Mapping[str, str]) -> tuple[list[str], list[str]]:
    """(packages of the units that run, packages of the units that are sampled), each sorted,
    a package in the first list never in the second."""
    first = sorted({m for u in units if actions.get(u.name, "run") == "run" for m in u.members})
    second = sorted({m for u in units if actions.get(u.name) == "sample" for m in u.members} - set(first))
    return first, second


@dataclasses.dataclass
class Tally:
    ran: int = 0
    reused: int = 0
    sampled: int = 0
    not_keyed: int = 0
    failed: int = 0
    unrecorded: int = 0
    disabled: str = ""


def summary_line(tally: Tally, seed: int, rate: float, commits: Mapping[str, int]) -> str:
    if tally.disabled:
        return f"native test units: not reusable ({tally.disabled}); ran the whole stage, failed {tally.failed}"
    sources = ", ".join(f"{n} from {c[:10]}" for c, n in sorted(commits.items()))
    return (
        f"native test units: ran {tally.ran}, reused {tally.reused}" + (f" [{sources}]" if sources else "")
        + f", sampled {tally.sampled} (each reusable unit with probability {rate:g}, seed {seed})"
        + (f", not keyed {tally.not_keyed}" if tally.not_keyed else "")
        + f", failed {tally.failed}"
        + (f", not recorded {tally.unrecorded}" if tally.unrecorded else "")
    )


# ---------------------------------------------------------------------------------------
# Files, processes and the ledger
# ---------------------------------------------------------------------------------------


def discover_packages(repo_root: Path) -> dict[str, Package]:
    """Every package that has a `moon.pkg` below the two source roots (directories that start with
    `_` hold generated or scratch packages and are skipped, as the other tools do)."""
    packages: dict[str, Package] = {}
    for module, root in SOURCE_ROOTS:
        for pkg in sorted((repo_root / root).rglob("moon.pkg")):
            relative = pkg.parent.relative_to(repo_root / root)
            if any(part.startswith("_") for part in relative.parts):
                continue
            pid = package_id(module, str(relative))
            packages[pid] = Package(pid, str(pkg.parent.relative_to(repo_root)), tuple(check_imports.imports_of(pkg)))
    return packages


def directory_files(repo_root: Path, directories: Sequence[str]) -> list[Path]:
    files: list[Path] = []
    for directory in directories:
        files += [p for p in (repo_root / directory).rglob("*") if p.is_file() and "_build" not in p.parts]
    return sorted(files)


def digest_directories(repo_root: Path, directories: Sequence[str]) -> str:
    return cf.hash_tree(directory_files(repo_root, directories), repo_root)


def module_files(repo_root: Path) -> list[Path]:
    return [repo_root / f for f in (*MODULE_FILES, WRAPPER) if (repo_root / f).is_file()]


@dataclasses.dataclass
class Plan:
    units: list[Unit]
    keys: dict[str, str]
    parts: dict[str, dict[str, str]]
    actions: dict[str, str]
    digests: dict[str, str]  # unit -> closure digest at planning time
    modules: str
    disabled: str
    ledger: inc.Ledger
    seed: int
    rate: float
    commit: str
    dirty: bool
    repo_root: Path
    packages: dict[str, Package] = dataclasses.field(default_factory=dict)


def make_plan(
    repo_root: Path,
    ledger: inc.Ledger,
    seed: int,
    rate: float = DEFAULT_RATE,
    reuse: bool = True,
    environ: Mapping[str, str] | None = None,
    run: Callable[..., str] | None = None,
    heavy: Sequence[str] = HEAVY,
) -> Plan:
    """The units, their keys and what to do with each (file system and processes: moon's dry runs,
    the toolchain, git). An error while forming keys disables reuse (the whole stage runs)."""
    commit, dirty = inc.git_head(repo_root)
    plan = Plan([], {}, {}, {}, {}, "", "", ledger, seed, rate, commit, dirty, repo_root)
    try:
        plan.packages = discover_packages(repo_root)
        plan.units = make_units(plan.packages, heavy)
        env = dict(os.environ if environ is None else environ)
        toolchain = cf.toolchain_digest(cf.collect_toolchain(repo_root, Path.home() / ".moon", cf.run_command, environ=dict(environ or {}) or None))
        verifier = inc.verifier_digest(repo_root)
        ambient = ku.ambient_environment(env)
        plan.modules = cf.hash_tree(module_files(repo_root), repo_root)
        wrapper = cf.hash_tree([repo_root / WRAPPER], repo_root)
        for unit in plan.units:
            if not unit.keyed:
                continue
            directories = unit_files(unit, plan.packages)
            plan.digests[unit.name] = digest_directories(repo_root, directories)
            compile_commands = ku.dry_run_commands(test_command(NATIVE_ARGUMENTS, unit.members), repo_root, run)
            if not compile_commands:
                plan.disabled = f"moon could not print the build of '{unit.name}'"
                return plan
            plan.keys[unit.name], plan.parts[unit.name] = unit_key(
                unit, plan.digests[unit.name], compile_commands, plan.modules, wrapper, toolchain, verifier, ambient
            )
    except (OSError, ValueError, KeyError) as error:
        plan.disabled = f"no key can be formed: {error}"
        plan.keys.clear()
        return plan
    drawn = ku.decide_units(plan.keys, lambda k: ledger.result(k) is not None, random.Random(seed), rate)
    plan.actions = {u.name: drawn.get(u.name, "run") for u in plan.units}
    if not reuse:
        plan.actions = {u.name: "run" for u in plan.units}
    return plan


def unchanged(plan: Plan, unit: Unit) -> bool:
    """Whether the files of the unit's key are what they were when the plan was made."""
    directories = unit_files(unit, plan.packages)
    return digest_directories(plan.repo_root, directories) == plan.digests.get(unit.name) and (
        cf.hash_tree(module_files(plan.repo_root), plan.repo_root) == plan.modules
    )


def record_pass(plan: Plan, unit: Unit, seconds: float, shared_with: int) -> bool:
    """Append the passing run of a unit; only for a keyed unit whose files are unchanged."""
    import socket

    if unit.name not in plan.keys or not unchanged(plan, unit):
        return False
    plan.ledger.append(
        [
            {
                "kind": "result",
                "key": plan.keys[unit.name],
                "unit": f"{STAGE} [{unit.name}]",
                "parts": plan.parts[unit.name],
                "result": {"passed": True, "seconds": round(seconds, 1), "units_in_the_run": shared_with},
                "commit": plan.commit + ("+dirty" if plan.dirty else ""),
                "dirty": plan.dirty,
                "date": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
                "host": socket.gethostname(),
                "log": "",
            }
        ]
    )
    return True


def run_plan(
    plan: Plan,
    jobs: int,
    execute: Callable[[tuple[str, ...]], int],
    out: Callable[[str], None] = print,
) -> tuple[int, Tally, dict[str, int]]:
    """Run what the plan says. Returns (exit status, tally, commits of the reused units)."""
    tally = Tally(disabled=plan.disabled)
    commits: dict[str, int] = {}
    if plan.disabled:
        status = execute(whole_command(jobs))
        tally.failed += status != 0
        return status, tally, commits
    for unit in plan.units:
        if plan.actions[unit.name] == "reuse":
            record = plan.ledger.result(plan.keys[unit.name])
            commit = str(record["commit"]) if record else ""
            tally.reused += 1
            commits[commit] = commits.get(commit, 0) + 1
            out(f"REUSED  {STAGE} [{unit.name}] (recorded on {commit[:10]}{'+dirty' if commit.endswith('+dirty') else ''}), not executed")
        elif not unit.keyed:
            tally.not_keyed += 1
            out(f"NOTE  {STAGE} [{unit.name}] is not keyed ({unit.why_not}) and runs")
    by_name = {u.name: u for u in plan.units}
    first, second = to_run(plan.units, plan.actions)
    for label, members, sampled in (("run", first, False), ("sampled rerun", second, True)):
        if not members:
            continue
        chosen = [u for u in plan.units if plan.actions[u.name] == ("sample" if sampled else "run")]
        started = time.monotonic()
        status = execute(test_command(NATIVE_ARGUMENTS, members, jobs))
        seconds = time.monotonic() - started
        names = ", ".join(u.name for u in chosen)
        if status != 0:
            tally.failed += 1
            out(f"FAIL  {STAGE} [{label}: {names}] exit {status}, {seconds:.1f}s")
            if sampled:
                out(f"DEFECT  {STAGE}: the key of {names} is recorded as passing and the sampled rerun failed: a defect of the incremental system, not of the change")
                return inc.EXIT_DEFECT, tally, commits
            return status, tally, commits
        out(f"PASS  {STAGE} [{label}: {names}], {seconds:.1f}s ({len(members)} packages in one moon invocation)")
        for unit in chosen:
            if sampled:
                tally.sampled += 1
                continue
            tally.ran += 1
            if unit.keyed and not plan.disabled:
                if not record_pass(plan, by_name[unit.name], seconds, len(chosen)):
                    tally.unrecorded += 1
                    out(f"NOTE  {unit.name} passed but was not recorded (its files changed during the run)")
    return 0, tally, commits


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--jobs", type=int, default=3)
    parser.add_argument("--no-reuse", action="store_true", help="run every unit (the result is still recorded)")
    parser.add_argument("--sample-rate", type=float, default=DEFAULT_RATE)
    parser.add_argument("--sample-seed", type=int, default=None)
    parser.add_argument("--ledger", type=Path, default=None)
    parser.add_argument("--plan-only", action="store_true", help="print what each unit would do and exit")
    parser.add_argument("--dry-run", action="store_true", help="print the units and exit")
    args = parser.parse_args(argv)
    seed = args.sample_seed if args.sample_seed is not None else int.from_bytes(os.urandom(4), "big")
    ledger = inc.Ledger(args.ledger or inc.ledger_path(REPO_ROOT))
    plan = make_plan(REPO_ROOT, ledger, seed, args.sample_rate, reuse=not args.no_reuse)
    if plan.disabled:
        print(f"native test units disabled: {plan.disabled}")
    if args.dry_run or args.plan_only:
        for unit in plan.units:
            print(f"{unit.name}: {len(unit.members)} packages, {'keyed' if unit.keyed else 'not keyed: ' + unit.why_not}, action {plan.actions.get(unit.name, 'run')}")
        return 0

    def execute(command: tuple[str, ...]) -> int:
        return subprocess.run(command, cwd=REPO_ROOT).returncode

    status, tally, commits = run_plan(plan, args.jobs, execute)
    print(summary_line(tally, seed, args.sample_rate, commits))
    return status


if __name__ == "__main__":
    raise SystemExit(main())
