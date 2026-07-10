#!/usr/bin/env python3

import argparse
import hashlib
import json
import os
import shutil
import sys
import tempfile
import urllib.request
import zipfile
from pathlib import Path, PurePosixPath


REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_MANIFEST = REPO_ROOT / "testdata/decimal/corpora.json"


def load_manifest(path: Path) -> dict:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("schemaVersion") != 1 or not isinstance(payload.get("corpora"), dict):
        raise ValueError(f"unsupported corpus manifest: {path}")
    return payload


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def repo_path(value: str) -> Path:
    path = (REPO_ROOT / value).resolve()
    if REPO_ROOT not in path.parents:
        raise ValueError(f"manifest path escapes repository: {value}")
    return path


def validate_archive(archive: Path, spec: dict) -> list[zipfile.ZipInfo]:
    actual_hash = sha256(archive)
    if actual_hash != spec["sha256"]:
        raise ValueError(
            f"checksum mismatch for {archive}: expected {spec['sha256']}, got {actual_hash}"
        )
    with zipfile.ZipFile(archive) as bundle:
        members = []
        for member in bundle.infolist():
            path = PurePosixPath(member.filename)
            if path.is_absolute() or ".." in path.parts:
                raise ValueError(f"unsafe archive member: {member.filename}")
            if not member.is_dir() and path.suffix == ".decTest":
                members.append(member)
        expected = spec["expectedDecTestFiles"]
        if len(members) != expected:
            raise ValueError(
                f"unexpected .decTest count in {archive}: expected {expected}, got {len(members)}"
            )
        return members


def download(spec: dict, archive: Path) -> None:
    archive.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=archive.parent, delete=False) as stream:
        temporary = Path(stream.name)
        try:
            with urllib.request.urlopen(spec["url"]) as response:
                shutil.copyfileobj(response, stream)
            stream.flush()
            os.fsync(stream.fileno())
            if sha256(temporary) != spec["sha256"]:
                raise ValueError(f"downloaded checksum does not match manifest: {spec['url']}")
            temporary.replace(archive)
        finally:
            temporary.unlink(missing_ok=True)


def extract(archive: Path, destination: Path, members: list[zipfile.ZipInfo]) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=f".{destination.name}-", dir=destination.parent))
    try:
        with zipfile.ZipFile(archive) as bundle:
            for member in members:
                output = temporary / PurePosixPath(member.filename).name
                with bundle.open(member) as source, output.open("wb") as target:
                    shutil.copyfileobj(source, target)
        if destination.exists():
            shutil.rmtree(destination)
        temporary.replace(destination)
    finally:
        if temporary.exists():
            shutil.rmtree(temporary)


def sync_corpus(name: str, spec: dict, verify_only: bool, force: bool) -> None:
    archive = repo_path(spec["archive"])
    destination = repo_path(spec["destination"])
    if force or not archive.exists():
        if verify_only:
            raise FileNotFoundError(f"archive is missing: {archive}")
        download(spec, archive)
    members = validate_archive(archive, spec)
    if not verify_only:
        extract(archive, destination, members)
        stamp = {
            "url": spec["url"],
            "sha256": spec["sha256"],
            "decTestFiles": len(members),
        }
        (destination / ".corpus.json").write_text(
            json.dumps(stamp, indent=2) + "\n", encoding="utf-8"
        )
    action = "verified" if verify_only else "installed"
    print(f"{action} {name}: {len(members)} files, sha256 {spec['sha256']}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Fetch pinned GDA decimal test corpora")
    parser.add_argument("names", nargs="*", help="corpus names; defaults to all")
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--verify-only", action="store_true")
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()
    try:
        manifest = load_manifest(args.manifest.resolve())
        names = args.names or list(manifest["corpora"])
        for name in names:
            if name not in manifest["corpora"]:
                raise ValueError(f"unknown corpus: {name}")
            sync_corpus(name, manifest["corpora"][name], args.verify_only, args.force)
        return 0
    except (OSError, ValueError, zipfile.BadZipFile) as error:
        print(f"decimal corpus fetch failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
