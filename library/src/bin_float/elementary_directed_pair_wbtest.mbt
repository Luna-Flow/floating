///|
fn directed_pair_values(p : Int32, seed0 : UInt64) -> Array[BinFloat] {
  let values : Array[BinFloat] = []
  let mut seed = seed0
  for top in [-30, -8, -3, -1, 0, 1, 2, 3, 5, 8, 12, 20, 30] {
    for _ in 0..<5 {
      seed += 1UL
      values.push(
        burst_test_value(Int32::max(p, 2), top, seed % 2UL == 0UL, seed),
      )
    }
  }
  values.push(BinFloat::from_int(1, precision=p))
  values.push(BinFloat::from_int(2, precision=p))
  values.push(BinFloat::from_int(-1, precision=p))
  values.push(BinFloat::zero(precision=p))
  values.push(BinFloat::negative_zero(precision=p))
  values.push(BinFloat::inf(Sign::Positive))
  values.push(BinFloat::inf(Sign::Negative))
  values.push(BinFloat::nan())
  values.push(BinFloat::make_coeff(Coeff::from_uint64(3UL), -1073741000, p))
  values.push(BinFloat::make_coeff(Coeff::from_uint64(3UL), 1073741000, p))
  values.push(BinFloat::make_coeff(Coeff::from_uint64(3UL), 40, p))
  values.push(BinFloat::make_coeff(Coeff::from_uint64(3UL), 40, p).neg())
  values.push(BinFloat::make_coeff(Coeff::from_uint64(2097153UL), -21, p))
  values
}

///|
fn directed_pair_same(a : BinFloat, b : BinFloat) -> Bool {
  a.classify() == b.classify() &&
  a.is_negative() == b.is_negative() &&
  a.precision() == b.precision() &&
  (a.classify() != FpClass::Finite || a.compare(b) == 0)
}

///|
/// The pair against the two directed calls on one operand: the same two values
/// bit for bit, or the same error.
fn directed_pair_agrees(
  pair : Result[(BinFloat, BinFloat), @def.ArithmeticError],
  low : Result[(BinFloat, BinaryFlags), @def.ArithmeticError],
  high : Result[(BinFloat, BinaryFlags), @def.ArithmeticError],
) -> Bool {
  match (pair, low, high) {
    (Ok((a, b)), Ok(x), Ok(y)) =>
      directed_pair_same(a, x.0) && directed_pair_same(b, y.0)
    (Err(e), Err(f), _) => e.message == f.message
    (Err(e), Ok(_), Err(g)) => e.message == g.message
    _ => false
  }
}

///|
test "exp directed pair equals the two directed calls on every operand" {
  let mut ok = 0
  let mut errors = 0
  for p in [2, 10, 24, 53, 64, 100, 128, 200, 512] {
    let downward = BinaryContext::new(
      precision=p,
      rounding=BinaryRoundingMode::RoundTowardNegative,
    )
    let upward = BinaryContext::new(
      precision=p,
      rounding=BinaryRoundingMode::RoundTowardPositive,
    )
    for value in directed_pair_values(p, 11UL + p.to_uint64()) {
      let pair = value.try_exp_directed_pair(p)
      assert_true(
        directed_pair_agrees(
          pair,
          value.try_exp_ctx(downward),
          value.try_exp_ctx(upward),
        ),
      )
      match pair {
        Ok(_) => ok += 1
        Err(_) => errors += 1
      }
    }
  }
  assert_true(ok > 300)
  assert_true(errors >= 0)
}

///|
test "ln directed pair equals the two directed calls on every operand" {
  let mut ok = 0
  let mut errors = 0
  for p in [2, 10, 24, 53, 64, 100, 128, 200, 512, 700] {
    let downward = BinaryContext::new(
      precision=p,
      rounding=BinaryRoundingMode::RoundTowardNegative,
    )
    let upward = BinaryContext::new(
      precision=p,
      rounding=BinaryRoundingMode::RoundTowardPositive,
    )
    for value in directed_pair_values(p, 77UL + p.to_uint64()) {
      let pair = value.try_ln_directed_pair(p)
      assert_true(
        directed_pair_agrees(
          pair,
          value.try_ln_ctx(downward),
          value.try_ln_ctx(upward),
        ),
      )
      match pair {
        Ok(_) => ok += 1
        Err(_) => errors += 1
      }
    }
  }
  assert_true(ok > 300)
  assert_true(errors > 0)
}
