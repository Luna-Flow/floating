import argparse
import hashlib
import json
import os
import shutil
import sys
import tempfile
import time
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


DOWNLOAD_ATTEMPTS = 4
RETRY_DELAY_SECONDS = 2.0


class IncompleteDownload(OSError):
    """The transfer ended before the advertised Content-Length was received."""


def check_complete(expected_length: int | None, received: int) -> None:
    """Pure check: raise IncompleteDownload if the body is shorter than advertised.

    http.client's chunked ``read(n)`` returns short data (no exception) when the
    peer resets the connection mid-body, so a truncated archive otherwise shows
    up only as a confusing SHA-256 mismatch (issue #361). A hash mismatch on a
    *complete* body is a real integrity failure and is never retried.
    """
    if expected_length is not None and received != expected_length:
        raise IncompleteDownload(
            f"truncated download: received {received} of {expected_length} bytes"
        )


def content_length(response: object) -> int | None:
    headers = getattr(response, "headers", None)
    value = headers.get("Content-Length") if headers is not None else None
    return int(value) if value is not None and str(value).isdigit() else None


def _download_once(url: str, expected_hash: str, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        dir=destination.parent, delete=False
    ) as stream:
        temporary = Path(stream.name)
        try:
            with urllib.request.urlopen(url) as response:
                shutil.copyfileobj(response, stream)
                expected_length = content_length(response)
            stream.flush()
            os.fsync(stream.fileno())
            check_complete(expected_length, temporary.stat().st_size)
            actual_hash = sha256(temporary)
            if actual_hash != expected_hash:
                raise ValueError(
                    f"downloaded checksum mismatch: expected {expected_hash}, "
                    f"got {actual_hash}"
                )
            temporary.replace(destination)
        finally:
            temporary.unlink(missing_ok=True)


def download(
    url: str,
    expected_hash: str,
    destination: Path,
    *,
    attempts: int = DOWNLOAD_ATTEMPTS,
    delay: float = RETRY_DELAY_SECONDS,
) -> None:
    """Download and verify; retry only transport failures, never hash mismatches."""
    for attempt in range(1, attempts + 1):
        try:
            _download_once(url, expected_hash, destination)
            return
        except OSError as error:  # includes IncompleteDownload, resets, timeouts
            if attempt == attempts:
                raise
            print(
                f"download attempt {attempt}/{attempts} failed ({error}); retrying",
                file=sys.stderr,
            )
            time.sleep(delay)


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


IEEE_DECIMAL_ROUNDINGS = ("half_even", "half_up", "down", "ceiling", "floor")
IEEE_DECIMAL_PRECISION_MAX = 999_999_999
IEEE_DECIMAL_E_MAX_LIMIT = 999_999_999


def check_ieee_decimal_context(
    precision: int, rounding: str, emin: int, emax: int, clamp: int, tininess: str
) -> None:
    """Reject a context that no IEEE 754-2019 decimal format has.

    The one definition of a legal `decimal` context that the generators and the
    runner share (the library enforces the same in `DecimalContext::try_new`):
    precision and `emax` within the implementation limits, `emin = 1 - emax`
    (3.3), every finite result a member of the format (`clamp` on), tininess
    detected before rounding (7.5), and one of the five rounding-direction
    attributes of 4.3. `half_up` is roundTiesToAway, `down` roundTowardZero,
    `ceiling` roundTowardPositive and `floor` roundTowardNegative.
    """
    if not 1 <= precision <= IEEE_DECIMAL_PRECISION_MAX:
        raise ValueError(f"precision {precision} outside 1..{IEEE_DECIMAL_PRECISION_MAX}")
    if not 1 <= emax <= IEEE_DECIMAL_E_MAX_LIMIT:
        raise ValueError(f"emax {emax} outside 1..{IEEE_DECIMAL_E_MAX_LIMIT}")
    if emin != 1 - emax:
        raise ValueError(f"emin {emin} is not 1 - emax ({1 - emax}): not an IEEE 754-2019 format")
    if not clamp:
        raise ValueError("clamp must be 1: every result of an IEEE format is a member of the format")
    if tininess != "b":
        raise ValueError("tininess must be b: decimal formats detect tininess before rounding (7.5)")
    if rounding not in IEEE_DECIMAL_ROUNDINGS:
        raise ValueError(f"rounding {rounding} is not a rounding-direction attribute of 4.3")
