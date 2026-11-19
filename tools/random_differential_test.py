import json
import tempfile
import unittest
from pathlib import Path

import random_differential as tool


class CaseIdTests(unittest.TestCase):
    def test_binary_and_decimal_ids_parse(self) -> None:
        self.assertEqual(tool.parse_case_id("20261118.add.42"), ("binary", 20261118, "add", 42))
        self.assertEqual(
            tool.parse_case_id("d7.squareroot.5"),
            ("decimal_gda", 7, "decimal_gda-squareroot", 5),
        )

    def test_decimal_elementary_ids_parse(self) -> None:
        self.assertEqual(tool.parse_case_id("m20261118.exp.42"), ("decimal", 20261118, "decimal-exp", 42))
        self.assertEqual(
            tool.expand_ids(["m1.atan2.3..m1.atan2.4"]),
            [("decimal", 1, "decimal-atan2", 3), ("decimal", 1, "decimal-atan2", 4)],
        )
        with self.assertRaises(tool.ToolError):
            tool.parse_case_id("m1.nope.3")

    def test_decimal_elementary_families_are_opt_in(self) -> None:
        self.assertTrue(all(tool.is_decm(f) for f in tool.DECM_FAMILIES))
        self.assertFalse(any(tool.is_decm(f) for f in tool.DEFAULT_FAMILIES))
        self.assertTrue(all(tool.uses_mpfr_rows(f) for f in tool.DECM_FAMILIES))
        self.assertIn("decimal-pow", tool.ALL_FAMILIES)

    def test_deprecated_family_prefixes_are_aliases(self) -> None:
        self.assertEqual(tool.canonical_family("dec-add"), "decimal_gda-add")
        self.assertEqual(tool.canonical_family("dec-powerwide"), "decimal_gda-powerwide")
        self.assertEqual(tool.canonical_family("decm-exp"), "decimal-exp")
        self.assertEqual(tool.canonical_family("decimal_gda-add"), "decimal_gda-add")
        self.assertEqual(tool.canonical_family("decimal-exp"), "decimal-exp")
        self.assertEqual(tool.canonical_family("add"), "add")
        args = tool.build_parser().parse_args(["plan", "--family", "dec-add", "--family", "decm-exp"])
        self.assertEqual(args.family, ["decimal_gda-add", "decimal-exp"])

    def test_unknown_families_are_rejected(self) -> None:
        with self.assertRaises(tool.ToolError):
            tool.parse_case_id("1.nope.3")
        with self.assertRaises(tool.ToolError):
            tool.parse_case_id("d1.sub.3")

    def test_ranges_expand_in_order(self) -> None:
        cases = tool.expand_ids(["1.mul.3..1.mul.5", "d2.add.9"])
        self.assertEqual(
            cases,
            [
                ("binary", 1, "mul", 3),
                ("binary", 1, "mul", 4),
                ("binary", 1, "mul", 5),
                ("decimal_gda", 2, "decimal_gda-add", 9),
            ],
        )

    def test_the_families_do_not_collide(self) -> None:
        self.assertEqual(len(set(tool.ALL_FAMILIES)), len(tool.ALL_FAMILIES))
        self.assertTrue(all(tool.is_binary(f) for f in tool.BINARY_FAMILIES))
        self.assertFalse(any(tool.is_binary(f) for f in tool.DECIMAL_FAMILIES))


class CommandTests(unittest.TestCase):
    def test_the_harness_command_records_the_replay_route(self) -> None:
        command = tool.harness_command("native", Path("/x/differential.exe"), Path("rows.txt"), 20261118, 500, "r1")
        self.assertEqual(command[0], "/x/differential.exe")
        self.assertIn("--rows", command)
        self.assertEqual(command[command.index("--batch") + 1], "500")
        self.assertEqual(command[command.index("--target") + 1], "native")
        self.assertEqual(command[command.index("--replay-command") + 1], "python3")
        self.assertIn("tools/random_differential.py", command)

    def test_wasm_and_js_use_a_launcher(self) -> None:
        wasm = tool.harness_command("wasm", Path("/x/d.wasm"), Path("r"), 1, 10, "r")
        self.assertEqual(wasm[1:3], ["/x/d.wasm", "--"])
        js = tool.harness_command("js", Path("/x/d.js"), Path("r"), 1, 10, "r")
        self.assertEqual(js[:2], ["node", "/x/d.js"])

    def test_large_seeds_fit_the_harness_option(self) -> None:
        command = tool.harness_command("native", Path("d"), Path("r"), 2**40 + 5, 10, "r")
        self.assertLess(int(command[command.index("--seed") + 1]), 2**31)


class CountingTests(unittest.TestCase):
    def test_operations_are_counted_per_row(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            binary = Path(directory) / "b.rows"
            binary.write_text(
                "# header\n1.elem.0 sin n 24 - - - 0x1p0 - - 0 0x1p0 x\n1.elem.1 cos n 24 - - - 0x1p0 - - 0 0x1p0 x\n"
                "1.elem.2 sin n 24 - - - 0x1p0 - - 0 0x1p0 x\n",
                encoding="utf-8",
            )
            counts = tool.operation_counts("elem", binary)
            self.assertEqual(dict(counts), {"sin": 2, "cos": 1})
            decimal = Path(directory) / "d.rows"
            decimal.write_text(
                "-- c\nversion: 2.62\nprecision: 3\nd1.add.0 add 1 2 -> 3\nd1.add.1 add 1 2 -> 3\n",
                encoding="utf-8",
            )
            self.assertEqual(dict(tool.operation_counts("decimal_gda-add", decimal)), {"add": 2})


class SummaryTests(unittest.TestCase):
    def shard(self, target: str, family: str, ops: dict[str, int], invalid: int = 0) -> tool.ShardResult:
        return tool.ShardResult(
            family, target, 1, 0, sum(ops.values()), ops, 3, invalid, ["x..y"] * invalid, [], 1.0, ""
        )

    def test_totals_add_up_per_target_family_and_operation(self) -> None:
        summary = tool.summarize(
            [
                self.shard("native", "elem", {"sin": 5, "cos": 3}),
                self.shard("native", "elem", {"sin": 2}),
                self.shard("wasm", "add", {"add": 7}),
            ],
            1,
            ["native", "wasm"],
        )
        self.assertEqual(summary["totalCases"], {"native": 10, "wasm": 7})
        self.assertEqual(summary["casesPerOperation"]["native"]["elem"], {"cos": 3, "sin": 7})
        self.assertEqual(summary["batches"], {"validated": 9, "invalid": 0})
        self.assertEqual(summary["failedBatches"], [])
        json.dumps(summary)

    def test_failed_batches_are_listed(self) -> None:
        summary = tool.summarize([self.shard("native", "add", {"add": 4}, invalid=1)], 1, ["native"])
        self.assertEqual(summary["failedBatches"], [{"target": "native", "family": "add", "batch": "x..y"}])


class PlanTests(unittest.TestCase):
    def test_the_plan_counts_shards(self) -> None:
        arguments = tool.build_parser().parse_args(["plan", "--count", "250000", "--shard", "100000", "--family", "add"])
        self.assertEqual(arguments.count, 250000)
        self.assertEqual(arguments.family, ["add"])


class CliLauncherTests(unittest.TestCase):
    def test_javascript_cli_is_imported_so_arguments_start_after_node(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "some dir" / "cli.js"
            command = tool.cli_launcher("js", path)
            self.assertEqual(command[:3], ["node", "--input-type=module", "-e"])
            self.assertEqual(command[3], "import " + json.dumps(path.resolve().as_uri()))
            self.assertIn("some%20dir", command[3])
        self.assertEqual(command[-1], "--")

    def test_other_targets_keep_the_shared_launcher(self) -> None:
        path = Path("/tmp/cli.wasm")
        for target in ("native", "wasm", "wasm-gc"):
            self.assertEqual(tool.cli_launcher(target, path), tool.launcher(target, path))


if __name__ == "__main__":
    unittest.main()
