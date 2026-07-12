import io
import unittest

from conformance_ui import Console, Progress, format_duration, progress_bar


class TtyBuffer(io.StringIO):
    def isatty(self) -> bool:
        return True


class ConformanceUiTests(unittest.TestCase):
    def test_progress_bar_clamps_values(self) -> None:
        self.assertEqual(progress_bar(-1, 4, 4), "░░░░")
        self.assertEqual(progress_bar(2, 4, 4), "██░░")
        self.assertEqual(progress_bar(9, 4, 4), "████")

    def test_duration_keeps_short_and_long_runs_readable(self) -> None:
        self.assertEqual(format_duration(4.25), "4.2s")
        self.assertEqual(format_duration(125), "2m 05s")

    def test_non_tty_progress_does_not_emit_ansi(self) -> None:
        stream = io.StringIO()
        progress = Progress("suite", 2, Console(stream, color=False))
        progress.advance("first")
        progress.finish(True, "done")
        self.assertEqual(stream.getvalue(), "PASS  suite  done\n")

    def test_tty_progress_updates_one_physical_line(self) -> None:
        stream = TtyBuffer()
        progress = Progress("suite", 2, Console(stream, color=False))
        progress.advance("first")
        progress.finish(True, "done")
        output = stream.getvalue()
        self.assertEqual(output.count("\n"), 1)
        self.assertTrue(output.endswith("\r\033[2KPASS  suite  done\n"))


if __name__ == "__main__":
    unittest.main()
