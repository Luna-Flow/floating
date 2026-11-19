#!/usr/bin/env python3

import argparse
import subprocess
from pathlib import Path

import check_doc_examples
import doc_quality


REPO_ROOT = Path(__file__).resolve().parent.parent


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Run documentation manual gates")
    parser.add_argument(
        "--skip-package-tests",
        action="store_true",
        help="do not run the src/doc_examples tests (the repository gate's native "
        "test stage runs that package with --deny-warn)",
    )
    parser.add_argument(
        "--quality-only",
        action="store_true",
        help="run only the pure-Python manual quality checks (no moon)",
    )
    parser.add_argument(
        "--examples-only",
        action="store_true",
        help="run only the manual examples and the package tests",
    )
    arguments = parser.parse_args(argv)
    if arguments.quality_only and arguments.examples_only:
        parser.error("--quality-only and --examples-only exclude each other")
    if not arguments.examples_only:
        quality_result = doc_quality.main([])
        if quality_result != 0:
            return quality_result
    if arguments.quality_only:
        return 0
    examples_result = check_doc_examples.main([])
    if examples_result != 0:
        return examples_result
    if arguments.skip_package_tests:
        return 0
    return subprocess.run(
        [
            "sh",
            "tools/run_moon_clean_exec.sh",
            "test",
            "src/doc_examples",
            "--target",
            "native",
            "--deny-warn",
        ],
        cwd=REPO_ROOT,
    ).returncode


if __name__ == "__main__":
    raise SystemExit(main())
