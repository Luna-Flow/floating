///|
/// `binary_ln_agm_min_precision`, the working precision from which the
/// arithmetic-geometric-mean enclosure replaces the Newton step for `ln` of a
/// number in `(1, 2]`, is per-target policy and lives with the coefficient-kernel
/// thresholds. It applies to the outermost call only (see
/// `binary_ln_unit_bounds`): `ln 2` and the constants are computed without it.

///|
/// Test hooks that make the kernel wrong on purpose.
priv struct AgmLnMutation {
  /// Bits taken away from the working precision.
  precision_drop : Int32
  /// Omit the model term `4 / s^2` of the lower end.
  drop_model : Bool
  /// Stop the mean after this many iterations (0: iterate to convergence).
  iteration_cap : Int32
  /// Bits taken away from the precision of `ln 2`.
  ln2_drop : Int32
}

///|
let agm_ln_no_mutation : AgmLnMutation = {
  precision_drop: 0,
  drop_model: false,
  iteration_cap: 0,
  ln2_drop: 0,
}

///|
/// `x * 2^k` for a finite value, exactly.
fn binary_scale_pow2(x : BinFloat, k : Int32) -> BinFloat {
  BinFloat::make_coeff(
    x.coefficient_,
    x.exponent2() + k,
    x.precision(),
    negative=x.negative,
  )
}

///|
/// The arithmetic-geometric mean of `1` and `x` (`0 < x < 1`, a finite value)
/// by the plain iteration `u' = sqrt(u v)`, `v' = (u + v) / 2`, every operation
/// rounded to nearest at `p` bits, until `|u - v| < 16 2^-p v` (tested through the
/// exponents: `|u - v| < 2^(top(v) - p + 3) <= 16 2^-p v`; two nearest-rounded
/// means of `p` bits can stay one unit apart, so a tolerance below that never
/// stops). Returns the last `v` and the number `n` of
/// iterations, `None` when the mean does not settle in 64 iterations.
///
/// Error: with `U_k, V_k` the exact sequence started at `(1, x)` and
/// `u_k = U_k (1 + a_k)`, `v_k = V_k (1 + b_k)`, `|a_k|, |b_k| <= eps_k`, one step
/// rounds a product, a square root and a sum, so `eps_{k+1} <= eps_k + 2 2^-p`
/// up to second order, and the first step multiplies by `1` exactly:
/// `eps_n <= (2 n + 1) 2^-p (1 + 2^-(p - 8))`, below the `(3 n + 4) 2^-p` that
/// the caller uses. `AG(U_n, V_n)` lies between `U_n` and `V_n`, which differ by
/// at most `16 2^-p v + 2 eps_n v (1 + eps_n)`, so `|AG - v_n| <= (9 n + 29) 2^-p v`
/// with the `2^-p` of the rounded `x`.
fn binary_agm_one(
  x : BinFloat,
  p : Int32,
  iteration_cap~ : Int32 = 0,
) -> (BinFloat, Int32)? {
  let context = BinaryContext::unbounded(p)
  let mut u = x
  let mut v = BinFloat::one_raw(precision=p)
  let mut n = 0
  while n < 64 {
    let next_u = u.mul_ctx(v, context).0.sqrt_ctx(context).0
    let next_v = binary_scale_pow2(u.add_ctx(v, context).0, -1)
    u = next_u
    v = next_v
    n += 1
    let difference = if u.compare(v) <= 0 {
      v.sub_ctx(u, context).0
    } else {
      u.sub_ctx(v, context).0
    }
    if (iteration_cap > 0 && n >= iteration_cap) ||
      difference.is_zero() ||
      binary_top_bound(difference) <= binary_top_bound(v) - p.to_int64() + 3 {
      return Some((v, n))
    }
  }
  None
}

///|
/// Enclosure of `ln(v)` for `1 + 2^-16 < v <= 2` (`v` an exact dyadic number of
/// any length) by the arithmetic-geometric mean, `None` when a precondition
/// fails (the caller then runs the Newton step or the series).
///
/// With `s = v 2^m`, `m = ceil(p / 2) + 2`, so that `s > 2^(p / 2 + 2)`:
/// `ln v = ln s - m ln 2` and `F (1 - 4 / s^2) <= ln s <= F` for
/// `F = pi / (2 AG(1, 4 / s))` (the model bound, taken from the literature, see
/// the design page). `AG` is increasing in each argument and homogeneous of
/// degree one, so the relative error `2^-p` of the rounded `x = 4 / s` moves `AG`
/// by at most that much; `binary_agm_one` gives `AG(1, x)` within the relative
/// error `e = (9 n + 30) 2^-p`; `pi` and `ln 2` are the cached directed bounds;
/// the divisions and the subtraction are directed. The working precision is
/// `p = w + (2 - lead) + bit_length(w) + 16`, which keeps the width of the
/// result below `2^-(w + 3)` (checked, as in the Newton step, not assumed).
fn binary_ln_unit_agm_bounds(
  value : BinFloat,
  work_precision : Int32,
  mutation~ : AgmLnMutation = agm_ln_no_mutation,
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
  let difference = value.sub_ctx(
      BinFloat::one_raw(precision=2),
      BinaryContext::unbounded(value.coefficient_.bit_length() + 8),
    ).0
  let lead = binary_top_bound(difference).to_int()
  let inner = work_precision + Int32::max(0, 2 - lead)
  let p = inner + binary_bit_length_i32(inner) + 16 - mutation.precision_drop
  guard p >= 64 else { return None }
  let m = (p + 1) / 2 + 2
  let down = BinaryContext::unbounded(p, rounding=RoundTowardNegative)
  let up = BinaryContext::unbounded(p, rounding=RoundTowardPositive)
  let nearest = BinaryContext::unbounded(p)
  // x = 4 / s = (4 / v) 2^-m.
  let four = BinFloat::from_int_raw(4, precision=3)
  let quotient = four.div_ctx(value, nearest).0
  let x = binary_scale_pow2(quotient, -m)
  guard binary_agm_one(x, p, iteration_cap=mutation.iteration_cap)
    is Some((mean, iterations)) else {
    return None
  }
  guard iterations >= 1 else { return None }
  let n = iterations
  // e = (9 n + 30) 2^-p; AG in [mean (1 - e), mean (1 + e)].
  let e = BinFloat::make_coeff(
    Coeff::from_uint64((9 * n + 30).to_uint64()),
    -p,
    32,
  )
  let spread = mean.mul_ctx(e, up).0
  let mean_high = mean.add_ctx(spread, up).0
  let mean_low = mean.sub_ctx(spread, down).0
  guard binary_pi_bounds(p + 8) is Some((pi_low, pi_high)) else { return None }
  // F in [pi_low / (2 mean_high), pi_high / (2 mean_low)].
  let f_low = binary_scale_pow2(pi_low.div_ctx(mean_high, down).0, -1)
  let f_high = binary_scale_pow2(pi_high.div_ctx(mean_low, up).0, -1)
  // ln s >= F (1 - 4 / s^2) >= F (1 - 2^-(p + 2)); the term taken is 16 times that
  // (4 / s^2 < 2^-(p + 2)), so the model constant has this much slack.
  let model_low = if mutation.drop_model {
    f_low
  } else {
    f_low.sub_ctx(binary_scale_pow2(f_low, -(p - 2)), down).0
  }
  let ln2_precision = p + 16 - mutation.ln2_drop
  guard binary_ln2_bounds(ln2_precision) is Some((ln2_low, ln2_high)) else {
    return None
  }
  let wide = 64 + binary_bit_length_i32(m)
  let multiplier = BinFloat::from_int_raw(m, precision=wide)
  let shift_low = ln2_low.mul_ctx(
      multiplier,
      BinaryContext::unbounded(
        ln2_precision + wide,
        rounding=RoundTowardNegative,
      ),
    ).0
  let shift_high = ln2_high.mul_ctx(
      multiplier,
      BinaryContext::unbounded(
        ln2_precision + wide,
        rounding=RoundTowardPositive,
      ),
    ).0
  let result_precision = p + 16
  let low = model_low.sub_ctx(
      shift_high,
      BinaryContext::unbounded(result_precision, rounding=RoundTowardNegative),
    ).0
  let high = f_high.sub_ctx(
      shift_low,
      BinaryContext::unbounded(result_precision, rounding=RoundTowardPositive),
    ).0
  // Width check: at most 8 units of `2^-inner`.
  let width = high.sub_ctx(
      low,
      BinaryContext::unbounded(result_precision, rounding=RoundTowardPositive),
    ).0
  let limit = BinFloat::make_coeff(Coeff::one(), -(inner - 3), 1)
  guard width.compare(limit) <= 0 else { return None }
  Some(
    (
      low.with_precision(work_precision, RoundingMode::TowardNegative),
      high.with_precision(work_precision, RoundingMode::TowardPositive),
    ),
  )
}

///|
fn binary_bit_length_i32(value : Int32) -> Int32 {
  let mut bits = 0
  let mut rest = value
  while rest > 0 {
    bits += 1
    rest = rest >> 1
  }
  bits
}
