import argparse
import hashlib
import json
import os
import shutil
import sys
import tempfile
import urllib.request
import zipfile
from contextlib import contextmanager
from collections.abc import Callable, Iterator
from pathlib import Path, PurePosixPath


CorpusSync = Callable[[str, dict, bool, bool], None]


def load_manifest(path: Path, collection: str) -> dict:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("schemaVersion") != 1 or not isinstance(
        payload.get(collection), dict
    ):
        raise ValueError(f"unsupported corpus manifest: {path}")
    return payload


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def verify_sha256(path: Path, expected_hash: str) -> None:
    actual_hash = sha256(path)
    if actual_hash != expected_hash:
        raise ValueError(
            f"checksum mismatch for {path}: expected {expected_hash}, got {actual_hash}"
        )


def repo_path(root: Path, value: str) -> Path:
    path = (root / value).resolve()
    if path != root and root not in path.parents:
        raise ValueError(f"manifest path escapes repository: {value}")
    return path


def archive_path(filename: str) -> PurePosixPath:
    path = PurePosixPath(filename)
    if path.is_absolute() or ".." in path.parts:
        raise ValueError(f"unsafe archive member: {filename}")
    return path


def download(url: str, expected_hash: str, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        dir=destination.parent, delete=False
    ) as stream:
        temporary = Path(stream.name)
        try:
            with urllib.request.urlopen(url) as response:
                shutil.copyfileobj(response, stream)
            stream.flush()
            os.fsync(stream.fileno())
            actual_hash = sha256(temporary)
            if actual_hash != expected_hash:
                raise ValueError(
                    f"downloaded checksum mismatch: expected {expected_hash}, "
                    f"got {actual_hash}"
                )
            temporary.replace(destination)
        finally:
            temporary.unlink(missing_ok=True)


def ensure_artifact(
    url: str,
    expected_hash: str,
    destination: Path,
    *,
    verify_only: bool,
    force: bool = False,
) -> None:
    if force or not destination.is_file():
        if verify_only:
            raise FileNotFoundError(f"artifact is missing: {destination}")
        download(url, expected_hash, destination)
    verify_sha256(destination, expected_hash)


def run_fetcher(
    argv: list[str] | None,
    *,
    description: str,
    default_manifest: Path,
    collection: str,
    item_label: str,
    sync: CorpusSync,
    error_prefix: str,
) -> int:
    parser = argparse.ArgumentParser(description=description)
    parser.add_argument("names", nargs="*", help=f"{item_label} names; defaults to all")
    parser.add_argument("--manifest", type=Path, default=default_manifest)
    parser.add_argument("--verify-only", action="store_true")
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args(argv)
    try:
        manifest = load_manifest(args.manifest.resolve(), collection)
        items = manifest[collection]
        names = args.names or list(items)
        unknown = [name for name in names if name not in items]
        if unknown:
            raise ValueError(f"unknown {item_label}: {', '.join(unknown)}")
        for name in names:
            sync(name, items[name], args.verify_only, args.force)
        return 0
    except (KeyError, OSError, ValueError, zipfile.BadZipFile) as error:
        print(f"{error_prefix}: {error}", file=sys.stderr)
        return 1


@contextmanager
def staged_directory(destination: Path, prefix: str | None = None) -> Iterator[Path]:
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(
        tempfile.mkdtemp(
            prefix=prefix or f".{destination.name}-",
            dir=destination.parent,
        )
    )
    try:
        yield temporary
        if destination.exists():
            shutil.rmtree(destination)
        temporary.replace(destination)
    finally:
        if temporary.exists():
            shutil.rmtree(temporary)
