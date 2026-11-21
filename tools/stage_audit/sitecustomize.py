"""Audit hook for the Python stages that run as incremental units (`tools/stage_units.py`).

Python imports this module at start-up of every interpreter whose `PYTHONPATH` starts with this
directory, so the stage's own process and every Python process it starts are observed. With
`STAGE_AUDIT_LOG` and `STAGE_AUDIT_ROOT` set it appends one line per event to the log:

    R <path>    a file below the root was opened for reading (or reading and writing)
    D <path>    a directory below the root was listed or scanned
    S <program> a program was started (subprocess, os.system, os.exec*, os.spawn*, posix_spawn)

Paths are relative to the root, with `/`. Nothing else is recorded and nothing is changed: the
hook only appends text, so the stage behaves as without it.
"""

import os
import sys

_LOG = os.environ.get("STAGE_AUDIT_LOG")
_ROOT = os.environ.get("STAGE_AUDIT_ROOT")

if _LOG and _ROOT:
    _ROOT = os.path.realpath(_ROOT)

    def _relative(path: object) -> str | None:
        try:
            absolute = os.path.realpath(os.path.join(os.getcwd(), os.fsdecode(path)))  # type: ignore[arg-type]
        except (TypeError, ValueError, OSError):
            return None
        if absolute == _ROOT or absolute.startswith(_ROOT + os.sep):
            return os.path.relpath(absolute, _ROOT).replace(os.sep, "/")
        return None

    def _write(line: str) -> None:
        with open(_LOG, "a", encoding="utf-8") as stream:
            stream.write(line + "\n")

    def _hook(event: str, args: tuple) -> None:  # type: ignore[type-arg]
        try:
            if event == "open":
                flags = args[2] if len(args) > 2 and isinstance(args[2], int) else 0
                if isinstance(args[0], (str, bytes, os.PathLike)) and flags & 3 != 1:  # not write-only
                    relative = _relative(args[0])
                    if relative is not None:
                        _write(f"R {relative}")
            elif event in ("os.listdir", "os.scandir", "glob.glob"):
                target = args[0] if args and args[0] is not None else "."
                if isinstance(target, (str, bytes, os.PathLike)):
                    relative = _relative(target)
                    if relative is not None:
                        _write(f"D {relative}")
            elif event == "subprocess.Popen":
                program = args[0] if args[0] else (args[1][0] if args[1] else "")
                _write(f"S {os.fsdecode(program)}")
            elif event in ("os.system", "os.exec", "os.posix_spawn"):
                _write(f"S {os.fsdecode(args[0])}")
            elif event == "os.spawn":
                _write(f"S {os.fsdecode(args[1])}")
        except Exception:  # an audit hook must never break the stage
            pass

    sys.addaudithook(_hook)
