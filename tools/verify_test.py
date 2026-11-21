import unittest

import run_ci
import verify


class VerifyTests(unittest.TestCase):
    def test_the_conformance_run_of_the_backend_gets_the_option(self) -> None:
        command = ("python3", "tools/conformance.py", "run", "--backend", "binary", "--jobs", "3")
        self.assertEqual(verify.incremental_command(command, "binary"), (*command, "--incremental"))
        self.assertEqual(verify.incremental_command((*command, "--incremental"), "binary"), (*command, "--incremental"))

    def test_other_stages_and_backends_are_left_alone(self) -> None:
        other = ("python3", "tools/conformance.py", "run", "--backend", "interval")
        self.assertEqual(verify.incremental_command(other, "binary"), other)
        test = ("sh", "tools/run_moon_clean_exec.sh", "test")
        self.assertEqual(verify.incremental_command(test, "binary"), test)

    def test_the_binary_scope_has_exactly_one_incremental_stage(self) -> None:
        stages = verify.plan("binary", 3)
        incremental = [name for name, _, flag in stages if flag]
        self.assertEqual(incremental, ["BINARY: TestFloat + MPFR"])
        self.assertEqual(len(stages), len(run_ci.stages_for("binary", 3)))

    def test_a_scope_without_an_incremental_stage_is_refused(self) -> None:
        self.assertEqual(verify.run("elementary", 3, dry_run=True), 2)


if __name__ == "__main__":
    unittest.main()
