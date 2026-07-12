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
    archive_path,
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
