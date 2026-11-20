#!/usr/bin/env python3
"""Run the opt-in `huge_trig_extreme` row table (decimal sin, cos, tan at `1E+999999`).

Each row costs 20 to 60 seconds (the argument reduction needs about 3.4 million
bits of pi), so the table is not part of `just gate decimal`. It is executed by
the same release-built conformance CLI as the gate's tables:

    python3 tools/run_huge_trig_extreme.py --target native
"""

from __future__ import annotations

import argparse
import subprocess
import sys

import decimal_row_table
import random_differential

ROOT = decimal_row_table.TABLE_ROOT.parents[3]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", default="native", choices=random_differential.TARGETS)
    args = parser.parse_args(argv)
    cli = random_differential.conformance_cli(args.target)
    status = 0
    for name in decimal_row_table.OPT_IN_TABLES:
        path = decimal_row_table.table_path(name)
        expected = decimal_row_table.count_rows(path.read_text(encoding="utf-8"))
        process = subprocess.run(
            [*cli, "--backend", "mpfr", "--json", str(path)],
            cwd=ROOT, check=False, capture_output=True, text=True,
        )
        outcome = decimal_row_table.evaluate_run(
            name, expected, process.returncode, process.stdout, process.stderr
        )
        print(f"{name} on {args.target}: {outcome}")
        status = status or int(outcome.get("failedCases", 0) != 0)
    return status


if __name__ == "__main__":
    sys.exit(main())
