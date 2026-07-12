///|
pub fn[A, B, E, C] result_lift2(
  left : Result[A, E],
  right : Result[B, E],
  combine : (A, B) -> C,
) -> Result[C, E] {
  left.bind(fn(lhs) { right.map(fn(rhs) { combine(lhs, rhs) }) })
}

///|
pub fn[A, B, E, C] result_lift2_checked(
  left : Result[A, E],
  right : Result[B, E],
  combine : (A, B) -> Result[C, E],
) -> Result[C, E] {
  left.bind(fn(lhs) { right.bind(fn(rhs) { combine(lhs, rhs) }) })
}
