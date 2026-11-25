///|
/// The guarded quotient must not be rounded with the target mode: when that
/// rounding manufactures an exact tie the final rounding applies the tie rule
/// to a case the exact quotient had already decided. 15/83294 = 0.000180085...,
/// so five digits round to 0.00018009, but a HalfEven intermediate produced
/// ...0805 and the final HalfEven then rounded down to 0.00018008.
// oracle: A
// source: the exact quotient 15/83294 = 0.000180085... computed with Python decimal (CPython, libmpdec) at 5 and at 30 digits: five digits give 0.00018009 (the digits after the fifth are 5 followed by more nonzero digits, not a tie)
// shares: Decimal::from_string, the operator / and div_ctx (the code under test)
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
// oracle: S
// source: the operator / against div_ctx with a default-rounding context of the same precision, two entry points of one function; no expected value is written out. The block `decimal division rounds once near a manufactured midpoint` of this file pins the value 0.00018009 for the first pair at precision 5 (written out)
// shares: Decimal::from_string, Decimal::div and Decimal::div_ctx (the code under test on both sides)
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
