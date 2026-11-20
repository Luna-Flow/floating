///|
/// IEEE 754-2019 9.2.1: rootn(+-0, n) is +-0 for odd n > 0 and +0 for even
/// n > 0; for n < 0 it is an infinity with divideByZero, signed only for odd n.
test "rootn of a zero follows the parity of the degree" {
  let ctx = DecimalContext::decimal64()
  let negative_zero = Decimal::from_string("-0").unwrap()
  let zero = Decimal::from_string("0").unwrap()
  for n in [1, 2, 3, 4, 100, 101] {
    let (value, flags) = negative_zero.rootn_ctx(n, ctx)
    assert_true(value.is_zero())
    assert_eq(value.is_negative(), n % 2 != 0)
    assert_true(flags == DecimalFlags::new())
    assert_false(zero.rootn_ctx(n, ctx).0.is_negative())
  }
  for n in [-1, -2, -3, -4] {
    let (value, flags) = negative_zero.rootn_ctx(n, ctx)
    assert_true(value.is_infinite())
    assert_eq(value.is_negative(), n % 2 != 0)
    assert_true(flags.division_by_zero)
  }
}
