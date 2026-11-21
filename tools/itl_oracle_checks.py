#!/usr/bin/env python3
"""Run every check mode of the interval oracle programs, one line each, with its run time.

The oracle programs recompute the expected values that the interval gate holds outside
ITF1788 (`testdata/interval/interpreter_refinements.json`, `testdata/interval/generated/`).
Each check below recomputes them from the exact definition in Python (stdlib `decimal` and
`fractions`; no code of this library runs), so a stored value that is edited by hand, or a
generator that drifts from its output, fails:

| check | what it asserts | corpus | about |
| --- | --- | --- | --- |
| trig-reverse | the 136 `sinRev/cosRev/tanRev` corpus statements are a superset of the exact hull; the 12 refinements equal the recomputed ones | yes | 1 s |
| pow-reverse-1 | all 429 `powRev1` statements equal the exact hull; no refinement is listed | yes | 1 s |
| pow-reverse-2 | all `powRev2` statements are a superset of the exact hull; the 2 hand-added refinements equal the recomputed ones | yes | 1 s |
| refinements | every entry of the JSON file is valid against the corpus (same rules as the gate's planner) | yes | under 1 s |
| atan2-reverse | `generated/atan2_rev.itl` is byte-identical to the generator output, and every one of the 15,582 grid cases agrees with the forward definition | no | 140 s CPU |

A check that needs the corpus and finds it missing is reported as skipped, with the count, and
the program fails under `--require-corpus` (the interval gate stage: the gate has fetched the
corpus). `--skip NAME` leaves a check out and says so.

    itl_oracle_checks.py [--require-corpus] [--skip NAME]... [--only NAME]...
"""

from __future__ import annotations

import argparse
import contextlib
import io
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

sys.path.insert(0, str(Path(__file__).resolve().parent))

import itl_atan2_reverse_oracle as atan2_oracle  # noqa: E402
import itl_pow2_reverse_oracle as pow2_oracle  # noqa: E402
import itl_pow_reverse_oracle as pow_oracle  # noqa: E402
import itl_refinements as refs  # noqa: E402
import itl_trig_reverse_oracle as trig_oracle  # noqa: E402

CORPUS_FILES = {
    "trig-reverse": trig_oracle.FILE,
    "pow-reverse-1": pow_oracle.FILE,
    "pow-reverse-2": pow2_oracle.FILE,
}


@dataclass(frozen=True)
class Check:
    name: str
    run: Callable[[], int]
    needs_corpus: bool


def refinements_valid() -> int:
    """The JSON file against the corpus statements: `itl_refinements.validate`."""
    listed = refs.load(trig_oracle.REFINEMENTS)
    try:
        refs.validate(listed, refs.corpus_statements(trig_oracle.CORPUS))
    except ValueError as error:
        print(f"interpreter_refinements.json: {error}")
        return 1
    print(f"{len(listed)} refinements are valid against the corpus")
    return 0


CHECKS = (
    Check("trig-reverse", lambda: trig_oracle.main(["--check"]), True),
    Check("pow-reverse-1", lambda: pow_oracle.main([]), True),
    Check("pow-reverse-2", lambda: pow2_oracle.main([]), True),
    Check("refinements", refinements_valid, True),
    Check("atan2-reverse", lambda: atan2_oracle.main(["--check"]), False),
)


def corpus_present(corpus: Path | None = None) -> bool:
    directory = trig_oracle.CORPUS if corpus is None else corpus
    return all((directory / name).is_file() for name in CORPUS_FILES.values())


def run_checks(
    checks: tuple[Check, ...],
    require_corpus: bool,
    corpus: Path | None = None,
    stream: object = None,
) -> tuple[int, int, int]:
    """Runs the checks; returns (passed, failed, skipped) and prints a line for each."""
    out = sys.stdout if stream is None else stream
    present = corpus_present(corpus)
    passed = failed = skipped = 0
    for check in checks:
        if check.needs_corpus and not present:
            if require_corpus:
                failed += 1
                print(f"FAIL  {check.name}: the ITF1788 corpus is missing", file=out)
            else:
                skipped += 1
                print(f"SKIP  {check.name}: the ITF1788 corpus is missing", file=out)
            continue
        captured = io.StringIO()
        started = time.monotonic()
        with contextlib.redirect_stdout(captured):
            status = check.run()
        seconds = time.monotonic() - started
        if status == 0:
            passed += 1
            print(f"PASS  {check.name} ({seconds:.1f} s)", file=out)
        else:
            failed += 1
            print(f"FAIL  {check.name} ({seconds:.1f} s)", file=out)
        detail = captured.getvalue().rstrip()
        if detail and status != 0:
            print("\n".join(f"      {line}" for line in detail.splitlines()[:40]), file=out)
    return passed, failed, skipped


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--require-corpus", action="store_true", help="a missing corpus is a failure, not a skip")
    parser.add_argument("--skip", action="append", default=[], metavar="NAME")
    parser.add_argument("--only", action="append", default=[], metavar="NAME")
    args = parser.parse_args(argv)
    names = {check.name for check in CHECKS}
    unknown = sorted((set(args.skip) | set(args.only)) - names)
    if unknown:
        parser.error(f"unknown check: {', '.join(unknown)}; known: {', '.join(sorted(names))}")
    selected = tuple(
        check
        for check in CHECKS
        if (not args.only or check.name in args.only) and check.name not in args.skip
    )
    for name in args.skip:
        print(f"SKIP  {name}: left out by --skip")
    passed, failed, skipped = run_checks(selected, args.require_corpus)
    print(f"interval oracle checks: {passed} passed, {failed} failed, {skipped + len(args.skip)} skipped")
    return 0 if failed == 0 and passed > 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
