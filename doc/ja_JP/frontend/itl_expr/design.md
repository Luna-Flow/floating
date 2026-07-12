# `frontend/itl_expr` 設計

ITF1788 行を解析し、`BallFloat`/`BallFloatDecorated` に operation を分配します。区間、bool、overlap、数値、decoration ごとの比較器で検証し、共有 conformance model で集計します。未対応 operation/arity/期待値は明示的 disposition です。
