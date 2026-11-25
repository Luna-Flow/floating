#!/usr/bin/env python3
"""The mutation test of incremental verification.

The question it answers: can a unit be reused although the code it runs has changed (a false
reuse)? The oracle for that is level A: the TestFloat vectors and the MPFR corpora. For each
mutation (a one-line edit of a library or tooling function, written out below with the function
it is in) the script, in a scratch worktree:

1. builds the baseline once and runs the selected units incrementally into a scratch ledger;
2. applies the edit, rebuilds, and runs the same units against a copy of the baseline ledger
   with sampling off (`--sample-rate 0`);
3. for a behavioural mutation, also runs every selected unit on the mutated build against an empty
   ledger (all of them execute: the full run);
4. checks, per mutation:
   (A) the false-reuse check, the independent one: a unit that fails in the full run (3) must
       have been executed in the incremental run (2), never reused. It shares no code with the
       keys: the oracle is the vectors and the corpora, and a unit whose interpreter crashes
       counts as failing;
   (B) a consistency check of two uses of the same reachability code: the set of units that ran
       equals the set whose closure in the baseline build contains the mutated function
       (membership in the reachable set of the baseline C against the keys of the mutated
       build). It catches a key that is too coarse or too fine, not an edge that `reachable`
       misses (both sides would miss it); (A) catches that;
   (C) for a behavioural mutation, at least one unit fails in the full run (the oracle sees the
       mutation: otherwise (A) is vacuous for it);
   (D) for a comment-only or formatting-only edit, no unit ran and nothing differs.
5. reverts the edit.

Two binding mutations come first: the executable or the C file no longer matches the build record
written by `build_backend`; the run must disable incremental (every unit executes, nothing is
recorded).

Usage: python3 tools/verify_mutation.py [--worktree DIR] [--only NAME ...] [--keep] [--kernel]
`--kernel` checks the kernel units (`kernel_units.py`) instead: a baseline that records the seven
kernel stages, then an edit of a package source (all seven must run and a stage must fail), of a
package test file and a comment-only edit (all seven run: the key is of file content, coarser than
code, allowed) and an edit of `binary` (none runs).
`--stages` checks the whole-stage units of the `decimal`, `decimal_gda` and `interval` gates (`stage_units.py`):
the key of every unit is formed before and after each edit and the set of units whose key changed
must be exactly the expected one (a code edit and a comment edit of a package the unit reaches, an edit
of a corpus row, an edit outside the reach: none); an edited oracle row must also make the stage fail.
Heavy: one build per mutation (about 30 s each) and two runs of the selection.
The scratch worktree defaults to `verify-mutation` beside the other worktrees; an existing one
must be clean and on the HEAD of this checkout.
Exit status: 0 all checks held; 1 a check failed; 2 the scratch worktree or its data is unusable.
"""

from __future__ import annotations

import argparse
import dataclasses
import json
import re
import shutil
import subprocess
import sys
import tempfile
from collections.abc import Collection, Mapping, Sequence
from pathlib import Path
from typing import Any

import code_fingerprint as cf
import incremental as inc
import run_ci
import stage_units as su

REPO_ROOT = Path(__file__).resolve().parent.parent

# The units of the test: small, so that a rebuild plus a run takes under a minute.
SELECTION = [
    "--format", "f16", "--format", "f128",
    "--operation", "add", "--operation", "sub", "--operation", "mul", "--operation", "div",
    "--operation", "sqrt", "--operation", "mulAdd", "--operation", "to_i32", "--operation", "eq",
    "--rounding", "rnear_even", "--rounding", "rmin",
]


@dataclasses.dataclass(frozen=True)
class Mutation:
    """A one-line edit. `symbol` is a regex for the C name of the function the line is in."""

    name: str
    path: str
    function: str  # the function the line is in, as written in the source
    symbol: str
    old: str
    new: str
    kind: str  # "behavioural" (a unit must fail), "key-only" (the key set is checked, no failure needed), "comment" or "format" (no key may change)


MUTATIONS: list[Mutation] = [
    Mutation(
        "kernel-compare", "library/src/internal/binary_kernel/coeff_words_nonjs.mbt",
        "bin_coeff_words_compare_padded", r"binary__kernel\d+bin__coeff__words__compare__padded$",
        "      return if left < right { -1 } else { 1 }",
        "      return if left < right { 1 } else { -1 }", "behavioural",
    ),
    Mutation(
        "binary-add", "library/src/binary/context_arithmetic.mbt",
        "Binary::add_ctx (the infinity branch)", r"binary\d+Binary\d+add__ctx$",
        "    (FpClass::Infinity, FpClass::Infinity) =>\n      if self.negative() == other.negative() {\n        (\n          Binary::inf_raw(\n            if self.negative() {\n              Sign::Negative\n            } else {\n              Sign::Positive\n            },\n            precision=context.precision,\n          ),\n          BinaryFlags::new(),\n        )\n      } else {\n        (Binary::nan_raw(precision=context.precision), binary_invalid_flags())\n      }\n    (FpClass::Infinity, _) =>\n      (\n        Binary::inf_raw(\n          if self.negative() {",
        "    (FpClass::Infinity, FpClass::Infinity) =>\n      if self.negative() != other.negative() {\n        (\n          Binary::inf_raw(\n            if self.negative() {\n              Sign::Negative\n            } else {\n              Sign::Positive\n            },\n            precision=context.precision,\n          ),\n          BinaryFlags::new(),\n        )\n      } else {\n        (Binary::nan_raw(precision=context.precision), binary_invalid_flags())\n      }\n    (FpClass::Infinity, _) =>\n      (\n        Binary::inf_raw(\n          if self.negative() {", "behavioural",
    ),
    Mutation(
        "binary-elementary", "library/src/binary/context_arithmetic.mbt",
        "Binary::pown_ctx (pown(x, 0), a row class of the MPFR elementary corpus)", r"binary\d+Binary\d+pown__ctx$",
        "  if exponent == 0 && !self.signaling() {\n    return (Binary::one_raw(precision=context.precision), BinaryFlags::new())",
        "  if exponent == 0 && !self.signaling() {\n    return (Binary::zero_raw(precision=context.precision), BinaryFlags::new())", "behavioural",
    ),
    Mutation(
        "frontend-arm", "tooling/src/frontend/testfloat_expr/testfloat_expr.mbt",
        "arm_sub", r"testfloat__expr\d+arm__sub$",
        "  left.sub_ctx(right, context)", "  left.add_ctx(right, context)", "behavioural",
    ),
    Mutation(
        "frontend-dispatcher", "tooling/src/frontend/testfloat_expr/testfloat_expr.mbt",
        "execute_float_case", r"testfloat__expr\d+execute__float__case$",
        "    (Add, [left, right]) => arm_add(left, right, context)",
        "    (Add, [left, right]) => arm_sub(left, right, context)", "behavioural",
    ),
    Mutation(
        "initialiser", "library/src/internal/binary_kernel/coeff_sqrt_array_nonjs.mbt",
        "top-level let bin_coeff_sqrt_empty_scratch (an initialiser in `moonbit_init`, read by the sqrt arm and the MPFR frontend)",
        r"^moonbit_init$",
        "let bin_coeff_sqrt_empty_scratch : FixedArray[UInt64] = FixedArray::make(0, 0UL)",
        "let bin_coeff_sqrt_empty_scratch : FixedArray[UInt64] = FixedArray::make(1, 0UL)", "key-only",
    ),
    Mutation(
        "interval", "library/src/interval/interval_decorated.mbt",
        "DecoratedInterval::is_empty", r"floating8interval\d+DecoratedInterval\d+is__empty$",
        "  !self.is_nai() && self.interval_.is_empty()",
        "  self.is_nai() && self.interval_.is_empty()", "key-only",
    ),
    Mutation(
        "decimal", "library/src/decimal/classify.mbt",
        "Decimal::is_zero (package decimal)", r"floating7decimal\d+Decimal\d+is__zero$",
        "  self.class == FpClass::Finite && self.coefficient.is_zero()",
        "  self.class == FpClass::Finite || self.coefficient.is_zero()", "key-only",
    ),
    Mutation(
        "decimal-gda", "library/src/decimal_gda/classify.mbt",
        "Decimal::is_finite (package decimal_gda)", r"decimal__gda\d+Decimal\d+is__finite$",
        "pub fn Decimal::is_finite(self : Decimal) -> Bool {\n  self.class == FpClass::Finite\n}",
        "pub fn Decimal::is_finite(self : Decimal) -> Bool {\n  self.class != FpClass::Finite\n}", "key-only",
    ),
    Mutation(
        "comment-only", "library/src/binary/binary_finish_nonjs.mbt",
        "bin_finish_round_up", r"binary\d+bin__finish__round__up$",
        "    RoundTowardZero => false",
        "    // a comment that changes no code\n    RoundTowardZero => false", "comment",
    ),
    Mutation(
        "format-only", "library/src/binary/binary_finish_nonjs.mbt",
        "bin_finish_round_up", r"binary\d+bin__finish__round__up$",
        "    RoundTiesToAway => round_bit",
        "\n\n    RoundTiesToAway   =>   round_bit", "format",
    ),
]


# ---------------------------------------------------------------------------------------
# Pure parts
# ---------------------------------------------------------------------------------------


def apply_mutation(text: str, mutation: Mutation) -> str:
    """The text with the mutation applied; the old text must occur exactly once. An empty old
    text appends the new text (a comment appended to a file)."""
    if mutation.old == "":
        return text + mutation.new
    count = text.count(mutation.old)
    if count != 1:
        raise ValueError(f"{mutation.name}: the old text occurs {count} times in {mutation.path}, not once")
    return text.replace(mutation.old, mutation.new, 1)


def unit_closure(
    builder: inc.KeyBuilder, frontend: str, arms: Sequence[str]
) -> set[str]:
    """The definitions a unit's key covers: the frame (start-up included) and the recorded arms."""
    program, spec = builder.program, builder.frontends[frontend]
    entry = inc._one(program, spec.entry, "entry")
    dispatcher = inc._one(program, spec.dispatcher, "dispatcher")
    arm_defs = inc.arm_definitions(program, spec.arm) if spec.arm else {}
    reach = cf.reachable(program, [*cf.START_UP, entry], cut={dispatcher}, exclude=set(arm_defs.values()))
    for arm in arms:
        reach |= cf.reachable(program, arm_defs[arm])
    return reach


def expected_ran(
    closures: Mapping[str, set[str]], symbol: str, definitions: Collection[str]
) -> set[str]:
    """The units whose closure contains a definition named by `symbol` (a regex)."""
    mutated = {name for name in definitions if re.search(symbol, name)}
    return {unit for unit, closure in closures.items() if mutated & closure}


def judge(
    mutation: Mutation,
    expected: set[str],
    ran: set[str],
    failed: set[str],
    all_units: set[str],
    mutated_definitions: Collection[str],
    failing_full: Collection[str] | None = None,
) -> list[str]:
    """The checks of one mutation; an empty list means they held.

    `failed` are the failing units of the incremental run (B), `failing_full` those of the run
    of every unit on the mutated build (A and C); None for a mutation that has no full run."""
    problems = []
    if failing_full is not None:
        reused_but_failing = set(failing_full) - ran
        if reused_but_failing:
            problems.append(
                f"FALSE REUSE: units that fail on the mutated build were not executed: {sorted(reused_but_failing)[:5]}"
            )
        if mutation.kind == "behavioural" and not failing_full:
            problems.append("no unit fails in the full run: the oracle did not see the mutation")
    if ran != expected:
        problems.append(
            f"units that ran differ from the units that reach {mutation.function}: "
            f"ran but not expected {sorted(ran - expected)[:5]}, expected but not run {sorted(expected - ran)[:5]}"
        )
    if mutation.kind in ("comment", "format") and ran:
        problems.append(f"an edit that changes no code changed {len(ran)} keys")
    if not mutated_definitions:
        problems.append(f"no definition in the baseline build matches {mutation.symbol!r}: the symbol is wrong")
    if mutation.kind == "behavioural" and not expected:
        problems.append("no unit reaches the mutated function: the mutation tests nothing")
    if not failed <= ran:
        problems.append(f"units that did not run failed: {sorted(failed - ran)[:5]}")
    if not ran <= all_units:
        problems.append("a unit that ran is not in the selection")
    return problems


BINDING_TAMPERS = ("executable", "c-file")


def judge_binding(summary: Mapping[str, Any], units: Collection[str], ledger_before: str, ledger_after: str) -> list[str]:
    """The checks of a binding mutation: after the build record was written, the executable (or
    the C file) no longer matches it. Incremental must be disabled for the run: every unit
    executes, nothing is recorded, and the summary has no `incremental` section."""
    problems = []
    if "incremental" in summary:
        problems.append("the run was incremental although the executable or the C file no longer matched its build record")
    executed = len(summary["testfloat"]["tasks"]) + len(summary["mpfr"])
    if executed != len(units):
        problems.append(f"{executed} units executed, expected all {len(units)}")
    if ledger_before != ledger_after:
        problems.append("the ledger changed: a run with a broken binding recorded results")
    return problems


def tamper(scratch: Path, kind: str) -> Any:
    """Break the binding; returns a function that restores it."""
    if kind == "executable":
        sidecar = scratch / "_build/conformance/testfloat/native/release/build/testfloat-conformance.exe.build.json"
        original = sidecar.read_text(encoding="utf-8")
        record = json.loads(original)
        record["exe_sha256"] = "0" * 64  # as if the executable had been replaced after the record
        sidecar.write_text(json.dumps(record), encoding="utf-8")
        return lambda: sidecar.write_text(original, encoding="utf-8")
    c_file = scratch / "_build/conformance/cli/native/release/build/Luna-Flow/floating-tools/cli/cli.c"
    text = c_file.read_bytes()
    c_file.write_bytes(text + b"\n")  # as if cli.c had been regenerated after the executable was copied
    return lambda: c_file.write_bytes(text)


# The kernel units (`kernel_units.py`): the edits of the second table of the mutation test, each
# with the number of units that must run and whether a stage must fail.
def _kernel_mutations() -> list[tuple[Mutation, int, bool]]:
    source = next(m for m in MUTATIONS if m.name == "kernel-compare")
    add = next(m for m in MUTATIONS if m.name == "binary-add")
    return [
        (dataclasses.replace(source, name="kernel-source"), 7, True),
        (
            Mutation(
                "kernel-test-file", "library/src/internal/binary_kernel/coeff_regression_wbtest.mbt",
                "a comment appended to a test file of the package", r"^$", "", "\n// a comment appended\n", "key-only",
            ),
            7, False,
        ),
        (
            Mutation(
                "kernel-comment-only", "library/src/internal/binary_kernel/coeff_words_nonjs.mbt",
                "a comment appended to a source file of the package (the key is of file content: all units run)",
                r"^$", "", "\n// a comment appended\n", "comment",
            ),
            7, False,
        ),
        (dataclasses.replace(add, name="binary-edit"), 0, False),
    ]


def judge_kernel(expected_run: int, plan: Mapping[str, Any], must_fail: bool, exit_status: int | None) -> list[str]:
    """The checks of one kernel row. `plan` is the `KERNEL-PLAN` the verify command printed."""
    problems = []
    if plan.get("disabled"):
        problems.append(f"the kernel units were disabled: {plan['disabled']}")
    ran = sum(1 for action in plan.get("actions", {}).values() if action == "run")
    if ran != expected_run:
        problems.append(f"{ran} kernel units would run, expected {expected_run}")
    if len(plan.get("actions", {})) != 7:
        problems.append(f"{len(plan.get('actions', {}))} kernel units in the plan, expected 7")
    if must_fail and exit_status == 0:
        problems.append("no kernel stage fails on the mutated tree: the oracles did not see the edit")
    return problems


def run_verify(worktree: Path, ledger: Path, extra: Sequence[str]) -> tuple[int, str]:
    command = [
        sys.executable, "tools/verify.py", "binary", "3", "--kernel-only", "--ledger", str(ledger), "--sample-rate", "0", *extra,
    ]
    result = subprocess.run(command, cwd=worktree, capture_output=True, text=True)
    return result.returncode, result.stdout


def kernel_plan(output: str) -> dict[str, Any]:
    for line in output.splitlines():
        if line.startswith("KERNEL-PLAN "):
            loaded = json.loads(line[len("KERNEL-PLAN ") :])
            assert isinstance(loaded, dict)
            return loaded
    raise RuntimeError("verify printed no KERNEL-PLAN:\n" + output[-1500:])


def kernel_rows(scratch: Path, work: Path) -> list[dict[str, object]]:
    """The rows for the kernel units: a baseline that records the seven stages, then each edit
    checked on the plan (which units would run); the source edit also runs the stages."""
    baseline = work / "kernel-baseline.jsonl"
    status, output = run_verify(scratch, baseline, [])
    if status != 0:
        raise RuntimeError("the kernel stages fail on the clean tree:\n" + output[-1500:])
    rows: list[dict[str, object]] = []
    for mutation, expected_run, must_fail in _kernel_mutations():
        path = scratch / mutation.path
        original = path.read_text(encoding="utf-8")
        ledger = work / f"kernel-{mutation.name}.jsonl"
        shutil.copy(baseline, ledger)
        try:
            path.write_text(apply_mutation(original, mutation), encoding="utf-8")
            _, plan_output = run_verify(scratch, ledger, ["--plan-only"])
            plan = kernel_plan(plan_output)
            exit_status = run_verify(scratch, ledger, [])[0] if must_fail else None
        finally:
            path.write_text(original, encoding="utf-8")
        problems = judge_kernel(expected_run, plan, must_fail, exit_status)
        rows.append(
            {
                "name": mutation.name, "kind": mutation.kind, "function": mutation.function,
                "expected": expected_run, "ran": sum(1 for a in plan.get("actions", {}).values() if a == "run"),
                "failed": 0 if exit_status in (None, 0) else 1, "reused_failing": 0,
                "verdict": "held" if not problems else "FAILED: " + "; ".join(problems),
            }
        )
        print(format_table(rows[-1:]).split("\n")[-1], flush=True)
    return rows


# The stage units of the decimal and decimal_gda gates (`stage_units.py`): the edits of the third
# table of the mutation test. Only keys are compared (no build): `expected` is the set of stage
# units whose key must change, written out from the import graph and the declared files.
GDA_PACKAGE_TESTS = "DECIMAL_GDA: package tests"
KERNEL_ORACLE_TABLE = "DECIMAL: kernel oracle table"
IEEE_1788 = "INTERVAL: IEEE 1788"
REVERSE_TRIG = "INTERVAL: reverse trigonometric reference"
ORACLE_CHECKS = "INTERVAL: oracle checks"
STAGE_SCOPES = ("decimal_gda", "decimal", "interval")


@dataclasses.dataclass(frozen=True)
class StageMutation:
    mutation: Mutation
    expected: frozenset[str]  # stage units whose key must change
    must_fail: tuple[str, ...] = ()  # a command (arguments of the interpreter, relative to the repository) that must fail on the edited tree


def _stage_mutations() -> list[StageMutation]:
    gda = next(m for m in MUTATIONS if m.name == "decimal-gda")
    binary = next(m for m in MUTATIONS if m.name == "binary-add")
    row = Mutation(
        "oracle-row", "library/src/internal/decimal_kernel/coeff_oracle_rows_wbtest.mbt",
        "the first row of the round table (a corpus row of the oracle stage)", r"^$",
        "  #|round-1 9618912607989939363", "  #|round-1 9618912607989939364", "key-only",
    )
    return [
        # decimal_gda imports `binary`, so an edit there reaches the GDA package tests too
        StageMutation(dataclasses.replace(gda, name="gda-source"), frozenset({GDA_PACKAGE_TESTS, IEEE_1788})),
        StageMutation(
            Mutation("gda-comment", gda.path, "a comment appended to a source file of the package (the key is of file content)", r"^$", "", "\n// a comment appended\n", "comment"),
            frozenset({GDA_PACKAGE_TESTS, IEEE_1788}),
        ),
        # `binary` is imported by `decimal_gda`, by `interval` and so by the conformance executable
        StageMutation(dataclasses.replace(binary, name="binary-edit"), frozenset({GDA_PACKAGE_TESTS, REVERSE_TRIG, IEEE_1788})),
        StageMutation(
            Mutation("oracle-program", "tools/decimal_kernel_oracle.py", "a comment appended to the oracle program", r"^$", "", "\n# a comment appended\n", "comment"),
            frozenset({KERNEL_ORACLE_TABLE}),
        ),
        # the rows file lives in `internal/decimal_kernel`, which `decimal_gda` imports: the key is of file
        # content, so the GDA package tests rerun too (coarser than code, allowed)
        StageMutation(row, frozenset({KERNEL_ORACLE_TABLE, GDA_PACKAGE_TESTS, IEEE_1788}), must_fail=("tools/decimal_kernel_oracle.py", "--check")),
        # `decimal` is not imported by `decimal_gda` but it is by the conformance executable
        StageMutation(
            Mutation("decimal-cli-only", "library/src/decimal/classify.mbt", "a comment appended to a source file of `decimal` (only the conformance executable imports it)", r"^$", "", "\n// a comment appended\n", "comment"),
            frozenset({IEEE_1788}),
        ),
        # the interval corpus run: a package of the executable, a package it imports, a corpus row (the
        # generated corpus is read by the stage and by the oracle checks), a tool file the runner imports,
        # a tool file only the oracle checks use, and an edit that no stage unit reaches
        StageMutation(
            Mutation("itl-frontend", "tooling/src/frontend/itl_expr/itl_expr.mbt", "a comment appended to the source of the interval frontend", r"^$", "", "\n// a comment appended\n", "comment"),
            frozenset({IEEE_1788}),
        ),
        StageMutation(
            Mutation("interval-source", "library/src/interval/interval_decorated.mbt", "a comment appended to a source file of `interval` (the reverse trigonometric tests and the executable import it)", r"^$", "", "\n// a comment appended\n", "comment"),
            frozenset({REVERSE_TRIG, IEEE_1788}),
        ),
        StageMutation(
            Mutation(
                "itl-corpus-row", "testdata/interval/generated/atan2_rev.itl", "the expected hull of the first atan2Rev1 row of the generated corpus", r"^$",
                "    atan2Rev1 [-infinity,-0x1.0000000000000p+1] [-infinity,-0x1.0000000000000p+2] [entire] = [empty];",
                "    atan2Rev1 [-infinity,-0x1.0000000000000p+1] [-infinity,-0x1.0000000000000p+2] [entire] = [entire];", "key-only",
            ),
            frozenset({IEEE_1788, ORACLE_CHECKS}),
            must_fail=("tools/conformance.py", "run", "--backend", "interval", "--phase", "atan2-reverse", "--strict-supported"),
        ),
        StageMutation(
            Mutation("itl-runner", "tools/run_itl_interpreter.py", "a comment appended to the runner of the interval corpus", r"^$", "", "\n# a comment appended\n", "comment"),
            frozenset({IEEE_1788}),
        ),
        StageMutation(
            Mutation("itl-oracle-checks", "tools/itl_oracle_checks.py", "a comment appended to the oracle check program", r"^$", "", "\n# a comment appended\n", "comment"),
            frozenset({ORACLE_CHECKS}),
        ),
        StageMutation(
            Mutation("outside-every-unit", "tooling/src/bench/binary/moon.pkg", "a comment appended to the package file of a benchmark package that no stage unit imports", r"^$", "", "\n// a comment appended\n", "comment"),
            frozenset(),
        ),
    ]


def stage_keys(root: Path, ledger: Path) -> dict[str, str]:
    """The key of every stage unit of the two gates in the tree at `root` (empty plan: nothing is run)."""
    keys: dict[str, str] = {}
    for scope in STAGE_SCOPES:
        stages = [(s.name, tuple(s.command)) for s in run_ci.stages_for(scope, 3)]
        plan = su.make_plan(scope, stages, root, inc.Ledger(ledger), 0, 0.0)
        if plan.disabled:
            raise RuntimeError(f"stage units are disabled in {root}: {plan.disabled}")
        for name, why in plan.unit_disabled.items():
            raise RuntimeError(f"stage unit {name} is not keyed in {root}: {why}")
        keys.update(plan.keys)
    return keys


def judge_stage(expected: Collection[str], before: Mapping[str, str], after: Mapping[str, str], must_fail: bool, failed: bool | None) -> list[str]:
    """The checks of one stage row: the units whose key changed are exactly the expected ones."""
    problems = []
    if set(before) != set(after):
        problems.append(f"the unit set changed: {sorted(set(before) ^ set(after))}")
    changed = {name for name in before if after.get(name) != before[name]}
    if changed != set(expected):
        problems.append(f"keys changed for {sorted(changed)}, expected {sorted(expected)}")
    if must_fail and not failed:
        problems.append("the stage passes on the edited tree: its oracle did not see the edit")
    return problems


def stage_rows(scratch: Path, work: Path) -> list[dict[str, object]]:
    ledger = work / "stage-keys.jsonl"
    # the `moon test --dry-run` of a moon stage needs the modules of the scratch tree (the gates' first stage)
    subprocess.run(run_ci.DEPENDENCY_STAGE.command, cwd=scratch, check=True, capture_output=True)
    # the interval corpus is fetched, not committed: the scratch tree gets the copy of this checkout
    corpus = REPO_ROOT / "testdata" / "interval" / "itf1788"
    if corpus.is_dir() and not (scratch / "testdata" / "interval" / "itf1788").exists():
        shutil.copytree(corpus, scratch / "testdata" / "interval" / "itf1788")
    before = stage_keys(scratch, ledger)
    rows: list[dict[str, object]] = []
    for item in _stage_mutations():
        mutation = item.mutation
        path = scratch / mutation.path
        original = path.read_text(encoding="utf-8")
        failed: bool | None = None
        try:
            path.write_text(apply_mutation(original, mutation), encoding="utf-8")
            after = stage_keys(scratch, ledger)
            if item.must_fail:
                failed = subprocess.run([sys.executable, *item.must_fail], cwd=scratch, capture_output=True).returncode != 0
        finally:
            path.write_text(original, encoding="utf-8")
        problems = judge_stage(item.expected, before, after, bool(item.must_fail), failed)
        rows.append(
            {
                "name": mutation.name, "kind": mutation.kind, "function": mutation.function,
                "expected": len(item.expected), "ran": sum(1 for n in before if after.get(n) != before[n]),
                "failed": 1 if failed else 0, "reused_failing": 0,
                "verdict": "held" if not problems else "FAILED: " + "; ".join(problems),
            }
        )
        print(format_table(rows[-1:]).split("\n")[-1], flush=True)
    return rows


def format_table(rows: Sequence[Mapping[str, object]]) -> str:
    """The result as a Markdown table."""
    lines = [
        "| mutation | kind | function | units reaching it | units that ran | failing in the full run | failing and reused | verdict |",
        "| --- | --- | --- | --- | --- | --- | --- | --- |",
    ]
    for row in rows:
        lines.append(
            f"| {row['name']} | {row['kind']} | {row['function']} | {row['expected']} | {row['ran']} | {row['failed']} | {row['reused_failing']} | {row['verdict']} |"
        )
    return "\n".join(lines)


# ---------------------------------------------------------------------------------------
# The driver
# ---------------------------------------------------------------------------------------


def run_selection(worktree: Path, ledger: Path, output_tag: str, extra: Sequence[str] = ()) -> tuple[int, dict[str, Any]]:
    """Run the selected units incrementally in `worktree`; returns (exit status, summary.json)."""
    command = [
        sys.executable, "tools/conformance.py", "run", "--backend", "binary", "--jobs", "3",
        "--level", "1", "--tininess", "after", *SELECTION,
        "--incremental", "--ledger", str(ledger), "--sample-rate", "0", "--sample-seed", "1",
        "--output", str(worktree / ".tmp" / "mutation-results" / output_tag), *extra,
    ]
    result = subprocess.run(command, cwd=worktree, capture_output=True, text=True)
    summary_path = worktree / ".tmp" / "mutation-results" / output_tag / "summary.json"
    if result.returncode not in (0, 1) or not summary_path.is_file():
        raise RuntimeError(f"run failed ({result.returncode}):\n{result.stdout[-2000:]}\n{result.stderr[-2000:]}")
    return result.returncode, json.loads(summary_path.read_text(encoding="utf-8"))


def scratch_problem(scratch: Path, needs_data: bool = True) -> str | None:
    """Why an existing scratch worktree cannot be used, or None: it must be on the HEAD of this
    checkout, clean, and have the corpora."""
    head = inc.git_output(REPO_ROOT, "rev-parse", "HEAD")
    there = inc.git_output(scratch, "rev-parse", "HEAD")
    if there != head:
        return f"{scratch} is on {there[:10] or 'no commit'}, this checkout on {head[:10]}: remove it or check it out"
    if inc.git_output(scratch, "status", "--porcelain", "--untracked-files=no"):
        return f"{scratch} has uncommitted changes: clean it"
    if needs_data and not (scratch / ".tmp" / "binary-conformance").is_dir():
        return f"{scratch} has no .tmp/binary-conformance"
    return None


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--worktree", type=Path, default=None, help="a scratch worktree (created if missing)")
    parser.add_argument("--only", action="append", default=[], help="run only these mutations")
    parser.add_argument("--keep", action="store_true", help="keep the scratch worktree")
    parser.add_argument("--kernel", action="store_true", help="check the kernel units instead of the TestFloat and MPFR units")
    parser.add_argument("--stages", action="store_true", help="check the whole-stage units of the decimal and decimal_gda gates")
    args = parser.parse_args(argv)
    mutations = [m for m in MUTATIONS if not args.only or m.name in args.only]
    scratch = args.worktree or inc.main_checkout(REPO_ROOT) / ".claude" / "worktrees" / "verify-mutation"
    created = False
    data = REPO_ROOT / ".tmp" / "binary-conformance"
    if not data.is_dir() and not args.stages:
        print(f"verify_mutation: {data} is missing: fetch the corpora first (`just conformance fetch binary`)", file=sys.stderr)
        return 2
    if not scratch.exists():
        subprocess.run(["git", "worktree", "add", "--detach", str(scratch), "HEAD"], cwd=REPO_ROOT, check=True)
        created = True
        if data.is_dir():
            shutil.copytree(data, scratch / ".tmp" / "binary-conformance")
    else:
        problem = scratch_problem(scratch, not args.stages)
        if problem:
            print(f"verify_mutation: {problem}", file=sys.stderr)
            return 2
    work = Path(tempfile.mkdtemp(prefix="verify-mutation-"))
    rows: list[dict[str, object]] = []
    failed_any = False
    try:
        if args.stages:
            rows = stage_rows(scratch, work)
            print()
            print(format_table(rows))
            return 1 if any(str(r["verdict"]).startswith("FAILED") for r in rows) else 0
        if args.kernel:
            rows = kernel_rows(scratch, work)
            print()
            print(format_table(rows))
            return 1 if any(str(r["verdict"]).startswith("FAILED") for r in rows) else 0
        baseline_ledger = work / "baseline.jsonl"
        _, summary = run_selection(scratch, baseline_ledger, "baseline")
        c_file = scratch / "_build/conformance/cli/native/release/build/Luna-Flow/floating-tools/cli/cli.c"
        baseline_c = work / "baseline.c"
        shutil.copy(c_file, baseline_c)
        program = cf.read_c_file(baseline_c)
        builder = inc.KeyBuilder(program, "t", "v")
        units = {u["unit"]: u["arms"] for u in summary["incremental"]["units"]}
        frontend_of = {name: ("mpfr" if name.endswith(".json") else "testfloat") for name in units}
        closures = {name: unit_closure(builder, frontend_of[name], arms) for name, arms in units.items()}
        for kind in BINDING_TAMPERS:
            ledger = work / f"binding-{kind}.jsonl"
            shutil.copy(baseline_ledger, ledger)
            before = ledger.read_text(encoding="utf-8")
            restore = tamper(scratch, kind)
            try:
                _, bound = run_selection(scratch, ledger, f"binding-{kind}", ["--no-build"])
            finally:
                restore()
            problems = judge_binding(bound, units, before, ledger.read_text(encoding="utf-8"))
            failed_any |= bool(problems)
            rows.append(
                {
                    "name": f"binding-{kind}", "kind": "binding", "function": "the build record",
                    "expected": 0, "ran": len(bound["testfloat"]["tasks"]) + len(bound["mpfr"]), "failed": 0, "reused_failing": 0,
                    "verdict": "held" if not problems else "FAILED: " + "; ".join(problems),
                }
            )
            print(format_table(rows[-1:]).split("\n")[-1], flush=True)
        for mutation in mutations:
            path = scratch / mutation.path
            original = path.read_text(encoding="utf-8")
            try:
                path.write_text(apply_mutation(original, mutation), encoding="utf-8")
                ledger = work / f"{mutation.name}.jsonl"
                shutil.copy(baseline_ledger, ledger)
                _, mutated = run_selection(scratch, ledger, mutation.name)
                failing_full: set[str] | None = None
                if mutation.kind == "behavioural":
                    empty = work / f"{mutation.name}-full.jsonl"
                    _, full = run_selection(scratch, empty, f"{mutation.name}-full", ["--no-build"])
                    failing_full = {u["unit"] for u in full["incremental"]["units"] if u["failedCases"]}
            finally:
                path.write_text(original, encoding="utf-8")
            status = {u["unit"]: u["status"] for u in mutated["incremental"]["units"]}
            ran = {u for u, s in status.items() if s == "ran"}
            failing_units = {u["unit"] for u in mutated["incremental"]["units"] if u["failedCases"]}
            expected = (
                set() if mutation.kind in ("comment", "format") else expected_ran(closures, mutation.symbol, program.definitions)
            )
            mutated_defs = [n for n in program.definitions if re.search(mutation.symbol, n)]
            problems = judge(mutation, expected, ran, failing_units, set(units), mutated_defs, failing_full)
            failed_any |= bool(problems)
            rows.append(
                {
                    "name": mutation.name, "kind": mutation.kind, "function": mutation.function,
                    "expected": len(expected), "ran": len(ran),
                    "failed": len(failing_full) if failing_full is not None else len(failing_units),
                    "reused_failing": len((failing_full or set()) - ran),
                    "verdict": "held" if not problems else "FAILED: " + "; ".join(problems),
                }
            )
            print(format_table(rows[-1:]).split("\n")[-1], flush=True)
    finally:
        shutil.rmtree(work, ignore_errors=True)
        if created and not args.keep:
            subprocess.run(["git", "worktree", "remove", "--force", str(scratch)], cwd=REPO_ROOT)
    print()
    print(format_table(rows))
    return 1 if failed_any else 0


if __name__ == "__main__":
    raise SystemExit(main())
