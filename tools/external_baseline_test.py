import random
import unittest
from dataclasses import asdict

import external_baseline as eb
import external_stats as stats


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

    def test_reference_blocks_become_pairs_and_raw_samples_use_the_case_lines_only(self) -> None:
        collected = eb.Collected()

        def line(variant: str, block: int, us: float, null_first: bool) -> dict[str, object]:
            return {"type": "observation", "case": "binary/add/53", "variant": variant, "null_first": null_first,
                    "phase": "confirmatory", "block": block, "iterations": 1000, "ops_per_iteration": 8,
                    "elapsed_us": us}  # fmt: skip

        events = [
            {"type": "calibration", "case": "binary/add/53", "variant": "null", "iterations": 9},
            {"type": "calibration", "case": "binary/add/53", "variant": "case", "iterations": 7},
            line("case", 0, 40.0, False), line("null", 0, 8.0, False),
            line("case", 1, 48.0, True), line("null", 1, 16.0, True),
            {"type": "observation", "case": "binary/add/53", "variant": "case", "null_first": False,
             "phase": "exploratory", "block": 0, "iterations": 1000, "ops_per_iteration": 8, "elapsed_us": 1.0},
        ]  # fmt: skip
        eb.add_reference_events(collected, 2, events)
        self.assertEqual(collected.reference, {"binary/add/53": {2: [5.0, 6.0]}})
        self.assertEqual(collected.reference_iterations, {"binary/add/53": 7})
        self.assertEqual(
            collected.reference_pairs,
            {"binary/add/53": {2: [stats.Pair(5.0, 1.0, False), stats.Pair(6.0, 2.0, True)]}},
        )

    def test_floating_blocks_become_pairs_in_line_order(self) -> None:
        collected = eb.Collected()

        def line(implementation: str, block_id: int, us: float, phase: str = "confirmatory") -> dict[str, object]:
            return {"type": "observation", "case": "external/binary/add", "scale": "53bit", "implementation": implementation,
                    "phase": phase, "block_id": block_id, "iterations": 100, "elapsed_us": us, "valid": True}  # fmt: skip

        events = [
            line("floating", 3, 3.2), line("null", 3, 0.8),  # the case ran first
            line("null", 4, 0.8), line("floating", 4, 4.0),  # the null ran first
            line("floating", 0, 9.0, "exploratory"), line("null", 0, 9.0, "exploratory"),
        ]  # fmt: skip
        eb.add_floating_events(collected, 1, events)
        self.assertEqual(collected.floating, {"binary/add/53": {1: [400.0, 500.0]}})
        self.assertEqual(
            collected.floating_pairs,
            {"binary/add/53": {1: [stats.Pair(400.0, 100.0, False), stats.Pair(500.0, 100.0, True)]}},
        )

    def test_invalid_floating_observation_is_an_error(self) -> None:
        event = {"type": "observation", "case": "external/binary/add", "scale": "53bit",
                 "phase": "confirmatory", "iterations": 1, "elapsed_us": 1.0, "valid": False}  # fmt: skip
        with self.assertRaises(ValueError):
            eb.add_floating_events(eb.Collected(), 0, [event])

    def test_parse_jsonl_with_and_without_marker(self) -> None:
        text = 'noise\nMAREMARK_JSONL={"a": 1}\nEXTBENCH_FAILED=0\n'
        self.assertEqual(eb.parse_jsonl(text, eb.EVENT_MARKER), [{"a": 1}])
        self.assertEqual(eb.parse_jsonl('{"b": 2}\n\n'), [{"b": 2}])

    @staticmethod
    def fill(collected: eb.Collected, case: str, floating: tuple[float, float], reference: tuple[float, float],
             rounds: int = 2, blocks: int = 4) -> None:  # fmt: skip
        """Constant pairs `(case ns, null ns)` on both sides, the null running first in every other block."""
        for side, (case_ns, null_ns), samples, pairs in (
            ("floating", floating, collected.floating, collected.floating_pairs),
            ("reference", reference, collected.reference, collected.reference_pairs),
        ):
            for round_index in range(rounds):
                block = [stats.Pair(case_ns, null_ns, j % 2 == 1) for j in range(blocks)]
                pairs.setdefault(case, {})[round_index] = block
                samples.setdefault(case, {})[round_index] = [pair.case_ns for pair in block]
        collected.floating_iterations[case] = 11
        collected.reference_iterations[case] = 22

    PROTOCOL = eb.Protocol(1, 1.0, 1.0, 1, 10, 10.0, 1, 4, 2, 100)

    def test_end_to_end_reduction_and_table(self) -> None:
        collected = eb.Collected()
        self.fill(collected, "binary/add/53", floating=(209.0, 9.0), reference=(10.0, 1.0))
        self.fill(collected, "binary/sqrt/53", floating=(100.0, 10.0), reference=(50.0, 5.0))
        results = eb.reduce_results(collected, self.PROTOCOL, 1)
        self.assertEqual([r.case for r in results], ["binary/add/53", "binary/sqrt/53"])
        add, sqrt = results
        self.assertEqual(add.ratio_raw.ratio, 20.9)
        self.assertEqual(add.ratio_net.ratio, 200.0 / 9.0)
        self.assertEqual(sqrt.ratio_raw.ratio, 2.0)
        self.assertEqual(sqrt.ratio_net.ratio, 2.0)
        self.assertEqual((add.status, sqrt.status), (stats.NOT_MET, stats.MET))
        self.assertEqual(add.floating.net.net_ns, 200.0)
        self.assertEqual(add.reference.null.median_ns, 1.0)
        self.assertEqual((add.floating.raw.iterations, add.reference.raw.iterations), (11, 22))
        text = eb.render_markdown(results)
        self.assertIn("1 of 2 cases meet the target", text)
        self.assertIn("Net ratio floating / MPFR", text)
        self.assertIn("| add | 22.22 [22.22, 22.22] |", text)
        self.assertIn("| sqrt | 2.00 [2.00, 2.00] met |", text)  # net table
        self.assertIn("| sqrt | 2.00 [2.00, 2.00] |", text)  # raw table
        self.assertIn("Null time per operation", text)

    def test_a_case_without_pairs_is_an_error(self) -> None:
        collected = eb.Collected()
        collected.floating["binary/add/53"] = {0: [1.0]}
        collected.reference["binary/add/53"] = {0: [1.0]}
        with self.assertRaises(ValueError):
            eb.reduce_results(collected, self.PROTOCOL, 1)

    def test_unresolved_case_shows_its_raw_verdict_and_is_never_met(self) -> None:
        collected = eb.Collected()
        # the reference net is zero: its case blocks cost what its null blocks cost
        self.fill(collected, "binary/add/53", floating=(40.0, 9.0), reference=(1.0, 1.0))
        (result,) = eb.reduce_results(collected, self.PROTOCOL, 1)
        self.assertEqual((result.status, result.reason), (stats.UNRESOLVED, stats.REASON_REFERENCE_ZERO))
        self.assertEqual(result.raw_status, stats.NOT_MET)
        self.assertEqual(eb.net_cell(result), "unresolved, raw 40.00 not met")
        self.assertFalse(result.order)
        text = eb.render_markdown([result])
        self.assertIn("0 of 1 cases meet the target", text)
        self.assertIn("1 are unresolved", text)
        self.assertIn("`binary/add/53` (reference net not above zero)", text)

    def test_flags_and_borderline_marks_are_shown(self) -> None:
        collected = eb.Collected()
        self.fill(collected, "binary/add/53", floating=(40.0, 9.0), reference=(11.0, 1.0))
        (result,) = eb.reduce_results(collected, self.PROTOCOL, 1)
        flagged = eb.CaseResult(**{**asdict(result), "drift": True, "order": True,
                                   "reference": result.reference, "floating": result.floating,
                                   "ratio_raw": result.ratio_raw, "ratio_net": result.ratio_net})  # fmt: skip
        self.assertTrue(eb.net_cell(flagged).endswith(" d o"))

    def test_number_formatting(self) -> None:
        self.assertEqual(eb.format_ns(12.34), "12.3 ns")
        self.assertEqual(eb.format_ns(12340.0), "12.3 us")
        self.assertEqual(eb.format_ns(12.34e6), "12.3 ms")
        self.assertEqual(eb.format_ratio(3.14159), "3.14")
        self.assertEqual(eb.format_ratio(1234.5), "1234")


class ComparisonTests(unittest.TestCase):
    @staticmethod
    def summary(ratios: dict[str, tuple[float, float, float]]) -> dict[str, object]:
        return {
            "schema": eb.SCHEMA_V1,
            "cases": [{"case": c, "ratio": {"ratio": r, "ci_low": lo, "ci_high": hi}} for c, (r, lo, hi) in ratios.items()],
        }

    @staticmethod
    def summary_v2(
        net: dict[str, tuple[float, float, float]], raw: dict[str, tuple[float, float, float]], unresolved: tuple[str, ...] = ()
    ) -> dict[str, object]:
        def entry(case: str) -> dict[str, object]:
            return {
                "case": case,
                "status": stats.UNRESOLVED if case in unresolved else stats.NOT_MET,
                "ratio_net": {"ratio": net[case][0], "ci_low": net[case][1], "ci_high": net[case][2]},
                "ratio_raw": {"ratio": raw[case][0], "ci_low": raw[case][1], "ci_high": raw[case][2]},
            }

        return {"schema": eb.SCHEMA, "protocol": {"floating_configuration": "native"}, "cases": [entry(c) for c in net]}

    def test_verdicts_follow_interval_overlap(self) -> None:
        old = self.summary({"a": (10.0, 9.0, 11.0), "b": (10.0, 9.0, 11.0), "c": (10.0, 9.0, 11.0), "d": (1.0, 1.0, 1.0)})
        new = self.summary({"a": (15.0, 14.0, 16.0), "b": (5.0, 4.0, 6.0), "c": (10.5, 9.8, 11.5), "e": (1.0, 1.0, 1.0)})
        changes = {c.case: c for c in eb.compare_summaries(old, new)}
        self.assertEqual(set(changes), {"a", "b", "c"})
        self.assertEqual(changes["a"].verdict, "slower")
        self.assertEqual(changes["b"].verdict, "faster")
        self.assertEqual(changes["c"].verdict, "same")
        self.assertAlmostEqual(changes["a"].change_pct, 50.0)
        self.assertIn("| `a` | 10.00 | 15.00 | +50.0% | slower | raw |", eb.render_changes(list(changes.values())))

    def test_two_v2_summaries_compare_their_net_ratios_unless_a_case_is_unresolved(self) -> None:
        net_old = {"a": (8.0, 7.5, 8.5), "b": (8.0, 7.5, 8.5)}
        net_new = {"a": (4.0, 3.5, 4.5), "b": (4.0, 3.5, 4.5)}
        raw_old = {"a": (9.0, 8.5, 9.5), "b": (9.0, 8.5, 9.5)}
        raw_new = {"a": (8.9, 8.4, 9.4), "b": (8.9, 8.4, 9.4)}
        old = self.summary_v2(net_old, raw_old)
        new = self.summary_v2(net_new, raw_new, unresolved=("b",))
        changes = {c.case: c for c in eb.compare_summaries(old, new)}
        self.assertEqual((changes["a"].basis, changes["a"].verdict), ("net", "faster"))
        self.assertEqual((changes["b"].basis, changes["b"].verdict), ("raw", "same"))  # one side unresolved: raw on both

    def test_a_v1_against_a_v2_summary_compares_raw_ratios(self) -> None:
        old = self.summary({"a": (9.0, 8.5, 9.5)})
        new = self.summary_v2({"a": (4.0, 3.5, 4.5)}, {"a": (9.2, 8.7, 9.7)})
        (change,) = eb.compare_summaries(old, new)
        self.assertEqual((change.basis, change.verdict, change.new), ("raw", "same", 9.2))

    def test_the_configuration_of_a_summary(self) -> None:
        self.assertEqual(eb.summary_configuration({"schema": eb.SCHEMA_V1}), "native")
        self.assertEqual(eb.summary_configuration({"schema": eb.SCHEMA, "protocol": {"floating_configuration": "portable"}}), "portable")


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
    def publish(self, version: str | None, configuration: str = "native") -> tuple[list[str], str]:
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
            document = {"schema": eb.SCHEMA, "protocol": {"floating_configuration": configuration}, "cases": []}
            (out / "results.json").write_text(json.dumps(document), encoding="utf-8")
            (out / "results.md").write_text("# results\n", encoding="utf-8")
            (out / "samples.json").write_text('{"schema": "x"}\n', encoding="utf-8")
            (root / "library").mkdir()
            (root / "library" / "moon.mod").write_text('name = "x"\nversion = "9.9.9"\n', encoding="utf-8")
            page = root / "doc" / "manual" / "performance" / "bench" / "external.md"
            page.parent.mkdir(parents=True)
            start, end = eb.page_markers(configuration)
            page.write_text(f"before\n{start}\nold tables\n{end}\nafter\n", encoding="utf-8")
            with (
                patch.object(eb, "SUMMARY_DIR", root / "summaries"),
                patch.object(eb, "REPO_ROOT", root),
                contextlib.redirect_stdout(io.StringIO()),
            ):
                eb.command_publish(argparse.Namespace(out=out, version=version))
            return sorted(path.name for path in (root / "summaries").iterdir()), page.read_text(encoding="utf-8")

    def test_the_names_follow_the_explicit_version_and_the_configuration(self) -> None:
        names, _ = self.publish("0.12.0", "portable")
        self.assertEqual(names, ["samples-0.12.0-portable.json.gz", "summary-0.12.0-portable.json", "summary-portable.md"])

    def test_the_summary_name_defaults_to_the_manifest_version(self) -> None:
        names, _ = self.publish(None)  # the temporary repository declares version 9.9.9
        self.assertEqual(names, ["samples-9.9.9-native.json.gz", "summary-9.9.9-native.json", "summary-native.md"])

    def test_publish_replaces_the_generated_tables_of_the_page(self) -> None:
        _, page = self.publish("0.12.0")
        self.assertEqual(page, "before\n<!-- external-baseline:native:start -->\n\n# results\n\n<!-- external-baseline:native:end -->\nafter\n")

    def test_the_stored_baseline_is_the_published_release_summary(self) -> None:
        self.assertEqual(eb.STORED_SUMMARY.name, "summary-0.11.0.json")
        self.assertTrue(eb.STORED_SUMMARY.is_file())

    def test_page_markers_and_configuration_names(self) -> None:
        self.assertEqual(eb.page_markers("native"), ("<!-- external-baseline:native:start -->", "<!-- external-baseline:native:end -->"))
        for bad in ("", "Native", "native build", "-x"):
            with self.assertRaises(ValueError):
                eb.valid_configuration(bad)
        with self.assertRaises(ValueError):
            eb.replace_page_tables("no markers", "native", "t")
        with self.assertRaises(ValueError):
            start, end = eb.page_markers("native")
            eb.replace_page_tables(f"{start}{end}{start}{end}", "native", "t")

    def test_moon_environment_arguments(self) -> None:
        self.assertEqual(eb.parse_environment(["A=1", "B=x=y", "C="]), {"A": "1", "B": "x=y", "C": ""})
        for bad in (["A"], ["=1"], ["A=1", "A=2"]):
            with self.assertRaises(ValueError):
                eb.parse_environment(bad)


class SamplesTests(unittest.TestCase):
    def collected(self) -> eb.Collected:
        collected = eb.Collected()
        ReductionTests.fill(collected, "binary/add/53", floating=(40.0, 9.0), reference=(5.0, 0.5), rounds=3, blocks=5)
        ReductionTests.fill(collected, "decimal_gda/mul/16", floating=(70.0, 9.0), reference=(20.0, 0.5), rounds=3, blocks=5)
        return collected

    def test_samples_round_trip(self) -> None:
        import json

        collected = self.collected()
        document = json.loads(json.dumps(eb.samples_document(collected)))
        loaded = eb.load_samples(document)
        self.assertEqual(loaded.floating_pairs, collected.floating_pairs)
        self.assertEqual(loaded.reference_pairs, collected.reference_pairs)
        self.assertEqual(loaded.floating, collected.floating)
        self.assertEqual((loaded.floating_iterations, loaded.reference_iterations), (collected.floating_iterations, collected.reference_iterations))
        with self.assertRaises(ValueError):
            eb.load_samples({"schema": "other"})

    def test_a_summary_is_recomputed_exactly_from_its_samples(self) -> None:
        import json

        protocol = eb.Protocol(1, 1.0, 1.0, 1, 10, 10.0, 1, 5, 3, 100)
        collected = self.collected()
        summary = eb.summary_document(eb.reduce_results(collected, protocol, 7), {"order_seed": 7}, protocol, "portable")
        samples = json.loads(json.dumps(eb.samples_document(collected)))
        summary = json.loads(json.dumps(summary))
        recomputed = [json.loads(json.dumps(asdict(r))) for r in eb.recompute(samples, summary)]
        self.assertEqual(recomputed, summary["cases"])
        self.assertEqual(summary["protocol"]["floating_configuration"], "portable")
        self.assertEqual(summary["protocol"]["method"], stats.METHOD_VERSION)
        self.assertEqual(summary["protocol"]["width_bound"], 1.25)
        self.assertEqual(summary["protocol"]["pairs_per_round"], 5)
        self.assertEqual(summary["schema"], "external-baseline-v2")

    def test_gzip_output_is_deterministic(self) -> None:
        import tempfile
        from pathlib import Path

        with tempfile.TemporaryDirectory() as directory:
            first, second = Path(directory) / "a.gz", Path(directory) / "b.gz"
            eb.write_gzip(first, "same text\n")
            eb.write_gzip(second, "same text\n")
            self.assertEqual(first.read_bytes(), second.read_bytes())


class QuickCheckTests(unittest.TestCase):
    def test_stored_medians_read_a_published_summary(self) -> None:
        summary = {"schema": eb.SCHEMA_V1, "cases": [
            {"case": "binary/add/53", "reference": {"median_ns": 4.0}, "floating": {"median_ns": 100.0}},
            {"case": "decimal_gda/ln/16", "reference": {"median_ns": 10000.0}, "floating": {"median_ns": 200000.0}},
        ]}  # fmt: skip
        self.assertEqual(
            eb.stored_medians(summary),
            {"binary/add/53": (4.0, 100.0), "decimal_gda/ln/16": (10000.0, 200000.0)},
        )

    def test_stored_medians_read_a_v2_summary(self) -> None:
        summary = {"schema": eb.SCHEMA, "cases": [
            {"case": "binary/add/53", "reference": {"raw": {"median_ns": 4.0}}, "floating": {"raw": {"median_ns": 100.0}}},
        ]}  # fmt: skip
        self.assertEqual(eb.stored_medians(summary), {"binary/add/53": (4.0, 100.0)})

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


if __name__ == "__main__":
    unittest.main()
