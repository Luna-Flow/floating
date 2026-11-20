///|
/// `binary_ln_burst_min_precision`, the working precision from which the
/// verified Newton step replaces the series for `ln` of a number in `(1, 2]`,
/// is per-target policy and lives with the coefficient-kernel thresholds.

///|
/// Arguments closer to 1 than this keep the series, whose terms then shrink
/// fast and whose enclosure stays relatively tight.
let binary_ln_burst_near_one_bits : Int32 = 16

///|
/// Test hooks that make the kernel wrong on purpose.
priv struct BurstLnMutation {
  /// Bits taken away from the start value's precision `work / 2 + 16`.
  start_bits_drop : Int32
  /// Omit the quadratic term of the lower end.
  drop_quadratic : Bool
  /// Add this many units of `2^-work` to the lower end.
  lower_bias : Int32
}

///|
let burst_ln_no_mutation : BurstLnMutation = {
  start_bits_drop: 0,
  drop_quadratic: false,
  lower_bias: 0,
}

///|
/// Enclosure of `ln(v)` for `1 + 2^-16 < v <= 2` (`v` an exact dyadic number of
/// any length) by one verified Newton step on `exp`, `None` when a precondition
/// fails (the caller then runs the series).
///
/// Let `y0` be a lower end of `ln(v')` at `w / 2 + 16` bits for `v'` the
/// rounding of `v` to that many bits; the enclosure of `ln v'` by the same
/// function one level down is a rigorous bound, so `|ln v - y0| < 2^-(w/2 + 12)`,
/// but the argument below does not use it: for any `y0`, `[E_l, E_u]` an
/// enclosure of `exp(y0)`, `q_l = RD(v / E_u) <= v / exp(y0) <= q_u = RU(v / E_l)`,
/// monotonicity of `ln` gives `ln v = y0 + ln(v / exp(y0)) in y0 + [ln q_l, ln q_u]`
/// and for `|q - 1| <= 1/2`, `(q - 1) - (q - 1)^2 <= ln q <= q - 1`. The result is
/// `[y0 + (q_l - 1) - (q_l - 1)^2, y0 + (q_u - 1)]` evaluated with directed
/// rounding. A poor `y0` only widens it (the quadratic term), which the width
/// check turns into `None`.
fn binary_ln_unit_burst_bounds(
  value : BinFloat,
  work_precision : Int32,
  mutation~ : BurstLnMutation = burst_ln_no_mutation,
) -> (BinFloat, BinFloat)? {
  guard value.classify() == FpClass::Finite &&
    !value.is_zero() &&
    !value.is_negative() else {
    return None
  }
  let two = BinFloat::from_int_raw(2, precision=2)
  let near_one = BinFloat::make_coeff(
    Coeff::one().shift_left(binary_ln_burst_near_one_bits).add(Coeff::one()),
    -binary_ln_burst_near_one_bits,
    binary_ln_burst_near_one_bits + 2,
  )
  guard value.compare(near_one) > 0 && value.compare(two) <= 0 else {
    return None
  }
  // `d = v - 1 >= 2^-16` and `ln v >= d / 2 >= 2^(top(d) - 2)`: work this many
  // bits more so that the result keeps `work_precision` significant bits.
  let difference = value.sub_ctx(
      BinFloat::one_raw(precision=2),
      binary_working_context(value.coefficient_.bit_length() + 8),
    ).0
  let lead = binary_top_bound(difference).to_int()
  let inner = work_precision + Int32::max(0, 2 - lead)
  let start_precision = inner / 2 + 16 - mutation.start_bits_drop
  guard start_precision >= 64 else { return None }
  let rounded = value.with_precision_raw(
    start_precision,
    BinaryRoundingMode::RoundTiesToEven,
  )
  guard binary_ln_unit_bounds(rounded, start_precision) is Some((start, _)) else {
    return None
  }
  // Below the nested-step threshold the argument is short enough for the
  // table kernel; from it on the table kernel measured slower than the burst
  // (see `binary_ln_burst_min_precision`), so `exp` is the burst enclosure.
  let exp_bounds = if work_precision < binary_ln_burst_min_precision {
    binary_exp_bounds(start, inner + 8)
  } else {
    binary_exp_bounds_burst(start, inner + 8)
  }
  guard exp_bounds is Some((exp_low, exp_high)) else { return None }
  let precision = inner + 24
  let downward = binary_working_context(precision, rounding=RoundTowardNegative)
  let upward = binary_working_context(precision, rounding=RoundTowardPositive)
  let one = BinFloat::one_raw(precision~)
  let half = BinFloat::make_coeff(Coeff::one(), -1, 1)
  let three_halves = BinFloat::make_coeff(Coeff::from_uint64(3UL), -1, 2)
  let quotient_low = value.div_ctx(exp_high, downward).0
  let quotient_high = value.div_ctx(exp_low, upward).0
  guard quotient_low.compare(half) >= 0 &&
    quotient_high.compare(three_halves) <= 0 else {
    return None
  }
  let offset_low = quotient_low.sub_ctx(one, downward).0
  let offset_high = quotient_high.sub_ctx(one, upward).0
  let square = offset_low.mul_ctx(offset_low, upward).0
  let mut low = start.add_ctx(offset_low, downward).0
  if !mutation.drop_quadratic {
    low = low.sub_ctx(square, downward).0
  }
  if mutation.lower_bias != 0 {
    low = low.add_ctx(
        BinFloat::make_coeff(
          Coeff::from_uint64(mutation.lower_bias.to_uint64()),
          -inner,
          64,
        ),
        upward,
      ).0
  }
  let high = start.add_ctx(offset_high, upward).0
  // Width check: at most 8 units of `2^-inner`.
  let width = high.sub_ctx(low, upward).0
  let limit = BinFloat::make_coeff(Coeff::one(), -(inner - 3), 1)
  guard width.compare(limit) <= 0 else { return None }
  Some(
    (
      low.with_precision_raw(
        work_precision,
        BinaryRoundingMode::RoundTowardNegative,
      ),
      high.with_precision_raw(
        work_precision,
        BinaryRoundingMode::RoundTowardPositive,
      ),
    ),
  )
}
