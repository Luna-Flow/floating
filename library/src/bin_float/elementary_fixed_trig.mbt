///|
/// Enclosure of `sin(value)` or `cos(value)` for a nonzero `value` with
/// `|value| <= 1` that is exact at the working precision, by the Taylor series
/// in fixed point; `None` when the argument is not covered (the general series
/// then runs).
///
/// With `|value| = x`, everything is measured in units of `2^-F`,
/// `F = work + 20 + lz` for the sine and `work + 20` for the cosine, where
/// `2^-lz <= x`, so the sine keeps `work + 20` significant bits for a small
/// argument. `X = x 2^F` is an integer because `x` has at most `work` bits
/// below its leading bit. The computed terms are `Q = floor(X^2 / 2^F)`,
/// `T(0) = X` (sine) or `2^F` (cosine) and
/// `T(k) = floor(floor(T(k-1) Q / 2^F) / D(k))` with `D(k) = 2k (2k + 1)`
/// (sine) or `(2k - 1) 2k` (cosine). Each is at most the exact term, and the
/// exact term minus it, `d(k)`, satisfies `d(k) <= (d(k-1) x^2 + 2) / D(k) + 1`
/// (the floors lose less than 1 each and `Q` is short by less than 1, which
/// weighs at most `T(k-1) / 2^F <= 1`), hence `d(k) <= 4` by induction since
/// `D(k) >= 2` and `x <= 1`. The series alternates with terms that decrease in
/// magnitude (`x^2 / D(k) < 1`), so after the computed `T(n) < 2^4` the omitted
/// tail is at most the exact `T(n) <= T(n) + 4` in size. With
/// `S = T(0) - T(1) + T(2) - ...` over the computed terms before `n`, the
/// value lies within `4n + 2^4 + 4` of `S`. The sign of a negative sine
/// argument flips the enclosure.
fn binary_sin_cos_fixed_series(
  value : BinFloat,
  cosine : Bool,
  work_precision : Int32,
) -> (BinFloat, BinFloat)? {
  guard value.classify() == FpClass::Finite && !value.is_zero() else {
    return None
  }
  let rounded = value.with_precision(
    work_precision,
    RoundingMode::TowardNegative,
  )
  guard rounded.compare(value) == 0 else { return None }
  let coefficient = value.coefficient()
  let exponent = value.exponent2()
  let top = exponent + coefficient.bit_length() - 1
  guard top <= 0 else { return None }
  // |value| < 2^(top + 1) <= 2 would allow values up to 2; the series bounds
  // above need |value| <= 1.
  guard top < 0 || (coefficient.bit_length() == 1 && exponent == 0) else {
    return None
  }
  let lz = if cosine { 0 } else { -top }
  guard lz <= 4 * work_precision + 64 else { return None }
  let fractional = work_precision + 20 + lz
  guard fractional + exponent >= 0 else { return None }
  let x_fixed = coefficient.shift_left(fractional + exponent)
  let square = x_fixed.mul(x_fixed).shift_right(fractional)
  let stop = BinCoeff::one().shift_left(4)
  let mut term = if cosine {
    BinCoeff::one().shift_left(fractional)
  } else {
    x_fixed
  }
  let mut positive_sum = term
  let mut negative_sum = BinCoeff::zero()
  let mut index = 0
  while index < 10000 {
    index += 1
    let k = index.to_uint64()
    let divisor = if cosine {
      (2UL * k - 1UL) * (2UL * k)
    } else {
      2UL * k * (2UL * k + 1UL)
    }
    term = term.mul(square).shift_right(fractional)
    term = term.div_rem_checked(BinCoeff::from_uint64(divisor)).unwrap().0
    if term.compare(stop) < 0 {
      let slack = BinCoeff::from_uint64((4 * index + 24).to_uint64())
      let signed_sum = positive_sum.sub_checked(negative_sum).unwrap()
      let lower = BinFloat::make(
        signed_sum.sub_checked(slack).unwrap(),
        -fractional,
        work_precision,
        mode=RoundingMode::TowardNegative,
      )
      let upper = BinFloat::make(
        signed_sum.add(slack),
        -fractional,
        work_precision,
        mode=RoundingMode::TowardPositive,
      )
      return if cosine || !value.is_negative() {
        Some((lower, upper))
      } else {
        Some((upper.neg(), lower.neg()))
      }
    }
    if index % 2 == 1 {
      negative_sum = negative_sum.add(term)
    } else {
      positive_sum = positive_sum.add(term)
    }
  }
  None
}
