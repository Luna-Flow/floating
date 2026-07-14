#!/usr/bin/env python3

import argparse
import subprocess
from pathlib import Path

import doc_quality


REPO_ROOT = Path(__file__).resolve().parent.parent


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Run localized documentation gates")
    parser.parse_args(argv)
    quality_result = doc_quality.main([])
    if quality_result != 0:
        return quality_result
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
