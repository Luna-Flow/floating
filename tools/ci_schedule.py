"""Run gate stages in lanes: stages of one lane in order, lanes concurrently.

A stage is `(name, lane, after)`. The stages of a lane run one after another;
different lanes run at the same time. `after` names a stage of another lane
that must have passed before this stage (and so the rest of its lane) starts.
Stages that share a build directory belong to one lane; the planner in
`run_ci.py` decides that, this module only enforces the order.

The output of a stage is captured and printed in one piece when the stage ends,
so concurrent stages never interleave, and the first failure is reported with
the stage's name and its whole output. After a failure no new stage starts and
`cancel` is called once so that the caller can stop the running children.
"""

from __future__ import annotations

import threading
import time
from collections.abc import Callable, Sequence
from dataclasses import dataclass
from typing import Protocol


class StageLike(Protocol):
    name: str
    lane: str
    after: str | None


@dataclass(frozen=True)
class Outcome:
    returncode: int
    output: str = ""
    seconds: float = 0.0
    skipped: bool = False


def group_lanes(stages: Sequence[StageLike]) -> dict[str, list[StageLike]]:
    """Stages by lane, each lane in plan order (the first lane seen first)."""
    lanes: dict[str, list[StageLike]] = {}
    for stage in stages:
        lanes.setdefault(stage.lane, []).append(stage)
    return lanes


def validate_plan(stages: Sequence[StageLike]) -> None:
    """Names are unique, and `after` names an earlier stage of another lane."""
    seen: dict[str, StageLike] = {}
    for stage in stages:
        if stage.name in seen:
            raise ValueError(f"duplicate stage name: {stage.name}")
        if stage.after is not None:
            earlier = seen.get(stage.after)
            if earlier is None:
                raise ValueError(f"{stage.name}: unknown or later stage {stage.after!r}")
            if earlier.lane == stage.lane:
                raise ValueError(f"{stage.name}: {stage.after!r} is in the same lane")
        seen[stage.name] = stage


def execute(
    stages: Sequence[StageLike],
    run_stage: Callable[[StageLike], Outcome],
    report: Callable[[StageLike, Outcome], None],
    cancel: Callable[[], None] = lambda: None,
    poll_seconds: float = 0.05,
) -> tuple[int, str | None]:
    """Run the plan; returns (exit code, name of the first failed stage)."""
    validate_plan(stages)
    lanes = group_lanes(stages)
    passed = {stage.name: threading.Event() for stage in stages}
    failed = threading.Event()
    lock = threading.Lock()
    first: list[tuple[StageLike, Outcome]] = []

    def finish(stage: StageLike, outcome: Outcome) -> None:
        with lock:
            if first:
                return  # a stage cancelled by the first failure is not a result
            if outcome.returncode != 0:
                first.append((stage, outcome))
                failed.set()
            report(stage, outcome)
        if outcome.returncode != 0:
            cancel()
        else:
            passed[stage.name].set()

    def worker(lane_stages: list[StageLike]) -> None:
        for stage in lane_stages:
            if stage.after is not None:
                while not passed[stage.after].is_set():
                    if failed.is_set():
                        return
                    time.sleep(poll_seconds)
            if failed.is_set():
                return
            finish(stage, run_stage(stage))

    threads = [
        threading.Thread(target=worker, args=(lane_stages,), name=f"lane-{lane}", daemon=True)
        for lane, lane_stages in lanes.items()
    ]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()
    if first:
        stage, outcome = first[0]
        return outcome.returncode, stage.name
    return 0, None
