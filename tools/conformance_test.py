import unittest
from contextlib import redirect_stderr, redirect_stdout
from io import StringIO
from pathlib import Path
from unittest.mock import patch

import conformance


class ConformanceEntryPointTests(unittest.TestCase):
    def test_build_uses_named_cli_backends(self) -> None:
        with patch.object(conformance, "build_backend") as build:
            build.side_effect = lambda backend: Path(
                f"/repo/_build/conformance/{backend}/native/release/build/{backend}-conformance.exe"
            )
            with redirect_stdout(StringIO()):
                self.assertEqual(
                    conformance.main(["build", "--backend", "binary"]),
                    0,
                )
        self.assertEqual(
            [call.args[0] for call in build.call_args_list],
            ["testfloat", "mpfr"],
        )

    def test_smoke_dispatches_to_selected_runner(self) -> None:
        backend = conformance.Backend(
            build_targets=(),
            runner=lambda args: 7,
            fetcher=lambda args: 0,
        )
        with patch.dict(conformance.BACKENDS, {"binary": backend}):
            self.assertEqual(
                conformance.main(["smoke", "--backend", "binary", "--json"]),
                7,
            )

    def test_fetch_dispatches_to_selected_fetcher(self) -> None:
        received: list[str] = []

        def fetch(arguments: list[str] | None) -> int:
            received.extend(arguments or [])
            return 0

        backend = conformance.Backend(
            build_targets=(),
            runner=lambda args: 0,
            fetcher=fetch,
        )
        with patch.dict(conformance.BACKENDS, {"decimal": backend}):
            self.assertEqual(
                conformance.main(["fetch", "--backend=decimal", "official"]),
                0,
            )
        self.assertEqual(received, ["official"])

    def test_backend_is_required(self) -> None:
        with redirect_stderr(StringIO()):
            self.assertEqual(conformance.main(["run"]), 2)


if __name__ == "__main__":
    unittest.main()
