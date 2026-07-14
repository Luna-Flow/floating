#!/usr/bin/env python3

import sys
from collections.abc import Callable
from dataclasses import dataclass

import fetch_binfloat_corpora
import fetch_decimal_corpora
import fetch_interval_corpora
import run_binfloat_interpreter
import run_dectest_interpreter
import run_ieee_decimal
import run_itl_interpreter
from conformance_cli import build_backend
from conformance_runtime import BackendName


EntryPoint = Callable[[list[str] | None], int]


@dataclass(frozen=True)
class Backend:
    build_targets: tuple[str, ...]
    runner: EntryPoint
    fetcher: EntryPoint


BACKENDS = {
    BackendName.DECIMAL: Backend(
        build_targets=(),
        runner=run_ieee_decimal.main,
        fetcher=run_ieee_decimal.fetch_main,
    ),
    BackendName.DECIMAL_GDA: Backend(
        build_targets=("gda",),
        runner=run_dectest_interpreter.main,
        fetcher=fetch_decimal_corpora.main,
    ),
    BackendName.BINARY: Backend(
        build_targets=("testfloat", "mpfr"),
        runner=run_binfloat_interpreter.main,
        fetcher=fetch_binfloat_corpora.main,
    ),
    BackendName.INTERVAL: Backend(
        build_targets=("itl",),
        runner=run_itl_interpreter.main,
        fetcher=fetch_interval_corpora.main,
    ),
}

ACTIONS = {"build", "run", "smoke", "plan", "fetch"}

def usage() -> str:
    return (
        "usage: conformance.py <build|run|smoke|plan|fetch> "
        "--backend <decimal|decimal_gda|binary|interval> [args ...]"
    )


def parse_command(arguments: list[str]) -> tuple[str, BackendName, list[str]]:
    if not arguments:
        raise ValueError(usage())
    action, *remaining = arguments
    if action not in ACTIONS:
        raise ValueError(f"unknown conformance action: {action}")
    backend = ""
    forwarded: list[str] = []
    index = 0
    while index < len(remaining):
        argument = remaining[index]
        if argument == "--backend":
            if index + 1 >= len(remaining):
                raise ValueError("--backend requires a value")
            if backend:
                raise ValueError("--backend may only be specified once")
            index += 1
            backend = remaining[index]
        elif argument.startswith("--backend="):
            if backend:
                raise ValueError("--backend may only be specified once")
            backend = argument.removeprefix("--backend=")
        else:
            forwarded.append(argument)
        index += 1
    if not backend:
        raise ValueError("--backend is required")
    try:
        selected_backend = BackendName(backend)
    except ValueError as error:
        raise ValueError(f"unknown conformance backend: {backend}")
    return action, selected_backend, forwarded


def main(argv: list[str] | None = None) -> int:
    arguments = list(sys.argv[1:] if argv is None else argv)
    if arguments and arguments[0] in {"-h", "--help"}:
        print(usage())
        return 0
    try:
        action, backend, remaining = parse_command(arguments)
    except ValueError as error:
        print(error, file=sys.stderr)
        print(usage(), file=sys.stderr)
        return 2
    selected = BACKENDS[backend]
    if action == "build":
        if remaining:
            print("build does not accept backend arguments", file=sys.stderr)
            return 2
        for cli_backend in selected.build_targets:
            path = build_backend(cli_backend)
            print(path)
        return 0
    if action == "fetch":
        return selected.fetcher(remaining)
    if action == "run":
        return selected.runner(remaining)
    if action == "smoke":
        return selected.runner(["--smoke", *remaining])
    if action == "plan":
        return selected.runner(["--plan", *remaining])
    raise AssertionError(f"unhandled conformance action: {action}")


if __name__ == "__main__":
    raise SystemExit(main())
