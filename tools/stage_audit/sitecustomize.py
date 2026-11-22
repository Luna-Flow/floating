"""Audit hook for the Python stages that run as incremental units (`tools/stage_units.py`).

Python imports this module at start-up of every interpreter whose `PYTHONPATH` starts with this
directory, so the stage's own process and every Python process it starts with that environment are
observed; a Python process that does not load it is detected by counting (`B` and `L` below). With
`STAGE_AUDIT_LOG` and `STAGE_AUDIT_ROOT` set it appends one line per event to the log:

    B <pid> <version>
                the hook was loaded by the interpreter process <pid> of this `sys.version` (the start
                line: one per hooked process; a Python process that does not load the hook, as with
                `-I`, `-E` or `-S`, an empty environment or a missing `PYTHONPATH`, writes none)
    L <program> a Python interpreter was launched (subprocess, os.exec*, os.spawn*, posix_spawn): the
                log must hold one start line for the stage's own process and one per launch
    R <path>    a file below the root was opened for reading (or reading and writing)
    D <path>    a directory below the root was listed or scanned
    S <program> a program was started (subprocess, os.system, os.exec*, os.spawn*, posix_spawn)
    X <path>    a file outside the root (absolute path) was opened for reading, or a directory outside
                the root was listed or scanned, except the standard library of the interpreter (not
                its site-packages: an installed package is an input that no key covers) and the files
                below `STAGE_AUDIT_EXEMPT` (the private compiled-module cache of the run)
    C <path>    a file outside the root was created by the run (a later `X` of the same path, read
                by any process of the run, is not an outside input)

Paths below the root are relative to it, with `/`. A name is written with every character that ends
a line for `str.splitlines` escaped as `\\uXXXX`, so that no name can forge a line. Nothing else is recorded and nothing is changed:
the hook only appends text, so the stage behaves as without it.
"""

import os
import sys

_LOG = os.environ.get("STAGE_AUDIT_LOG")
_ROOT = os.environ.get("STAGE_AUDIT_ROOT")

if _LOG and _ROOT:
    import sysconfig
    import threading

    _ROOT = os.path.realpath(_ROOT)

    def _real(path: str) -> str:
        return os.path.realpath(path)

    def _paths(*names: str) -> tuple[str, ...]:
        return tuple(sorted({_real(p) for p in (sysconfig.get_path(name) for name in names) if p}))

    _STDLIB = _paths("stdlib", "platstdlib")
    _SITE = _paths("purelib", "platlib")  # usually below the standard library path
    _EXEMPT = tuple(_real(p) for p in os.environ.get("STAGE_AUDIT_EXEMPT", "").split(os.pathsep) if p)

    def _under(absolute: str, bases: tuple[str, ...]) -> bool:
        return any(absolute == base or absolute.startswith(base + os.sep) for base in bases)

    def _own(absolute: str) -> bool:
        """The standard library, but not an installed package below it."""
        return _under(absolute, _STDLIB) and not _under(absolute, _SITE)

    _ENDS_A_LINE = {chr(c) for c in (0x0A, 0x0B, 0x0C, 0x0D, 0x1C, 0x1D, 0x1E, 0x85, 0x2028, 0x2029)}

    def _clean(text: str) -> str:
        return "".join(f"\\u{ord(c):04x}" if c in _ENDS_A_LINE else c for c in text)

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
        with open(_LOG, "a", encoding="utf-8", errors="backslashreplace") as stream:
            stream.write(_clean(line) + "\n")

    # One launch can raise two events: `subprocess.Popen` and then, when the interpreter starts the child with
    # `posix_spawn` (always on recent Linux builds, with `close_fds=False` elsewhere), `os.posix_spawn` with the
    # same program, arguments and environment, directly after it. That second event is the same launch.
    # Anything else in between, or a different program, argument list or environment, makes it a launch of its own.
    _pending: list = [None]

    def _launch_key(program: object, argv: object, env: object) -> tuple:  # type: ignore[type-arg]
        try:
            return (threading.get_ident(), os.fsdecode(program), tuple(os.fsdecode(a) for a in argv), repr(env))  # type: ignore[attr-defined,union-attr]
        except Exception:
            return (None,)

    def _launched(program: object, may_be_python: bool = True) -> None:
        name = os.fsdecode(program)
        _write(f"S {name}")
        if may_be_python and os.path.basename(name).startswith("python"):
            _write(f"L {name}")

    def _hook(event: str, args: tuple) -> None:  # type: ignore[type-arg]
        pending, _pending[0] = _pending[0], None
        try:
            if event == "os.posix_spawn" and pending is not None and pending == _launch_key(args[0], args[1], args[2]):
                return  # the second event of a launch that `subprocess.Popen` already wrote
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
                elif _own(absolute) or _under(absolute, _EXEMPT):
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
                    elif absolute is not None and not _own(absolute) and not _under(absolute, _EXEMPT):
                        _write(f"X {absolute}")
            elif event == "subprocess.Popen":
                program = args[0] if args[0] else (args[1][0] if args[1] else "")
                _launched(program)
                _pending[0] = _launch_key(program, args[1], args[3])
            elif event in ("os.system", "os.exec", "os.posix_spawn"):
                _launched(args[0], event != "os.system")
            elif event == "os.spawn":
                _launched(args[1])
        except Exception:  # an audit hook must never break the stage
            pass

    _write(f"B {os.getpid()} {sys.version}")
    sys.addaudithook(_hook)
