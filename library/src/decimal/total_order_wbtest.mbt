///|
fn total_order_operand(source : String) -> Decimal {
  match Decimal::from_string(source) {
    Some(value) => value
    None => abort("total order operand: " + source)
  }
}

///|
test "total_order and total_order_mag follow IEEE 754-2019 5.10" {
  // Ascending chain of 5.10 (a): -NaN < -sNaN < -inf < -1 < -0 < +0 < 1 < inf < sNaN < NaN
  // (signed-zero and cohort rows are in the generated 5.10 corpus).
  let chain = [
    Decimal::quiet_nan(negative=true),
    Decimal::signaling_nan(negative=true),
    total_order_operand("-Infinity"),
    total_order_operand("-1"),
    total_order_operand("-0"),
    total_order_operand("0"),
    total_order_operand("1"),
    total_order_operand("Infinity"),
    Decimal::signaling_nan(),
    Decimal::quiet_nan(),
  ]
  for i in 0..<chain.length() {
    for j in 0..<chain.length() {
      assert_eq(chain[i].total_order(chain[j]), i <= j)
      assert_eq(
        chain[i].total_order_compare(chain[j]),
        if i < j {
          -1
        } else if i == j {
          0
        } else {
          1
        },
      )
    }
  }
}

///|
test "total_order orders the cohort by exponent and total_order_mag ignores the sign" {
  let wide = total_order_operand("1.00")
  let narrow = total_order_operand("1.0")
  assert_true(wide.total_order(narrow))
  assert_false(narrow.total_order(wide))
  assert_true(
    total_order_operand("-1.0").total_order(total_order_operand("-1.00")),
  )
  let negative = total_order_operand("-5")
  let positive = total_order_operand("3")
  assert_true(positive.total_order_mag(negative))
  assert_false(negative.total_order_mag(positive))
  assert_true(negative.total_order_mag(total_order_operand("5")))
  assert_true(total_order_operand("5").total_order_mag(negative))
  assert_true(
    Decimal::quiet_nan(negative=true).total_order_mag(Decimal::quiet_nan()),
  )
}
