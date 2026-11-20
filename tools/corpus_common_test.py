import corpus_common
import hashlib
import io
import json
import tempfile
import unittest
from contextlib import redirect_stderr
from io import StringIO
from pathlib import Path
from unittest.mock import patch

from corpus_common import (
    IncompleteDownload,
    archive_path,
    check_complete,
    download,
    ensure_artifact,
    repo_path,
    run_fetcher,
    staged_directory,
)


class CorpusCommonTests(unittest.TestCase):
    def test_rejects_paths_outside_expected_roots(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            self.assertEqual(repo_path(root, "nested/file"), root / "nested/file")
            with self.assertRaises(ValueError):
                repo_path(root, "../escape")
        with self.assertRaises(ValueError):
            archive_path("../../escape")
        with self.assertRaises(ValueError):
            archive_path("/absolute")

    def test_downloads_and_verifies_artifact_atomically(self) -> None:
        payload = b"pinned corpus"
        expected_hash = hashlib.sha256(payload).hexdigest()
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "cache" / "artifact.zip"
            with patch("urllib.request.urlopen", return_value=io.BytesIO(payload)):
                ensure_artifact(
                    "https://example.invalid/artifact.zip",
                    expected_hash,
                    destination,
                    verify_only=False,
                )
            self.assertEqual(destination.read_bytes(), payload)
            ensure_artifact(
                "https://example.invalid/artifact.zip",
                expected_hash,
                destination,
                verify_only=True,
            )
            destination.write_bytes(b"corrupt")
            with self.assertRaises(ValueError):
                ensure_artifact(
                    "https://example.invalid/artifact.zip",
                    expected_hash,
                    destination,
                    verify_only=True,
                )

    def test_check_complete_flags_truncation(self) -> None:
        check_complete(None, 5)
        check_complete(10, 10)
        with self.assertRaises(IncompleteDownload):
            check_complete(10, 9)

    def test_truncated_download_is_retried_then_succeeds(self) -> None:
        payload = b"pinned corpus payload"
        expected_hash = hashlib.sha256(payload).hexdigest()

        def response(body: bytes) -> io.BytesIO:
            stream = io.BytesIO(body)
            stream.headers = {"Content-Length": str(len(payload))}  # type: ignore[attr-defined]
            return stream

        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "a.zip"
            with patch(
                "urllib.request.urlopen",
                side_effect=[response(payload[:5]), response(payload)],
            ) as opener, redirect_stderr(StringIO()):
                download("https://example.invalid/a", expected_hash, destination, delay=0)
            self.assertEqual(opener.call_count, 2)
            self.assertEqual(destination.read_bytes(), payload)

    def test_persistent_truncation_fails_without_installing(self) -> None:
        payload = b"pinned corpus payload"
        expected_hash = hashlib.sha256(payload).hexdigest()

        def short() -> io.BytesIO:
            stream = io.BytesIO(payload[:5])
            stream.headers = {"Content-Length": str(len(payload))}  # type: ignore[attr-defined]
            return stream

        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "a.zip"
            with patch(
                "urllib.request.urlopen", side_effect=[short(), short()]
            ), redirect_stderr(StringIO()):
                with self.assertRaises(IncompleteDownload):
                    download("u", expected_hash, destination, attempts=2, delay=0)
            self.assertFalse(destination.exists())

    def test_hash_mismatch_on_complete_body_is_not_retried(self) -> None:
        payload = b"tampered body"
        stream = io.BytesIO(payload)
        stream.headers = {"Content-Length": str(len(payload))}  # type: ignore[attr-defined]
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "a.zip"
            with patch("urllib.request.urlopen", return_value=stream) as opener:
                with self.assertRaises(ValueError):
                    download("u", "0" * 64, destination, attempts=3, delay=0)
            self.assertEqual(opener.call_count, 1)
            self.assertFalse(destination.exists())

    def test_staged_directory_replaces_only_after_success(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "installed"
            destination.mkdir()
            (destination / "old").write_text("old", encoding="utf-8")
            with self.assertRaises(RuntimeError):
                with staged_directory(destination) as staging:
                    (staging / "new").write_text("new", encoding="utf-8")
                    raise RuntimeError("stop")
            self.assertTrue((destination / "old").is_file())
            with staged_directory(destination) as staging:
                (staging / "new").write_text("new", encoding="utf-8")
            self.assertFalse((destination / "old").exists())
            self.assertEqual(
                (destination / "new").read_text(encoding="utf-8"), "new"
            )

    def test_fetcher_selects_items_and_forwards_common_flags(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            manifest_path = Path(directory) / "corpora.json"
            manifest_path.write_text(
                json.dumps(
                    {
                        "schemaVersion": 1,
                        "corpora": {"first": {"id": 1}, "second": {"id": 2}},
                    }
                ),
                encoding="utf-8",
            )
            received = []

            def sync(name: str, spec: dict, verify_only: bool, force: bool) -> None:
                received.append((name, spec["id"], verify_only, force))

            result = run_fetcher(
                ["second", "--verify-only", "--force"],
                description="Fetch test corpora",
                default_manifest=manifest_path,
                collection="corpora",
                item_label="corpus",
                sync=sync,
                error_prefix="fetch failed",
            )
            self.assertEqual(result, 0)
            self.assertEqual(received, [("second", 2, True, True)])

    def test_fetcher_rejects_unknown_items_before_syncing(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            manifest_path = Path(directory) / "corpora.json"
            manifest_path.write_text(
                json.dumps({"schemaVersion": 1, "corpora": {"known": {}}}),
                encoding="utf-8",
            )
            received = []
            with redirect_stderr(StringIO()) as stderr:
                result = run_fetcher(
                    ["known", "missing"],
                    description="Fetch test corpora",
                    default_manifest=manifest_path,
                    collection="corpora",
                    item_label="corpus",
                    sync=lambda *args: received.append(args),
                    error_prefix="fetch failed",
                )
            self.assertEqual(result, 1)
            self.assertEqual(received, [])
            self.assertIn("unknown corpus: missing", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()


class IeeeDecimalContextTests(unittest.TestCase):
    def test_a_format_is_accepted(self) -> None:
        for args in (
            (7, "half_even", -95, 96, 1, "b"),
            (34, "floor", -6143, 6144, 1, "b"),
            (5, "half_up", -9, 10, 1, "b"),
        ):
            corpus_common.check_ieee_decimal_context(*args)

    def test_what_no_format_has_is_rejected(self) -> None:
        for args in (
            (7, "half_even", -96, 96, 1, "b"),  # emin is not 1 - emax
            (7, "half_even", -95, 96, 0, "b"),  # no clamp
            (7, "half_even", -95, 96, 1, "a"),  # tininess after rounding
            (7, "half_down", -95, 96, 1, "b"),  # not a rounding-direction attribute
            (7, "up", -95, 96, 1, "b"),
            (7, "05up", -95, 96, 1, "b"),
            (0, "half_even", -95, 96, 1, "b"),
            (7, "half_even", 1, 0, 1, "b"),  # emax below 1
        ):
            with self.assertRaises(ValueError, msg=str(args)):
                corpus_common.check_ieee_decimal_context(*args)
