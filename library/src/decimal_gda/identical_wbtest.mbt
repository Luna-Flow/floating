///|
test "identical is the same datum, precision attribute included" {
  let d = fn(text : String) { Decimal::from_string(text).unwrap() }
  assert_true(d("2.5").identical(d("2.5")))
  assert_true(d("2.5") == d("2.50"))
  assert_false(d("2.5").identical(d("2.50")))
  assert_false(d("2.5").identical(d("-2.5")))
  assert_false(d("0").identical(d("-0")))
  assert_true(d("-0").identical(d("-0")))
  assert_false(d("0E+1").identical(d("0")))
  assert_true(d("inf").identical(d("Infinity")))
  assert_false(d("inf").identical(d("-inf")))
  assert_true(d("NaN7").identical(d("NaN7")))
  assert_false(d("NaN7").identical(d("NaN8")))
  assert_false(d("NaN7").identical(d("sNaN7")))
  assert_true(d("NaN") == d("NaN7"))
  assert_false(d("NaN").identical(d("1")))
  // the precision attribute is part of the datum: the plain operators round to
  // the larger attribute of their operands, so the values are not interchangeable
  let narrow = Decimal::from_int(1, precision=3)
  let wide = Decimal::from_int(1)
  assert_false(narrow.identical(wide))
  assert_true(narrow.identical(Decimal::from_int(1, precision=3)))
  assert_eq(compare_total(narrow, wide, GdaContext::decimal128()).value(), 0)
  assert_true(narrow == wide)
  let three = Decimal::from_int(3, precision=3)
  assert_eq((narrow / three).to_string(), "0.333")
  assert_eq((wide / three).to_string(), "0.3333333333333333333333333333333333")
  // identical is compare_total being 0 with equal precision attributes (every
  // value of the table has the default attribute)
  let texts = [
    "1", "1.0", "-1", "0", "-0", "inf", "NaN", "NaN3", "sNaN", "7E+5",
  ]
  for a in texts {
    for b in texts {
      let total = compare_total(d(a), d(b), GdaContext::decimal128()).value()
      assert_eq(d(a).identical(d(b)), total == 0, msg=a + " " + b)
    }
  }
}
