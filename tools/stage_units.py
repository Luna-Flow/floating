"""Whole stages of the gates as incremental verification units (`just verify interval`,
`just verify decimal_gda`).

A *stage unit* is one stage of a gate that has a key: a `moon test` stage whose tests can only see
the packages they import, or a Python stage whose inputs are a declared set of files. The key holds
the inputs, the command, the toolchain and the verifier; a stage whose key is in the ledger is
reported as `REUSED` with the commit it passed on and not run (never printed as a pass), 2 % of
them are rerun by a draw whose seed is printed, and a sampled rerun that fails is a defect of the
system (exit status 70). The ledger and the guards are those of `kernel_units` and `native_units`.

Moon stages (`kind == "moon"`): the key is the content of the packages of the stage and of every
package they import inside the two modules (the closure is read from `moon.pkg`), the module
files, the command, what `moon ... --dry-run` prints, the wrapper, the toolchain, the verifier and
the `MOON*`/`LUNA_*` environment. A package whose closure imports anything outside
`native_units.PURE_IMPORTS` (the file system, the environment, the clock, async) is not keyed: a
test that cannot import `x/fs` cannot read a data file at run time, and that is what makes the
content of the packages the whole input. A pass is read from moon's output as well as its status
(`native_units.judge`: no tests, or a package that was not found, is a failure).

Python stages (`kind == "python"`): the key is the content of a *declared* set of files and
directories written in `SPECS` below, rounded up to whole directories, the Python version and the
hook file. What a run happened to open is not a key: a file opened only on some path is missing
from any observation. The declaration is therefore checked by every real run, which executes under
the audit hook of `tools/stage_audit/sitecustomize.py` (the process and every Python process it
starts). A read or a listing of anything below the repository outside the declared set fails the
unit: nothing is recorded, the exit status is 70 (a defect of the system, with the path), so that the
declaration cannot go stale silently. A program that is not Python started by the stage cannot be
observed: the stage still runs and passes, but its result is not recorded (and the report says so).

Everything that cannot be read (a `moon.pkg`, the dry run, the toolchain) disables reuse for the
stage, which then runs as in the gate. Stages of these gates that are not here stay full stages:
`verify.py` lists them.

The functions are pure unless their name says they touch files or processes.
"""

from __future__ import annotations

import dataclasses
import os
import random
import shutil
import socket
import subprocess
import sys
import tempfile
import time
from collections.abc import Callable, Mapping, Sequence
from pathlib import Path

import code_fingerprint as cf
import incremental as inc
import kernel_units as ku
import native_units as nu

L = nu.LIBRARY
KEY_VERSION = "stage-units-v1"
AUDIT_DIR = "tools/stage_audit"
AUDIT_FILE = f"{AUDIT_DIR}/sitecustomize.py"
IGNORED_PARTS = ("__pycache__", ".git")
DEFAULT_RATE = ku.DEFAULT_RATE


@dataclasses.dataclass(frozen=True)
class StageSpec:
    """The stage `stage` of a gate as a unit."""

    stage: str
    kind: str  # "moon" or "python"
    packages: tuple[str, ...] = ()  # moon: the packages whose closure is the key
    declared: tuple[str, ...] = ()  # python: the files and directories (with a trailing `/`) the stage may read


# Stage name -> spec. The keys of the stages of a scope that are not here run as in the gate.
SPECS: dict[str, tuple[StageSpec, ...]] = {
    "interval": (
        # `moon test` of six white-box files of `interval`; the tests import only pure packages.
        StageSpec("INTERVAL: reverse trigonometric reference", "moon", (f"{L}/interval",)),
        # Python only: recomputes the generated corpora and the refinements from `decimal` and
        # `fractions`. Declared from an audit of one run (the oracle programs, the refinement
        # planner they import, the corpus and the generated files below `testdata/interval/`).
        StageSpec(
            "INTERVAL: oracle checks",
            "python",
            declared=(
                "tools/itl_atan2_reverse_oracle.py",
                "tools/itl_oracle_checks.py",
                "tools/itl_pow2_reverse_oracle.py",
                "tools/itl_pow_reverse_oracle.py",
                "tools/itl_refinements.py",
                "tools/itl_trig_reverse_oracle.py",
                "testdata/interval/",
            ),
        ),
    ),
    "decimal_gda": (StageSpec("DECIMAL_GDA: package tests", "moon", (f"{L}/decimal_gda",)),),
}


@dataclasses.dataclass(frozen=True)
class StageUnit:
    spec: StageSpec
    command: tuple[str, ...]

    @property
    def name(self) -> str:
        return self.spec.stage


# ---------------------------------------------------------------------------------------
# Pure parts
# ---------------------------------------------------------------------------------------


def units_for(scope: str, stages: Sequence[tuple[str, tuple[str, ...]]]) -> list[StageUnit]:
    """The stages of `stages` `(name, command)` that have a spec in `scope`, in order."""
    specs = {s.stage: s for s in SPECS.get(scope, ())}
    return [StageUnit(specs[name], tuple(command)) for name, command in stages if name in specs]


def covered(path: str, declared: Sequence[str]) -> bool:
    """Whether a repository-relative path lies in the declared set (a file, or below a directory)."""
    if any(part in IGNORED_PARTS for part in path.split("/")):
        return True
    for item in declared:
        if item.endswith("/"):
            if path == item.rstrip("/") or path.startswith(item):
                return True
        elif path == item:
            return True
    return False


@dataclasses.dataclass(frozen=True)
class Audit:
    reads: tuple[str, ...]
    listings: tuple[str, ...]
    programs: tuple[str, ...]
    starts: tuple[str, ...] = ()  # `sys.version` of every interpreter that loaded the hook
    outside: tuple[str, ...] = ()  # files outside the repository that were read and not created by the run


def parse_audit(text: str) -> Audit:
    """The log in the order it was written: a file outside the repository that a process of the run
    created is an input of nothing when a later line reads it; every other outside read counts."""
    reads: set[str] = set()
    listings: set[str] = set()
    programs: set[str] = set()
    starts: set[str] = set()
    outside: set[str] = set()
    created: set[str] = set()
    for line in text.splitlines():
        kind, _, value = line.partition(" ")
        if kind == "R":
            reads.add(value)
        elif kind == "D":
            listings.add(value)
        elif kind == "S":
            programs.add(value)
        elif kind == "B":
            starts.add(value)
        elif kind == "C":
            created.add(value)
        elif kind == "X" and value not in created:
            outside.add(value)
    return Audit(tuple(sorted(reads)), tuple(sorted(listings)), tuple(sorted(programs)), tuple(sorted(starts)), tuple(sorted(outside)))


def ancestors(declared: Sequence[str]) -> set[str]:
    """The directories above the declared entries (`.` is the repository root): the import system
    lists the directory of a module it loads, which says nothing about files that are not imported."""
    found = {"."}
    for item in declared:
        parts = item.rstrip("/").split("/")[:-1]
        found.update("/".join(parts[: i + 1]) for i in range(len(parts)))
    return found


def with_hook(declared: Sequence[str]) -> tuple[str, ...]:
    """The declared set of a unit with the directory of the audit hook: the interpreter reads or lists
    it on start-up (and, on some builds, again when a module is looked for after the hook is installed),
    and a change of the hook changes what is recorded, so it is an input of every unit."""
    return (*declared, f"{AUDIT_DIR}/")


def undeclared(audit: Audit, declared: Sequence[str]) -> list[str]:
    """Everything the run read or listed below the repository outside the declared set (the hook
    directory is always declared). Listing a directory above a declared entry is allowed (the import
    system does it); reading in it is not. Files outside the repository are `outside_reads`."""
    declared = with_hook(declared)
    above = ancestors(declared)
    outside = [p for p in audit.reads if not covered(p, declared)]
    outside += [p for p in audit.listings if not covered(p, declared) and p not in above]
    return sorted(set(outside))


def outside_reads(audit: Audit) -> list[str]:
    """Files outside the repository that the run read, other than the interpreter's own files (its
    standard library and site-packages), the run's private compiled-module cache and files that the run
    created itself first: inputs that no key covers, so the run is not recorded."""
    return list(audit.outside)


def compiled_reads(audit: Audit) -> list[str]:
    """Compiled modules read from a `__pycache__` below the repository: the run was started with the
    cache redirected, so a process that read one did not honour that and may have run a stale one."""
    return [p for p in audit.reads if p.endswith(".pyc") and "__pycache__" in p.split("/")]


def not_recorded_why(audit: Audit, python: str, version: str) -> str:
    """Why the pass of a Python stage must not be recorded ('' when it may be): no hook ran in the
    process (an interpreter run with `-I` or `-S` does not load it, and an empty log would read as
    nothing outside), an interpreter other than the one the key names ran, a program the audit cannot
    see into, a read outside the repository, or a compiled module of the tree."""
    if not audit.starts:
        return "the audit hook did not start (no start line in its log), so nothing the stage read was seen"
    other = [s for s in audit.starts if s != version]
    if other:
        return f"a Python of another version ran ({other[0].split()[0]}), not the one of the key ({version.split()[0] if version else 'unknown'})"
    unseen = unseen_programs(audit, python)
    if unseen:
        return f"it started {unseen}, which the audit cannot see into"
    outside = outside_reads(audit)
    if outside:
        return f"it read {outside[:3]}{' ...' if len(outside) > 3 else ''} outside the repository, which no key covers"
    compiled = compiled_reads(audit)
    if compiled:
        return f"it read the compiled module {compiled[0]} from the tree, which may be older than its source"
    return ""


def unseen_programs(audit: Audit, python: str) -> list[str]:
    """Programs started by the stage that the audit cannot see into (not the Python interpreter)."""
    names = {Path(python).name, "python", "python3", Path(python).resolve().name}
    return sorted(p for p in audit.programs if Path(p).name not in names and not Path(p).name.startswith("python"))


def key_parts(
    unit: StageUnit,
    content: str,
    modules: str,
    compile_commands: str,
    wrapper: str,
    hook: str,
    toolchain: str,
    verifier: str,
    python_version: str,
    ambient: str,
) -> tuple[str, dict[str, str]]:
    parts = {
        "version": KEY_VERSION,
        "unit": unit.name,
        "kind": unit.spec.kind,
        "command": " ".join(unit.command),
        "content": content,
        "declared": inc.digest(*unit.spec.declared),
        "packages": inc.digest(*unit.spec.packages),
        "modules": modules if unit.spec.kind == "moon" else "",
        "compile": inc.digest(compile_commands) if unit.spec.kind == "moon" else "",
        "wrapper": wrapper if unit.spec.kind == "moon" else "",
        "hook": hook,
        "toolchain": toolchain,
        "verifier": verifier,
        "python": python_version if unit.spec.kind == "python" else "",
        "ambient": inc.digest(ambient),
    }
    return inc.digest(*(f"{k}={v}" for k, v in sorted(parts.items()))), parts


def is_python(program: str) -> bool:
    return Path(program).name.startswith("python")


def interpreter_version(command: Sequence[str], run: Callable[..., "subprocess.CompletedProcess[str]"] | None = None) -> str:
    """`sys.version` of the interpreter that runs a Python stage, asked of that interpreter (the one
    of the command, which need not be the one that runs the verifier). '' when it cannot be asked."""
    if not command or not is_python(command[0]):
        return ""
    try:
        result = (run or subprocess.run)([command[0], "-c", "import sys; print(sys.version)"], capture_output=True, text=True, timeout=60)
    except (OSError, subprocess.SubprocessError):
        return ""
    return result.stdout.strip().replace("\n", " ") if result.returncode == 0 else ""


@dataclasses.dataclass
class Tally:
    ran: int = 0
    reused: int = 0
    sampled: int = 0
    failed: int = 0
    unrecorded: int = 0
    disabled: str = ""


def summary_line(tally: Tally, seed: int, rate: float, commits: Mapping[str, int]) -> str:
    sources = ", ".join(f"{n} from {c[:10]}" for c, n in sorted(commits.items()))
    return (
        f"stage units: ran {tally.ran}, reused {tally.reused}" + (f" [{sources}]" if sources else "")
        + f", sampled {tally.sampled} (each reusable stage with probability {rate:g}, seed {seed}), failed {tally.failed}"
        + (f", not recorded {tally.unrecorded}" if tally.unrecorded else "")
        + (f", reuse off ({tally.disabled})" if tally.disabled else "")
    )


# ---------------------------------------------------------------------------------------
# Files, processes and the ledger
# ---------------------------------------------------------------------------------------


def hook_files(repo_root: Path) -> list[Path]:
    """Every file of the hook directory: all of it is an input of every unit."""
    return sorted(p for p in (repo_root / AUDIT_DIR).rglob("*") if p.is_file() and not any(part in IGNORED_PARTS for part in p.parts))


def content_files(repo_root: Path, unit: StageUnit, packages: Mapping[str, nu.Package]) -> list[Path]:
    """The files whose content is the key of the unit, sorted."""
    files: list[Path] = []
    if unit.spec.kind == "moon":
        directories: list[str] = []
        for member in unit.spec.packages:
            directories += nu.unit_files(nu.Unit(unit.name, (member,), True), packages)
        files += nu.directory_files(repo_root, sorted(set(directories)))
        files += nu.module_files(repo_root)
    else:
        for item in unit.spec.declared:
            target = repo_root / item.rstrip("/")
            if item.endswith("/"):
                files += [p for p in target.rglob("*") if p.is_file() and not any(part in IGNORED_PARTS for part in p.parts)]
            elif target.is_file():
                files.append(target)
            else:
                raise FileNotFoundError(f"declared file {item} does not exist")
    return sorted(set(files))


@dataclasses.dataclass
class Plan:
    units: list[StageUnit]
    keys: dict[str, str]
    parts: dict[str, dict[str, str]]
    actions: dict[str, str]
    digests: dict[str, str]
    unit_disabled: dict[str, str]  # unit -> why it always runs
    disabled: str
    ledger: inc.Ledger
    seed: int
    rate: float
    commit: str
    dirty: bool
    repo_root: Path
    packages: dict[str, nu.Package] = dataclasses.field(default_factory=dict)


def make_plan(
    scope: str,
    stages: Sequence[tuple[str, tuple[str, ...]]],
    repo_root: Path,
    ledger: inc.Ledger,
    seed: int,
    rate: float = DEFAULT_RATE,
    environ: Mapping[str, str] | None = None,
    run: Callable[..., str] | None = None,
    ask_version: Callable[[Sequence[str]], str] = interpreter_version,
) -> Plan:
    """Keys and actions of the stage units of a scope (file system and processes: moon's dry runs,
    the toolchain, git). An error while forming keys disables reuse for all of them."""
    units = units_for(scope, stages)
    commit, dirty = inc.git_head(repo_root)
    plan = Plan(units, {}, {}, {u.name: "run" for u in units}, {}, {}, "", ledger, seed, rate, commit, dirty, repo_root)
    if not units:
        return plan
    try:
        nu.check_manifests(repo_root)
        plan.packages = nu.discover_packages(repo_root)
        env = dict(os.environ if environ is None else environ)
        toolchain = cf.toolchain_digest(cf.collect_toolchain(repo_root, Path.home() / ".moon", cf.run_command, environ=dict(environ or {}) or None))
        verifier = inc.verifier_digest(repo_root)
        ambient = ku.ambient_environment(env)
        modules = cf.hash_tree(nu.module_files(repo_root), repo_root)
        wrapper = cf.hash_tree([repo_root / nu.WRAPPER], repo_root)
        hook = cf.hash_tree(hook_files(repo_root), repo_root)
        for unit in units:
            if unit.spec.kind == "moon":
                bad = nu.impure_imports(unit.spec.packages, plan.packages)
                if bad:
                    plan.unit_disabled[unit.name] = f"its closure imports {bad}: tests could read files or the environment"
                    continue
            python_version = ""
            if unit.spec.kind == "python":
                python_version = ask_version(unit.command)
                if not python_version:
                    plan.unit_disabled[unit.name] = f"its interpreter '{unit.command[0] if unit.command else ''}' could not be asked for its version"
                    continue
            files = content_files(repo_root, unit, plan.packages)
            plan.digests[unit.name] = cf.hash_tree(files, repo_root)
            compile_commands = ""
            if unit.spec.kind == "moon":
                compile_commands = ku.dry_run_commands(unit.command, repo_root, run)
                if not compile_commands:
                    plan.disabled = f"moon could not print the build of '{unit.name}'"
                    return plan
                if nu.NOT_FOUND.search(compile_commands):
                    plan.disabled = f"moon did not find a package of '{unit.name}'"
                    return plan
            plan.keys[unit.name], plan.parts[unit.name] = key_parts(
                unit, plan.digests[unit.name], modules, compile_commands, wrapper, hook, toolchain, verifier, python_version, ambient
            )
    except (OSError, ValueError, KeyError) as error:
        plan.disabled = f"no key can be formed: {error}"
        plan.keys.clear()
        return plan
    drawn = ku.decide_units(plan.keys, lambda k: ledger.result(k) is not None, random.Random(seed), rate)
    for unit in units:
        plan.actions[unit.name] = drawn.get(unit.name, "run")
    return plan


def unchanged(plan: Plan, unit: StageUnit) -> bool:
    """Whether the files of the key are what they were when the plan was made."""
    files = content_files(plan.repo_root, unit, plan.packages)
    return cf.hash_tree(files, plan.repo_root) == plan.digests.get(unit.name)


def record_pass(plan: Plan, unit: StageUnit, seconds: float, tests: int = 0) -> bool:
    if unit.name in plan.unit_disabled or unit.name not in plan.keys or not unchanged(plan, unit):
        return False
    plan.ledger.append(
        [
            {
                "kind": "result",
                "key": plan.keys[unit.name],
                "unit": unit.name,
                "parts": plan.parts[unit.name],
                "result": {"passed": True, "seconds": round(seconds, 1), "tests": tests},
                "commit": plan.commit + ("+dirty" if plan.dirty else ""),
                "dirty": plan.dirty,
                "date": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
                "host": socket.gethostname(),
                "log": "",
            }
        ]
    )
    return True


def audit_environment(repo_root: Path, log: Path, environ: Mapping[str, str], pycache: Path | None = None) -> dict[str, str]:
    """The environment of a Python stage run under the audit hook. With `pycache` (an empty directory
    made for this run) every Python process of the stage compiles its modules from source into that
    directory and reads nothing from a `__pycache__` of the tree: a compiled module of the tree, stale
    or hand-made (an `unchecked-hash` one is loaded without looking at its source), cannot run in place
    of a source file that the key covers. Mapping a compiled module back to its source would not do
    that: the module that runs would still be the compiled one."""
    env = dict(environ)
    hook_dir = str(repo_root / AUDIT_DIR)
    env["PYTHONPATH"] = hook_dir + (os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
    env["STAGE_AUDIT_LOG"] = str(log)
    env["STAGE_AUDIT_ROOT"] = str(repo_root)
    if pycache is not None:
        env["PYTHONPYCACHEPREFIX"] = str(pycache)
        env["STAGE_AUDIT_EXEMPT"] = str(pycache)
    return env


Execute = Callable[[tuple[str, ...], "Mapping[str, str] | None"], "tuple[int, str]"]


def run_stage(
    plan: Plan,
    unit: StageUnit,
    execute: Execute,
    tally: Tally,
    commits: dict[str, int],
    out: Callable[[str], None] = print,
    environ: Mapping[str, str] | None = None,
) -> int:
    """Reuse, run or sample one stage unit. Returns the exit status of the stage (0 passed;
    `inc.EXIT_DEFECT` a defect of the incremental system)."""
    name = unit.name
    action = "run" if plan.disabled or name in plan.unit_disabled else plan.actions.get(name, "run")
    if action == "reuse":
        record = plan.ledger.result(plan.keys[name])
        commit = str(record["commit"]) if record else ""
        tally.reused += 1
        commits[commit] = commits.get(commit, 0) + 1
        out(f"REUSED  {name} [stage unit, recorded on {commit[:10]}{'+dirty' if commit.endswith('+dirty') else ''}], not executed")
        return 0
    tag = "stage unit, sampled rerun" if action == "sample" else ("stage unit" if name in plan.keys else "full")
    started = time.monotonic()
    log: Path | None = None
    pycache: Path | None = None
    env: Mapping[str, str] | None = None
    if unit.spec.kind == "python":
        handle, raw = tempfile.mkstemp(prefix="stage-audit-", suffix=".log")
        os.close(handle)
        log = Path(raw)
        pycache = Path(tempfile.mkdtemp(prefix="stage-pycache-"))
        env = audit_environment(plan.repo_root, log, dict(os.environ if environ is None else environ), pycache)
    try:
        raw_status, output = execute(unit.command, env)
        seconds = time.monotonic() - started
        if unit.spec.kind == "moon":
            status, why = nu.judge(raw_status, output)
            tests = nu.test_count(output)
        else:
            status, why, tests = raw_status, f"exit {raw_status}", 0
        audit = parse_audit(log.read_text(encoding="utf-8") if log else "")
    finally:
        if log:
            log.unlink(missing_ok=True)
        if pycache:
            shutil.rmtree(pycache, ignore_errors=True)
    if status != 0:
        tally.failed += 1
        out(f"FAIL  {name} [{tag}] {why}, {seconds:.1f}s")
        if action == "sample":
            out(f"DEFECT  {name}: its key is recorded as passing and the sampled rerun failed: a defect of the incremental system, not of the change")
            return inc.EXIT_DEFECT
        return status
    if unit.spec.kind == "python" and name in plan.keys:
        outside = undeclared(audit, unit.spec.declared)
        if outside:
            tally.failed += 1
            out(f"DEFECT  {name}: the stage read {outside[:5]}{' ...' if len(outside) > 5 else ''} outside its declared inputs {list(unit.spec.declared)}: the declaration of the unit is stale, nothing is recorded (tools/stage_units.py)")
            return inc.EXIT_DEFECT
    out(f"PASS  {name} [{tag}], {seconds:.1f}s" + (f" ({tests} tests)" if tests else ""))
    if action == "sample":
        tally.sampled += 1
        return 0
    tally.ran += 1
    if name in plan.keys and not plan.disabled:
        why_not = ""
        if unit.spec.kind == "python":
            why_not = not_recorded_why(audit, sys.executable, plan.parts[name]["python"])
        if not why_not and not record_pass(plan, unit, seconds, tests):
            why_not = "its files changed during the run"
        if why_not:
            tally.unrecorded += 1
            out(f"NOTE  {name} passed but was not recorded: {why_not}")
    elif name in plan.unit_disabled:
        out(f"NOTE  {name} is not keyed ({plan.unit_disabled[name]}) and always runs")
    return 0
