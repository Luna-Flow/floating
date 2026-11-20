///|
/// Enclosure of `ln(value)` for `1 < value <= 2` that is exact at the working
/// precision, by the series `ln v = 2 * sum z^(2k+1) / (2k+1)` with
/// `z = (v - 1) / (v + 1) <= 1/3`, in fixed point; `None` when the argument is
/// not exact, not in range, or so close to 1 that the general path is cheaper.
///
/// Everything is measured in units of `2^-F` with `F = work + 16 + lz`, where
/// `2^-lz` is about `z`, so the result keeps `work + 16` significant bits even
/// when `z` is small. The computed quantities are `Z = floor(z 2^F)`,
/// `Q = floor(Z^2 / 2^F)`, `P(0) = Z`, `P(k) = floor(P(k-1) Q / 2^F)` and the
/// terms `T(k) = floor(P(k) / (2k + 1))`. Every one is at most its exact
/// counterpart (all are nonnegative, every operation rounds down and `Z <=
/// z 2^F`), so `sum T` is a lower bound. For the error `d(k)` of `P(k)`,
/// `Q >= Z^2 / 2^F - 1 >= z^2 2^F - 2 z - 1 > z^2 2^F - 5/3`, so
/// `d(k) <= d(k-1) / 9 + (5/3) / 3 + 1 < d(k-1) / 9 + 1.56`, `d(0) < 1`, hence
/// `d(k) < 2` and each term is short by less than `2 / (2k + 1) + 1 < 2`.
/// When `P(n) < 2^6` the omitted terms sum to at most `P(n) / (2n + 1) / (1 -
/// z^2)`, below the exact `P(n) < 2^6 + 2` (`2n + 1 >= 3`, `1 - z^2 >= 8/9`),
/// so `sum T + 2n + 2^6 + 6` bounds the sum from above.
fn binary_ln_unit_fixed_bounds(
  value : BinFloat,
  work_precision : Int32,
) -> (BinFloat, BinFloat)? {
  guard value.classify() == FpClass::Finite &&
    !value.is_zero() &&
    !value.is_negative() else {
    return None
  }
  let rounded = value.with_precision(
    work_precision,
    RoundingMode::TowardNegative,
  )
  guard rounded.compare(value) == 0 else { return None }
  let one = BinFloat::one(precision=work_precision)
  guard value.compare(one) > 0 &&
    value.compare(BinFloat::from_int(2, precision=work_precision)) <= 0 else {
    return None
  }
  let coefficient = value.coefficient_
  let exponent = value.exponent2()
  let (scaled_value, unit_shift) = if exponent >= 0 {
    (coefficient.shift_left(exponent), 0)
  } else {
    (coefficient, -exponent)
  }
  let unit = Coeff::one().shift_left(unit_shift)
  let numerator = scaled_value.sub_checked(unit).unwrap()
  let denominator = scaled_value.add(unit)
  // z = numerator / denominator lies in (0, 1/3] and 2^-lz <= 2z.
  let lz = denominator.bit_length() - numerator.bit_length() + 1
  guard lz <= 4 * work_precision + 64 else { return None }
  let fractional = work_precision + 16 + lz
  let z = numerator.shift_left(fractional).div_rem_checked(denominator).unwrap().0
  let square = z.mul(z).shift_right(fractional)
  let stop = Coeff::one().shift_left(6)
  let mut power = z
  let mut sum = z
  let mut index = 0
  while index < 10000 {
    index += 1
    power = power.mul(square).shift_right(fractional)
    if power.compare(stop) < 0 {
      let slack = Coeff::from_uint64((2 * index + 70).to_uint64())
      let lower = BinFloat::make_coeff(
        sum.shift_left(1),
        -fractional,
        work_precision,
        mode=RoundingMode::TowardNegative,
      )
      let upper = BinFloat::make_coeff(
        sum.add(slack).shift_left(1),
        -fractional,
        work_precision,
        mode=RoundingMode::TowardPositive,
      )
      return Some((lower, upper))
    }
    let divisor = Coeff::from_uint64((2 * index + 1).to_uint64())
    sum = sum.add(power.div_rem_checked(divisor).unwrap().0)
  }
  None
}
