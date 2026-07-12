#!/usr/bin/env python3

import shutil
import zipfile
from pathlib import Path, PurePosixPath

from corpus_common import (
    archive_path,
    ensure_artifact,
    repo_path,
    run_fetcher,
    staged_directory,
)


REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_MANIFEST = REPO_ROOT / "testdata/bin_float/corpora.json"


def validate_zip(archive: Path, spec: dict) -> list[zipfile.ZipInfo]:
    root = spec["root"]
    with zipfile.ZipFile(archive) as bundle:
        members = bundle.infolist()
        for member in members:
            path = archive_path(member.filename)
            if not path.parts or path.parts[0] != root:
                raise ValueError(f"archive member escapes expected root: {member.filename}")
        return members


def extract_zip(
    archive: Path,
    destination: Path,
    root: str,
    members: list[zipfile.ZipInfo],
) -> None:
    with staged_directory(destination) as temporary:
        with zipfile.ZipFile(archive) as bundle:
            for member in members:
                path = PurePosixPath(member.filename)
                relative = PurePosixPath(*path.parts[1:])
                if not relative.parts:
                    continue
                output = temporary.joinpath(*relative.parts)
                if member.is_dir():
                    output.mkdir(parents=True, exist_ok=True)
                else:
                    output.parent.mkdir(parents=True, exist_ok=True)
                    with bundle.open(member) as source, output.open("wb") as target:
                        shutil.copyfileobj(source, target)


def sync_zip(name: str, spec: dict, verify_only: bool, force: bool) -> None:
    archive = repo_path(REPO_ROOT, spec["archive"])
    destination = repo_path(REPO_ROOT, spec["destination"])
    ensure_artifact(
        spec["url"],
        spec["sha256"],
        archive,
        verify_only=verify_only,
        force=force,
    )
    members = validate_zip(archive, spec)
    if not verify_only:
        extract_zip(archive, destination, spec["root"], members)
    action = "verified" if verify_only else "installed"
    print(f"{action} {name}: sha256 {spec['sha256']}")


def sync_file(name: str, spec: dict, verify_only: bool, force: bool) -> None:
    destination = repo_path(REPO_ROOT, spec["destination"])
    ensure_artifact(
        spec["url"],
        spec["sha256"],
        destination,
        verify_only=verify_only,
        force=force,
    )
    action = "verified" if verify_only else "installed"
    print(f"{action} {name}: sha256 {spec['sha256']}")


def main(argv: list[str] | None = None) -> int:
    def sync(name: str, spec: dict, verify_only: bool, force: bool) -> None:
        if spec["kind"] == "zip":
            sync_zip(name, spec, verify_only, force)
        elif spec["kind"] == "file":
            sync_file(name, spec, verify_only, force)
        else:
            raise ValueError(f"unsupported artifact kind: {spec['kind']}")

    return run_fetcher(
        argv,
        description="Fetch pinned TestFloat, SoftFloat, and MPFR binary corpora",
        default_manifest=DEFAULT_MANIFEST,
        collection="artifacts",
        item_label="binary artifact",
        sync=sync,
        error_prefix="binary corpus fetch failed",
    )


if __name__ == "__main__":
    raise SystemExit(main())
