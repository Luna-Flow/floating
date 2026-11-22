"""Audit hook for the Python stages that run as incremental units (`tools/stage_units.py`).

Python imports this module at start-up of every interpreter whose `PYTHONPATH` starts with this
directory, so the stage's own process is observed. The audit is a check against an honest mistake, not a
sandbox: it reports what CPython reports. With
`STAGE_AUDIT_LOG` and `STAGE_AUDIT_ROOT` set it appends one line per event to the log:

    B <pid> <version>
                the hook was loaded by the interpreter process <pid> of this `sys.version` (the start
                line: a log must hold exactly one, the stage's own process; a Python process that does
                not load the hook, as with `-I`, `-E` or `-S`, writes none)
    R <path>    a file below the root was opened for reading (or reading and writing)
    D <path>    a directory below the root was listed or scanned
    L <event> <what>
                a process was launched or replaced (`subprocess.Popen`, `os.posix_spawn`, `os.exec`,
                `os.spawn`, `os.system`, `os.fork`, `os.forkpty`, `pty.spawn`, `os.startfile`,
                `webbrowser.open`): a run with any such line is not recorded
    U <event>   a `ctypes` event (a call into a foreign library, which can start anything unseen)
    X <path>    a file outside the root (absolute path) was opened for reading, or a directory outside
                the root was listed or scanned, except the standard library of the interpreter (not
                its site-packages: an installed package is an input that no key covers), the
                directories on the interpreter's own `sys.path` at start-up (the import system looking
                for a module; opening a file below them is still an `X`) and the files below
                `STAGE_AUDIT_EXEMPT` (the private compiled-module cache of the run)
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

    _ROOT = os.path.realpath(_ROOT)

    def _real(path: str) -> str:
        return os.path.realpath(path)

    def _paths(*names: str) -> tuple[str, ...]:
        return tuple(sorted({_real(p) for p in (sysconfig.get_path(name) for name in names) if p}))

    _STDLIB = _paths("stdlib", "platstdlib")
    _SITE = _paths("purelib", "platlib")  # usually below the standard library path
    _SYS_PATH = frozenset(_real(p) for p in sys.path if p)  # where the import system looks, as of start-up
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

    # Every event that starts or replaces a process (CPython's audit events table): a stage that raises one is
    # not recorded, so no launch has to be counted or matched with a start line.
    _LAUNCH = {
        "subprocess.Popen", "os.posix_spawn", "os.exec", "os.spawn", "os.system", "os.fork", "os.forkpty",
        "pty.spawn", "os.startfile", "webbrowser.open",
    }
    _unsafe_seen: set = set()

    def _detail(event: str, args: tuple) -> str:  # type: ignore[type-arg]
        try:
            if event == "subprocess.Popen":
                return os.fsdecode(args[0] if args[0] else (args[1][0] if args[1] else ""))
            if event == "os.spawn":
                return os.fsdecode(args[1])
            if event in ("os.system", "os.exec", "os.posix_spawn", "pty.spawn", "os.startfile", "webbrowser.open"):
                return os.fsdecode(args[0])
        except Exception:
            pass
        return ""

    def _hook(event: str, args: tuple) -> None:  # type: ignore[type-arg]
        try:
            if event in _LAUNCH:
                _write(f"L {event} {_detail(event, args)}")
            elif event.startswith("ctypes."):  # a call into a foreign library starts anything unseen
                if event not in _unsafe_seen:
                    _unsafe_seen.add(event)
                    _write(f"U {event}")
            elif event == "open":
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
                    elif absolute is not None and not _own(absolute) and not _under(absolute, _EXEMPT) and absolute not in _SYS_PATH:
                        _write(f"X {absolute}")
        except Exception:  # an audit hook must never break the stage
            pass

    _write(f"B {os.getpid()} {sys.version}")
    sys.addaudithook(_hook)
