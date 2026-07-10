///|
test "numeric expression evaluates nested invocations" {
  let span = @numeric_expr.SourceSpan::new("example.expr", line=2, column=4)
  let expression = @numeric_expr.Expr::invoke(
    @numeric_expr.Operation::new("add", span~),
    [
      @numeric_expr.Expr::literal(@numeric_expr.Literal::new("2", span~)),
      @numeric_expr.Expr::invoke(@numeric_expr.Operation::new("mul", span~), [
        @numeric_expr.Expr::literal(@numeric_expr.Literal::new("3", span~)),
        @numeric_expr.Expr::literal(@numeric_expr.Literal::new("4", span~)),
      ]),
    ],
  )
  let result = @numeric_expr.evaluate(
    expression,
    fn(literal) {
      match literal.raw() {
        "2" => Ok(2)
        "3" => Ok(3)
        "4" => Ok(4)
        value => Err("unexpected literal " + value)
      }
    },
    fn(operation, arguments) {
      match (operation.name(), arguments) {
        ("add", [left, right]) => Ok(left + right)
        ("mul", [left, right]) => Ok(left * right)
        _ => Err("unexpected operation")
      }
    },
  )
  match result {
    Ok(value) => assert_eq(value, 14)
    Err(_) => fail("expected successful nested evaluation")
  }
}

///|
test "numeric expression preserves literal source failures" {
  let span = @numeric_expr.SourceSpan::new("bad.expr", line=7, column=3)
  let result : Result[Int, @numeric_expr.EvalError[String]] = @numeric_expr.evaluate(
    @numeric_expr.Expr::literal(@numeric_expr.Literal::new("bad", span~)),
    fn(_) { Err("invalid") },
    fn(_, _) { Err("unused") },
  )
  match result {
    Err(@numeric_expr.LiteralFailure(literal, "invalid")) => {
      assert_eq(literal.span().source(), "bad.expr")
      assert_eq(literal.span().line(), 7)
      assert_eq(literal.span().column(), 3)
    }
    _ => fail("expected a source-aware literal failure")
  }
}
