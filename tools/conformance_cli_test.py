import unittest
from unittest.mock import patch

import conformance_cli


class ConformanceCliTests(unittest.TestCase):
    def test_cli_build_uses_release_optimizations(self) -> None:
        command = conformance_cli.build_command()
        self.assertIn("--release", command)
        self.assertEqual(command[-1], "tooling/src/cli")

    def test_backend_artifacts_are_named_and_isolated(self) -> None:
        gda = conformance_cli.executable_path("gda")
        itl = conformance_cli.executable_path("itl")
        self.assertEqual(gda.name, "gda-conformance.exe")
        self.assertEqual(itl.name, "itl-conformance.exe")
        self.assertNotEqual(gda.parent, itl.parent)

    def test_backends_share_one_build_directory(self) -> None:
        seen = []

        def fake_run(command, cwd, env, text, capture_output):
            seen.append(env["CODEX_MOON_TARGET_DIR"])
            raise RuntimeError("stop after recording the target dir")

        with patch.object(conformance_cli.subprocess, "run", side_effect=fake_run):
            for backend in conformance_cli.BACKENDS:
                with self.assertRaisesRegex(RuntimeError, "stop after"):
                    conformance_cli.build_backend(backend)
        self.assertEqual(set(seen), {str(conformance_cli.SHARED_TARGET_DIR)})

    def test_unknown_backend_is_rejected(self) -> None:
        with self.assertRaisesRegex(ValueError, "unknown CLI backend"):
            conformance_cli.executable_path("unknown")


if __name__ == "__main__":
    unittest.main()
