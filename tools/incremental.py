"""Incremental verification: unit keys, the ledger, sampled reruns and the report.

A verification unit (one TestFloat task, one corpus file) is not run again when its key is in
the ledger. The key of a unit is the hash of:

* the frame fingerprint: the code reachable from the frontend's entry, with the start-up code,
  the dispatcher covered by its own text and the operation functions (arms) left out
  (`code_fingerprint.fingerprint`);
* the input identity: the sha256 of the data, or the generator's binary hash, arguments, seed;
* the arguments of the interpreter;
* the toolchain digest (`code_fingerprint.collect_toolchain`) and the verifier digest (the
  sources of the tools that judge a unit);
* the set of normalisations (inside the frame fingerprint) and `KEY_VERSION`;
* for a frontend with arms: the fingerprints of the arms that the process recorded.

The arms are measured, not read from a table: a run prints the set of arms that ran, the ledger
stores it under the key without arms (`pre key`), and the full key adds the closures of exactly
those arms. A unit with no record for its pre key runs. A rerouting inside the dispatcher changes
the frame and so the pre key.

The ledger is append-only, written only by the runner, only for a passing unit. A unit whose key
is in the ledger is reported as reused with the commit it ran on. A random 2 % of the units that
would be reused (at least one) are really run; a result that differs from the ledger is a defect
of the system (`EXIT_DEFECT`), never a verification failure.

The functions are pure unless their name says they touch the file system, git or a process
(`Ledger`, `main_checkout`, `git_head`, `load_context`).
"""

from __future__ import annotations

import contextlib
import dataclasses
import fcntl
import hashlib
import json
import math
import os
import random
import re
import socket
import subprocess
import sys
import tempfile
import time
from collections.abc import Callable, Iterator, Mapping, Sequence
from pathlib import Path
from typing import Any

import code_fingerprint as cf

KEY_VERSION = "incremental-v1"
EXIT_DEFECT = 70
DEFAULT_SAMPLE_RATE = 0.02
RESULT_FIELDS = ("totalCases", "selectedCases", "passedCases", "failedCases", "failedIds")


class SystemDefect(RuntimeError):
    """The incremental system contradicted itself: a sampled rerun differs from the ledger, or
    two runs recorded different arm sets for one key. Never a verification failure."""


# ---------------------------------------------------------------------------------------
# Keys (pure)
# ---------------------------------------------------------------------------------------


def digest(*parts: str) -> str:
    """A sha256 over length-prefixed parts (no two part lists give the same input)."""
    h = hashlib.sha256()
    for part in parts:
        data = part.encode()
        h.update(str(len(data)).encode() + b":" + data)
    return h.hexdigest()


@dataclasses.dataclass(frozen=True)
class FrontendSpec:
    """How the entry, the dispatcher and the arms of a frontend are found in the generated C.

    Each pattern is searched in the definition names and must match exactly one definition
    (entry, dispatcher). `arm` matches the arm definitions; its group 1 is the mangled name
    (`__` stands for `_`). `arm=None`: the frontend is one coarse unit per input.
    """

    entry: str
    dispatcher: str
    arm: str | None = None
    note: str | None = None  # the function every arm must reference (it records the arm at run time)


FRONTENDS: dict[str, FrontendSpec] = {
    "testfloat": FrontendSpec(
        entry=r"3cli20testfloat__expr__cli3run$",
        dispatcher=r"3cli8dispatch8dispatch$",
        arm=r"8frontend\d+testfloat__expr\d+arm__(\w+)$",
        note=r"8frontend\d+testfloat__expr\d+note__arm$",
    ),
    "mpfr": FrontendSpec(
        entry=r"3cli15mpfr__expr__cli3run$",
        dispatcher=r"3cli8dispatch8dispatch$",
    ),
}


def _one(program: cf.Program, pattern: str, what: str) -> str:
    found = [n for n, d in program.definitions.items() if d.is_function and re.search(pattern, n)]
    if len(found) != 1:
        raise cf.UnknownEntryError(f"{what}: {len(found)} definitions match {pattern!r}")
    return found[0]


def arm_definitions(program: cf.Program, pattern: str) -> dict[str, str]:
    """Arm name -> definition, for the functions named by `pattern` (derived closures excluded)."""
    arms: dict[str, str] = {}
    for name, definition in program.definitions.items():
        found = re.search(pattern, name)
        if found and definition.is_function and "__canon__" not in name and cf.counter_stem(name) == name:
            arms[found.group(1).replace("__", "_")] = name
    return arms


class KeysUnavailable(RuntimeError):
    """No key can be formed for this build (a pattern that matches 0 or 2 definitions, a parse
    error). The run goes on without incremental verification and records nothing."""


@dataclasses.dataclass
class KeyBuilder:
    """Computes pre keys and full keys of the units of one build."""

    program: cf.Program
    toolchain: str
    verifier: str
    frontends: Mapping[str, FrontendSpec] = dataclasses.field(default_factory=lambda: FRONTENDS)
    warnings: list[str] = dataclasses.field(default_factory=list)
    _arms: dict[str, dict[str, str] | None] = dataclasses.field(default_factory=dict)

    def arms(self, frontend: str) -> dict[str, str] | None:
        """The arm definitions of a frontend, or None when it is one coarse unit.

        A frontend with an arm pattern is coarse (and a warning is kept) when the build has no
        arm function, when the note function is missing, or when an arm does not reference it:
        "an arm records itself first" is a convention, and a convention that fails is reported.
        """
        if frontend in self._arms:
            return self._arms[frontend]
        spec = self.frontends[frontend]
        result: dict[str, str] | None = None
        if spec.arm is not None:
            definitions = arm_definitions(self.program, spec.arm)
            if not definitions:
                self.warnings.append(f"{frontend}: no arm function in this build, one coarse unit per input")
            elif spec.note is not None:
                note = _one(self.program, spec.note, f"{frontend} note function")
                silent = sorted(a for a, d in definitions.items() if note not in self.program.definitions[d].refs)
                if silent:
                    self.warnings.append(f"{frontend}: arms that do not reference the note function: {silent}; one coarse unit per input")
                else:
                    result = definitions
            else:
                result = definitions
        self._arms[frontend] = result
        return result

    def has_arms(self, frontend: str) -> bool:
        return self.arms(frontend) is not None

    def frame(self, frontend: str) -> str:
        spec = self.frontends[frontend]
        entry = _one(self.program, spec.entry, f"{frontend} entry")
        dispatcher = _one(self.program, spec.dispatcher, f"{frontend} dispatcher")
        arms = self.arms(frontend)
        excluded = set(arms.values()) if arms else set()
        return cf.fingerprint(self.program, entry, cut={dispatcher}, exclude=excluded)

    def pre_parts(self, frontend: str, input_id: str, args: str) -> dict[str, str]:
        """The components of a pre key, so that a later reader can see why a key changed."""
        return {
            "version": KEY_VERSION,
            "frame": self.frame(frontend),
            "input": input_id,
            "args": args,
            "toolchain": self.toolchain,
            "verifier": self.verifier,
        }

    def pre_key(self, frontend: str, input_id: str, args: str) -> str:
        parts = self.pre_parts(frontend, input_id, args)
        return digest(parts["version"], "pre", parts["frame"], input_id, args, self.toolchain, self.verifier)

    def arm_fingerprints(self, frontend: str, arms: Sequence[str]) -> dict[str, str] | None:
        """Fingerprint of each recorded arm's closure, or None when an arm has no definition."""
        definitions = self.arms(frontend)
        if definitions is None:
            return {}
        out: dict[str, str] = {}
        for arm in sorted(set(arms)):
            if arm not in definitions:
                return None
            out[arm] = cf.fingerprint(self.program, definitions[arm], startup=False)
        return out

    def result_key(self, frontend: str, pre_key: str, arms: Sequence[str]) -> str | None:
        """The full key for the recorded arms, or None when an arm has no definition."""
        fingerprints = self.arm_fingerprints(frontend, arms)
        if fingerprints is None:
            return None
        return digest(KEY_VERSION, "result", pre_key, *(f"{a}:{f}" for a, f in fingerprints.items()))


# ---------------------------------------------------------------------------------------
# The ledger
# ---------------------------------------------------------------------------------------


class Ledger:
    """An append-only JSON-lines file of arm records and results.

    Reads see the whole file; an append takes an exclusive lock, rereads the file, writes the
    old lines and the new ones to a temporary file in the same directory and renames it over
    the ledger (atomic). The first record of a key is the one that counts.
    """

    def __init__(self, path: Path) -> None:
        self.path = path
        self.arms: dict[str, dict[str, Any]] = {}
        self.results: dict[str, dict[str, Any]] = {}
        self.load()

    def load(self) -> None:
        self.arms, self.results = {}, {}
        if not self.path.is_file():
            return
        for line in self.path.read_text(encoding="utf-8").splitlines():
            if line.strip():
                self._index(json.loads(line))

    def _index(self, record: dict[str, Any]) -> None:
        table = self.arms if record["kind"] == "arms" else self.results
        table.setdefault(record["key"], record)

    def recorded_arms(self, pre_key: str) -> list[str] | None:
        record = self.arms.get(pre_key)
        return None if record is None else list(record["arms"])

    def result(self, key: str) -> dict[str, Any] | None:
        return self.results.get(key)

    @contextlib.contextmanager
    def _locked(self) -> Iterator[None]:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with open(self.path.parent / (self.path.name + ".lock"), "w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            try:
                yield
            finally:
                fcntl.flock(lock, fcntl.LOCK_UN)

    def append(self, records: Sequence[dict[str, Any]]) -> None:
        """Add records atomically. An arms record that contradicts the one on file is a defect."""
        with self._locked():
            self.load()
            fresh: list[dict[str, Any]] = []
            for record in records:
                known = self.arms.get(record["key"]) if record["kind"] == "arms" else None
                if known is not None and sorted(known["arms"]) != sorted(record["arms"]):
                    raise SystemDefect(
                        f"two runs recorded different arms for one key: {known['arms']} and {record['arms']}"
                    )
                if (self.arms if record["kind"] == "arms" else self.results).get(record["key"]) is None:
                    fresh.append(record)
            if not fresh:
                return
            old = self.path.read_text(encoding="utf-8") if self.path.is_file() else ""
            if old and not old.endswith("\n"):
                old += "\n"
            text = old + "".join(json.dumps(r, sort_keys=True) + "\n" for r in fresh)
            with tempfile.NamedTemporaryFile("w", dir=self.path.parent, prefix=".ledger.", delete=False, encoding="utf-8") as stream:
                stream.write(text)
                temporary = Path(stream.name)
            temporary.replace(self.path)
            for record in fresh:
                self._index(record)


# ---------------------------------------------------------------------------------------
# Deciding what runs (pure)
# ---------------------------------------------------------------------------------------


@dataclasses.dataclass(frozen=True)
class Decision:
    unit: str
    action: str  # "run", "reuse" or "sample"
    reason: str
    record: dict[str, Any] | None = None


def decide(
    lookups: Mapping[str, tuple[str, dict[str, Any] | None]],
    rng: random.Random,
    rate: float = DEFAULT_SAMPLE_RATE,
) -> list[Decision]:
    """Decide per unit. `lookups[unit] = (reason, record)`: a record means the key is in the ledger.

    Units with a record are reused, except `max(1, ceil(rate * n))` of them (n = the number of
    units with a record, at least one when n > 0), chosen at random, which are sampled: run
    for real and compared. Units in input order. A rate of 0 or less samples nothing; only the
    system's own mutation test uses it (the gates always sample).
    """
    candidates = sorted(unit for unit, (_, record) in lookups.items() if record is not None)
    sampled: set[str] = set()
    if candidates and rate > 0:
        sampled = set(rng.sample(candidates, min(len(candidates), max(1, math.ceil(rate * len(candidates))))))
    out = []
    for unit, (reason, record) in lookups.items():
        if record is None:
            out.append(Decision(unit, "run", reason))
        elif unit in sampled:
            out.append(Decision(unit, "sample", "sampled rerun of a reusable unit", record))
        else:
            out.append(Decision(unit, "reuse", "key in the ledger", record))
    return out


def compare_result(recorded: Mapping[str, Any], actual: Mapping[str, Any]) -> list[str]:
    """The fields of a result that differ from the recorded one (empty when identical)."""
    return [
        f"{field}: recorded {recorded.get(field)!r}, now {actual.get(field)!r}"
        for field in RESULT_FIELDS
        if recorded.get(field) != actual.get(field)
    ]


def stored_result(payload: Mapping[str, Any]) -> dict[str, Any]:
    """What the ledger keeps of a payload: all of it except the volatile timing."""
    return {key: value for key, value in payload.items() if key != "elapsedSeconds"}


@dataclasses.dataclass
class Tally:
    ran: int = 0
    reused: int = 0
    sampled: int = 0
    failed: int = 0
    unrecorded: int = 0  # ran and passed but no key could be formed
    sampled_differing: int = 0


def summary_line(tally: Tally, seed: int | None, reused_commits: Mapping[str, int]) -> str:
    """The one summary line: never a total that mixes run and reused units."""
    commits = ", ".join(f"{count} from {commit[:10]}" for commit, count in sorted(reused_commits.items()))
    seed_text = "" if seed is None else f" (seed {seed})"
    return (
        f"incremental: ran {tally.ran}, reused {tally.reused}"
        + (f" [{commits}]" if commits else "")
        + f", sampled {tally.sampled}{seed_text} ({tally.sampled_differing} differing), failed {tally.failed}"
        + (f", not recorded {tally.unrecorded}" if tally.unrecorded else "")
    )


# ---------------------------------------------------------------------------------------
# Running a set of units
# ---------------------------------------------------------------------------------------


@dataclasses.dataclass(frozen=True)
class UnitSpec:
    name: str
    frontend: str
    input_id: str
    args: str


@dataclasses.dataclass
class Outcome:
    unit: str
    status: str  # "ran", "reused", "sampled", "sampled-differing"
    payload: dict[str, Any]
    commit: str | None = None  # the commit a reused or sampled result was recorded on
    note: str = ""


@dataclasses.dataclass
class Environment:
    """What the runner needs besides the units (injected so the flow is testable)."""

    ledger: Ledger
    builder: KeyBuilder
    commit: str
    dirty: bool
    log_dir: str
    seed: int
    rate: float = DEFAULT_SAMPLE_RATE
    host: str = dataclasses.field(default_factory=socket.gethostname)
    clock: Callable[[], str] = lambda: time.strftime("%Y-%m-%dT%H:%M:%S%z")


def run_units(
    units: Sequence[UnitSpec],
    environment: Environment,
    run: Callable[[Sequence[UnitSpec]], list[dict[str, Any]]],
) -> tuple[list[Outcome], Tally]:
    """Run, reuse or sample every unit and record the passing runs in the ledger.

    `run(units)` runs the given units (in parallel if it likes) and returns their payloads in
    order; a payload has the `RESULT_FIELDS` and, for a frontend with arms, `arms`. Raises
    SystemDefect when a sampled rerun differs from the ledger.
    """
    ledger, builder = environment.ledger, environment.builder
    pre: dict[str, str] = {}
    lookups: dict[str, tuple[str, dict[str, Any] | None]] = {}
    try:
        for unit in units:
            pre[unit.name] = builder.pre_key(unit.frontend, unit.input_id, unit.args)
            arms = ledger.recorded_arms(pre[unit.name]) if builder.has_arms(unit.frontend) else []
            if arms is None:
                lookups[unit.name] = ("no recorded arms for this frame, input and toolchain", None)
                continue
            key = builder.result_key(unit.frontend, pre[unit.name], arms)
            if key is None:
                lookups[unit.name] = ("a recorded arm has no definition in this build", None)
                continue
            record = ledger.result(key)
            lookups[unit.name] = ("key not in the ledger", None) if record is None else ("", record)
    except (cf.UnknownEntryError, cf.ParseError, KeyError, ValueError) as error:
        raise KeysUnavailable(f"no key can be formed: {error}") from error
    decisions = {d.unit: d for d in decide(lookups, random.Random(environment.seed), environment.rate)}
    to_run = [u for u in units if decisions[u.name].action != "reuse"]
    payloads = dict(zip((u.name for u in to_run), run(to_run))) if to_run else {}
    for unit in to_run:
        ran_in = payloads[unit.name].get("frontend")
        if ran_in != unit.frontend:
            raise SystemDefect(
                f"{unit.name}: the process ran frontend {ran_in!r}, the key assumes {unit.frontend!r}: "
                "the route through the dispatcher is not the one the key was computed for"
            )
    tally = Tally()
    outcomes: list[Outcome] = []
    new_records: list[dict[str, Any]] = []
    for unit in units:
        decision = decisions[unit.name]
        if decision.action == "reuse":
            assert decision.record is not None
            tally.reused += 1
            outcomes.append(
                Outcome(unit.name, "reused", {**decision.record["result"], "elapsedSeconds": 0.0}, decision.record["commit"])
            )
            continue
        payload = payloads[unit.name]
        passed = payload.get("failedCases") == 0
        if decision.action == "sample":
            assert decision.record is not None
            tally.sampled += 1
            differences = compare_result(decision.record["result"], payload)
            if differences:
                tally.sampled_differing += 1
                outcomes.append(Outcome(unit.name, "sampled-differing", payload, decision.record["commit"], "; ".join(differences)))
                continue
            outcomes.append(Outcome(unit.name, "sampled", payload, decision.record["commit"]))
            if not passed:
                tally.failed += 1
            continue
        tally.ran += 1
        outcomes.append(Outcome(unit.name, "ran", payload, note=decision.reason))
        if not passed:
            tally.failed += 1
            continue
        arms = list(payload.get("arms", [])) if builder.has_arms(unit.frontend) else []
        fingerprints = builder.arm_fingerprints(unit.frontend, arms)
        key = builder.result_key(unit.frontend, pre[unit.name], arms)
        if key is None or fingerprints is None:
            tally.unrecorded += 1
            outcomes[-1].note += "; not recorded: an arm has no definition"
            continue
        base = {
            "unit": unit.name,
            "commit": environment.commit + ("+dirty" if environment.dirty else ""),
            "dirty": environment.dirty,
            "log": environment.log_dir,
            "date": environment.clock(),
            "host": environment.host,
        }
        parts = builder.pre_parts(unit.frontend, unit.input_id, unit.args)
        if builder.has_arms(unit.frontend):
            new_records.append({"kind": "arms", "key": pre[unit.name], "arms": sorted(set(arms)), "parts": parts, **base})
        new_records.append(
            {
                "kind": "result", "key": key, "pre_key": pre[unit.name], "parts": parts,
                "arm_fingerprints": fingerprints, "result": stored_result(payload), **base,
            }
        )
    if new_records:
        ledger.append(new_records)
    differing = [o for o in outcomes if o.status == "sampled-differing"]
    if differing:
        raise SystemDefect(
            "a sampled rerun differs from the ledger: "
            + "; ".join(f"{o.unit}: {o.note}" for o in differing)
        )
    return outcomes, tally


def reused_by_commit(outcomes: Sequence[Outcome]) -> dict[str, int]:
    counts: dict[str, int] = {}
    for outcome in outcomes:
        if outcome.status == "reused" and outcome.commit:
            counts[outcome.commit] = counts.get(outcome.commit, 0) + 1
    return counts


# ---------------------------------------------------------------------------------------
# Touching the file system, git and processes
# ---------------------------------------------------------------------------------------


def git_output(repo_root: Path, *arguments: str) -> str:
    result = subprocess.run(["git", *arguments], cwd=repo_root, capture_output=True, text=True)
    return result.stdout.strip() if result.returncode == 0 else ""


def main_checkout(repo_root: Path) -> Path:
    """The main checkout of the repository: the parent of the common git directory."""
    common = git_output(repo_root, "rev-parse", "--path-format=absolute", "--git-common-dir")
    return Path(common).parent if common else repo_root


def ledger_path(repo_root: Path, environ: Mapping[str, str] | None = None) -> Path:
    """`.tmp/verification-ledger/ledger.jsonl` of the main checkout (shared by worktrees)."""
    environ = os.environ if environ is None else environ
    override = environ.get("LUNA_VERIFICATION_LEDGER")
    return Path(override) if override else main_checkout(repo_root) / ".tmp" / "verification-ledger" / "ledger.jsonl"


def git_head(repo_root: Path) -> tuple[str, bool]:
    return git_output(repo_root, "rev-parse", "HEAD") or "unknown", bool(git_output(repo_root, "status", "--porcelain"))


def file_digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def imported_tool_files(repo_root: Path, modules: Mapping[str, Any] | None = None) -> list[Path]:
    """The source files of `tools/` that the running process has imported (or runs as `__main__`).

    The judge of a unit is whatever the runner imported: a module added later is covered
    without anyone remembering to list it."""
    modules = sys.modules if modules is None else modules
    tools = (repo_root / "tools").resolve()
    found: set[Path] = set()
    for module in modules.values():
        name = getattr(module, "__file__", None)
        if not name:
            continue
        path = Path(name).resolve()
        if path.suffix == ".py" and path.parent == tools and path.is_file():
            found.add(path)
    return sorted(found)


def verifier_digest(repo_root: Path, modules: Mapping[str, Any] | None = None) -> str:
    """The digest of the tool modules the process imported (a change to any reruns every unit)."""
    files = imported_tool_files(repo_root, modules)
    return digest(*(f"{p.name}={file_digest(p)}" for p in files))


def binding_problem(executable: Path, c_file: Path) -> str | None:
    """Why the key computed from `c_file` may not describe `executable`, or None when it does.

    `conformance_cli.build_backend` writes `<executable>.build.json` with the sha256 of the C
    file it was built from and of the executable it copied; both must still match."""
    sidecar = executable.with_name(executable.name + ".build.json")
    if not sidecar.is_file():
        return f"{executable.name} has no build record ({sidecar.name}): rebuild it"
    if not executable.is_file() or not c_file.is_file():
        return f"{executable} or {c_file} is missing"
    try:
        record = json.loads(sidecar.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        return f"the build record of {executable.name} is unreadable: {error}"
    if record.get("exe_sha256") != file_digest(executable):
        return f"{executable.name} is not the executable that was recorded at its build"
    if record.get("cli_c_sha256") != file_digest(c_file):
        return f"{c_file.name} is not the C file {executable.name} was built from"
    return None


@dataclasses.dataclass
class Context:
    builder: KeyBuilder
    problems: list[str]


def load_context(
    repo_root: Path,
    c_file: Path,
    target_dir: Path,
    executables: Sequence[Path] = (),
    modules: Mapping[str, Any] | None = None,
    stage_env: Mapping[str, str] | None = None,
    environ: Mapping[str, str] | None = None,
) -> Context:
    """Parse the generated C, bind it to the executables and collect the toolchain.

    `problems` non-empty (or an error while forming keys: `KeysUnavailable`): the caller runs
    everything and records nothing. `environ` is the environment the units' processes get
    (default: this process's); the variables the stub sources read are part of the key.
    """
    problems: list[str] = []
    for executable in executables:
        reason = binding_problem(executable, c_file)
        if reason:
            problems.append(reason)
    try:
        program = cf.read_c_file(c_file, forbidden_paths=(str(repo_root),))
        commands = cf.moon_build_commands(repo_root, target_dir)
        parts = cf.collect_toolchain(
            repo_root, Path.home() / ".moon", cf.run_command, dict(stage_env or {}),
            environ=dict(os.environ if environ is None else environ), build_commands=commands,
        )
        problems += cf.toolchain_problems(parts)
        if program.path_hits:
            problems.append(f"{program.path_hits} checkout paths outside #line directives")
        overlap = cf.local_name_overlap(program, repo_root, Path.home() / ".moon")
        if overlap:
            problems.append(f"{len(overlap)} renamed local names also occur in headers or stubs: {overlap[:3]}")
        builder = KeyBuilder(program, cf.toolchain_digest(parts), verifier_digest(repo_root, modules))
        for frontend in builder.frontends:
            builder.frame(frontend)
            builder.arms(frontend)
    except (cf.UnknownEntryError, cf.ParseError, KeyError, ValueError, OSError) as error:
        raise KeysUnavailable(f"no key can be formed: {error}") from error
    return Context(builder, problems)
