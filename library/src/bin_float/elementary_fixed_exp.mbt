///|
/// Guard bits of the fixed-point exponential series below the working
/// precision. With them the enclosure is about `2^-(work_precision + 7)` wide,
/// the width the floating-point series gave.
let binary_exp_fixed_guard_bits : Int32 = 16

///|
/// Enclosure of `exp(value)` for a nonzero finite `value` with `|value| <= 1/8`
/// by the Taylor series in fixed point, `None` outside that range.
///
/// Write `|value| = c / 2^s` and measure in units of `2^-F`, `F = work + 16`.
/// The computed terms are `t0 = 2^F` and
/// `t(i) = floor(floor(t(i-1) * c / 2^s) / i)`. Every `t(i)` is at most the
/// exact term, by induction, because both floors round down, so the sum of the
/// computed terms is a lower bound of `exp(|value|)`. The exact term minus the
/// computed one, `d(i)`, satisfies `d(i) < d(i-1) * |value| / i + 1/i + 1`
/// (the first floor loses less than 1 before the division by `i`, the second
/// less than 1 after it), hence `d(i) < 2.3 <= 3` for every `i`. After the last
/// computed term `t(n) < 2^8` the remaining exact terms sum to less than the
/// last exact term, which is at most `t(n) + 3`. So `S + 3n + t(n) + 4`, with
/// `S` the sum of the computed terms, is an upper bound. A negative `value`
/// gives `exp(value) = 1 / exp(|value|)` with directed division.
fn binary_exp_small_fixed_bounds(
  value : BinFloat,
  work_precision : Int32,
) -> (BinFloat, BinFloat)? {
  guard value.classify() == FpClass::Finite && !value.is_zero() else {
    return None
  }
  let shift = -value.exponent2()
  guard shift >= 3 else { return None }
  let magnitude = value.coefficient_
  guard magnitude.bit_length() <= shift - 2 else { return None }
  let fractional = work_precision + binary_exp_fixed_guard_bits
  guard fixed_exp_series(magnitude, shift, fractional, 10000)
    is Some((sum, term, index)) else {
    return None
  }
  let slack = Coeff::from_uint64((3 * index + 4).to_uint64())
  let lower = BinFloat::make_coeff(
    sum,
    -fractional,
    work_precision,
    mode=BinaryRoundingMode::RoundTowardNegative,
  )
  let upper = BinFloat::make_coeff(
    sum.add(term).add(slack),
    -fractional,
    work_precision,
    mode=BinaryRoundingMode::RoundTowardPositive,
  )
  if !value.is_negative() {
    return Some((lower, upper))
  }
  let one = BinFloat::one_raw(precision=work_precision)
  Some(
    (
      one.div_ctx(
        upper,
        binary_working_context(work_precision, rounding=RoundTowardNegative),
      ).0,
      one.div_ctx(
        lower,
        binary_working_context(work_precision, rounding=RoundTowardPositive),
      ).0,
    ),
  )
}

///|
/// `binary_exp_bounds` for an argument that is exact at the working precision
/// (`work_precision` bits cover it), the case of every elementary function
/// that works on a value rounded to the target precision: the argument is
/// halved until it is at most 1/8 and the fixed-point series bounds the small
/// exponential, which is then squared back with directed rounding as in the
/// general path. `None` when the argument is not exact or the series does not
/// apply, in which case the general path runs.
fn binary_exp_bounds_fixed(
  value : BinFloat,
  work_precision : Int32,
) -> (BinFloat, BinFloat)? {
  guard value.classify() == FpClass::Finite && !value.is_zero() else {
    return None
  }
  let lower = value.with_precision_raw(
    work_precision,
    BinaryRoundingMode::RoundTowardNegative,
  )
  guard lower.compare(value) == 0 else { return None }
  let downward = binary_working_context(
    work_precision,
    rounding=RoundTowardNegative,
  )
  let upward = binary_working_context(
    work_precision,
    rounding=RoundTowardPositive,
  )
  let eighth = BinFloat::make_coeff(Coeff::one(), -3, work_precision)
  let half = BinFloat::make_coeff(Coeff::one(), -1, work_precision)
  let mut reduced = lower
  let mut reductions = 0
  while reduced.abs().compare(eighth) > 0 && reductions < 4096 {
    reduced = reduced.mul_ctx(half, downward).0
    reductions += 1
  }
  guard reduced.abs().compare(eighth) <= 0 else { return None }
  guard binary_exp_small_fixed_bounds(reduced, work_precision)
    is Some((small_lower, small_upper)) else {
    return None
  }
  let mut result_lower = small_lower
  let mut result_upper = small_upper
  for _ in 0..<reductions {
    result_lower = result_lower.mul_ctx(result_lower, downward).0
    result_upper = result_upper.mul_ctx(result_upper, upward).0
  }
  Some((result_lower, result_upper))
}
