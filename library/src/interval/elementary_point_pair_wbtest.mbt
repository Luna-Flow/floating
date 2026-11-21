///|
/// `exp` of an interval by the route before the point shortcut: one certified call per end.
fn Interval::interval_exp_two_calls(
  self : Interval,
) -> Result[Interval, @def.ArithmeticError] {
  self.try_certified_monotone(true, fn(value, context) {
    value.try_exp_ctx(context)
  })
}

///|
/// `ln` of an interval by the route before the point shortcut.
fn Interval::interval_ln_two_calls(
  self : Interval,
) -> Result[Interval, @def.ArithmeticError] {
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
  a : Result[Interval, @def.ArithmeticError],
  b : Result[Interval, @def.ArithmeticError],
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
// Oracle (level C, stated by the audit of 2026-11-21): the expected value is
// the two-call route, which goes through `try_exp_ctx` and `try_ln_ctx` (the
// code under test also calls them for a point) and shares `binary_exp_bounds`
// and `binary_ln_bounds`. It proves that the point shortcut agrees with the
// general route, not that either is right. Independent values: the test below
// (level A, p = 53), and the MPFR rows of `testdata/bin_float/mpfr-4.2.2-
// elementary.txt` for p = 24, 53, 113 and |x| up to about 2^5; nothing at
// level A covers p = 64, 128, 200, |x| up to 2^40, or the exponent-range ends
// used here.
test "exp and ln of a point interval equal the two-call route" {
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
      let interval = Interval::from_bounds(value, value, precision=p)
      assert_true(
        point_pair_same(interval.try_exp(), interval.interval_exp_two_calls()),
      )
      assert_true(
        point_pair_same(interval.try_ln(), interval.interval_ln_two_calls()),
      )
      checked += 1
    }
  }
  assert_true(checked >= 300)
}

///|
fn point_pair_end(
  coefficient : UInt64,
  exponent : Int32,
) -> @bin_float.BinFloat {
  @bin_float.BinFloat::make(
    @bin_float.BinCoeff::from_uint64(coefficient),
    exponent,
    53,
  )
}

///|
// oracle: A
// source: the four endpoint values written out: the directed 53-bit roundings of exp(3), exp(3 + 2^-40),
//   ln(3) and ln(3 + 2^-40), computed with Python 3 decimal (libmpdec, correctly rounded) at 120 digits and
//   rounded down (lower end) and up (upper end) on exact fractions; the values are irrational, so the upward
//   bound is the floor plus one unit; this library did not produce them
// shares: nothing
test "exp and ln of an interval with two ends are the directed bounds of the ends" {
  let a = @bin_float.BinFloat::from_int(3, precision=53)
  let b = a.add(@bin_float.BinFloat::make(@bin_float.BinCoeff::one(), -40, 53))
  let interval = Interval::from_bounds(a, b, precision=53)
  let exp_interval = interval.try_exp().unwrap()
  assert_eq(
    exp_interval.lo_.compare(point_pair_end(5653576037675269UL, -48)),
    0,
  )
  assert_eq(
    exp_interval.hi_.compare(point_pair_end(5653576037680412UL, -48)),
    0,
  )
  let ln_interval = interval.try_ln().unwrap()
  assert_eq(ln_interval.lo_.compare(point_pair_end(4947709893870346UL, -52)), 0)
  assert_eq(ln_interval.hi_.compare(point_pair_end(4947709893871712UL, -52)), 0)
}
