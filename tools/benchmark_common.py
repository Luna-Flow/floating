from __future__ import annotations

import json
import platform
import subprocess
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class CommandResult:
    returncode: int
    output: str


def capture_command(command: list[str], cwd: Path) -> CommandResult:
    completed = subprocess.run(
        command,
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    return CommandResult(completed.returncode, completed.stdout.strip())


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def utc_stamp(format_string: str) -> str:
    return datetime.now(timezone.utc).strftime(format_string)


def platform_metadata() -> dict[str, str]:
    return {
        "system": platform.system(),
        "release": platform.release(),
        "machine": platform.machine(),
    }


def write_json(path: Path, payload: Any, *, ensure_ascii: bool = True) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(payload, ensure_ascii=ensure_ascii, indent=2) + "\n",
        encoding="utf-8",
    )


def write_report_files(
    output_dir: Path,
    stem: str,
    payload: Any,
    markdown: str,
    *,
    ensure_ascii: bool = True,
) -> tuple[Path, Path]:
    output_dir.mkdir(parents=True, exist_ok=True)
    raw_path = output_dir / f"{stem}.json"
    markdown_path = output_dir / f"{stem}.md"
    write_json(raw_path, payload, ensure_ascii=ensure_ascii)
    markdown_path.write_text(markdown, encoding="utf-8")
    return raw_path, markdown_path
