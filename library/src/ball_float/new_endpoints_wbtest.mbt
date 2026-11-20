// The endpoints of `BallFloat::new(c, r, precision=p)` are the exact
// `c' - R` and `c' + R` (`c'` the center rounded to `p` bits, `R` the radius
// rounded upward to `p` bits plus the upward rounding error of the center): the
// ball is symmetric around `c'` (issue #581). They were made at their own bit
// length, which rounds a result of few bits below the normal range outward to the
// quantum of those few bits.

///|
fn ne_next(state : Ref[UInt64]) -> UInt64 {
  let mut x = state.val
  x = x ^ (x << 13)
  x = x ^ (x >> 7)
  x = x ^ (x << 17)
  state.val = x
  x
}

///|
fn ne_value(
  c : UInt64,
  exponent : Int32,
  precision : Int32,
) -> @bin_float.BinFloat {
  @bin_float.BinFloat::make(
    @bin_float.BinCoeff::from_uint64(c),
    exponent,
    precision,
  )
}

///|
/// The oracle: `c'`, the total radius `R` and the exact endpoints by `add_ctx`
/// and `sub_ctx` in 600 bits.
fn ne_expected(
  c : @bin_float.BinFloat,
  r : @bin_float.BinFloat,
  p : Int32,
) -> (@bin_float.BinFloat, @bin_float.BinFloat, @bin_float.BinFloat) {
  let wide = @bin_float.BinaryContext::new(precision=600)
  let up = @bin_float.BinaryContext::new(
    precision=p,
    rounding=BinaryRoundingMode::RoundTowardPositive,
  )
  let rounded = c.with_precision(
    p,
    @bin_float.BinaryRoundingMode::RoundTiesToEven,
  )
  let error = if c.compare(rounded) >= 0 {
    c.sub_ctx(rounded, up).0
  } else {
    rounded.sub_ctx(c, up).0
  }
  let radius = r.with_precision(
    p,
    @bin_float.BinaryRoundingMode::RoundTowardPositive,
  )
  let total = radius.add_ctx(error, up).0
  (rounded.sub_ctx(total, wide).0, rounded.add_ctx(total, wide).0, rounded)
}

///|
test "the endpoints of BallFloat::new are the exact center minus and plus the radius" {
  let state = Ref(0x2545f4914f6cdd1dUL)
  let e_min = @bin_float.binary_implementation_e_min
  for _ in 0..<4000 {
    let bits = 1 + (ne_next(state) % 60UL).to_int()
    let c = ne_value(
      (ne_next(state) % (1UL << bits)) | 1UL,
      e_min - 70 + (ne_next(state) % 90UL).to_int(),
      200,
    )
    let r = ne_value(
      ne_next(state) % 1000UL + 1UL,
      e_min - 70 + (ne_next(state) % 90UL).to_int(),
      200,
    )
    let precisions = [24, 53, 113]
    let p = precisions[(ne_next(state) % 3UL).to_int()]
    let ball = BallFloat::new(c, r, precision=p)
    let (lo, hi, rounded) = ne_expected(c, r, p)
    if ball.lower_bound().compare(lo) != 0 ||
      ball.upper_bound().compare(hi) != 0 {
      abort(
        "center \{c} radius \{r} p \{p}: expected [\{lo}, \{hi}], got [\{ball.lower_bound()}, \{ball.upper_bound()}]",
      )
    }
    // symmetric around the rounded center
    assert_eq(ball.midpoint().compare(rounded), 0)
  }
}

///|
test "away from the bottom of the range the endpoints are unchanged" {
  let state = Ref(0x9e3779b97f4a7c15UL)
  for _ in 0..<3000 {
    let c = ne_value(
      ne_next(state) % 1000000UL + 1UL,
      (ne_next(state) % 400UL).to_int() - 200,
      53,
    )
    let r = ne_value(
      ne_next(state) % 1000UL + 1UL,
      (ne_next(state) % 400UL).to_int() - 250,
      53,
    )
    let ball = BallFloat::new(c, r, precision=53)
    let (lo, hi, _) = ne_expected(c, r, 53)
    assert_eq(ball.lower_bound().compare(lo), 0)
    assert_eq(ball.upper_bound().compare(hi), 0)
  }
}

///|
test "the first case of the issue" {
  // center 133022375522373997 * 2^-1073741877 (57 bits, stored at 200), radius
  // 389 * 2^-1073741869, 53 bits: the ball was
  // [8313623592241431, 8314173348055319] * 2^-1073741873, it is
  // [16627796940284301, 16627796940309199] * 2^-1073741874
  let c = ne_value(133022375522373997UL, -1073741877, 200)
  let r = ne_value(389UL, -1073741869, 200)
  let ball = BallFloat::new(c, r, precision=53)
  inspect(
    ball.lower_bound().to_string(),
    content="16627796940284301p-1073741874",
  )
  inspect(
    ball.upper_bound().to_string(),
    content="16627796940309199p-1073741874",
  )
}
