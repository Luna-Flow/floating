import time
import unittest

from conformance_runtime import ensure_available, ordered_parallel_map


class RecordingProgress:
    def __init__(self) -> None:
        self.details: list[str] = []

    def advance(self, detail: str = "") -> None:
        self.details.append(detail)


class ConformanceRuntimeTests(unittest.TestCase):
    def test_ready_input_does_not_fetch(self) -> None:
        calls = []
        result = ensure_available(
            is_ready=lambda: True,
            fetcher=lambda args: calls.append(args) or 0,
            fetch_args=["official"],
            force=False,
            missing_message="missing",
        )
        self.assertEqual(result, 0)
        self.assertEqual(calls, [])

    def test_missing_input_fetches_and_rechecks(self) -> None:
        ready = False

        def fetch(arguments: list[str] | None) -> int:
            nonlocal ready
            self.assertEqual(arguments, ["official"])
            ready = True
            return 0

        self.assertEqual(
            ensure_available(
                is_ready=lambda: ready,
                fetcher=fetch,
                fetch_args=["official"],
                force=False,
                missing_message="missing",
            ),
            0,
        )

    def test_fetch_failure_is_returned(self) -> None:
        self.assertEqual(
            ensure_available(
                is_ready=lambda: False,
                fetcher=lambda args: 7,
                fetch_args=[],
                force=False,
                missing_message="missing",
            ),
            7,
        )

    def test_successful_fetch_must_make_input_ready(self) -> None:
        with self.assertRaisesRegex(FileNotFoundError, "still missing"):
            ensure_available(
                is_ready=lambda: False,
                fetcher=lambda args: 0,
                fetch_args=[],
                force=False,
                missing_message="still missing",
            )

    def test_parallel_map_preserves_input_order(self) -> None:
        progress = RecordingProgress()

        def worker(value: int) -> int:
            time.sleep((4 - value) * 0.005)
            return value * 10

        self.assertEqual(
            ordered_parallel_map(
                [1, 2, 3],
                3,
                worker,
                progress,
                lambda value: str(value),
            ),
            [10, 20, 30],
        )
        self.assertCountEqual(progress.details, ["1", "2", "3"])

    def test_parallel_map_propagates_worker_failure(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "worker failed"):
            ordered_parallel_map(
                [1],
                1,
                lambda value: (_ for _ in ()).throw(RuntimeError("worker failed")),
                RecordingProgress(),
                str,
            )


if __name__ == "__main__":
    unittest.main()
