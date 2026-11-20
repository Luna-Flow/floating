import math
import random
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import external_stats as st  # noqa: E402


def constant_pairs(case: float, null: float, rounds: int = 7, blocks: int = 12) -> st.Pairs:
    return {
        r: [st.Pair(case, null, j % 2 == 0) for j in range(blocks)] for r in range(rounds)
    }


def noisy_pairs(seed: int, case: float, null: float, sd: float, rounds: int = 7, blocks: int = 12) -> st.Pairs:
    rng = random.Random(seed)
    return {
        r: [
            st.Pair(case * (1.0 + rng.gauss(0.0, sd)), null * (1.0 + rng.gauss(0.0, sd)), j % 2 == 0)
            for j in range(blocks)
        ]
        for r in range(rounds)
    }


SMALL: st.Pairs = {
    0: [st.Pair(10.0, 2.0, True), st.Pair(11.0, 2.0, False), st.Pair(12.0, 3.0, True)],
    1: [st.Pair(20.0, 4.0, False), st.Pair(22.0, 5.0, True), st.Pair(24.0, 5.0, False)],
}


class ElementaryTests(unittest.TestCase):
    def test_median_percentile_mean(self) -> None:
        self.assertEqual(st.median([3.0, 1.0, 2.0]), 2.0)
        self.assertEqual(st.median([4.0, 1.0, 2.0, 3.0]), 2.5)
        self.assertEqual(st.percentile([0.0, 10.0], 0.25), 2.5)
        self.assertEqual(st.mean([1.0, 2.0, 6.0]), 3.0)
        for empty in (st.median, st.mean):
            with self.assertRaises(ValueError):
                empty([])
        with self.assertRaises(ValueError):
            st.percentile([], 0.5)

    def test_percentile_keeps_infinite_ends(self) -> None:
        values = [1.0, 2.0, math.inf, math.inf]
        self.assertEqual(st.percentile(values, 0.0), 1.0)
        self.assertEqual(st.percentile(values, 1.0), math.inf)
        self.assertEqual(st.percentile(values, 0.9), math.inf)
        self.assertEqual(st.percentile([math.inf, math.inf], 0.5), math.inf)


class NetTimeTests(unittest.TestCase):
    def test_differences_and_net_time_on_fixed_input(self) -> None:
        self.assertEqual(st.differences(SMALL), [8.0, 9.0, 9.0, 16.0, 17.0, 19.0])
        self.assertEqual(st.net_time(SMALL), 12.5)

    def test_net_time_is_robust_to_one_slow_block(self) -> None:
        pairs = constant_pairs(40.0, 9.0)
        pairs[3][5] = st.Pair(4000.0, 9.0, False)
        self.assertEqual(st.net_time(pairs), 31.0)

    def test_replicates_are_seeded_and_pinned(self) -> None:
        self.assertEqual(st.net_replicates(SMALL, "t", 4), [18.0, 12.5, 8.5, 9.0])
        self.assertEqual(st.net_replicates(SMALL, "t", 4), st.net_replicates(SMALL, "t", 4))
        self.assertNotEqual(st.net_replicates(SMALL, "u", 50), st.net_replicates(SMALL, "t", 50))
        with self.assertRaises(ValueError):
            st.net_replicates({}, "t", 4)

    def test_constant_data_gives_a_degenerate_interval(self) -> None:
        side = st.side_net(constant_pairs(40.0, 9.0), 1, "native", "c", "floating", 200)
        self.assertEqual((side.net_ns, side.ci_low_ns, side.ci_high_ns), (31.0, 31.0, 31.0))
        self.assertEqual(side.pairs, 84)
        self.assertEqual(side.drift_pct, 0.0)
        self.assertEqual(side.order_pct, 0.0)

    def test_interval_brackets_the_net_and_narrows_with_less_noise(self) -> None:
        loud = st.side_net(noisy_pairs(1, 100.0, 10.0, 0.05), 1, "native", "a", "floating", 400)
        quiet = st.side_net(noisy_pairs(1, 100.0, 10.0, 0.005), 1, "native", "a", "floating", 400)
        for side in (loud, quiet):
            self.assertLess(side.ci_low_ns, side.net_ns)
            self.assertGreater(side.ci_high_ns, side.net_ns)
        self.assertLess(quiet.ci_high_ns - quiet.ci_low_ns, loud.ci_high_ns - loud.ci_low_ns)

    def test_pairing_cancels_a_drift_shared_by_the_two_blocks_of_a_pair(self) -> None:
        # Each round runs at its own clock speed; case and null scale together.
        speeds = [1.0, 1.3, 0.8, 1.1, 0.9, 1.2, 1.0]
        pairs = {r: [st.Pair(40.0 * s, 10.0 * s, j % 2 == 0) for j in range(12)] for r, s in enumerate(speeds)}
        self.assertAlmostEqual(st.net_time(pairs), 30.0 * 1.0)  # median round speed is 1.0
        self.assertGreater(st.drift_pct(pairs), 20.0)  # and the nulls show the drift


class SeedTests(unittest.TestCase):
    def test_derived_seeds_differ_by_run_configuration_case_side_and_purpose_and_reproduce(self) -> None:
        seed = st.derive_seed(1, "native", "binary/add/53", "floating", "net")
        self.assertEqual(seed, st.derive_seed(1, "native", "binary/add/53", "floating", "net"))
        variants = {
            st.derive_seed(2, "native", "binary/add/53", "floating", "net"),
            st.derive_seed(1, "wasm", "binary/add/53", "floating", "net"),
            st.derive_seed(1, "native", "binary/mul/53", "floating", "net"),
            st.derive_seed(1, "native", "binary/add/53", "reference", "net"),
            st.derive_seed(1, "native", "binary/add/53", "floating", "raw"),
            st.derive_seed(1, "native", "binary/add/53", "both", "raw-ratio"),
        }
        self.assertEqual(len(variants | {seed}), 7)
        for bad in (("native", "c", "left", "net"), ("native", "c", "floating", "other"), ("", "c", "floating", "net")):
            with self.assertRaises(ValueError):
                st.derive_seed(1, *bad)
        with self.assertRaises(ValueError):
            st.side_net(constant_pairs(2.0, 1.0), 1, "native", "c", "both", 10)

    def test_two_sides_with_identical_data_get_different_draws_and_one_side_reproduces(self) -> None:
        pairs = noisy_pairs(7, 100.0, 10.0, 0.05)
        floating = st.side_net(pairs, 5, "native", "case", "floating", 200)
        reference = st.side_net(pairs, 5, "native", "case", "reference", 200)
        again = st.side_net(pairs, 5, "native", "case", "floating", 200)
        self.assertEqual(floating.replicates, again.replicates)  # same run seed, configuration, case and side: the same draws
        self.assertNotEqual(floating.replicates, reference.replicates)  # same data, other side: other draws
        self.assertEqual(floating.net_ns, reference.net_ns)  # the point estimate is the same data's median
        self.assertLess(sum(a == b for a, b in zip(floating.replicates, reference.replicates)), 100)
        self.assertNotEqual(floating.replicates, st.side_net(pairs, 6, "native", "case", "floating", 200).replicates)

    def test_the_same_case_in_two_configurations_gets_different_draws(self) -> None:
        pairs = noisy_pairs(8, 100.0, 10.0, 0.05)
        native = st.side_net(pairs, 5, "native-portable", "case", "floating", 200)
        wasm = st.side_net(pairs, 5, "wasm", "case", "floating", 200)
        self.assertNotEqual(native.replicates, wasm.replicates)
        self.assertEqual(native.replicates, st.side_net(pairs, 5, "native-portable", "case", "floating", 200).replicates)


class BetweenTests(unittest.TestCase):
    def test_ratio_between_two_configurations_recovers_a_known_ratio_and_has_no_verdict(self) -> None:
        wasm = st.side_net(noisy_pairs(2, 130.0, 10.0, 0.01), 1, "wasm", "case", "floating", 400)
        portable = st.side_net(noisy_pairs(3, 50.0, 10.0, 0.01), 1, "native-portable", "case", "floating", 400)
        between = st.ratio_between(wasm, portable)
        self.assertAlmostEqual(between.ratio, 3.0, delta=0.05)
        self.assertLess(between.ci_low, between.ratio)
        self.assertGreater(between.ci_high, between.ratio)
        self.assertLess(between.ci_high - between.ci_low, 0.2)

    def test_a_denominator_at_or_below_zero_gives_an_infinite_ratio(self) -> None:
        zero = st.side_net(constant_pairs(5.0, 5.0), 1, "native-portable", "case", "floating", 50)
        positive = st.side_net(constant_pairs(40.0, 9.0), 1, "wasm", "case", "floating", 50)
        between = st.ratio_between(positive, zero)
        self.assertTrue(math.isinf(between.ratio) and math.isinf(between.ci_high))


class RatioTests(unittest.TestCase):
    def test_ratio_replicates_and_zero_reference(self) -> None:
        self.assertEqual(st.ratio_replicates([6.0, 9.0, 4.0], [2.0, 3.0, 0.0]), [3.0, 3.0, math.inf])
        self.assertEqual(st.ratio_replicates([1.0], [-1.0]), [math.inf])
        with self.assertRaises(ValueError):
            st.ratio_replicates([1.0], [1.0, 2.0])

    def test_interval_of_a_known_ratio(self) -> None:
        floating = st.side_net(noisy_pairs(2, 310.0, 10.0, 0.01), 1, "native", "x", "floating", 400)
        reference = st.side_net(noisy_pairs(3, 105.0, 5.0, 0.01), 1, "native", "x", "reference", 400)
        verdict = st.judge(floating, reference, raw_ci_high=3.2)
        self.assertLess(verdict.ci_low, 3.0)
        self.assertGreater(verdict.ci_high, 3.0)
        self.assertAlmostEqual(verdict.ratio, 3.0, delta=0.1)


def side(
    net: float, low: float, high: float, replicates: tuple[float, ...], drift: float = 0.0, order: float = 0.0, warm: float = 0.0
) -> st.SideNet:
    return st.SideNet(net, low, high, 84, drift, order, warm, replicates)


class VerdictTests(unittest.TestCase):
    """One row per outcome of the rule, on constructed replicates."""

    F = (30.0,) * 100
    R_EXACT = (10.0,) * 100  # ratio 3.0 exactly: upper end 3.0, which meets the target

    def test_met_when_the_upper_end_is_at_most_the_target(self) -> None:
        v = st.judge(side(30.0, 30.0, 30.0, self.F), side(10.0, 10.0, 10.0, self.R_EXACT), raw_ci_high=9.0)
        self.assertEqual((v.status, v.reason, v.borderline), (st.MET, "", False))
        self.assertEqual(v.raw_status, st.NOT_MET)
        self.assertEqual((v.ratio, v.ci_low, v.ci_high), (3.0, 3.0, 3.0))

    def test_not_met_above_the_target(self) -> None:
        v = st.judge(side(31.0, 31.0, 31.0, (31.0,) * 100), side(10.0, 10.0, 10.0, self.R_EXACT), raw_ci_high=1.0)
        self.assertEqual((v.status, v.borderline), (st.NOT_MET, False))
        self.assertEqual(v.raw_status, st.MET)

    def test_borderline_when_the_interval_contains_the_target(self) -> None:
        reference = tuple(9.5 + 0.01 * i for i in range(100))  # 9.5 .. 10.49: ratios about 2.86 .. 3.16
        v = st.judge(side(30.0, 30.0, 30.0, self.F), side(10.0, 9.5, 10.5, reference), raw_ci_high=3.5)
        self.assertLess(v.ci_low, 3.0)
        self.assertGreater(v.ci_high, 3.0)
        self.assertEqual((v.status, v.borderline), (st.NOT_MET, True))

    def test_unresolved_reference_net_not_above_zero(self) -> None:
        reference = (0.5,) * 90 + (-0.1,) * 10  # more than 2.5 percent at or below zero
        v = st.judge(side(30.0, 30.0, 30.0, self.F), side(0.4, -0.1, 0.5, reference), raw_ci_high=2.0)
        self.assertEqual((v.status, v.reason), (st.UNRESOLVED, st.REASON_REFERENCE_ZERO))
        self.assertEqual(v.raw_status, st.MET)  # the raw verdict stands, shown as met (raw)
        self.assertTrue(math.isinf(v.ci_high))

    def test_unresolved_reference_point_at_or_below_zero(self) -> None:
        v = st.judge(side(30.0, 30.0, 30.0, self.F), side(0.0, 0.0, 0.0, (0.0,) * 100), raw_ci_high=5.0)
        self.assertEqual((v.status, v.reason, v.raw_status), (st.UNRESOLVED, st.REASON_REFERENCE_ZERO, st.NOT_MET))
        self.assertTrue(math.isinf(v.ratio))

    def test_unresolved_floating_net_not_above_zero(self) -> None:
        v = st.judge(side(-1.0, -2.0, 0.0, (-1.0,) * 100), side(10.0, 10.0, 10.0, self.R_EXACT), raw_ci_high=4.0)
        self.assertEqual((v.status, v.reason), (st.UNRESOLVED, st.REASON_FLOATING_ZERO))

    def test_unresolved_when_the_interval_is_too_wide(self) -> None:
        reference = tuple(8.0 + 0.05 * i for i in range(100))  # 8 .. 12.95: ratio interval about 2.4 .. 3.7
        v = st.judge(side(30.0, 30.0, 30.0, self.F), side(10.0, 8.0, 13.0, reference), raw_ci_high=2.9)
        self.assertEqual((v.status, v.reason), (st.UNRESOLVED, st.REASON_WIDE))
        self.assertGreater(v.ci_high / v.ci_low, 1.25)
        self.assertEqual(v.raw_status, st.MET)

    def test_width_bound_is_a_rule_parameter(self) -> None:
        reference = tuple(8.0 + 0.05 * i for i in range(100))
        args = (side(30.0, 30.0, 30.0, self.F), side(10.0, 8.0, 13.0, reference))
        v = st.judge(*args, raw_ci_high=2.9, rules=st.Rules(width_bound=2.0))
        self.assertEqual(v.status, st.NOT_MET)

    def test_flags_follow_the_thresholds_and_never_change_the_status(self) -> None:
        base = st.judge(side(30.0, 30.0, 30.0, self.F), side(10.0, 10.0, 10.0, self.R_EXACT), raw_ci_high=9.0)
        flagged = st.judge(
            side(30.0, 30.0, 30.0, self.F, drift=6.0), side(10.0, 10.0, 10.0, self.R_EXACT, order=5.5), raw_ci_high=9.0
        )
        self.assertEqual((base.drift, base.order), (False, False))
        self.assertEqual((flagged.drift, flagged.order), (True, True))
        self.assertEqual(flagged.status, base.status)
        edge = st.judge(side(30.0, 30.0, 30.0, self.F, drift=5.0, order=5.0), side(10.0, 10.0, 10.0, self.R_EXACT), raw_ci_high=9.0)
        self.assertEqual((edge.drift, edge.order), (False, False))  # at the threshold is not above it


class CriterionTests(unittest.TestCase):
    F = (30.0,) * 100
    R = (10.0,) * 100

    def test_without_a_criterion_the_ratio_is_computed_and_the_status_is_not_applicable(self) -> None:
        v = st.judge(side(30.0, 30.0, 30.0, self.F), side(10.0, 10.0, 10.0, self.R), raw_ci_high=9.0, criterion_applies=False)
        self.assertEqual((v.status, v.reason, v.raw_status, v.borderline), (st.NOT_APPLICABLE,) * 1 + ("", st.NOT_APPLICABLE, False))
        self.assertEqual((v.ratio, v.ci_low, v.ci_high), (3.0, 3.0, 3.0))

    def test_without_a_criterion_an_unresolved_case_is_still_not_applicable(self) -> None:
        v = st.judge(side(30.0, 30.0, 30.0, self.F), side(0.0, 0.0, 0.0, (0.0,) * 100), raw_ci_high=9.0, criterion_applies=False)
        self.assertEqual((v.status, v.reason), (st.NOT_APPLICABLE, ""))
        self.assertTrue(math.isinf(v.ratio))

    def test_the_warm_flag_follows_its_threshold(self) -> None:
        for warm, flagged in ((5.0, False), (5.5, True)):
            v = st.judge(side(30.0, 30.0, 30.0, self.F, warm=warm), side(10.0, 10.0, 10.0, self.R), raw_ci_high=9.0)
            self.assertEqual(v.warm, flagged)
        v = st.judge(side(30.0, 30.0, 30.0, self.F), side(10.0, 10.0, 10.0, self.R, warm=9.0), raw_ci_high=9.0)
        self.assertTrue(v.warm)  # either side


class FlagTests(unittest.TestCase):
    def test_warm_pct_compares_the_first_and_the_last_third_of_every_round(self) -> None:
        cooling = {r: [st.Pair(30.0 + 6.0 * (2 - j // 4), 10.0, False) for j in range(12)] for r in range(3)}
        # nets 32 (first third), 26 (middle), 20 (last third): the median net is 26, the gap 12
        self.assertAlmostEqual(st.warm_pct(cooling), 100.0 * 12.0 / 26.0)
        self.assertEqual(st.warm_pct(constant_pairs(40.0, 9.0)), 0.0)
        self.assertEqual(st.warm_pct({0: [st.Pair(5.0, 1.0, True), st.Pair(6.0, 1.0, False)]}), 0.0)  # too few pairs for thirds

    def test_drift_pct_is_the_worst_round_against_the_median_round(self) -> None:
        pairs = {r: [st.Pair(10.0, n, True)] * 4 for r, n in enumerate([9.0, 10.0, 10.0, 10.0, 11.0])}
        self.assertAlmostEqual(st.drift_pct(pairs), 10.0)
        self.assertEqual(st.drift_pct(constant_pairs(10.0, 5.0)), 0.0)

    def test_order_pct_compares_null_first_with_case_first(self) -> None:
        pairs = {0: [st.Pair(12.0, 2.0, True), st.Pair(10.0, 2.0, False)] * 6}
        # net 10 when the null ran first, 8 otherwise; the median net is 9
        self.assertAlmostEqual(st.order_pct(pairs), 100.0 * 2.0 / 9.0)
        self.assertEqual(st.order_pct({0: [st.Pair(12.0, 2.0, True)] * 3}), 0.0)  # one order only: no effect to measure
        self.assertEqual(st.order_pct(constant_pairs(40.0, 9.0)), 0.0)
        zero = {0: [st.Pair(5.0, 5.0, True), st.Pair(5.0, 5.0, False)]}
        self.assertEqual(st.order_pct(zero), 0.0)  # a zero net with no order effect
        skewed = {0: [st.Pair(6.0, 5.0, True), st.Pair(4.0, 5.0, False), st.Pair(5.0, 5.0, False)]}
        self.assertEqual(st.order_pct(skewed), math.inf)  # a zero net with an order effect


if __name__ == "__main__":
    unittest.main()
