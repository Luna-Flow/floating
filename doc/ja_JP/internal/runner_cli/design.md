# `internal/runner_cli` 設計

共通 option、決定的 file collection、source read、diagnostic、JSON 構築という runner の副作用を隔離します。corpus parser と数値操作は持たず、frontend を純粋に保ちます。
