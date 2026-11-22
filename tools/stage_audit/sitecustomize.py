"""Audit hook for the Python stages that run as incremental units (`tools/stage_units.py`).

Python imports this module at start-up of every interpreter whose `PYTHONPATH` starts with this
directory, so the stage's own process and every Python process it starts are observed. With
`STAGE_AUDIT_LOG` and `STAGE_AUDIT_ROOT` set it appends one line per event to the log:

    B <version> the hook was loaded by an interpreter of this `sys.version` (the start line: a log
                without one says that no hook ran, as with `python -I` or `-S`)
    R <path>    a file below the root was opened for reading (or reading and writing)
    D <path>    a directory below the root was listed or scanned
    S <program> a program was started (subprocess, os.system, os.exec*, os.spawn*, posix_spawn)
    X <path>    a file outside the root (absolute path) was opened for reading, except the files of
                the interpreter itself (its standard library and site-packages) and the files below
                `STAGE_AUDIT_EXEMPT` (the private compiled-module cache of the run)
    C <path>    a file outside the root was created by the run (a later `X` of the same path, read
                by any process of the run, is not an outside input)

Paths below the root are relative to it, with `/`. Nothing else is recorded and nothing is changed:
the hook only appends text, so the stage behaves as without it.
"""

import os
import sys

_LOG = os.environ.get("STAGE_AUDIT_LOG")
_ROOT = os.environ.get("STAGE_AUDIT_ROOT")

if _LOG and _ROOT:
    import sysconfig

    _ROOT = os.path.realpath(_ROOT)

    def _real(path: str) -> str:
        return os.path.realpath(path)

    _OWN = tuple(
        sorted(
            {
                _real(p)
                for p in (sysconfig.get_path(name) for name in ("stdlib", "platstdlib", "purelib", "platlib"))
                if p
            }
        )
    )
    _EXEMPT = tuple(_real(p) for p in os.environ.get("STAGE_AUDIT_EXEMPT", "").split(os.pathsep) if p)

    def _under(absolute: str, bases: tuple[str, ...]) -> bool:
        return any(absolute == base or absolute.startswith(base + os.sep) for base in bases)

    def _resolve(path: object) -> str | None:
        try:
            return os.path.realpath(os.path.join(os.getcwd(), os.fsdecode(path)))  # type: ignore[arg-type]
        except (TypeError, ValueError, OSError):
            return None

    def _relative(absolute: str) -> str | None:
        if absolute == _ROOT or absolute.startswith(_ROOT + os.sep):
            return os.path.relpath(absolute, _ROOT).replace(os.sep, "/")
        return None

    def _write(line: str) -> None:
        with open(_LOG, "a", encoding="utf-8") as stream:
            stream.write(line.replace("\n", " ") + "\n")

    def _hook(event: str, args: tuple) -> None:  # type: ignore[type-arg]
        try:
            if event == "open":
                flags = args[2] if len(args) > 2 and isinstance(args[2], int) else 0
                if not isinstance(args[0], (str, bytes, os.PathLike)):
                    return
                absolute = _resolve(args[0])
                if absolute is None:
                    return
                relative = _relative(absolute)
                if relative is not None:
                    if flags & 3 != 1:  # not write-only
                        _write(f"R {relative}")
                elif _under(absolute, _OWN) or _under(absolute, _EXEMPT):
                    return
                elif flags & 3 != 1:
                    _write(f"X {absolute}")
                if relative is None and flags & os.O_CREAT and not os.path.lexists(absolute):
                    _write(f"C {absolute}")
            elif event in ("os.listdir", "os.scandir", "glob.glob"):
                target = args[0] if args and args[0] is not None else "."
                if isinstance(target, (str, bytes, os.PathLike)):
                    absolute = _resolve(target)
                    relative = _relative(absolute) if absolute is not None else None
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

    _write(f"B {sys.version}")
    sys.addaudithook(_hook)
