// Shared layer of the IEEE 754-2019 9.2 functions added after the range audit
// of #271, #272, #273, #274, #275, #278, #289, #293, #315 and #316. Every
// function of the family `exp2m1`, `exp10m1`, `log2p1`, `log10p1` (and those of
// the following families) takes its decisions here, so that none of the
// patterns that caused those defects can be written again:
//
// - a signaling NaN is checked before any shortcut (`binary_nan_unary`);
// - an exact result is rounded as a dyadic by `binary_round_dyadic`, never
//   built by `BinFloat::make`, which flushes a value below 2^(e_min - (w - 1))
//   at its own width w;
// - a result certainly outside the range is decided from certified log2
//   brackets before the Ziv loop (`binary_positive_exp_minus_one_overflow`);
// - the Ziv loop is one driver (`binary_ziv_round`).

///|
/// A NaN operand: a quiet NaN with the sign and payload of the operand, and
/// `invalid` when it is signaling (IEEE 754-2019 6.2, 7.2 a).
fn binary_nan_unary(
  value : BinFloat,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags)? {
  if value.class() == FpClass::NaN {
    Some(
      (
        binary_quiet_nan(value, context.precision),
        if value.signaling() {
          binary_invalid_flags()
        } else {
          BinaryFlags::new()
        },
      ),
    )
  } else {
    None
  }
}

///|
/// A pole: a signed infinity with `divideByZero` (IEEE 754-2019 7.3).
fn binary_pole_result(
  negative : Bool,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  (
    BinFloat::inf_raw(
      if negative {
        Sign::Negative
      } else {
        Sign::Positive
      },
      precision=context.precision,
    ),
    binary_division_by_zero_flags(),
  )
}

///|
/// An integer result (such as log2 of an exact power of two), rounded as a
/// dyadic: exact when it fits the context, with the flags of the context
/// otherwise.
fn binary_integer_result(
  value : Int32,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  let magnitude = if value < 0 { -value.to_int64() } else { value.to_int64() }
  binary_round_dyadic(
    value < 0,
    Coeff::from_uint64(magnitude.reinterpret_as_uint64()),
    0,
    context,
  )
}

///|
/// The result of `x -> -1 + d` with `0 < d < 2^-(p + 3)`: the rounding
/// direction alone decides between `-1` and the value below it in magnitude,
/// `-(1 - 2^-p)`. Used where the function saturates towards -1 (`exp2m1` and
/// `exp10m1` of a large negative argument); always inexact, never underflow.
fn binary_saturated_minus_one(
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  let toward_zero = match context.rounding {
    RoundTowardZero | RoundTowardPositive => true
    RoundTiesToEven | RoundTiesToAway | RoundTowardNegative => false
  }
  let result = if toward_zero {
    finite_from_parts(
      true,
      Coeff::one()
      .shift_left(context.precision)
      .sub_checked(Coeff::one())
      .unwrap(),
      -context.precision,
      context.precision,
    )
  } else {
    BinFloat::one_raw(precision=context.precision).neg()
  }
  (result, binary_inexact_flags(false))
}

///|
/// The correctly rounded `2^n - 1` for an integer `n > 0`, or `1 - 2^-k`
/// negated for `n = -k < 0`, that is `2^n - 1` for any integer `n != 0`.
/// Exact (or a rounding tie) while the value has at most `p + 1` bits; beyond
/// that it lies strictly between the midpoint below the power of two and the
/// power of two, where any value of that open interval rounds alike in every
/// direction, so the representative `2^(p + 2) - 1` scaled to the same binade
/// stands for it, without forming `2^n - 1` for a huge `n`.
fn binary_pow2_minus_one_integer(
  n : Int32,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  let p = context.precision
  let all_ones = fn(bits : Int32) {
    Coeff::one().shift_left(bits).sub_checked(Coeff::one()).unwrap()
  }
  if n > 0 {
    if n <= p + 1 {
      binary_round_dyadic(false, all_ones(n), 0, context)
    } else {
      binary_round_dyadic(false, all_ones(p + 2), n - (p + 2), context)
    }
  } else {
    let k = -n
    if k <= p + 1 {
      binary_round_dyadic(true, all_ones(k), n, context)
    } else {
      binary_round_dyadic(true, all_ones(p + 2), -(p + 2), context)
    }
  }
}

///|
/// Overflow of `f(x) = b^x - 1` for `x >= 1` decided from certified bounds of
/// `log2(b)` (`scale_bounds`, below `2^scale_bits`): `b^x - 1 >= b^x / 2`, and
/// for `x >= 64` even `b^x - 1 >= b^(x - 2^-60)`, which decides the window
/// `[e_max + 1, e_max + 2)` in log2 that the offset of the first form leaves
/// open (the case fixed for `expm1` in #274). `None` when the bounds do not
/// decide it; the Ziv loop works in unbounded contexts and cannot certify an
/// enclosure that itself overflows.
fn binary_positive_exp_minus_one_overflow(
  value : BinFloat,
  scale_bounds : () -> (BinFloat, BinFloat)?,
  scale_bits : Int32,
  base_is_two : Bool,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags)? {
  if value.is_negative() || value.compare(BinFloat::one_raw()) < 0 {
    return None
  }
  if value.compare(BinFloat::from_int_raw(64, precision=7)) >= 0 {
    // Base 2, L = e_max + 1 >= 64 and x > L with x - L >= 2^(-L + 1) (a
    // multiple of 2^exponent2(x)): 2^x - 1 >= 2^L (1 + 2^(-L + 1) ln 2) - 1 >
    // 2^L, so the result is beyond the range. This decides x = L + tiny, which
    // the shifted form below cannot (it needs x >= L + 2^-60).
    if base_is_two {
      let limit = context.range_e_max() + 1
      if limit >= 64 &&
        value.compare(BinFloat::from_int_raw(limit, precision=53)) > 0 &&
        value.exponent2() > -limit {
        return Some(binary_overflow_result(false, context))
      }
    }
    return binary_log2_linear_out_of_range(
      value.sub_ctx(
        BinFloat::make_coeff(Coeff::one(), -60, 1),
        binary_working_context(
          binary_range_check_precision,
          rounding=RoundTowardNegative,
        ),
      ).0,
      scale_bounds,
      scale_bits,
      0,
      false,
      false,
      context,
    )
  }
  binary_log2_linear_out_of_range(
    value, scale_bounds, scale_bits, -1, false, false, context,
  )
}

///|
/// The Ziv driver: certified enclosures `[lower, upper]` of a result known to
/// be inexact at increasing working precisions until the context rounds both
/// ends alike (IEEE 754-2019 9.2: correctly rounded; 7.6: inexact; 7.5: both
/// tininess rules through `apply_ctx`). `bounds_at(work)` returns `None` when it
/// cannot enclose at that precision.
fn binary_ziv_round(
  operation : String,
  context : BinaryContext,
  bounds_at : (Int32) -> (BinFloat, BinFloat)?,
  edge_side? : (Int32) -> Bool?,
) -> Result[(BinFloat, BinaryFlags), @def.ArithmeticError] {
  let mut budget = CertifiedRefinementBudget::new(
    context.precision + 64,
    limit=context.refinement_limit,
  )
  while budget.available() {
    match bounds_at(budget.precision()) {
      Some(bounds) => {
        let (result, unique, flags) = match edge_side {
          // The enclosure overflows the implementation range: the side of the
          // argument against the overflow threshold decides
          // (`binary_certified_edge_rounding`).
          Some(side) =>
            binary_certified_edge_rounding(
              bounds.0,
              bounds.1,
              context,
              budget.precision(),
              false,
              fn() { side(budget.precision()) },
            )
          None =>
            binary_certified_inexact_target_rounding(
              bounds.0,
              bounds.1,
              context,
            )
        }
        if unique {
          return Ok((result, flags))
        }
      }
      None => ()
    }
    budget = budget.next()
  }
  Err(binary_refinement_failure_for(operation, context, budget))
}
