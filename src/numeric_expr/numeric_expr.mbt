///|
pub struct SourceSpan {
  priv source : String
  priv line : Int
  priv column : Int
} derive(Eq, Debug)

///|
pub fn SourceSpan::new(
  source : String,
  line? : Int = 0,
  column? : Int = 0,
) -> SourceSpan {
  { source, line, column }
}

///|
pub fn SourceSpan::source(self : SourceSpan) -> String {
  self.source
}

///|
pub fn SourceSpan::line(self : SourceSpan) -> Int {
  self.line
}

///|
pub fn SourceSpan::column(self : SourceSpan) -> Int {
  self.column
}

///|
pub struct Literal {
  priv raw : String
  priv span : SourceSpan
} derive(Eq, Debug)

///|
pub fn Literal::new(
  raw : String,
  span? : SourceSpan = SourceSpan::new(""),
) -> Literal {
  { raw, span }
}

///|
pub fn Literal::raw(self : Literal) -> String {
  self.raw
}

///|
pub fn Literal::span(self : Literal) -> SourceSpan {
  self.span
}

///|
pub struct Operation {
  priv name : String
  priv span : SourceSpan
} derive(Eq, Debug)

///|
pub fn Operation::new(
  name : String,
  span? : SourceSpan = SourceSpan::new(""),
) -> Operation {
  { name, span }
}

///|
pub fn Operation::name(self : Operation) -> String {
  self.name
}

///|
pub fn Operation::span(self : Operation) -> SourceSpan {
  self.span
}

///|
priv enum Atom {
  LiteralAtom(Literal)
  PrimitiveAtom(Operation)
}

///|
pub struct Expr {
  priv term : @tt_syntax.Term[Atom]
}

///|
pub fn Expr::literal(value : Literal) -> Expr {
  { term: @tt_syntax.Value(LiteralAtom(value)) }
}

///|
pub fn Expr::invoke(operation : Operation, arguments : Array[Expr]) -> Expr {
  {
    term: @tt_syntax.Apply(
      @tt_syntax.Value(PrimitiveAtom(operation)),
      arguments.map(fn(argument) { argument.term }),
    ),
  }
}

///|
pub(all) enum EvalError[E] {
  LiteralFailure(Literal, E)
  OperationFailure(Operation, E)
  UnsupportedExpression(SourceSpan)
}

///|
fn[V, E] evaluate_term(
  term : @tt_syntax.Term[Atom],
  decode : (Literal) -> Result[V, E],
  invoke : (Operation, Array[V]) -> Result[V, E],
) -> Result[V, EvalError[E]] {
  match term {
    @tt_syntax.Value(LiteralAtom(literal)) =>
      match decode(literal) {
        Ok(value) => Ok(value)
        Err(error) => Err(LiteralFailure(literal, error))
      }
    @tt_syntax.Apply(@tt_syntax.Value(PrimitiveAtom(operation)), arguments) => {
      let values : Array[V] = []
      for argument in arguments {
        match evaluate_term(argument, decode, invoke) {
          Ok(value) => values.push(value)
          Err(error) => return Err(error)
        }
      }
      match invoke(operation, values) {
        Ok(value) => Ok(value)
        Err(error) => Err(OperationFailure(operation, error))
      }
    }
    @tt_syntax.Value(PrimitiveAtom(operation)) =>
      Err(UnsupportedExpression(operation.span()))
    @tt_syntax.Variable(_) | @tt_syntax.Apply(_, _) | @tt_syntax.Bind(_, _) =>
      Err(UnsupportedExpression(SourceSpan::new("")))
  }
}

///|
pub fn[V, E] evaluate(
  expression : Expr,
  decode : (Literal) -> Result[V, E],
  invoke : (Operation, Array[V]) -> Result[V, E],
) -> Result[V, EvalError[E]] {
  evaluate_term(expression.term, decode, invoke)
}
