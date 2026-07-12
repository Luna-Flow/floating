# `cli/mpfr_expr_cli` 設計

固定文法から sqrt/整数冪を判別し、`frontend/mpfr_expr` に委譲して text/JSON を出力します。一回一ファイルで shard は無効です。判別は transport 層です。
