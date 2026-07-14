from __future__ import annotations

import concurrent.futures
from collections.abc import Callable, Sequence
from enum import StrEnum
from typing import TypeVar

from conformance_ui import Progress


class BackendName(StrEnum):
    DECIMAL = "decimal"
    DECIMAL_GDA = "decimal_gda"
    BINARY = "binary"
    INTERVAL = "interval"


FetchEntryPoint = Callable[[list[str] | None], int]
Item = TypeVar("Item")
Result = TypeVar("Result")


def ensure_available(
    *,
    is_ready: Callable[[], bool],
    fetcher: FetchEntryPoint,
    fetch_args: list[str],
    force: bool,
    missing_message: str,
) -> int:
    if force or not is_ready():
        return_code = fetcher(fetch_args)
        if return_code != 0:
            return return_code
    if not is_ready():
        raise FileNotFoundError(missing_message)
    return 0


def ordered_parallel_map(
    items: Sequence[Item],
    jobs: int,
    worker: Callable[[Item], Result],
    progress: Progress,
    detail: Callable[[Item], str],
) -> list[Result]:
    results: dict[int, Result] = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as pool:
        future_map = {
            pool.submit(worker, item): index for index, item in enumerate(items)
        }
        for future in concurrent.futures.as_completed(future_map):
            index = future_map[future]
            results[index] = future.result()
            progress.advance(detail(items[index]))
    return [results[index] for index in range(len(items))]
