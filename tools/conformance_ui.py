import os
import sys
from dataclasses import dataclass
from typing import TextIO


RESET = "\033[0m"
COLORS = {
    "bold": "\033[1m",
    "cyan": "\033[36m",
    "green": "\033[32m",
    "red": "\033[31m",
    "yellow": "\033[33m",
    "dim": "\033[2m",
}


def format_duration(seconds: float) -> str:
    if seconds < 60:
        return f"{seconds:.1f}s"
    minutes, remainder = divmod(int(seconds), 60)
    return f"{minutes}m {remainder:02d}s"


def progress_bar(completed: int, total: int, width: int = 24) -> str:
    ratio = 1.0 if total == 0 else min(1.0, max(0.0, completed / total))
    filled = round(width * ratio)
    return "█" * filled + "░" * (width - filled)


@dataclass(frozen=True)
class SummaryRow:
    label: str
    passed: int
    total: int
    failed: int
    detail: str = ""


class Console:
    def __init__(self, stream: TextIO = sys.stderr, color: bool | None = None):
        self.stream = stream
        self.interactive = bool(getattr(stream, "isatty", lambda: False)())
        self.color = (
            self.interactive and "NO_COLOR" not in os.environ
            if color is None
            else color
        )

    def paint(self, value: str, color: str) -> str:
        if not self.color:
            return value
        return COLORS[color] + value + RESET

    def heading(self, title: str, detail: str = "") -> None:
        suffix = f"  {self.paint(detail, 'dim')}" if detail else ""
        print(f"\n{self.paint(title, 'bold')}{suffix}", file=self.stream, flush=True)

    def status(self, ok: bool, label: str, detail: str = "") -> None:
        marker = self.paint("PASS", "green") if ok else self.paint("FAIL", "red")
        suffix = f"  {detail}" if detail else ""
        print(f"{marker:>4}  {label}{suffix}", file=self.stream, flush=True)

    def note(self, label: str, detail: str = "") -> None:
        suffix = f"  {detail}" if detail else ""
        print(f" {self.paint('RUN', 'cyan')}  {label}{suffix}", file=self.stream, flush=True)


class Progress:
    def __init__(self, label: str, total: int, console: Console | None = None):
        self.label = label
        self.total = total
        self.console = console or Console()
        self.completed = 0
        self._active = False
        if self.console.interactive:
            self.update(0)

    def _render(self, value: str, newline: bool = False) -> None:
        print(
            f"\r\033[2K{value}",
            end="\n" if newline else "",
            file=self.console.stream,
            flush=True,
        )

    def update(self, completed: int, detail: str = "") -> None:
        self.completed = min(self.total, max(0, completed))
        if not self.console.interactive:
            return
        bar = self.console.paint(progress_bar(self.completed, self.total), "cyan")
        count = f"{self.completed}/{self.total}"
        suffix = f"  {detail}" if detail else ""
        self._render(f" {bar}  {count:>9}  {self.label}{suffix}")
        self._active = True

    def advance(self, detail: str = "") -> None:
        self.update(self.completed + 1, detail)

    def pause(self) -> None:
        if self._active:
            print(file=self.console.stream, flush=True)
            self._active = False

    def finish(self, ok: bool, detail: str = "") -> None:
        if self._active:
            marker = (
                self.console.paint("PASS", "green")
                if ok
                else self.console.paint("FAIL", "red")
            )
            suffix = f"  {detail}" if detail else ""
            self._render(f"{marker:>4}  {self.label}{suffix}", newline=True)
            self._active = False
            return
        self.console.status(ok, self.label, detail)


def print_summary(
    title: str,
    authority: str,
    rows: list[SummaryRow],
    passed: int,
    total: int,
    failed: int,
    elapsed: float,
    failed_ids: list[str] | None = None,
) -> None:
    console = Console(sys.stdout)
    console.heading(title, authority)
    for row in rows:
        detail = f"{row.passed:,}/{row.total:,} passed"
        if row.detail:
            detail += f" · {row.detail}"
        console.status(row.failed == 0, row.label, detail)
    console.status(
        failed == 0,
        "TOTAL",
        f"{passed:,}/{total:,} passed · {format_duration(elapsed)}",
    )
    if failed_ids:
        print("failed ids: " + ", ".join(failed_ids), file=sys.stdout)
