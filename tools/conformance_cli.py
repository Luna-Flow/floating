import hashlib
import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
BUILD_ROOT = REPO_ROOT / "_build/conformance"
BACKENDS = ("gda", "testfloat", "mpfr", "itl")
# Every backend runs the same `tooling/src/cli` program, so it is built once into one
# shared target directory; only the copied executables are named per backend.
SHARED_TARGET_DIR = BUILD_ROOT / "cli"


CLI_C_FILE = SHARED_TARGET_DIR / "native/release/build/Luna-Flow/floating-tools/cli/cli.c"


def sidecar_path(executable: Path) -> Path:
    """The build record written next to a copied executable."""
    return executable.with_name(executable.name + ".build.json")


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_build_record(executable: Path, c_file: Path) -> None:
    """Record the hash of the executable and of the C file it was built from (atomic).

    Incremental verification computes its keys from the C file; this record is what binds the
    C file to the executable that runs, so a rebuild after the copy, or a build that failed half
    way, is seen (`incremental.binding_problem`).

    Residue: a second build into the same target directory between the build and this hashing
    would bind the wrong pair; in one checkout the sources are the same, so the C file is the
    same, and a file that changes afterwards fails the check at run time."""
    record = {"exe_sha256": _sha256(executable), "cli_c_sha256": _sha256(c_file)}
    destination = sidecar_path(executable)
    with tempfile.NamedTemporaryFile("w", dir=destination.parent, prefix=f".{destination.name}.", delete=False) as stream:
        stream.write(json.dumps(record, sort_keys=True) + "\n")
        temporary = Path(stream.name)
    temporary.replace(destination)


def executable_path(backend: str) -> Path:
    if backend not in BACKENDS:
        raise ValueError(f"unknown CLI backend: {backend}")
    return (
        BUILD_ROOT
        / backend
        / "native/release/build"
        / f"{backend}-conformance.exe"
    )


def build_command() -> list[str]:
    return [
        "sh",
        "tools/run_moon_clean_exec.sh",
        "run",
        "--release",
        "--target",
        "native",
        "--build-only",
        "tooling/src/cli",
    ]


def build_backend(backend: str) -> Path:
    destination = executable_path(backend)
    target_dir = SHARED_TARGET_DIR
    environment = os.environ.copy()
    environment["CODEX_MOON_TARGET_DIR"] = str(target_dir)
    result = subprocess.run(
        build_command(),
        cwd=REPO_ROOT,
        env=environment,
        text=True,
        capture_output=True,
    )
    generated = target_dir / "native/release/build/Luna-Flow/floating-tools/cli/cli.exe"
    if result.returncode != 0 or not generated.is_file():
        raise RuntimeError(
            f"failed to build {backend} conformance interpreter:\n"
            + result.stdout
            + result.stderr
        )
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        dir=destination.parent,
        prefix=f".{destination.name}.",
        delete=False,
    ) as stream:
        temporary = Path(stream.name)
    try:
        shutil.copy2(generated, temporary)
        temporary.replace(destination)
        sidecar_path(destination).unlink(missing_ok=True)
        c_file = target_dir / "native/release/build/Luna-Flow/floating-tools/cli/cli.c"
        if c_file.is_file():
            write_build_record(destination, c_file)
    finally:
        temporary.unlink(missing_ok=True)
    return destination
