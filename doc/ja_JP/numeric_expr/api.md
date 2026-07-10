# `numeric_expr` API

`numeric_expr` はホスト言語に依存しない数値式コアを提供し、式の保存表現を非公開にします。

## 構文型

`SourceSpan` は source・line・column、`Literal` は生テキストと span、`Operation` は操作名と span を保持します。`Expr::literal` と `Expr::invoke` がリテラルと原始適用を作ります。

対応 accessor は `SourceSpan::{new,source,line,column}`、
`Literal::{new,raw,span}`、`Operation::{new,name,span}` です。

## 評価

`evaluate(expr, literal_callback, operation_callback)` は子を先に評価してから操作コールバックを呼び、`Result[V, EvalError[E]]` を返します。エラーはリテラル失敗、操作失敗、未対応の式形を区別します。
