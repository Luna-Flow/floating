///|
/// The guarded quotient must not be rounded with the target mode: when that
/// rounding manufactures an exact tie the final rounding applies the tie rule
/// to a case the exact quotient had already decided. 15/83294 = 0.000180085...,
/// so five digits round to 0.00018009, but a HalfEven intermediate produced
/// ...0805 and the final HalfEven then rounded down to 0.00018008.
test "decimal division rounds once near a manufactured midpoint" {
  let a = Decimal::from_string("15", precision=5).unwrap()
  let b = Decimal::from_string("83294", precision=5).unwrap()
  inspect(a / b, content="0.00018009")
  inspect(
    a.div_ctx(b, DecimalContext::new(precision=5)).0,
    content="0.00018009",
  )
}

///|
test "decimal division keeps the context-free and contextual paths equal" {
  let cases = [
    ("15", "83294"),
    ("1", "2222"),
    ("1", "3"),
    ("2", "7"),
    ("10", "7"),
    ("1", "9801"),
    ("355", "113"),
    ("1", "17"),
  ]
  for pair in cases {
    let (left, right) = pair
    for precision in [1, 2, 5, 7, 16] {
      let a = Decimal::from_string(left, precision~).unwrap()
      let b = Decimal::from_string(right, precision~).unwrap()
      let operator = a / b
      let contextual = a.div_ctx(b, DecimalContext::new(precision~)).0
      assert_eq(operator, contextual)
    }
  }
}
