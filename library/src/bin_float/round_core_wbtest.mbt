///|
/// Test-only copy of the rounding core before #378 (rounds twice, no early
/// exit for bounded contexts, full normalization): the new `binary_round_dyadic`
/// must agree with it on value, representation and flags.

///|
fn old_finalize_rounded(
  negative : Bool,
  magnitude : Coeff,
  exponent2 : Int32,
  inexact : Bool,
  exact_top : Int32,
  unbounded_rounded_top : Int32,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  let rounded_top = if magnitude.is_zero() {
    exact_top
  } else {
    binary_exact_top(magnitude, exponent2)
  }
  if !magnitude.is_zero() && rounded_top > context.range_e_max() {
    return binary_overflow_result(negative, context)
  }
  let value = finite_from_parts(
    negative,
    magnitude,
    exponent2,
    context.precision,
  )
  if !inexact {
    return (value, BinaryFlags::new())
  }
  let e_min = context.range_e_min()
  let tiny = match context.tininess {
    BeforeRounding => exact_top < e_min
    AfterRounding => unbounded_rounded_top < e_min
  }
  (value, binary_inexact_flags(tiny))
}

///|
fn old_round_pack(
  negative : Bool,
  retained : Coeff,
  round_bit : Bool,
  sticky : Bool,
  exponent2 : Int32,
  exact_top : Int32,
  unbounded_rounded_top : Int32,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  old_finalize_rounded(
    negative,
    binary_apply_round_bits(
      retained,
      round_bit,
      sticky,
      negative,
      context.rounding,
    ),
    exponent2,
    round_bit || sticky,
    exact_top,
    unbounded_rounded_top,
    context,
  )
}

///|
fn old_round_dyadic(
  negative : Bool,
  magnitude : Coeff,
  exponent2 : Int32,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  if magnitude.is_zero() {
    return (
      finite_from_parts(negative, Coeff::zero(), 0, context.precision),
      BinaryFlags::new(),
    )
  }
  let bits = magnitude.bit_length()
  let exact_top = binary_exact_top(magnitude, exponent2)
  if bits <= context.precision &&
    context.e_min is None &&
    context.e_max is None &&
    exact_top >= binary_implementation_e_min &&
    exact_top <= binary_implementation_e_max {
    return (
      finite_from_parts(negative, magnitude, exponent2, context.precision),
      BinaryFlags::new(),
    )
  }
  let precision_shift = Int32::max(0, bits - context.precision)
  let (precision_retained, precision_guard, precision_sticky) = binary_split_shift(
    magnitude, precision_shift,
  )
  let precision_rounded = binary_apply_round_bits(
    precision_retained,
    precision_guard,
    precision_sticky,
    negative,
    context.rounding,
  )
  let unbounded_rounded_top = binary_exact_top(
    precision_rounded,
    binary_add_sat(exponent2, precision_shift),
  )
  let range_shift = Int32::max(
    0,
    binary_sub_sat(
      binary_sub_sat(context.range_e_min(), context.precision - 1),
      exponent2,
    ),
  )
  let shift = Int32::max(precision_shift, range_shift)
  let (retained, round_bit, sticky) = if shift == precision_shift {
    (precision_retained, precision_guard, precision_sticky)
  } else {
    binary_split_shift(magnitude, shift)
  }
  old_round_pack(
    negative,
    retained,
    round_bit,
    sticky,
    binary_add_sat(exponent2, shift),
    exact_top,
    unbounded_rounded_top,
    context,
  )
}

///|
struct RoundCoreRng {
  mut round_state : UInt64
}

///|
fn RoundCoreRng::next(self : RoundCoreRng) -> UInt64 {
  self.round_state = self.round_state * 6364136223846793005UL +
    1442695040888963407UL
  self.round_state >> 11
}

///|
fn round_test_magnitude(rng : RoundCoreRng) -> Coeff {
  let words = (rng.next() % 4UL).to_int() + 1
  let mut value = Coeff::from_uint64(rng.next() | 1UL)
  for _ in 1..<words {
    value = value.shift_left(40).add(Coeff::from_uint64(rng.next()))
  }
  // Random low zeros and a random trim to vary the bit length.
  let trim = (rng.next() % 70UL).to_int()
  let low = (rng.next() % 6UL).to_int()
  let shifted = value.shift_right(trim)
  let base = if shifted.is_zero() { Coeff::one() } else { shifted }
  base.shift_left(low)
}

///|
fn round_test_contexts() -> Array[BinaryContext] {
  let out : Array[BinaryContext] = []
  let modes = [
    BinaryRoundingMode::RoundTiesToEven,
    BinaryRoundingMode::RoundTiesToAway,
    BinaryRoundingMode::RoundTowardZero,
    BinaryRoundingMode::RoundTowardPositive,
    BinaryRoundingMode::RoundTowardNegative,
    BinaryRoundingMode::RoundAwayFromZero,
  ]
  for mode in modes {
    for
      tininess in [
        TininessDetection::BeforeRounding,
        TininessDetection::AfterRounding,
      ] {
      out.push(BinaryContext::binary16(rounding=mode, tininess~))
      out.push(BinaryContext::binary32(rounding=mode, tininess~))
      out.push(BinaryContext::binary64(rounding=mode, tininess~))
      out.push(
        BinaryContext::new(7, rounding=mode, e_min=-20, e_max=20, tininess~),
      )
      out.push(
        BinaryContext::new(1, rounding=mode, e_min=-3, e_max=3, tininess~),
      )
    }
    for precision in [1, 2, 5, 24, 53, 64, 100, 200] {
      out.push(BinaryContext::unbounded(precision, rounding=mode))
    }
  }
  out
}

///|
test "binary_round_dyadic agrees with the pre-#378 rounding core" {
  let rng : RoundCoreRng = { round_state: 20261120UL, }
  let contexts = round_test_contexts()
  let mut checked = 0
  for context in contexts {
    let e_lo = match context.e_min() {
      Some(v) => v
      None => -300
    }
    let e_hi = match context.e_max() {
      Some(v) => v
      None => 300
    }
    for _ in 0..<150 {
      let magnitude = round_test_magnitude(rng)
      let bits = magnitude.bit_length()
      // Exponents around the range boundaries of the context, plus wide ones.
      let pick = (rng.next() % 5UL).to_int()
      let exponent2 = match pick {
        0 => e_lo - bits - 70 + (rng.next() % 140UL).to_int()
        1 => e_hi - bits + (rng.next() % 6UL).to_int() - 3
        2 => e_lo - context.precision + (rng.next() % 6UL).to_int() - 3
        3 => (rng.next() % 40UL).to_int() - 20
        _ => (rng.next() % 2000UL).to_int() - 1000
      }
      let negative = rng.next() % 2UL == 0UL
      let fresh = binary_round_dyadic(negative, magnitude, exponent2, context)
      let old = old_round_dyadic(negative, magnitude, exponent2, context)
      assert_eq(fresh.0, old.0)
      assert_eq(fresh.1, old.1)
      checked += 1
    }
  }
  assert_true(checked > 3000)
}

///|
test "binary_round_dyadic boundaries on both sides of the exact early exit" {
  // Exactly representable values at, just inside and just beyond the range.
  for context in round_test_contexts() {
    if context.e_min() is Some(e_min) && context.e_max() is Some(e_max) {
      let p = context.precision()
      for
        top in [
          e_min - 2,
          e_min - 1,
          e_min,
          e_min + 1,
          e_max - 1,
          e_max,
          e_max + 1,
        ] {
        for bits in [1, 2, p, p + 1] {
          if bits >= 1 {
            let magnitude = Coeff::one()
              .shift_left(bits - 1)
              .add(if bits > 1 { Coeff::one() } else { Coeff::zero() })
            let exponent2 = top - (bits - 1)
            for negative in [false, true] {
              let fresh = binary_round_dyadic(
                negative, magnitude, exponent2, context,
              )
              let old = old_round_dyadic(
                negative, magnitude, exponent2, context,
              )
              assert_eq(fresh.0, old.0)
              assert_eq(fresh.1, old.1)
            }
          }
        }
      }
    }
  }
}
