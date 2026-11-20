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
        side = st.side_net(constant_pairs(40.0, 9.0), "c", 200)
        self.assertEqual((side.net_ns, side.ci_low_ns, side.ci_high_ns), (31.0, 31.0, 31.0))
        self.assertEqual(side.pairs, 84)
        self.assertEqual(side.drift_pct, 0.0)
        self.assertEqual(side.order_pct, 0.0)

    def test_interval_brackets_the_net_and_narrows_with_less_noise(self) -> None:
        loud = st.side_net(noisy_pairs(1, 100.0, 10.0, 0.05), "a", 400)
        quiet = st.side_net(noisy_pairs(1, 100.0, 10.0, 0.005), "a", 400)
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


class RatioTests(unittest.TestCase):
    def test_ratio_replicates_and_zero_reference(self) -> None:
        self.assertEqual(st.ratio_replicates([6.0, 9.0, 4.0], [2.0, 3.0, 0.0]), [3.0, 3.0, math.inf])
        self.assertEqual(st.ratio_replicates([1.0], [-1.0]), [math.inf])
        with self.assertRaises(ValueError):
            st.ratio_replicates([1.0], [1.0, 2.0])

    def test_interval_of_a_known_ratio(self) -> None:
        floating = st.side_net(noisy_pairs(2, 310.0, 10.0, 0.01), "f", 400)
        reference = st.side_net(noisy_pairs(3, 105.0, 5.0, 0.01), "r", 400)
        verdict = st.judge(floating, reference, raw_ci_high=3.2)
        self.assertLess(verdict.ci_low, 3.0)
        self.assertGreater(verdict.ci_high, 3.0)
        self.assertAlmostEqual(verdict.ratio, 3.0, delta=0.1)


def side(net: float, low: float, high: float, replicates: tuple[float, ...], drift: float = 0.0, order: float = 0.0) -> st.SideNet:
    return st.SideNet(net, low, high, 84, drift, order, replicates)


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


class FlagTests(unittest.TestCase):
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
