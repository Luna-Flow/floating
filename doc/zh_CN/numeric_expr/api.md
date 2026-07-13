# `numeric_expr` API

`numeric_expr` 提供与宿主语言无关的数值表达式核心，表达式存储保持私有。

## 语法类型

`SourceSpan` 保存来源、行和列；`Literal` 保存原始文本与 span；`Operation` 保存操作名与 span；`Expr::literal`、`Expr::invoke` 构造字面量和原语调用。

对应 accessor 为 `SourceSpan::{new,source,line,column}`、
`Literal::{new,raw,span}` 和 `Operation::{new,name,span}`。

## 求值

`evaluate(expr, literal_callback, operation_callback)` 先求值子节点，再调用操作回调，返回 `Result[V, EvalError[E]]`。错误区分字面量失败、操作失败和当前求值器不支持的表达式形态。

## 完整公开接口

以下快照是 `0.6.0` 的完整生成包接口。公开声明是名称与签名的权威清单；前文按行为解释这些能力。

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
