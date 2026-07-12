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
DEFAULT_MANIFEST = REPO_ROOT / "testdata/interval/corpora.json"


def validate_archive(archive: Path, spec: dict) -> list[zipfile.ZipInfo]:
    with zipfile.ZipFile(archive) as bundle:
        members = []
        for member in bundle.infolist():
            path = archive_path(member.filename)
            if not member.is_dir() and len(path.parts) >= 2 and path.parts[-2] == "itl" and path.suffix == ".itl":
                members.append(member)
        if len(members) != spec["expectedItlFiles"]:
            raise ValueError(
                f"unexpected ITL count: expected {spec['expectedItlFiles']}, got {len(members)}"
            )
        return members


def install(name: str, spec: dict, verify_only: bool, force: bool) -> None:
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
        with staged_directory(destination, prefix=".itf1788-") as temporary:
            with zipfile.ZipFile(archive) as bundle:
                for member in members:
                    with bundle.open(member) as source, (temporary / PurePosixPath(member.filename).name).open("wb") as target:
                        shutil.copyfileobj(source, target)
            (temporary / ".corpus.json").write_text(
                json.dumps(
                    {
                        "url": spec["url"],
                        "revision": spec["revision"],
                        "sha256": spec["sha256"],
                        "itlFiles": len(members),
                    },
                    indent=2,
                )
                + "\n",
                encoding="utf-8",
            )
    print(f"{'verified' if verify_only else 'installed'} {name}: {len(members)} ITL files")


def main(argv: list[str] | None = None) -> int:
    return run_fetcher(
        argv,
        description="Fetch pinned IEEE 1788 test corpora",
        default_manifest=DEFAULT_MANIFEST,
        collection="corpora",
        item_label="corpus",
        sync=install,
        error_prefix="interval corpus fetch failed",
    )


if __name__ == "__main__":
    raise SystemExit(main())
