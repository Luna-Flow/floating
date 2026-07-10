#!/usr/bin/env python3
"""Regression tests for tools/run_moon_clean_exec.sh."""

from __future__ import annotations

import os
import stat
import subprocess
import tempfile
from pathlib import Path


def assert_true(value: bool, message: str) -> None:
    if not value:
        raise AssertionError(message)


def write_executable(path: Path, content: str) -> None:
    path.write_text(content, encoding="utf-8")
    current_mode = path.stat().st_mode
    path.chmod(current_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


def main() -> int:
    repo_root = Path(__file__).resolve().parents[1]
    wrapper = repo_root / "tools" / "run_moon_clean_exec.sh"
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        build_dir = root / "_build" / "wasm-gc" / "debug" / "test"
        build_dir.mkdir(parents=True, exist_ok=True)
        db = build_dir / "test.moon_db"
        shm = build_dir / "test.moon_db-shm"
        wal = build_dir / "test.moon_db-wal"
        db.write_text("stale-db", encoding="utf-8")
        shm.write_text("stale-shm", encoding="utf-8")
        wal.write_text("stale-wal", encoding="utf-8")

        fake_bin = root / "bin"
        fake_bin.mkdir()
        fake_moon = fake_bin / "moon"
        marker = root / "fake-moon-ok.txt"
        write_executable(
            fake_moon,
            f"""#!/bin/sh
set -eu
test ! -e "_build/wasm-gc/debug/test/test.moon_db"
test ! -e "_build/wasm-gc/debug/test/test.moon_db-shm"
test ! -e "_build/wasm-gc/debug/test/test.moon_db-wal"
printf '%s\\n' "$*" > "{marker}"
""",
        )

        env = os.environ.copy()
        env["PATH"] = f"{fake_bin}:{env.get('PATH', '')}"
        completed = subprocess.run(
            ["sh", str(wrapper), "test", "src/consistency/core_wbtest.mbt", "--no-parallelize"],
            cwd=root,
            env=env,
            text=True,
            capture_output=True,
        )
        assert_true(completed.returncode == 0, f"wrapper should succeed: {completed.stderr}")
        assert_true(not db.exists(), "wrapper should remove stale test.moon_db before invoking moon")
        assert_true(not shm.exists(), "wrapper should remove stale test.moon_db-shm before invoking moon")
        assert_true(not wal.exists(), "wrapper should remove stale test.moon_db-wal before invoking moon")
        assert_true(marker.exists(), "fake moon should have been invoked after cleanup")
        invoked = marker.read_text(encoding="utf-8").strip()
        assert_true(
            invoked == "--target-dir _build test src/consistency/core_wbtest.mbt --no-parallelize",
            f"wrapper should forward moon arguments verbatim, got: {invoked!r}",
        )

        isolated_target = root / "custom-target"
        isolated_target.mkdir()
        custom_db = isolated_target / "test.moon_db"
        custom_db.write_text("custom-stale-db", encoding="utf-8")
        custom_marker = root / "fake-moon-custom.txt"
        write_executable(
            fake_moon,
            f"""#!/bin/sh
set -eu
test ! -e "custom-target/test.moon_db"
printf '%s\\n' "$*" > "{custom_marker}"
""",
        )
        env["CODEX_MOON_TARGET_DIR"] = "custom-target"
        completed = subprocess.run(
            ["sh", str(wrapper), "check", "src/decimal"],
            cwd=root,
            env=env,
            text=True,
            capture_output=True,
        )
        assert_true(completed.returncode == 0, f"wrapper should support custom target dir: {completed.stderr}")
        assert_true(not custom_db.exists(), "wrapper should remove stale db files from custom target dir")
        assert_true(custom_marker.exists(), "fake moon should have been invoked with custom target dir")
        custom_invoked = custom_marker.read_text(encoding="utf-8").strip()
        assert_true(
            custom_invoked == "--target-dir custom-target check src/decimal",
            f"wrapper should pass custom target dir through to moon, got: {custom_invoked!r}",
        )
    print("[test] run_moon_clean_exec removes stale test.moon_db files before invoking moon")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
