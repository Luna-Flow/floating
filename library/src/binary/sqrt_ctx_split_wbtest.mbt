///|
/// The split of the square root before the midpoint was decided by the
/// remainder: the radicand shifted and rooted by the kernel, the midpoint
/// decided by comparing `N` with `(2 root + 1)^2 / 4` (a full square). Kept
/// here as the private reference of `binary_sqrt_split`.
fn sqctx_split_reference(
  magnitude : Coeff,
  scale : Int32,
) -> (Coeff, Bool, Int32) {
  if scale >= 0 {
    let radicand = magnitude.shift_left(scale)
    let (root, remainder) = bin_coeff_sqrt_rem_kernel(radicand)
    let exact = remainder.is_zero()
    let midpoint = root.shift_left(1).add(Coeff::one()).square()
    (
      root,
      exact,
      magnitude.shift_left(binary_add_sat(scale, 2)).compare(midpoint),
    )
  } else if scale == binary_int_min {
    (Coeff::zero(), false, -1)
  } else {
    let denominator_shift = -scale
    let (root, _) = bin_coeff_sqrt_rem_kernel(
      magnitude.shift_right(denominator_shift),
    )
    let root_square = root.square()
    let exact = !root.is_zero() &&
      binary_compare_shifted(root_square, denominator_shift, magnitude, 0) == 0
    let midpoint = root.shift_left(1).add(Coeff::one()).square()
    (
      root,
      exact,
      binary_compare_shifted(magnitude, 2, midpoint, denominator_shift),
    )
  }
}

///|
/// `binary_round_sqrt` with the reference split.
fn sqctx_round_reference(
  magnitude : Coeff,
  exponent2 : Int32,
  context : BinaryContext,
) -> (Binary, BinaryFlags) {
  let exact_top = binary_floor_div2(binary_exact_top(magnitude, exponent2))
  if exact_top > context.range_e_max() {
    return binary_overflow_result(false, context)
  }
  let target_exponent = binary_target_exponent(exact_top, context)
  let scale = binary_sub_sat(exponent2, binary_mul_sat(2, target_exponent))
  let (floor_root, exact, midpoint_comparison) = sqctx_split_reference(
    magnitude, scale,
  )
  let (round_bit, sticky) = binary_sqrt_round_bits(exact, midpoint_comparison)
  let unbounded_target = binary_sub_sat(exact_top, context.precision - 1)
  let unbounded_scale = binary_sub_sat(
    exponent2,
    binary_mul_sat(2, unbounded_target),
  )
  let (unbounded_root, unbounded_exact, unbounded_midpoint_comparison) = if unbounded_scale ==
    scale {
    (floor_root, exact, midpoint_comparison)
  } else {
    sqctx_split_reference(magnitude, unbounded_scale)
  }
  let (unbounded_guard, unbounded_sticky) = binary_sqrt_round_bits(
    unbounded_exact, unbounded_midpoint_comparison,
  )
  let unbounded_rounded = binary_apply_round_bits(
    unbounded_root,
    unbounded_guard,
    unbounded_sticky,
    false,
    context.rounding,
  )
  binary_round_pack(
    false,
    floor_root,
    round_bit,
    sticky,
    target_exponent,
    exact_top,
    binary_exact_top(unbounded_rounded, unbounded_target),
    context,
  )
}

///|
struct SqctxRandom {
  mut sqctx_state : UInt64
}

///|
fn SqctxRandom::next(self : SqctxRandom) -> UInt64 {
  self.sqctx_state = self.sqctx_state * 6364136223846793005UL +
    1442695040888963407UL
  (self.sqctx_state >> 17) | (self.sqctx_state << 47)
}

///|
/// A coefficient of exactly `bits` bits (`bits >= 1`).
fn sqctx_coeff(random : SqctxRandom, bits : Int32) -> Coeff {
  let mut value = Coeff::one()
  while value.bit_length() < bits {
    value = value.shift_left(32).add(Coeff::from_uint64(random.next() >> 32))
  }
  let trimmed = value.shift_right(value.bit_length() - bits)
  // the top bit is set by construction of the loop only when the first word
  // did; force it
  if trimmed.bit_length() < bits {
    Coeff::one().shift_left(bits - 1).add(trimmed)
  } else {
    trimmed
  }
}

///|
/// `(odd coefficient, exponent)` of `magnitude * 2^exponent2`.
fn sqctx_odd(magnitude : Coeff, exponent2 : Int32) -> (Coeff, Int32) {
  let mut value = magnitude
  let mut exponent = exponent2
  while !value.is_zero() && !value.is_odd() {
    value = value.shift_right(1)
    exponent += 1
  }
  (value, exponent)
}

///|
fn sqctx_check(
  magnitude : Coeff,
  exponent2 : Int32,
  context : BinaryContext,
) -> Unit raise {
  if magnitude.is_zero() {
    return
  }
  let (odd, exponent) = sqctx_odd(magnitude, exponent2)
  let actual = binary_round_sqrt(odd, exponent, context)
  let expected = sqctx_round_reference(odd, exponent, context)
  assert_identical_with_flags(actual, expected)
}

///|
/// Radicands that put the midpoint test at its edge: perfect squares, one
/// below and one above, `root^2 + root` and `root^2 + root + 1` (the last
/// values below and above the midpoint), `(2 root + 1)^2` (an exact midpoint
/// of the next precision at exponent -2, a tie of the precision at 0), all
/// ones.
fn sqctx_edge_radicands(root : Coeff) -> Array[Coeff] {
  let one = Coeff::one()
  let square = root.square()
  let doubled = root.shift_left(1).add(one)
  [
    square,
    square.add(one),
    square.add(root),
    square.add(root).add(one),
    square.add(root.shift_left(1)),
    doubled.square(),
    doubled.square().add(one),
    if square.is_zero() {
      one
    } else {
      square.sub_checked(one).unwrap()
    },
  ]
}

///|
fn sqctx_contexts(precision : Int32) -> Array[BinaryContext] {
  let modes = [
    BinaryRoundingMode::RoundTiesToEven,
    BinaryRoundingMode::RoundTiesToAway,
    BinaryRoundingMode::RoundTowardZero,
    BinaryRoundingMode::RoundTowardPositive,
    BinaryRoundingMode::RoundTowardNegative,
  ]
  let contexts : Array[BinaryContext] = []
  for mode in modes {
    contexts.push(BinaryContext::new(precision~, rounding=mode))
    for e_max in [1, 3, 20, precision + 5] {
      for
        tininess in [
          TininessDetection::AfterRounding,
          TininessDetection::BeforeRounding,
        ] {
        match
          BinaryContext::try_new(precision~, e_max~, rounding=mode, tininess~) {
          Ok(context) => contexts.push(context)
          Err(_) => ()
        }
      }
    }
  }
  contexts
}

///|
test "sqrt_ctx with the remainder midpoint equals the reference split: edges and random, every direction and range" {
  let random = { sqctx_state: 0x5DEE_CE66_D1CE_4E5BUL, }
  let precisions = [
    2, 3, 7, 8, 24, 53, 63, 64, 65, 113, 127, 128, 129, 192, 255, 256, 257, 512,
    1024, 2048, 4096, 8192,
  ]
  for precision in precisions {
    let contexts = sqctx_contexts(precision)
    let roots_per = if precision <= 256 { 6 } else { 2 }
    let exponents_per = if precision <= 256 { 4 } else { 2 }
    for context in contexts {
      let e_max = context.range_e_max()
      for round in 0..<roots_per {
        // a root of `precision - 1`, `precision`, `precision + 1` bits
        let root_bits = Int32::max(1, precision - 1 + round % 3)
        let root = sqctx_coeff(random, root_bits)
        for radicand in sqctx_edge_radicands(root) {
          // exponents: 0, -2, and some that land in the subnormal, normal and
          // overflowing ranges of a small context
          let exponents = [0, -2, 2]
          for k in 0..<exponents_per {
            let top_low = -2 * (e_max + precision + 3)
            let span = 4 * e_max + 2 * precision + 10
            let top = top_low + (random.next() % span.to_uint64()).to_int()
            exponents.push(top - radicand.bit_length() + 1 + k)
          }
          for exponent in exponents {
            sqctx_check(radicand, exponent, context)
          }
        }
      }
      // random radicands of every width around the working widths
      for
        bits in [
          1,
          2,
          precision - 1,
          precision,
          precision + 1,
          2 * precision - 1,
          2 * precision,
          2 * precision + 1,
          2 * precision + 2,
          2 * precision + 3,
          3 * precision,
        ] {
        if bits >= 1 {
          let magnitude = sqctx_coeff(random, bits)
          let span = 4 * e_max + 2 * precision + 10
          let top = -2 * (e_max + precision + 3) +
            (random.next() % span.to_uint64()).to_int()
          sqctx_check(magnitude, top - bits + 1, context)
          // all ones
          let ones = Coeff::one()
            .shift_left(bits)
            .sub_checked(Coeff::one())
            .unwrap()
          sqctx_check(ones, top - bits + 1, context)
          sqctx_check(ones, 0, context)
        }
      }
    }
  }
}

///|
test "sqrt_ctx with the remainder midpoint equals the reference split at the exponent limits" {
  let random = { sqctx_state: 0x1234_5678_9ABC_DEF1UL, }
  for precision in [2, 53, 64, 128, 513] {
    for context in sqctx_contexts(precision) {
      for
        exponent in [
          -2147483647, -2147483000, -1073741824, -1073741823, 1073741823, 1073741824,
          2147483000, 2147483647,
        ] {
        for bits in [1, precision, 2 * precision + 1] {
          sqctx_check(sqctx_coeff(random, bits), exponent, context)
        }
      }
    }
  }
}

///|
test "sqrt_ctx on finite values equals the reference through Binary" {
  let random = { sqctx_state: 0xC0FF_EE00_DEAD_BEEFUL, }
  for precision in [2, 24, 53, 64, 128, 300, 2048] {
    for context in sqctx_contexts(precision) {
      for bits in [1, precision - 1, precision, 2 * precision + 1] {
        if bits >= 1 {
          let magnitude = sqctx_coeff(random, bits)
          let (odd, exponent) = sqctx_odd(magnitude, -bits)
          let value = finite_from_parts(false, odd, exponent, precision)
          let (actual, actual_flags) = value.sqrt_ctx(context)
          let (expected, expected_flags) = sqctx_round_reference(
            value.coefficient_(),
            value.exponent2_(),
            context,
          )
          assert_identical(actual, expected)
          assert_eq(actual_flags, expected_flags)
        }
      }
    }
  }
}
