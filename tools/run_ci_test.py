import unittest

import run_ci


class RunCiTests(unittest.TestCase):
    def test_type_scope_has_one_authoritative_suite(self) -> None:
        stages = run_ci.stages_for("decimal", 3)
        self.assertEqual(len(stages), 1)
        self.assertIn("--backend", stages[0].command)
        self.assertIn("3", stages[0].command)

    def test_bin_scope_maps_to_binary_backend(self) -> None:
        command = run_ci.stages_for("bin", 2)[0].command
        backend_index = command.index("--backend") + 1
        self.assertEqual(command[backend_index], "binary")

    def test_all_scope_covers_repository_and_three_suites(self) -> None:
        stages = run_ci.stages_for("all", 5)
        self.assertEqual(len(stages), 8)
        self.assertEqual(
            [stage.name.split(" · ")[0] for stage in stages],
            ["FORMAT", "DOCS", "CHECK", "INFO", "TEST", "DECIMAL", "BINARY", "INTERVAL"],
        )

    def test_quick_scope_runs_native_tools_and_three_smokes(self) -> None:
        stages = run_ci.stages_for("quick", 4)
        self.assertEqual(
            [stage.name.split(" · ")[0] for stage in stages],
            ["FORMAT", "DOCS", "CHECK", "TEST", "TEST", "SMOKE", "SMOKE", "SMOKE"],
        )
        commands = [stage.command for stage in stages]
        self.assertIn("native", commands[3])
        self.assertIn("--deny-warn", commands[2])
        self.assertIn("unittest", commands[4])
        self.assertEqual(
            [command[command.index("--backend") + 1] for command in commands[5:]],
            ["decimal", "binary", "interval"],
        )
        self.assertIn("--strict-supported", commands[-1])

    def test_binary_gate_locks_level_and_both_tininess_modes(self) -> None:
        command = run_ci.stages_for("bin", 2)[0].command
        self.assertEqual(command[command.index("--level") + 1], "1")
        self.assertEqual(
            [command[index + 1] for index, value in enumerate(command) if value == "--tininess"],
            ["after", "before"],
        )

    def test_interval_gate_uses_declared_strict_phases(self) -> None:
        command = run_ci.stages_for("interval", 2)[0].command
        self.assertIn("--strict-supported", command)
        self.assertIn("elementary-core", command)
        self.assertIn("trigonometric", command)
        self.assertIn("general-power", command)
        self.assertNotIn("reverse", command)


if __name__ == "__main__":
    unittest.main()
