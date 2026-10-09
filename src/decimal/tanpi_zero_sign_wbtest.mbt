///|
/// tanPi(n) = sinPi(n) / cosPi(n), so the zero it returns at an integer has
/// the sign of sinPi(n) times the sign of cosPi(n): -0 at positive odd n, +0 at
/// negative odd n (IEEE 754-2019 9.2.1), and the argument's sign at even n.
test "tanpi of an integer takes the sign of sinpi over cospi" {
  let ctx = DecimalContext::decimal64()
  for n in [-4, -3, -2, -1, 0, 1, 2, 3, 4, 101, -101] {
    let (value, flags) = Decimal::from_int(n).tanpi_ctx(ctx)
    let odd = n % 2 != 0
    let negative = (n < 0) != odd
    assert_true(value.is_zero())
    assert_eq(value.is_negative(), if n == 0 { false } else { negative })
    assert_true(flags == DecimalFlags::new())
  }
  let (negative_zero, _) = Decimal::from_string("-0").unwrap().tanpi_ctx(ctx)
  assert_true(negative_zero.is_negative())
  // sinpi and cospi keep their signs.
  assert_true(Decimal::from_int(-1).sinpi_ctx(ctx).0.is_negative())
  assert_eq(Decimal::from_int(3).cospi_ctx(ctx).0.to_string(), "-1")
}
