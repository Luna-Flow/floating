"""Statistics of the external baseline: the net ratio of floating to a reference library.

Pure functions only: no I/O, no clock, no process control.  The method is fixed
in advance (see doc/manual/design/bench/external.md):

* A *pair* is a case block and a null block (the same loop without the library
  call) measured back to back, both in ns per operation.  Its *difference* is
  `case - null`.
* The *net time* of a side is the median of the differences of all its pairs.
* Its interval is a two-level percentile bootstrap (resample the rounds, then
  the pairs of each chosen round, pairs kept intact).
* The interval of the net ratio resamples the two sides independently.
* A case *meets* the target when the upper end of the ratio interval is at most
  the target, unless it is *unresolved* (reference net not above zero, floating
  net not above zero, or an interval wider than `width_bound`); an unresolved
  case is judged on the raw ratio and is never counted as met.
* Nothing is removed from the data after the fact: only the exploratory blocks,
  by position, which the caller never passes in.
"""

from __future__ import annotations

import math
import random
from dataclasses import dataclass
from typing import Sequence

# ---------------------------------------------------------------------------
# Method parameters (fixed; a change is a new method version)
# ---------------------------------------------------------------------------

METHOD_VERSION = "net-ratio-v1"
TARGET_RATIO = 3.0
WIDTH_BOUND = 1.25  # ratio interval high / low above this: unresolved
DRIFT_PCT = 5.0  # spread of the per-round null medians
ORDER_PCT = 5.0  # difference of the mean net between null-first and case-first pairs
WARM_PCT = 5.0  # difference of the median net of the first and the last third of the pairs of every round
LEVEL = 0.95


@dataclass(frozen=True)
class Rules:
    """The parameters of the verdict; the defaults are the published method."""

    target: float = TARGET_RATIO
    limit: float | None = None  # the tolerated bound, at least `target`; `None` means the target (no tolerated band)
    width_bound: float = WIDTH_BOUND
    drift_pct: float = DRIFT_PCT
    order_pct: float = ORDER_PCT
    warm_pct: float = WARM_PCT
    level: float = LEVEL

    @property
    def tolerated_limit(self) -> float:
        return self.target if self.limit is None else self.limit

    def __post_init__(self) -> None:
        if self.limit is not None and self.limit < self.target:
            raise ValueError("the limit must be at least the target")


# ---------------------------------------------------------------------------
# Elementary statistics
# ---------------------------------------------------------------------------


def median(values: Sequence[float]) -> float:
    ordered = sorted(values)
    n = len(ordered)
    if n == 0:
        raise ValueError("median of no values")
    mid = n // 2
    return ordered[mid] if n % 2 else (ordered[mid - 1] + ordered[mid]) / 2.0


def percentile(sorted_values: Sequence[float], fraction: float) -> float:
    """Linear-interpolated percentile of a sorted sequence; infinite ends are kept infinite."""
    if not sorted_values:
        raise ValueError("percentile of no values")
    position = fraction * (len(sorted_values) - 1)
    low = math.floor(position)
    high = math.ceil(position)
    weight = position - low
    if weight == 0.0 or sorted_values[low] == sorted_values[high]:
        return sorted_values[low]
    if math.isinf(sorted_values[low]) or math.isinf(sorted_values[high]):
        return sorted_values[high] if sorted_values[high] > 0 else sorted_values[low]
    return sorted_values[low] * (1.0 - weight) + sorted_values[high] * weight


def mean(values: Sequence[float]) -> float:
    if not values:
        raise ValueError("mean of no values")
    return sum(values) / len(values)


# ---------------------------------------------------------------------------
# Seeds: one stream per run, case, side and purpose
# ---------------------------------------------------------------------------

SIDES = ("floating", "reference", "both")  # "both" is for a draw that belongs to neither side alone
PURPOSES = ("net", "raw", "null", "raw-ratio")


def derive_seed(run_seed: int, configuration: str, case_id: str, side: str, purpose: str) -> str:
    """The bootstrap seed of one draw: a pure function of the run seed, the configuration, the case, the side and the purpose.

    Two sides, two cases, two purposes or two configurations never share a
    stream, so the replicates of the floating and the reference side are
    independent even when their data are identical, and so are the replicates
    of the same case measured in two configurations (the ratio between two
    configurations divides replicate `b` of one by replicate `b` of the other
    only to build a distribution, not to pair them). The same arguments always
    give the same seed, so a summary is reproducible.
    """
    if side not in SIDES:
        raise ValueError(f"unknown side {side!r}")
    if purpose not in PURPOSES:
        raise ValueError(f"unknown purpose {purpose!r}")
    if not configuration:
        raise ValueError("a bootstrap seed needs the configuration")
    return f"external-baseline-bootstrap:{run_seed}:{configuration}:{case_id}:{side}:{purpose}"


# ---------------------------------------------------------------------------
# Pairs
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class Pair:
    """One pair of blocks, both in ns per operation."""

    case_ns: float
    null_ns: float
    null_first: bool  # whether the null block ran before the case block

    @property
    def net_ns(self) -> float:
        return self.case_ns - self.null_ns


# round index -> pairs of that round, in measurement order
Pairs = dict[int, list[Pair]]


def differences(pairs: Pairs) -> list[float]:
    return [pair.net_ns for key in sorted(pairs) for pair in pairs[key]]


def net_time(pairs: Pairs) -> float:
    """The median of the differences of all pairs."""
    return median(differences(pairs))


def _draw(rng: random.Random, pairs: Pairs) -> list[float]:
    """One two-level bootstrap draw of differences: rounds, then pairs within each chosen round."""
    keys = sorted(pairs)
    drawn: list[float] = []
    for key in rng.choices(keys, k=len(keys)):
        block = pairs[key]
        drawn.extend(pair.net_ns for pair in rng.choices(block, k=len(block)))
    return drawn


def net_replicates(pairs: Pairs, seed: str, resamples: int) -> list[float]:
    """`resamples` bootstrap replicates of the net time, in draw order (not sorted)."""
    if not pairs:
        raise ValueError("no pairs")
    rng = random.Random(seed)
    return [median(_draw(rng, pairs)) for _ in range(resamples)]


def interval(replicates: Sequence[float], level: float = LEVEL) -> tuple[float, float]:
    """Percentile interval of replicates."""
    ordered = sorted(replicates)
    tail = (1.0 - level) / 2.0
    return percentile(ordered, tail), percentile(ordered, 1.0 - tail)


def ratio_replicates(
    floating: Sequence[float], reference: Sequence[float]
) -> list[float]:
    """Element-wise ratios of two independent replicate lists; a reference net at or below zero gives +inf."""
    if len(floating) != len(reference):
        raise ValueError("replicate lists differ in length")
    return [f / r if r > 0.0 else math.inf for f, r in zip(floating, reference)]


# ---------------------------------------------------------------------------
# Flags from the null blocks
# ---------------------------------------------------------------------------


def drift_pct(pairs: Pairs) -> float:
    """Largest relative deviation (percent) of a round's null median from the median of those medians.

    The null loop scales with the clock, so a changed machine state between
    rounds (frequency scaling, thermal limits, other load) shifts it.
    """
    round_medians = [median([pair.null_ns for pair in pairs[key]]) for key in sorted(pairs)]
    centre = median(round_medians)
    if centre <= 0.0:
        return math.inf
    return 100.0 * max(abs(m / centre - 1.0) for m in round_medians)


def order_pct(pairs: Pairs) -> float:
    """Difference (percent of the net time) of the mean net between null-first and case-first pairs."""
    first = [pair.net_ns for key in sorted(pairs) for pair in pairs[key] if pair.null_first]
    second = [pair.net_ns for key in sorted(pairs) for pair in pairs[key] if not pair.null_first]
    if not first or not second:
        return 0.0
    centre = net_time(pairs)
    gap = abs(mean(first) - mean(second))
    if centre == 0.0:
        return 0.0 if gap == 0.0 else math.inf
    return 100.0 * gap / abs(centre)


def warm_pct(pairs: Pairs) -> float:
    """Difference (percent of the net time) of the median net of the first third and of the last third of the pairs of every round.

    On a runtime that compiles while it runs, the early pairs of a round are
    slower than the late ones until the code is warm; the first and the last
    third are pooled over the rounds so that the medians rest on many pairs.
    """
    first: list[float] = []
    last: list[float] = []
    for key in sorted(pairs):
        block = [pair.net_ns for pair in pairs[key]]
        third = len(block) // 3
        if third == 0:
            continue
        first.extend(block[:third])
        last.extend(block[-third:])
    if not first or not last:
        return 0.0
    centre = net_time(pairs)
    gap = abs(median(first) - median(last))
    if centre == 0.0:
        return 0.0 if gap == 0.0 else math.inf
    return 100.0 * gap / abs(centre)


# ---------------------------------------------------------------------------
# One side
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class SideNet:
    net_ns: float
    ci_low_ns: float
    ci_high_ns: float
    pairs: int
    drift_pct: float
    order_pct: float
    warm_pct: float
    replicates: tuple[float, ...]  # not stored in summaries; the ratio interval needs them


def side_net(
    pairs: Pairs, run_seed: int, configuration: str, case_id: str, side: str, resamples: int, level: float = LEVEL
) -> SideNet:
    """The net time of one side of one case; the bootstrap seed is derived, never passed in."""
    if side == "both":
        raise ValueError("a side's net time is drawn for floating or reference")
    replicates = net_replicates(pairs, derive_seed(run_seed, configuration, case_id, side, "net"), resamples)
    low, high = interval(replicates, level)
    return SideNet(
        net_ns=net_time(pairs),
        ci_low_ns=low,
        ci_high_ns=high,
        pairs=sum(len(block) for block in pairs.values()),
        drift_pct=drift_pct(pairs),
        order_pct=order_pct(pairs),
        warm_pct=warm_pct(pairs),
        replicates=tuple(replicates),
    )


# ---------------------------------------------------------------------------
# The verdict
# ---------------------------------------------------------------------------

MET = "met"  # the upper end of the interval is at most the target
TOLERATED = "tolerated"  # above the target and at most the limit (only where the limit is above the target)
NOT_MET = "not_met"
UNRESOLVED = "unresolved"
NOT_APPLICABLE = "not_applicable"  # the criterion is not defined for the configuration

REASON_REFERENCE_ZERO = "reference net not above zero"
REASON_FLOATING_ZERO = "floating net not above zero"
REASON_WIDE = "interval too wide"


@dataclass(frozen=True)
class Verdict:
    ratio: float  # net_F / net_R (inf when the reference net is not positive)
    ci_low: float
    ci_high: float
    status: str  # MET, TOLERATED, NOT_MET, UNRESOLVED or NOT_APPLICABLE
    reason: str  # why unresolved; empty otherwise
    borderline: bool  # resolved, and the interval contains the target or the limit
    raw_status: str  # MET, TOLERATED or NOT_MET by the raw ratio's upper end; the verdict of an unresolved case
    drift: bool  # either side's null drifted between rounds
    order: bool  # either side shows an order effect
    warm: bool  # either side is still warming up between the first and the last third of its pairs


def classify(ci_high: float, rules: Rules) -> str:
    """`met` at most the target, `tolerated` at most the limit, `not_met` above."""
    if ci_high <= rules.target:
        return MET
    return TOLERATED if ci_high <= rules.tolerated_limit else NOT_MET


def judge(
    floating: SideNet,
    reference: SideNet,
    raw_ci_high: float,
    rules: Rules = Rules(),
    criterion_applies: bool = True,
) -> Verdict:
    """Classify one case.

    `raw_ci_high` is the upper end of the interval of the raw median ratio;
    it decides an unresolved case, which is reported as `unresolved` and never
    as `met`. Where the criterion is not defined (`criterion_applies` false) the
    ratio and its interval are computed as usual and the status is
    `not_applicable`, with no raw verdict and no borderline mark.
    """
    ratios = ratio_replicates(floating.replicates, reference.replicates)
    low, high = interval(ratios, rules.level)
    point = floating.net_ns / reference.net_ns if reference.net_ns > 0.0 else math.inf
    raw_status = classify(raw_ci_high, rules)
    reference_tail = interval(reference.replicates, rules.level)[0]
    reason = ""
    if reference.net_ns <= 0.0 or reference_tail <= 0.0:
        reason = REASON_REFERENCE_ZERO
    elif floating.net_ns <= 0.0:
        reason = REASON_FLOATING_ZERO
    elif math.isinf(high) or low <= 0.0 or high / low > rules.width_bound:
        reason = REASON_WIDE
    drift = floating.drift_pct > rules.drift_pct or reference.drift_pct > rules.drift_pct
    order = floating.order_pct > rules.order_pct or reference.order_pct > rules.order_pct
    warm = floating.warm_pct > rules.warm_pct or reference.warm_pct > rules.warm_pct
    if not criterion_applies:
        return Verdict(point, low, high, NOT_APPLICABLE, "", False, NOT_APPLICABLE, drift, order, warm)
    if reason:
        return Verdict(point, low, high, UNRESOLVED, reason, False, raw_status, drift, order, warm)
    status = classify(high, rules)
    borderline = any(low <= bound < high for bound in (rules.target, rules.tolerated_limit))
    return Verdict(point, low, high, status, "", borderline, raw_status, drift, order, warm)


@dataclass(frozen=True)
class Between:
    """The ratio of the net times of the same case in two configurations: no verdict, no criterion."""

    ratio: float
    ci_low: float
    ci_high: float


def ratio_between(numerator: SideNet, denominator: SideNet, level: float = LEVEL) -> Between:
    """Net time of `numerator` over net time of `denominator`, with the interval of independent resampling.

    Both come from `side_net` with their own configuration in the seed, so the
    two replicate lists are independent streams. A denominator net at or below
    zero gives an infinite ratio (the interval then reaches infinity).
    """
    replicates = ratio_replicates(numerator.replicates, denominator.replicates)
    low, high = interval(replicates, level)
    point = numerator.net_ns / denominator.net_ns if denominator.net_ns > 0.0 else math.inf
    return Between(point, low, high)
