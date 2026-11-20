///|
/// `exp` of a ball by the route before the point shortcut: one certified call per end.
fn BallFloat::ball_exp_two_calls(
  self : BallFloat,
) -> Result[BallFloat, @def.ArithmeticError] {
  self.try_certified_monotone(true, fn(value, context) {
    value.try_exp_ctx(context)
  })
}

///|
/// `ln` of a ball by the route before the point shortcut.
fn BallFloat::ball_ln_two_calls(
  self : BallFloat,
) -> Result[BallFloat, @def.ArithmeticError] {
  if self.is_empty() {
    return Ok(self)
  }
  let zero = @bin_float.BinFloat::zero(precision=self.precision_)
  if self.hi_.compare(zero) <= 0 {
    return Ok(empty_interval(self.precision_))
  }
  let upward = @bin_float.BinaryContext::new(
    precision=self.precision_,
    rounding=@bin_float.BinaryRoundingMode::RoundTowardPositive,
  )
  let upper = self.hi_.try_ln_ctx(upward)
  if self.lo_.compare(zero) <= 0 {
    return upper.map(fn(result) {
      store_interval(neg_inf(self.precision_), result.0, self.precision_)
    })
  }
  let downward = @bin_float.BinaryContext::new(
    precision=self.precision_,
    rounding=@bin_float.BinaryRoundingMode::RoundTowardNegative,
  )
  self.lo_
  .try_ln_ctx(downward)
  .bind(fn(lower) {
    upper.map(fn(upper_result) {
      store_interval(lower.0, upper_result.0, self.precision_)
    })
  })
}

///|
fn point_pair_same(
  a : Result[BallFloat, @def.ArithmeticError],
  b : Result[BallFloat, @def.ArithmeticError],
) -> Bool {
  match (a, b) {
    (Ok(x), Ok(y)) =>
      x.is_empty() == y.is_empty() &&
      x.precision() == y.precision() &&
      (
        x.is_empty() ||
        (
          x.lo_.classify() == y.lo_.classify() &&
          x.hi_.classify() == y.hi_.classify() &&
          x.lo_.precision() == y.lo_.precision() &&
          x.hi_.precision() == y.hi_.precision() &&
          (x.lo_.classify() != FpClass::Finite || x.lo_.compare(y.lo_) == 0) &&
          (x.hi_.classify() != FpClass::Finite || x.hi_.compare(y.hi_) == 0)
        )
      )
    (Err(x), Err(y)) => x.message == y.message
    _ => false
  }
}

///|
test "exp and ln of a point ball equal the two-call route" {
  let mut seed = 5UL
  let mut checked = 0
  for p in [24, 53, 64, 128, 200] {
    let values : Array[@bin_float.BinFloat] = []
    for top in [-30, -8, -3, -1, 0, 1, 2, 3, 5, 8, 12, 20, 30] {
      for _ in 0..<4 {
        seed += 1UL
        let coefficient = @bin_float.BinFloat::from_int(
          (seed * 2654435761UL % 4294967291UL).to_int() + 3,
          precision=p,
        )
        let scale = @bin_float.BinFloat::make(
          @bin_float.BinCoeff::one(),
          top - 31,
          p,
        )
        let value = coefficient.mul(scale)
        values.push(if seed % 2UL == 0UL { value } else { value.neg() })
      }
    }
    for k in [-5, -2, 0, 1, 3] {
      values.push(@bin_float.BinFloat::from_int(k, precision=p))
    }
    values.push(@bin_float.BinFloat::make(@bin_float.BinCoeff::one(), 40, p))
    values.push(
      @bin_float.BinFloat::make(@bin_float.BinCoeff::one(), 1073741000, p),
    )
    values.push(
      @bin_float.BinFloat::make(@bin_float.BinCoeff::one(), -1073741000, p),
    )
    values.push(@bin_float.BinFloat::zero(precision=p))
    for value in values {
      let ball = BallFloat::from_bounds(value, value, precision=p)
      assert_true(point_pair_same(ball.try_exp(), ball.ball_exp_two_calls()))
      assert_true(point_pair_same(ball.try_ln(), ball.ball_ln_two_calls()))
      checked += 1
    }
  }
  assert_true(checked >= 300)
}

///|
test "exp and ln of a ball with two ends are unchanged" {
  let a = @bin_float.BinFloat::from_int(3, precision=53)
  let b = a.add(@bin_float.BinFloat::make(@bin_float.BinCoeff::one(), -40, 53))
  let ball = BallFloat::from_bounds(a, b, precision=53)
  assert_true(point_pair_same(ball.try_exp(), ball.ball_exp_two_calls()))
  assert_true(point_pair_same(ball.try_ln(), ball.ball_ln_two_calls()))
}
