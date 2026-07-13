# `numeric_expr` API

`numeric_expr` はホスト言語に依存しない数値式コアを提供し、式の保存表現を非公開にします。

## 構文型

`SourceSpan` は source・line・column、`Literal` は生テキストと span、`Operation` は操作名と span を保持します。`Expr::literal` と `Expr::invoke` がリテラルと原始適用を作ります。

対応 accessor は `SourceSpan::{new,source,line,column}`、
`Literal::{new,raw,span}`、`Operation::{new,name,span}` です。

## 評価

`evaluate(expr, literal_callback, operation_callback)` は子を先に評価してから操作コールバックを呼び、`Result[V, EvalError[E]]` を返します。エラーはリテラル失敗、操作失敗、未対応の式形を区別します。

## 完全な公開インターフェース

次の snapshot は `0.6.0` の完全な生成 package interface です。公開宣言が名前と signature の基準で、前の説明は挙動別に整理しています。

<!-- generated-api-start -->
```moonbit
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating/numeric_expr"

import {
  "moonbitlang/core/debug",
}

// Values
pub fn[V, E] evaluate(Expr, (Literal) -> Result[V, E], (Operation, Array[V]) -> Result[V, E]) -> Result[V, EvalError[E]]

// Errors

// Types and methods
pub(all) enum EvalError[E] {
  LiteralFailure(Literal, E)
  OperationFailure(Operation, E)
  UnsupportedExpression(SourceSpan)
}

pub struct Expr {
  // private fields
}
pub fn Expr::invoke(Operation, Array[Self]) -> Self
pub fn Expr::literal(Literal) -> Self

pub struct Literal {
  // private fields
} derive(Eq, @debug.Debug)
pub fn Literal::new(String, span? : SourceSpan) -> Self
pub fn Literal::raw(Self) -> String
pub fn Literal::span(Self) -> SourceSpan

pub struct Operation {
  // private fields
} derive(Eq, @debug.Debug)
pub fn Operation::name(Self) -> String
pub fn Operation::new(String, span? : SourceSpan) -> Self
pub fn Operation::span(Self) -> SourceSpan

pub struct SourceSpan {
  // private fields
} derive(Eq, @debug.Debug)
pub fn SourceSpan::column(Self) -> Int
pub fn SourceSpan::line(Self) -> Int
pub fn SourceSpan::new(String, line? : Int, column? : Int) -> Self
pub fn SourceSpan::source(Self) -> String

// Type aliases

// Traits
```
<!-- generated-api-end -->
