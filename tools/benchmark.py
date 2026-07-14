#!/usr/bin/env python3

import sys
from collections.abc import Callable

import run_bin_coeff_bench
import run_decimal_bench
import run_decimal_threshold_bench


EntryPoint = Callable[[list[str] | None], int]
BENCHMARKS: dict[str, EntryPoint] = {
    "binary": run_bin_coeff_bench.main,
    "decimal": run_decimal_bench.main,
    "decimal-threshold": run_decimal_threshold_bench.main,
}


def usage() -> str:
    return "usage: benchmark.py <binary|decimal|decimal-threshold> [args ...]"


def main(argv: list[str] | None = None) -> int:
    arguments = list(sys.argv[1:] if argv is None else argv)
    if arguments and arguments[0] in {"-h", "--help"}:
        print(usage())
        return 0
    if not arguments:
        print(usage(), file=sys.stderr)
        return 2
    suite, *remaining = arguments
    entry_point = BENCHMARKS.get(suite)
    if entry_point is None:
        print(f"unknown benchmark suite: {suite}", file=sys.stderr)
        print(usage(), file=sys.stderr)
        return 2
    return entry_point(remaining)


if __name__ == "__main__":
    raise SystemExit(main())
