// `half_width` (the radius of the midpoint-radius view, shown as `center +/- half-width`) is
// the exact `(upper - lower) / 2` also below the normal range (issue #583). It
// was made at its own bit length and rounded upward there, to the quantum of a
// few bits.

///|
fn hw_next(state : Ref[UInt64]) -> UInt64 {
  let mut x = state.val
  x = x ^ (x << 13)
  x = x ^ (x >> 7)
  x = x ^ (x << 17)
  state.val = x
  x
}

///|
fn hw_value(c : UInt64, exponent : Int32) -> @bin_float.BinFloat {
  @bin_float.BinFloat::make(@bin_float.BinCoeff::from_uint64(c), exponent, 200)
}

///|
/// The oracle: `(upper - lower) / 2` by `sub_ctx` in 600 bits and a product
/// with 1/2.
fn hw_expected(interval : Interval) -> @bin_float.BinFloat {
  let wide = @bin_float.BinaryContext::new(precision=600)
  let half = @bin_float.BinFloat::make(@bin_float.BinCoeff::one(), -1, 1)
  interval.upper_bound().sub_ctx(interval.lower_bound(), wide).0.mul_ctx(
    half, wide,
  ).0
}

///|
test "the half-width of the interval of the issue" {
  let e_min = @bin_float.binary_implementation_e_min
  let interval = Interval::from_bounds(
    hw_value(1UL, e_min - 60),
    hw_value(3UL, e_min - 60),
    precision=113,
  )
  inspect(interval.half_width().to_string(), content="1p-1073741882")
  inspect(interval.center().to_string(), content="1p-1073741881")
  inspect(
    interval.to_midpoint_radius_string(),
    content="1p-1073741881 +/- 1p-1073741882",
  )
  // Show is the portable literal: bounds this far down the exponent range are written in
  // hexadecimal (a decimal expansion would need a power of ten of that size)
  inspect(interval.to_string(), content="[0x1p-1073741882, 0x3p-1073741882]")
}

///|
test "the half-width is exact near the bottom of the range" {
  let state = Ref(0x9e3779b97f4a7c15UL)
  let e_min = @bin_float.binary_implementation_e_min
  let precisions = [24, 53, 113, 128]
  for _ in 0..<3000 {
    let bits_x = 1 + (hw_next(state) % 60UL).to_int()
    let bits_y = 1 + (hw_next(state) % 60UL).to_int()
    let a = hw_value(
      (hw_next(state) % (1UL << bits_x)) | 1UL,
      e_min - 70 + (hw_next(state) % 90UL).to_int(),
    )
    let b = hw_value(
      (hw_next(state) % (1UL << bits_y)) | 1UL,
      e_min - 70 + (hw_next(state) % 90UL).to_int(),
    )
    let (lo, hi) = if a.compare(b) <= 0 { (a, b) } else { (b, a) }
    let interval = Interval::from_bounds(
      lo,
      hi,
      precision=precisions[(hw_next(state) % 4UL).to_int()],
    )
    assert_eq(interval.half_width().compare(hw_expected(interval)), 0)
  }
}

///|
test "away from the bottom of the range the half-width is unchanged" {
  let state = Ref(0x2545f4914f6cdd1dUL)
  for _ in 0..<3000 {
    let a = hw_value(
      hw_next(state) % 1000000UL + 1UL,
      (hw_next(state) % 400UL).to_int() - 200,
    )
    let b = hw_value(
      hw_next(state) % 1000000UL + 1UL,
      (hw_next(state) % 400UL).to_int() - 200,
    )
    let (lo, hi) = if a.compare(b) <= 0 { (a, b) } else { (b, a) }
    let interval = Interval::from_bounds(lo, hi, precision=53)
    let old = exact_half(
      exact_sub(
        min_bits=1,
        interval.upper_bound(),
        interval.lower_bound(),
        mode=BinaryRoundingMode::RoundTowardPositive,
      ),
      mode=BinaryRoundingMode::RoundTowardPositive,
    ).abs()
    assert_identical(interval.half_width(), old)
  }
}
