///|
// Shared decisions of the IEEE 754-2019 9.2 functions that every new decimal
// operation must not re-implement (issue #236): the exact results and their
// cohort, the certain out-of-range results, and the exact-case gates in front
// of the certified Ziv driver (`decimal_certified_unary_result`).
//
// A result is only ever produced by rounding an exact decimal with the context
// (`decimal_apply_finite_ctx`), by a far-endpoint representative that rounds
// identically in all eight modes, or by a certified enclosure. Nothing here
// returns a zero or an infinity because a value is "small" or "large": the
// subnormal, Underflow, Overflow, Clamped and sign-of-zero behaviour is always
// that of the context rounding.

///|
/// An exact result `(-1)^negative * coefficient * 10^exponent10` of a 9.2
/// function, rounded once by the context and then moved to the cohort member
/// closest to `preferred` (IEEE 754-2019 9.2.2 and 5.2). A context whose
/// precision or exponent range cannot hold the value rounds it, with the flags
/// of that rounding; an inexact result keeps the least exponent.
fn decimal_exact_constant(
  negative : Bool,
  coefficient : DecCoeff,
  exponent10 : Int32,
  preferred : Int64,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  let exact = finite_with_exponent_repr(
    negative,
    coefficient,
    exponent10,
    Int32::max(1, coefficient.digits10()),
  )
  let rounded = decimal_apply_finite_ctx(exact, decimal_math_result_ctx(ctx))
  decimal_power_adjust_exact_cohort(rounded, preferred, ctx)
}

///|
/// Decides a positive result `f` from a certified bracket `[low, high]` of
/// `log2 f` (128-bit binary bounds) when `f` is certainly beyond
/// `10^(e_max + 2)` or certainly below `10^(etiny - 2)`. Such a value rounds
/// like the representative `10^(e_max + 2)` (overflow) or `10^(etiny - 2)`
/// (below half the smallest subnormal) in every rounding mode, so the result
/// and its flags are those of rounding the representative with the context.
/// Returns `None` when the bracket does not decide.
fn decimal_range_from_log2_bracket(
  low : @bin_float.BinFloat,
  high : @bin_float.BinFloat,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags)? {
  let work = 128
  let huge = ctx.e_max.to_int64() + 2L
  let tiny = etiny(ctx).to_int64() - 2L
  // log2(10) < 3.322, so these bounds are conservative on both sides.
  let overflow_log2 = (huge * 3322L + 999L) / 1000L
  let tiny_log2 = (tiny * 3322L - 999L) / 1000L
  let one = BigInt::from_int(1)
  let overflow_bound = @bin_float.BinFloat::from_string(
    overflow_log2.to_string(),
    precision=work,
  ).unwrap()
  let tiny_bound = @bin_float.BinFloat::from_string(
    tiny_log2.to_string(),
    precision=work,
  ).unwrap()
  if low.compare(overflow_bound) >= 0 {
    return Some(
      decimal_apply_finite_ctx(
        finite_with_exponent(false, one, huge.to_int(), 1),
        decimal_math_result_ctx(ctx),
      ),
    )
  }
  if high.compare(tiny_bound) <= 0 {
    return Some(
      decimal_apply_finite_ctx(
        finite_with_exponent(false, one, tiny.to_int(), 1),
        decimal_math_result_ctx(ctx),
      ),
    )
  }
  None
}

///|
/// `2^k mod 10^9` for `k >= 0`.
fn decimal_pow2_mod_1e9(k : Int64) -> Int64 {
  let modulus = 1_000_000_000L
  let mut result = 1L
  let mut base = 2L
  let mut e = k
  while e > 0L {
    if (e & 1L) == 1L {
      result = result * base % modulus
    }
    base = base * base % modulus
    e = e >> 1
  }
  result
}

///|
/// `5^k mod 10^9` for `k >= 0`.
fn decimal_pow5_mod_1e9(k : Int64) -> Int64 {
  let modulus = 1_000_000_000L
  let mut result = 1L
  let mut base = 5L
  let mut e = k
  while e > 0L {
    if (e & 1L) == 1L {
      result = result * base % modulus
    }
    base = base * base % modulus
    e = e >> 1
  }
  result
}

///|
/// The `k` with `value = 2^k`, if any. A coefficient of `D` digits can only be
/// one of the three or four powers of two with `D` digits; each candidate is
/// first compared on the lowest unit (`mod 10^9`) and only a match forms the
/// power, so a long coefficient costs a few modular exponentiations.
fn decimal_coeff_power_of_two_exponent(value : DecCoeff) -> Int64? {
  guard !value.is_zero() else { return None }
  let digits = value.digits10()
  if digits <= 9 {
    let small = dec_coeff_limb_at(value, 0).to_int64()
    guard (small & (small - 1L)) == 0L else { return None }
    let mut k = 0L
    let mut v = small
    while v > 1L {
      v = v >> 1
      k = k + 1L
    }
    return Some(k)
  }
  let low = dec_coeff_limb_at(value, 0).to_int64()
  // 2^k has D digits for (D - 1) log2(10) <= k < D log2(10).
  let log2_10 = 3.321928094887362
  let first = ((digits - 1).to_double() * log2_10).to_int64() - 2L
  let last = (digits.to_double() * log2_10).to_int64() + 2L
  for k = Int64::max(30L, first); k <= last; k = k + 1L {
    if decimal_pow2_mod_1e9(k) != low {
      continue
    }
    guard k <= 2147483647L else { return None }
    let power = dec_coeff_pow_unit_repr(2, k.to_int())
    if dec_coeff_compare_repr(power, value) == 0 {
      return Some(k)
    }
  }
  None
}

///|
/// Whether `value = 10^m - 5^m`, the coefficient of `1 - 2^-m` at exponent
/// `-m`. The candidate has exactly `m` digits and ends in 5; the lowest unit
/// is compared before the power is formed.
fn decimal_coeff_is_ten_minus_five_power(value : DecCoeff, m : Int32) -> Bool {
  guard m >= 1 && value.digits10() == m else { return false }
  let low = dec_coeff_limb_at(value, 0).to_int64()
  guard low % 10L == 5L else { return false }
  if m >= 9 {
    let expected = (1_000_000_000L - decimal_pow5_mod_1e9(m.to_int64())) %
      1_000_000_000L
    guard low == expected else { return false }
  }
  let candidate = dec_coeff_magnitude_sub_repr(
    dec_coeff_power10_repr(m),
    dec_coeff_pow_unit_repr(5, m),
  )
  dec_coeff_compare_repr(candidate, value) == 0
}
