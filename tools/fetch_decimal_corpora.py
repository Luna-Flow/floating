#!/usr/bin/env python3

import json
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
DEFAULT_MANIFEST = REPO_ROOT / "testdata/decimal/corpora.json"


def validate_archive(archive: Path, spec: dict) -> list[zipfile.ZipInfo]:
    with zipfile.ZipFile(archive) as bundle:
        members = []
        for member in bundle.infolist():
            path = archive_path(member.filename)
            if not member.is_dir() and path.suffix == ".decTest":
                members.append(member)
        expected = spec["expectedDecTestFiles"]
        if len(members) != expected:
            raise ValueError(
                f"unexpected .decTest count in {archive}: expected {expected}, got {len(members)}"
            )
        return members


def extract(archive: Path, destination: Path, members: list[zipfile.ZipInfo]) -> None:
    with staged_directory(destination) as temporary:
        with zipfile.ZipFile(archive) as bundle:
            for member in members:
                output = temporary / PurePosixPath(member.filename).name
                with bundle.open(member) as source, output.open("wb") as target:
                    shutil.copyfileobj(source, target)


def sync_corpus(name: str, spec: dict, verify_only: bool, force: bool) -> None:
    archive = repo_path(REPO_ROOT, spec["archive"])
    destination = repo_path(REPO_ROOT, spec["destination"])
    ensure_artifact(
        spec["url"],
        spec["sha256"],
        archive,
        verify_only=verify_only,
        force=force,
    )
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


def main(argv: list[str] | None = None) -> int:
    return run_fetcher(
        argv,
        description="Fetch pinned GDA decimal test corpora",
        default_manifest=DEFAULT_MANIFEST,
        collection="corpora",
        item_label="corpus",
        sync=sync_corpus,
        error_prefix="decimal corpus fetch failed",
    )


if __name__ == "__main__":
    raise SystemExit(main())
