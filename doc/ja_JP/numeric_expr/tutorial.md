# `numeric_expr` チュートリアル

## 構文と数値意味論を分ける

`Literal` と `Operation` で式を作り、`evaluate` に二つのコールバックを渡します。一つはリテラル文字列を backend 値へ変換し、もう一つは評価済み引数に操作名を適用します。

同じ式木を `Decimal`、`BinFloat`、意味値、テストダブルへ適用できます。ファイルシステム方針を式パッケージへ入れず、frontend 診断に `SourceSpan` を残します。
