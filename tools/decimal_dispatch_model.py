"""Pure statistical model for Decimal algorithm dispatch calibration."""

from __future__ import annotations

import math
import random
import statistics
from dataclasses import dataclass
from typing import Iterable


@dataclass(frozen=True)
class DispatchObservation:
    size: int
    process_ratios: tuple[float, ...]


MIN_PROCESS_COUNT = 5
MIN_BOOTSTRAP_SAMPLES = 5000


def _validate_observations(
    observations: Iterable[DispatchObservation],
) -> list[DispatchObservation]:
    ordered = sorted(observations, key=lambda item: item.size)
    if len(ordered) < 2:
        raise ValueError("dispatch model requires at least two sizes")
    if any(item.size <= 0 for item in ordered):
        raise ValueError("dispatch sizes must be positive")
    if len({item.size for item in ordered}) != len(ordered):
        raise ValueError("dispatch sizes must be unique")
    process_count = len(ordered[0].process_ratios)
    if process_count < MIN_PROCESS_COUNT:
        raise ValueError(
            f"dispatch model requires at least {MIN_PROCESS_COUNT} independent processes"
        )
    for item in ordered:
        if len(item.process_ratios) != process_count:
            raise ValueError("every size must have the same process count")
        if any(not math.isfinite(value) or value <= 0 for value in item.process_ratios):
            raise ValueError("process ratios must be finite and positive")
    steps = {right.size - left.size for left, right in zip(ordered, ordered[1:])}
    if len(steps) != 1:
        raise ValueError("dispatch observations must use a regular size grid")
    return ordered


def median_absolute_deviation(values: Iterable[float]) -> float:
    samples = list(values)
    if not samples:
        raise ValueError("MAD requires at least one value")
    median = statistics.median(samples)
    return statistics.median(abs(value - median) for value in samples)


def isotonic_decreasing(values: list[float], weights: list[float]) -> list[float]:
    """Return the weighted least-squares non-increasing fit via PAVA."""
    if len(values) != len(weights) or not values:
        raise ValueError("isotonic inputs must have the same nonzero length")
    if any(not math.isfinite(value) for value in values):
        raise ValueError("isotonic values must be finite")
    if any(not math.isfinite(weight) or weight <= 0 for weight in weights):
        raise ValueError("isotonic weights must be finite and positive")
    blocks: list[list[float | int]] = []
    for index, (value, weight) in enumerate(zip(values, weights)):
        blocks.append([index, index, value * weight, weight])
        while len(blocks) >= 2:
            left = blocks[-2]
            right = blocks[-1]
            left_mean = float(left[2]) / float(left[3])
            right_mean = float(right[2]) / float(right[3])
            if left_mean >= right_mean:
                break
            blocks[-2:] = [
                [
                    int(left[0]),
                    int(right[1]),
                    float(left[2]) + float(right[2]),
                    float(left[3]) + float(right[3]),
                ]
            ]
    fitted = [0.0] * len(values)
    for start, end, weighted_sum, total_weight in blocks:
        mean = float(weighted_sum) / float(total_weight)
        for index in range(int(start), int(end) + 1):
            fitted[index] = mean
    return fitted


def one_sided_sign_p_value(wins: int, trials: int) -> float:
    if trials <= 0 or wins < 0 or wins > trials:
        raise ValueError("invalid sign-test counts")
    return sum(math.comb(trials, count) for count in range(wins, trials + 1)) / (
        2**trials
    )


def _nearest_rank(values: list[int], probability: float) -> int:
    if not values or probability < 0 or probability > 1:
        raise ValueError("invalid percentile request")
    ordered = sorted(values)
    rank = max(1, math.ceil(probability * len(ordered)))
    return ordered[rank - 1]


def _point_statistics(
    observations: list[DispatchObservation],
) -> tuple[list[float], list[float], list[dict[str, float | int | list[float]]]]:
    medians: list[float] = []
    weights: list[float] = []
    points: list[dict[str, float | int | list[float]]] = []
    for item in observations:
        logs = [math.log(value) for value in item.process_ratios]
        median_log = statistics.median(logs)
        log_mad = median_absolute_deviation(logs)
        robust_sigma = max(1.4826 * log_mad, 0.005)
        weight = len(logs) / (robust_sigma * robust_sigma)
        wins = sum(value < 1.0 for value in item.process_ratios)
        medians.append(median_log)
        weights.append(weight)
        points.append(
            {
                "size": item.size,
                "process_ratios": list(item.process_ratios),
                "median_ratio": math.exp(median_log),
                "log_mad": log_mad,
                "weight": weight,
                "wins": wins,
                "sign_p_value": one_sided_sign_p_value(wins, len(logs)),
            }
        )
    return medians, weights, points


def _threshold_from_fit(
    sizes: list[int], fitted_logs: list[float], target_log_ratio: float, sentinel: int
) -> int:
    for size, fitted in zip(sizes, fitted_logs):
        if fitted <= target_log_ratio:
            return size
    return sentinel


def fit_dispatch_model(
    observations: Iterable[DispatchObservation],
    *,
    margin: float = 0.03,
    alpha: float = 0.05,
    bootstrap_samples: int = 5000,
    seed: int = 20260713,
) -> dict[str, object]:
    """Fit a conservative monotone crossover within one padding band."""
    ordered = _validate_observations(observations)
    if margin <= 0 or margin >= 1:
        raise ValueError("margin must be in (0, 1)")
    if alpha <= 0 or alpha >= 1:
        raise ValueError("alpha must be in (0, 1)")
    if bootstrap_samples < MIN_BOOTSTRAP_SAMPLES:
        raise ValueError(
            f"at least {MIN_BOOTSTRAP_SAMPLES} bootstrap samples are required"
        )
    sizes = [item.size for item in ordered]
    step = sizes[1] - sizes[0]
    sentinel = sizes[-1] + step
    target_log_ratio = math.log1p(-margin)
    median_logs, weights, points = _point_statistics(ordered)
    fitted_logs = isotonic_decreasing(median_logs, weights)
    for point, fitted in zip(points, fitted_logs):
        point["fitted_ratio"] = math.exp(fitted)

    generator = random.Random(seed)
    bootstrapped_thresholds: list[int] = []
    for _ in range(bootstrap_samples):
        sampled_processes = [
            generator.randrange(len(ordered[0].process_ratios))
            for _ in range(len(ordered[0].process_ratios))
        ]
        sampled_medians: list[float] = []
        sampled_weights: list[float] = []
        for item in ordered:
            ratios = item.process_ratios
            sampled_logs = [
                math.log(ratios[process]) for process in sampled_processes
            ]
            sampled_median = statistics.median(sampled_logs)
            sampled_mad = median_absolute_deviation(sampled_logs)
            sampled_sigma = max(1.4826 * sampled_mad, 0.005)
            sampled_medians.append(sampled_median)
            sampled_weights.append(len(sampled_logs) / (sampled_sigma**2))
        sampled_fit = isotonic_decreasing(sampled_medians, sampled_weights)
        bootstrapped_thresholds.append(
            _threshold_from_fit(sizes, sampled_fit, target_log_ratio, sentinel)
        )

    threshold_median = _nearest_rank(bootstrapped_thresholds, 0.5)
    threshold_upper = _nearest_rank(bootstrapped_thresholds, 1.0 - alpha)
    selected: int | None = None
    if threshold_upper <= sizes[-1]:
        start = sizes.index(threshold_upper)
        for index in range(start, len(points)):
            point = points[index]
            if (
                float(point["median_ratio"]) <= 1.0 - margin
                and float(point["sign_p_value"]) <= alpha
            ):
                selected = int(point["size"])
                break

    no_switch_probability = sum(
        value == sentinel for value in bootstrapped_thresholds
    ) / len(bootstrapped_thresholds)
    return {
        "method": "banded-weighted-isotonic-log-ratio",
        "margin": margin,
        "alpha": alpha,
        "bootstrap_samples": bootstrap_samples,
        "seed": seed,
        "process_count": len(ordered[0].process_ratios),
        "grid": {"low": sizes[0], "high": sizes[-1], "step": step},
        "threshold": {
            "bootstrap_median": None if threshold_median == sentinel else threshold_median,
            "upper_confidence": None if threshold_upper == sentinel else threshold_upper,
            "selected": selected,
            "no_switch_probability": no_switch_probability,
        },
        "points": points,
    }
