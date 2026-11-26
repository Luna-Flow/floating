///|
fn total_order_operand(source : String) -> Decimal {
  match Decimal::from_string(source) {
    Ok(value) => value
    Err(_) => abort("total order operand: " + source)
  }
}

///|
// oracle: A
// source: written out from IEEE Std 754-2019 5.10 (pdftotext of the PDF): -qNaN < -sNaN < -inf < -1 < -0 < +0 < 1 < +inf < +sNaN < +qNaN for all 10 x 10 pairs, with total_order_compare equal to -1, 0 or 1 by position
// shares: total_order_operand reads the finite and infinite operands with Decimal::from_string; Decimal::quiet_nan and signaling_nan build the NaNs; total_order and total_order_compare are the code under test
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
// oracle: A
// source: written out from IEEE Std 754-2019 5.10 c) 3) (positive members of a cohort: the larger exponent first, so 1.00 is below 1.0 in total order; negative members reversed: -1.0 is below -1.00) and the definition totalOrderMag(x, y) = totalOrder(|x|, |y|): 3 is below -5 in magnitude order, -5 and 5 are equal, and a negative and a positive quiet NaN are equal
// shares: total_order_operand reads the operands with Decimal::from_string; Decimal::quiet_nan builds the NaNs; total_order and total_order_mag are the code under test
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
