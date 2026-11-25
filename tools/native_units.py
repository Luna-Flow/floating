#!/usr/bin/env python3
"""The `TEST: native` stage of the quick gate as incremental verification units.

The stage used to be one `moon test --target native` of every package. It is now this program,
which runs the same tests but skips the packages whose tests cannot have changed since a recorded
passing run, and says so. A *unit* is one package of the six that carry the time (`HEAVY`), or the
rest of the packages in one or two coarse units (the keyed ones, the ones that are not keyed).

The key of a unit holds, and the ledger keeps, these parts:

* `closure`: the content of every file of every package of the unit, and of every file except the
  test files (`TEST_SUFFIXES`: `_wbtest.mbt`, `_test.mbt`, `.mbt.md`) of every package they import
  inside the two modules (the closure is computed from the `moon.pkg` files, never listed by
  hand; test and white-box test imports count). Test files of an imported package are compiled
  only into that package's own test executables, never into a dependent's build; the program
  checks this against moon's own dry run (`test_files_in_library_builds`) and, if a build
  without a test flag names a test file, hashes every file as key version 1 did. The `rule` part
  of the key says which was used. The key also covers the module files (`library/moon.mod`,
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

A pass is read from moon's output as well as its exit status (`judge`): moon exits 0 when a `-p`
name selects nothing (a warning, or nothing at all), so an invocation without a `Total tests: N`
line, with N = 0, with failed tests or with a `not found` warning is a failure of the stage and
records nothing. The number of tests of the invocation is in the PASS line and in the record. The
module names and source directories are read from `library/moon.mod` and `tooling/moon.mod` and
must be the constants of this file, else reuse is off. `--no-reuse` runs the stage as it was (every
package in one `moon test`, no discovery) and records every keyed unit on a pass.

The two modules this stage depends on that are not in the repository, `Luna-Flow/arithmetic` and
`Luna-Flow/luna-generic`, are in the key by the version in `moon.mod`, not by the content of
`.mooncakes`.

Which job is the audit: this program is the pull-request stage. The complete native run without
reuse, by the plain `moon test --target native --deny-warn --frozen`, must be a scheduled job
(`unit-tests` of `.github/workflows/nightly.yml`, added with the workflow change); it must not go
through this program, so that the audit does not share the discovery of packages.

Usage: python3 tools/native_units.py [--jobs N] [--no-reuse] [--sample-rate R] [--sample-seed S]
       [--ledger FILE] [--plan-only] [--dry-run]
The functions are pure unless their name says they touch files or processes.
"""

from __future__ import annotations

import argparse
import dataclasses
import os
import random
import re
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
KEY_VERSION = "native-units-v2"
STAGE = "TEST: native"
DEFAULT_RATE = ku.DEFAULT_RATE
# The packages that carry the time of the stage (measured, `.tmp/plan-0.12/x-incr-ci-package-times.md`):
# 99 % of the 128 s of per-package time. Each is its own unit.
HEAVY = tuple(
    f"{LIBRARY}/{name}" for name in ("interval", "decimal_gda", "decimal", "internal/binary_kernel", "binary", "internal/decimal_kernel")
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


# Files that moon compiles only into the test executables of their own package (white-box,
# black-box and doc tests). The build of a package that imports it never contains them, so the key
# of a unit hashes them only for the packages of the unit itself, not for the packages it imports.
TEST_SUFFIXES = ("_wbtest.mbt", "_test.mbt", ".mbt.md")
TEST_FLAGS = ("-test-mode", "-whitebox-test", "-blackbox-test", "-include-doctests", "-doctest-only")
RULE_ALL = "closure-all-files"
RULE_IMPORTED_TESTS_OUT = "closure-imported-test-files-out"


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


def is_test_file(name: str) -> bool:
    return name.endswith(TEST_SUFFIXES)


BUILD_SOURCE = re.compile(r"\./[^\s']+\.mbt(?:\.md)?")


def test_files_in_library_builds(dry_run: str) -> list[str]:
    """Source files with a test name that a `moonc build-package` line without a test flag
    compiles (pure). The rule that test files of imported packages are not part of a dependent's
    build rests on moon's naming; this finds a build that contradicts it, from moon's own dry run.
    A source is the `./path.mbt` words before the first option of the line."""
    found: set[str] = set()
    for line in dry_run.splitlines():
        if not line.startswith("moonc build-package") or any(flag in line for flag in TEST_FLAGS):
            continue
        head = line.split(" -", 1)[0]
        found.update(m for m in BUILD_SOURCE.findall(head) if is_test_file(m))
    return sorted(found)


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
    rule: str = RULE_IMPORTED_TESTS_OUT,
) -> tuple[str, dict[str, str]]:
    parts = {
        "version": KEY_VERSION,
        "rule": rule,
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


NOT_FOUND = re.compile(r"package .*not found", re.IGNORECASE)
TOTAL_TESTS = re.compile(r"Total tests: (\d+), passed: (\d+), failed: (\d+)")


def judge(status: int, output: str) -> tuple[int, str]:
    """(exit status, why) of a `moon test` invocation from its status and output: moon exits 0 when
    a package name selects nothing, so a pass needs at least one `Total tests` line, every line with
    tests and none failed, and no `not found` warning. The counts of several lines are summed. The second item is the problem, empty for a pass."""
    if status != 0:
        return status, f"moon exited {status}"
    totals = TOTAL_TESTS.findall(output)
    if NOT_FOUND.search(output):
        return 1, f"moon warned: {NOT_FOUND.search(output).group(0)}"  # type: ignore[union-attr]
    if not totals:
        return 1, "moon printed no `Total tests` line"
    for index, (total_text, passed_text, failed_text) in enumerate(totals, start=1):
        total, passed, failed = int(total_text), int(passed_text), int(failed_text)
        if total == 0:
            return 1, f"moon ran 0 tests (`Total tests` line {index} of {len(totals)})"
        if failed or passed != total:
            return 1, f"moon reports {failed} failed, {passed} of {total} passed (`Total tests` line {index} of {len(totals)})"
    return 0, ""


def test_count(output: str) -> int:
    return sum(int(total) for total, _, _ in TOTAL_TESTS.findall(output))


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


MANIFEST_NAME = re.compile(r'^name\s*=\s*"([^"]+)"', re.MULTILINE)
MANIFEST_SOURCE = re.compile(r'^source\s*=\s*"([^"]+)"', re.MULTILINE)


def manifest_problem(text: str, module: str, root: str, manifest: str) -> str | None:
    """Why a `moon.mod` is not the module and source directory this program assumes, or None.
    The source directory is `src` when the manifest names none."""
    name = MANIFEST_NAME.search(text)
    source = MANIFEST_SOURCE.search(text)
    found_name = name.group(1) if name else None
    found_root = f"{Path(manifest).parent.as_posix()}/{source.group(1) if source else 'src'}"
    if found_name != module:
        return f"{manifest} names the module {found_name!r}, this program assumes {module!r}"
    if found_root != root:
        return f"{manifest} has the source directory {found_root!r}, this program assumes {root!r}"
    return None


def check_manifests(repo_root: Path) -> None:
    """Raise ValueError when a module of `SOURCE_ROOTS` is not what its `moon.mod` says."""
    for (module, root), manifest in zip(SOURCE_ROOTS, ("library/moon.mod", "tooling/moon.mod")):
        problem = manifest_problem((repo_root / manifest).read_text(encoding="utf-8"), module, root, manifest)
        if problem:
            raise ValueError(problem)


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


def digest_unit(repo_root: Path, unit: Unit, packages: Mapping[str, Package], refine: bool = True) -> str:
    """The content digest of a unit's closure: every file of the packages of the unit itself, and
    of the packages it only imports every file except the test files (`is_test_file`). With
    `refine=False` every file of the whole closure (the rule of key version 1)."""
    own = {packages[m].directory for m in unit.members}
    files: set[Path] = set()
    for directory in unit_files(unit, packages):
        found = directory_files(repo_root, [directory])
        if refine and directory not in own:
            found = [f for f in found if not is_test_file(f.name)]
        files.update(found)
    return cf.hash_tree(sorted(files), repo_root)


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
    reuse: bool = True
    last_tests: int = 0
    rules: dict[str, str] = dataclasses.field(default_factory=dict)  # unit -> RULE_* the digest was taken with


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
        check_manifests(repo_root)
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
            compile_commands = ku.dry_run_commands(test_command(NATIVE_ARGUMENTS, unit.members), repo_root, run)
            if not compile_commands:
                plan.disabled = f"moon could not print the build of '{unit.name}'"
                return plan
            if NOT_FOUND.search(compile_commands):
                plan.disabled = f"moon did not find a package of '{unit.name}': {NOT_FOUND.search(compile_commands).group(0)}"  # type: ignore[union-attr]
                return plan
            # The rule that imported test files are not compiled into a dependent rests on moon's
            # naming; a build that contradicts it in moon's own dry run turns the rule off.
            refine = not test_files_in_library_builds(compile_commands)
            plan.rules[unit.name] = RULE_IMPORTED_TESTS_OUT if refine else RULE_ALL
            plan.digests[unit.name] = digest_unit(repo_root, unit, plan.packages, refine)
            plan.keys[unit.name], plan.parts[unit.name] = unit_key(
                unit, plan.digests[unit.name], compile_commands, plan.modules, wrapper, toolchain, verifier, ambient, plan.rules[unit.name]
            )
    except (OSError, ValueError, KeyError) as error:
        plan.disabled = f"no key can be formed: {error}"
        plan.keys.clear()
        return plan
    drawn = ku.decide_units(plan.keys, lambda k: ledger.result(k) is not None, random.Random(seed), rate)
    plan.actions = {u.name: drawn.get(u.name, "run") for u in plan.units}
    plan.reuse = reuse
    if not reuse:
        plan.actions = {u.name: "run" for u in plan.units}
    return plan


def unchanged(plan: Plan, unit: Unit) -> bool:
    """Whether the files of the unit's key are what they were when the plan was made."""
    refine = plan.rules.get(unit.name) == RULE_IMPORTED_TESTS_OUT
    return digest_unit(plan.repo_root, unit, plan.packages, refine) == plan.digests.get(unit.name) and (
        cf.hash_tree(module_files(plan.repo_root), plan.repo_root) == plan.modules
    )


def record_pass(plan: Plan, unit: Unit, seconds: float, shared_with: int, tests: int = 0) -> bool:
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
                "result": {"passed": True, "seconds": round(seconds, 1), "units_in_the_run": shared_with, "tests_in_the_run": tests},
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
    execute: Callable[[tuple[str, ...]], tuple[int, str]],
    out: Callable[[str], None] = print,
) -> tuple[int, Tally, dict[str, int]]:
    """Run what the plan says. Returns (exit status, tally, commits of the reused units)."""
    tally = Tally(disabled=plan.disabled)
    commits: dict[str, int] = {}
    if plan.disabled or not plan.reuse:
        started = time.monotonic()
        raw_status, output = execute(whole_command(jobs))
        status, why = judge(raw_status, output)
        plan.last_tests = test_count(output)
        seconds = time.monotonic() - started
        tally.failed += status != 0
        if status != 0:
            out(f"FAIL  {STAGE} [whole stage] {why}, {seconds:.1f}s")
            return status, tally, commits
        tally.ran = len(plan.units)
        out(f"PASS  {STAGE} [whole stage], {seconds:.1f}s ({plan.last_tests} tests in one moon invocation)")
        if not plan.disabled:
            by_name = {u.name: u for u in plan.units}
            for unit in plan.units:
                if unit.keyed and not record_pass(plan, by_name[unit.name], seconds, len(plan.units), plan.last_tests):
                    tally.unrecorded += 1
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
        raw_status, output = execute(test_command(NATIVE_ARGUMENTS, members, jobs))
        status, why = judge(raw_status, output)
        tests = test_count(output)
        seconds = time.monotonic() - started
        names = ", ".join(u.name for u in chosen)
        if status != 0:
            tally.failed += 1
            out(f"FAIL  {STAGE} [{label}: {names}] {why}, {seconds:.1f}s")
            if sampled:
                out(f"DEFECT  {STAGE}: the key of {names} is recorded as passing and the sampled rerun failed: a defect of the incremental system, not of the change")
                return inc.EXIT_DEFECT, tally, commits
            return status, tally, commits
        out(f"PASS  {STAGE} [{label}: {names}], {seconds:.1f}s ({len(members)} packages, {tests} tests in one moon invocation)")
        for unit in chosen:
            if sampled:
                tally.sampled += 1
                continue
            tally.ran += 1
            if unit.keyed and not plan.disabled:
                if not record_pass(plan, by_name[unit.name], seconds, len(chosen), tests):
                    tally.unrecorded += 1
                    out(f"NOTE  {unit.name} passed but was not recorded (its files changed during the run)")
    return 0, tally, commits


def run_tee(command: Sequence[str], cwd: Path, env: Mapping[str, str] | None = None) -> tuple[int, str]:
    """Run a command, show its output as it comes (stdout and stderr together) and return the
    status and the whole output."""
    process = subprocess.Popen(list(command), cwd=cwd, env=None if env is None else dict(env), stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, errors="replace")
    assert process.stdout is not None
    lines: list[str] = []
    for line in process.stdout:
        sys.stdout.write(line)
        sys.stdout.flush()
        lines.append(line)
    return process.wait(), "".join(lines)


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

    def execute(command: tuple[str, ...]) -> tuple[int, str]:
        return run_tee(command, REPO_ROOT)

    status, tally, commits = run_plan(plan, args.jobs, execute)
    print(summary_line(tally, seed, args.sample_rate, commits))
    return status


if __name__ == "__main__":
    raise SystemExit(main())
