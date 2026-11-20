import random
import unittest

import external_baseline as eb


class GenerationTests(unittest.TestCase):
    def test_generation_is_deterministic(self) -> None:
        cases = eb.benchmark_cases([53, 128], [16], ["add", "sqrt"])
        first = eb.generate_rows(7, 4, cases)
        second = eb.generate_rows(7, 4, cases)
        self.assertEqual(first, second)
        self.assertNotEqual(first, eb.generate_rows(8, 4, cases))

    def test_streams_are_independent_per_case(self) -> None:
        both = eb.generate_rows(7, 4, [eb.Case("binary", "add", 53), eb.Case("binary", "mul", 53)])
        alone = eb.generate_rows(7, 4, [eb.Case("binary", "mul", 53)])
        self.assertEqual([r for r in both if r.op == "mul"], alone)

    def test_binary_operands_are_exact_at_the_requested_precision(self) -> None:
        for row in eb.generate_rows(1, 16, [eb.Case("binary", "mul", 128)]):
            for text in (row.a, row.b):
                assert text is not None
                body = text.lstrip("-")
                self.assertTrue(body.startswith("0x"))
                mantissa_text, exponent_text = body[2:].split("p")
                mantissa = int(mantissa_text, 16)
                self.assertEqual(mantissa.bit_length(), 128)
                exponent = int(exponent_text)
                leading = exponent + 127
                self.assertTrue(-8 <= leading <= 8)

    def test_unary_and_positive_domains(self) -> None:
        sqrt_rows = eb.generate_rows(1, 32, [eb.Case("binary", "sqrt", 53)])
        self.assertTrue(all(r.b is None and not r.a.startswith("-") for r in sqrt_rows))
        ln_rows = eb.generate_rows(1, 32, [eb.Case("decimal_gda", "ln", 16)])
        self.assertTrue(all(r.b is None and not r.a.startswith("-") for r in ln_rows))

    def test_decimal_operands_have_exact_digits(self) -> None:
        for row in eb.generate_rows(1, 16, [eb.Case("decimal_gda", "div", 34)]):
            for text in (row.a, row.b):
                assert text is not None
                coefficient, exponent = text.lstrip("-").split("E")
                self.assertEqual(len(coefficient), 34)
                self.assertNotEqual(coefficient[0], "0")
                self.assertTrue(-2 <= int(exponent) + 33 <= 2)

    def test_file_format_lists_one_row_per_operand_set(self) -> None:
        cases = [eb.Case("binary", "add", 53), eb.Case("binary", "sqrt", 53)]
        text = eb.format_inputs(eb.generate_rows(3, 2, cases), 3, 2)
        lines = text.splitlines()
        self.assertTrue(lines[0].startswith("# external-baseline inputs v1 seed=3"))
        self.assertEqual(len(lines), 1 + 4)
        self.assertEqual(len(lines[1].split(" ")), 6)  # binary operation: two operands
        self.assertEqual(len(lines[3].split(" ")), 5)  # unary operation: one operand

    def test_cases_cover_the_specified_matrix(self) -> None:
        cases = eb.benchmark_cases()
        binary = {c for c in cases if c.kind == "binary"}
        decimal = {c for c in cases if c.kind == "decimal_gda"}
        self.assertEqual(len(binary), 7 * 5)
        self.assertEqual(len(decimal), 6 * 4)
        self.assertNotIn("sin", {c.op for c in decimal})
        self.assertEqual(eb.Case.parse("binary/add/53").id, "binary/add/53")


class PlanTests(unittest.TestCase):
    def test_first_side_alternates_and_orders_are_seeded(self) -> None:
        ids = [f"binary/add/{n}" for n in range(6)]
        plans = eb.plan_rounds(5, 6, ids)
        firsts = [p.first for p in plans]
        self.assertEqual(firsts.count("reference"), 3)
        self.assertEqual(firsts.count("floating"), 3)
        for earlier, later in zip(firsts, firsts[1:]):
            self.assertNotEqual(earlier, later)
        self.assertEqual(plans, eb.plan_rounds(5, 6, ids))
        for plan in plans:
            self.assertCountEqual(plan.case_order, ids)
        self.assertGreater(len({p.case_order for p in plans}), 1)


class StatisticsTests(unittest.TestCase):
    def test_median_and_percentile(self) -> None:
        self.assertEqual(eb.median([3.0, 1.0, 2.0]), 2.0)
        self.assertEqual(eb.median([4.0, 1.0, 2.0, 3.0]), 2.5)
        self.assertEqual(eb.percentile([0.0, 10.0], 0.25), 2.5)
        with self.assertRaises(ValueError):
            eb.median([])

    def test_mad_pct(self) -> None:
        self.assertEqual(eb.mad_pct([10.0, 10.0, 10.0]), 0.0)
        self.assertAlmostEqual(eb.mad_pct([9.0, 10.0, 11.0]), 10.0)

    @staticmethod
    def noisy_samples(seed: int, centre: float, rounds: int = 5, blocks: int = 20) -> eb.Samples:
        rng = random.Random(seed)
        return {r: [centre * (1.0 + rng.gauss(0.0, 0.01)) for _ in range(blocks)] for r in range(rounds)}

    def test_median_interval_brackets_the_median_and_is_seeded(self) -> None:
        samples = self.noisy_samples(1, 100.0)
        low, high = eb.bootstrap_median_ci(samples, "s", 300)
        self.assertLess(low, eb.median(eb.pooled(samples)))
        self.assertGreater(high, eb.median(eb.pooled(samples)))
        self.assertLess((high - low) / 100.0, 0.02)
        self.assertEqual((low, high), eb.bootstrap_median_ci(samples, "s", 300))

    def test_ratio_interval_recovers_a_known_ratio(self) -> None:
        slow = self.noisy_samples(2, 300.0)
        fast = self.noisy_samples(3, 100.0)
        low, high = eb.bootstrap_ratio_ci(slow, fast, "r", 400)
        self.assertLess(low, 3.0)
        self.assertGreater(high, 3.0)
        self.assertLess(high - low, 0.2)

    def test_ratio_pairs_rounds_so_shared_drift_cancels(self) -> None:
        # Both sides drift together by +-20% between rounds; the ratio stays 2.
        drift = [1.0, 1.2, 0.8, 1.1, 0.9]
        slow = {r: [200.0 * d] * 10 for r, d in enumerate(drift)}
        fast = {r: [100.0 * d] * 10 for r, d in enumerate(drift)}
        low, high = eb.bootstrap_ratio_ci(slow, fast, "d", 200)
        self.assertAlmostEqual(low, 2.0)
        self.assertAlmostEqual(high, 2.0)
        with self.assertRaises(ValueError):
            eb.bootstrap_ratio_ci({0: [1.0]}, {1: [1.0]}, "x", 10)

    def test_summary_and_noise_flag(self) -> None:
        quiet = eb.summarize(self.noisy_samples(4, 100.0), "q", 200, 10)
        self.assertFalse(eb.is_noisy(quiet))
        self.assertEqual(quiet.rounds, 5)
        self.assertEqual(quiet.blocks, 100)
        drifting = {r: [100.0 * (1.0 + 0.2 * r)] * 10 for r in range(5)}
        self.assertTrue(eb.is_noisy(eb.summarize(drifting, "d", 200, 10)))


class ReductionTests(unittest.TestCase):
    def test_reference_lines_become_ns_per_operation(self) -> None:
        collected = eb.Collected()
        events = [
            {"type": "calibration", "case": "binary/add/53", "iterations": 100},
            {"type": "observation", "case": "binary/add/53", "phase": "exploratory",
             "iterations": 100, "ops_per_iteration": 8, "elapsed_us": 5000.0},
            {"type": "observation", "case": "binary/add/53", "phase": "confirmatory",
             "iterations": 100, "ops_per_iteration": 8, "elapsed_us": 8000.0},
        ]  # fmt: skip
        eb.add_reference_events(collected, 0, events)
        self.assertEqual(collected.reference, {"binary/add/53": {0: [10000.0]}})  # 8000 us / 800 ops
        self.assertEqual(collected.reference_iterations, {"binary/add/53": 100})

    def test_floating_observation_is_already_per_iteration(self) -> None:
        collected = eb.Collected()
        events = [
            {"type": "observation", "case": "external/binary/add", "scale": "53bit",
             "phase": "confirmatory", "iterations": 2000, "elapsed_us": 1.6, "valid": True},
            {"type": "observation", "case": "external/decimal_gda/ln", "scale": "16digit",
             "phase": "exploratory", "iterations": 5, "elapsed_us": 9.0, "valid": True},
            {"type": "validation", "case": "external/binary/add", "scale": "53bit", "status": "valid"},
            {"type": "validation", "case": "external/binary/add", "scale": "53bit", "status": "invalid"},
            {"type": "summary"},
        ]  # fmt: skip
        eb.add_floating_events(collected, 3, events)
        self.assertEqual(collected.floating, {"binary/add/53": {3: [200.0]}})  # 1.6 us / 8 operations
        self.assertEqual(collected.floating_validation, {"binary/add/53": (1, 2)})

    def test_invalid_floating_observation_is_an_error(self) -> None:
        event = {"type": "observation", "case": "external/binary/add", "scale": "53bit",
                 "phase": "confirmatory", "iterations": 1, "elapsed_us": 1.0, "valid": False}  # fmt: skip
        with self.assertRaises(ValueError):
            eb.add_floating_events(eb.Collected(), 0, [event])

    def test_parse_jsonl_with_and_without_marker(self) -> None:
        text = 'noise\nMAREMARK_JSONL={"a": 1}\nEXTBENCH_FAILED=0\n'
        self.assertEqual(eb.parse_jsonl(text, eb.EVENT_MARKER), [{"a": 1}])
        self.assertEqual(eb.parse_jsonl('{"b": 2}\n\n'), [{"b": 2}])

    def test_end_to_end_reduction_and_table(self) -> None:
        collected = eb.Collected()
        protocol = eb.Protocol(1, 1.0, 1.0, 1, 10, 10.0, 1, 4, 2, 100)
        for round_index in range(2):
            for case, reference_ns, floating_ns in (("binary/add/53", 10.0, 200.0), ("binary/sqrt/53", 50.0, 100.0)):
                collected.reference.setdefault(case, {})[round_index] = [reference_ns] * 4
                collected.floating.setdefault(case, {})[round_index] = [floating_ns] * 4
        collected.floating.setdefault("binary/null/53", {})[0] = [3.0, 3.0]
        results = eb.reduce_results(collected, protocol, 1)
        self.assertEqual([r.case for r in results], ["binary/add/53", "binary/sqrt/53"])
        self.assertEqual(results[0].ratio.ratio, 20.0)
        self.assertEqual(results[1].ratio.ratio, 2.0)
        text = eb.render_markdown(results)
        self.assertIn("Ratio floating / MPFR", text)
        self.assertIn("| add | 20.00 [20.00, 20.00] |", text)
        self.assertIn("| sqrt | 2.00 [2.00, 2.00] |", text)
        self.assertEqual(eb.overhead_results(collected, protocol, 1)[0]["case"], "binary/null/53")

    def test_number_formatting(self) -> None:
        self.assertEqual(eb.format_ns(12.34), "12.3 ns")
        self.assertEqual(eb.format_ns(12340.0), "12.3 us")
        self.assertEqual(eb.format_ns(12.34e6), "12.3 ms")
        self.assertEqual(eb.format_ratio(3.14159), "3.14")
        self.assertEqual(eb.format_ratio(1234.5), "1234")


class ComparisonTests(unittest.TestCase):
    @staticmethod
    def summary(ratios: dict[str, tuple[float, float, float]]) -> dict[str, object]:
        return {"cases": [{"case": c, "ratio": {"ratio": r, "ci_low": lo, "ci_high": hi}} for c, (r, lo, hi) in ratios.items()]}

    def test_verdicts_follow_interval_overlap(self) -> None:
        old = self.summary({"a": (10.0, 9.0, 11.0), "b": (10.0, 9.0, 11.0), "c": (10.0, 9.0, 11.0), "d": (1.0, 1.0, 1.0)})
        new = self.summary({"a": (15.0, 14.0, 16.0), "b": (5.0, 4.0, 6.0), "c": (10.5, 9.8, 11.5), "e": (1.0, 1.0, 1.0)})
        changes = {c.case: c for c in eb.compare_summaries(old, new)}
        self.assertEqual(set(changes), {"a", "b", "c"})
        self.assertEqual(changes["a"].verdict, "slower")
        self.assertEqual(changes["b"].verdict, "faster")
        self.assertEqual(changes["c"].verdict, "same")
        self.assertAlmostEqual(changes["a"].change_pct, 50.0)
        self.assertIn("| `a` | 10.00 | 15.00 | +50.0% | slower |", eb.render_changes(list(changes.values())))


class QuietGateTests(unittest.TestCase):
    def test_foreign_cpu_excludes_own_process_tree(self) -> None:
        rows = [(10, 1, 1.0), (11, 10, 99.0), (12, 11, 98.0), (20, 1, 40.0), (21, 20, 30.0)]
        self.assertEqual(eb.foreign_cpu_pct(rows, 10), 1.0 + 40.0 + 30.0 - 1.0)

    def test_sampling_runs(self) -> None:
        self.assertGreaterEqual(eb.sample_foreign_cpu(), 0.0)


class ProtocolTests(unittest.TestCase):
    def test_both_sides_receive_the_same_numbers(self) -> None:
        protocol = eb.PRESETS["standard"]
        args = eb.c_protocol_args(protocol)
        env = eb.moon_protocol_env(protocol)
        self.assertEqual(float(args[args.index("--target-batch-us") + 1]), float(env["EXTBENCH_TARGET_BATCH_US"]))
        self.assertEqual(int(args[args.index("--confirmatory") + 1]), int(env["EXTBENCH_CONFIRMATORY"]))
        self.assertEqual(int(args[args.index("--max-batch-iterations") + 1]), int(env["EXTBENCH_MAX_BATCH"]))

    def test_moon_environment_drops_the_stale_shadow(self) -> None:
        import os

        old = os.environ["PATH"]
        os.environ["PATH"] = "/tmp/qed-moon-latest/bin" + os.pathsep + old
        try:
            self.assertNotIn("qed-moon-latest", eb.moon_environment()["PATH"])
        finally:
            os.environ["PATH"] = old


class PublishNameTests(unittest.TestCase):
    def publish(self, version: str | None) -> list[str]:
        import argparse
        import contextlib
        import io
        import json
        import tempfile
        from pathlib import Path
        from unittest.mock import patch

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            out = root / "out"
            out.mkdir()
            (out / "results.json").write_text(json.dumps({"cases": []}), encoding="utf-8")
            (out / "results.md").write_text("# results\n", encoding="utf-8")
            with patch.object(eb, "SUMMARY_DIR", root / "summaries"), contextlib.redirect_stdout(io.StringIO()):
                eb.command_publish(argparse.Namespace(out=out, version=version))
            return sorted(path.name for path in (root / "summaries").iterdir())

    def test_the_summary_name_follows_the_explicit_version_not_the_manifest(self) -> None:
        self.assertEqual(self.publish("0.10.2"), ["summary-0.10.2.json", "summary.md"])

    def test_the_summary_name_defaults_to_the_manifest_version(self) -> None:
        self.assertEqual(self.publish(None), [f"summary-{eb.module_version()}.json", "summary.md"])

    def test_the_stored_baseline_is_the_published_release_summary(self) -> None:
        self.assertEqual(eb.STORED_SUMMARY.name, "summary-0.11.0.json")
        self.assertTrue(eb.STORED_SUMMARY.is_file())


class QuickCheckTests(unittest.TestCase):
    def test_stored_medians_read_a_published_summary(self) -> None:
        summary = {"cases": [
            {"case": "binary/add/53", "reference": {"median_ns": 4.0}, "floating": {"median_ns": 100.0}},
            {"case": "decimal_gda/ln/16", "reference": {"median_ns": 10000.0}, "floating": {"median_ns": 200000.0}},
        ]}  # fmt: skip
        self.assertEqual(
            eb.stored_medians(summary),
            {"binary/add/53": (4.0, 100.0), "decimal_gda/ln/16": (10000.0, 200000.0)},
        )

    def test_rows_flag_cells_above_the_target_and_order_by_case(self) -> None:
        stored = {"binary/add/53": (4.0, 100.0), "binary/exp/53": (500.0, 30000.0), "binary/add/128": (6.0, 120.0)}
        floating = {"binary/exp/53": 2500.0, "binary/add/53": 50.0, "binary/add/128": 30.0, "binary/ln/53": 1.0}
        rows = eb.quick_rows(floating, stored, 10.0)
        self.assertEqual([row[0] for row in rows], ["binary/add/53", "binary/add/128", "binary/exp/53"])
        by_case = {row[0]: row for row in rows}
        self.assertEqual(by_case["binary/add/53"][3:], ["12.5", "25.0", ">10x"])
        self.assertEqual(by_case["binary/add/128"][3:], ["5.0", "20.0", "ok"])
        self.assertEqual(by_case["binary/exp/53"][3:], ["5.0", "60.0", "ok"])

    def test_render_aligns_columns(self) -> None:
        text = eb.render_quick(eb.quick_rows({"binary/add/53": 50.0}, {"binary/add/53": (4.0, 100.0)}, 10.0))
        lines = text.splitlines()
        self.assertEqual(len(lines), 2)
        self.assertTrue(lines[0].startswith("case"))
        self.assertIn("binary/add/53", lines[1])

    def test_overhead_cases_are_left_out_of_the_medians(self) -> None:
        collected = eb.Collected()
        collected.floating["binary/null/53"] = {0: [9.0]}
        collected.floating["binary/add/53"] = {0: [100.0, 120.0, 110.0]}
        self.assertEqual(eb.floating_medians(collected), {"binary/add/53": 110.0})


if __name__ == "__main__":
    unittest.main()
