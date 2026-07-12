import os
import shutil
import subprocess
import tempfile
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
BUILD_ROOT = REPO_ROOT / "_build/conformance"
BACKENDS = ("gda", "testfloat", "mpfr", "itl")


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
        "src/cli",
    ]


def build_backend(backend: str) -> Path:
    destination = executable_path(backend)
    target_dir = BUILD_ROOT / backend
    environment = os.environ.copy()
    environment["CODEX_MOON_TARGET_DIR"] = str(target_dir)
    result = subprocess.run(
        build_command(),
        cwd=REPO_ROOT,
        env=environment,
        text=True,
        capture_output=True,
    )
    generated = target_dir / "native/release/build/cli/cli.exe"
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
    finally:
        temporary.unlink(missing_ok=True)
    return destination
