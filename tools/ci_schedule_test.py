import threading
import time
import unittest
from dataclasses import dataclass

import ci_schedule as sched


@dataclass(frozen=True)
class S:
    name: str
    lane: str = "main"
    after: str | None = None


class PlanTests(unittest.TestCase):
    def test_lanes_keep_plan_order(self) -> None:
        stages = [S("a", "x"), S("b", "y"), S("c", "x")]
        lanes = sched.group_lanes(stages)
        self.assertEqual([s.name for s in lanes["x"]], ["a", "c"])
        self.assertEqual(list(lanes), ["x", "y"])

    def test_plan_validation(self) -> None:
        sched.validate_plan([S("a", "x"), S("b", "y", after="a")])
        for bad in (
            [S("a"), S("a")],  # duplicate
            [S("b", "y", after="a"), S("a", "x")],  # after names a later stage
            [S("a", "x"), S("b", "x", after="a")],  # same lane
            [S("b", "y", after="zzz")],  # unknown
        ):
            with self.assertRaises(ValueError):
                sched.validate_plan(bad)


class ExecuteTests(unittest.TestCase):
    def run_plan(self, stages, behaviour, cancel=lambda: None):
        log: list[str] = []
        lock = threading.Lock()
        reported: list[str] = []

        def run_stage(stage):
            with lock:
                log.append("start " + stage.name)
            outcome = behaviour(stage)
            with lock:
                log.append("end " + stage.name)
            return outcome

        code, failed = sched.execute(
            stages, run_stage, lambda stage, outcome: reported.append(stage.name), cancel, poll_seconds=0.001
        )
        return code, failed, log, reported

    def test_a_lane_runs_in_order(self) -> None:
        stages = [S("a"), S("b"), S("c")]
        code, failed, log, reported = self.run_plan(stages, lambda s: sched.Outcome(0))
        self.assertEqual((code, failed), (0, None))
        self.assertEqual(reported, ["a", "b", "c"])

    def test_lanes_overlap(self) -> None:
        barrier = threading.Barrier(2, timeout=5)

        def behaviour(stage):
            barrier.wait()  # both lanes must be running at once to pass
            return sched.Outcome(0)

        code, failed, *_ = self.run_plan([S("a", "x"), S("b", "y")], behaviour)
        self.assertEqual((code, failed), (0, None))

    def test_after_waits_for_the_named_stage(self) -> None:
        def behaviour(stage):
            if stage.name == "slow":
                time.sleep(0.1)
            return sched.Outcome(0)

        stages = [S("slow", "x"), S("dependent", "y", after="slow")]
        _, _, log, _ = self.run_plan(stages, behaviour)
        self.assertLess(log.index("end slow"), log.index("start dependent"))

    def test_first_failure_is_reported_and_stops_new_stages(self) -> None:
        cancelled: list[int] = []

        def behaviour(stage):
            if stage.name == "bad":
                return sched.Outcome(3, "boom")
            if stage.name == "other1":
                time.sleep(0.1)
            return sched.Outcome(0)

        stages = [S("bad", "x"), S("never", "x"), S("other1", "y"), S("other2", "y")]
        code, failed, log, reported = self.run_plan(stages, behaviour, lambda: cancelled.append(1))
        self.assertEqual((code, failed), (3, "bad"))
        self.assertNotIn("start never", log)
        self.assertNotIn("start other2", log)  # not started after the failure
        self.assertEqual(cancelled, [1])
        self.assertEqual(reported, ["bad"])  # the cancelled stage is not a result

    def test_dependent_lane_does_not_start_when_its_stage_failed(self) -> None:
        stages = [S("bad", "x"), S("dependent", "y", after="bad")]
        code, failed, log, _ = self.run_plan(stages, lambda s: sched.Outcome(1 if s.name == "bad" else 0))
        self.assertEqual((code, failed), (1, "bad"))
        self.assertNotIn("start dependent", log)

    def test_reports_never_run_concurrently(self) -> None:
        inside = []
        overlaps = []
        lock = threading.Lock()

        def report(stage, outcome):
            with lock:
                inside.append(1)
                if len(inside) > 1:
                    overlaps.append(stage.name)
            time.sleep(0.01)
            with lock:
                inside.pop()

        stages = [S(f"s{i}", f"lane{i}") for i in range(6)]
        sched.execute(stages, lambda s: sched.Outcome(0), report, poll_seconds=0.001)
        self.assertEqual(overlaps, [])


if __name__ == "__main__":
    unittest.main()
