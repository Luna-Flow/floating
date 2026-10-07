///|
fn fma_show(result : (BinFloat, BinaryFlags)) -> String {
  let (value, flags) = result
  "\{value} flags=\{flags.to_testfloat_bits()}"
}

///|
fn fma_value(coefficient : Int, exponent : Int) -> BinFloat {
  let magnitude = BinCoeff::from_uint64(coefficient.abs().to_uint64())
  BinFloat::make(magnitude, exponent, 53, negative=coefficient < 0)
}

///|
test "fma rounds the exact sum once" {
  let context = BinaryContext::binary64()
  // a * b = 1 - 2^-104 is not representable; a * b - 1 is exact only when fused.
  let a = BinFloat::make(BinCoeff::from_uint64((1UL << 52) + 1UL), -52, 53)
  let b = BinFloat::make(BinCoeff::from_uint64((1UL << 52) - 1UL), -52, 53)
  let minus_one = fma_value(-1, 0)
  inspect(
    fma_show(a.fma_ctx(b, minus_one, context)),
    content=(
      #|-1p-104 flags=0
    ),
  )
  inspect(
    fma_show(a.mul_ctx(b, context).0.add_ctx(minus_one, context)),
    content=(
      #|0 flags=0
    ),
  )
}

///|
test "fma special values follow IEEE 754 and SoftFloat" {
  let context = BinaryContext::binary64()
  let inf = BinFloat::inf(Sign::Positive)
  let zero = BinFloat::zero()
  let one = fma_value(1, 0)
  let qnan = BinFloat::nan()
  let snan = BinFloat::signaling_nan()
  inspect(
    fma_show(inf.fma_ctx(zero, one, context)),
    content=(
      #|nan flags=16
    ),
  )
  inspect(
    fma_show(zero.fma_ctx(inf, qnan, context)),
    content=(
      #|nan flags=16
    ),
  )
  inspect(
    fma_show(one.fma_ctx(one, snan, context)),
    content=(
      #|nan flags=16
    ),
  )
  inspect(
    fma_show(qnan.fma_ctx(one, one, context)),
    content=(
      #|nan flags=0
    ),
  )
  inspect(
    fma_show(inf.fma_ctx(one, inf.neg(), context)),
    content=(
      #|nan flags=16
    ),
  )
  inspect(
    fma_show(inf.fma_ctx(one, inf, context)),
    content=(
      #|inf flags=0
    ),
  )
  inspect(
    fma_show(one.fma_ctx(one, inf.neg(), context)),
    content=(
      #|-inf flags=0
    ),
  )
}

///|
test "fma exact zero sums use the IEEE sign rules" {
  let nearest = BinaryContext::binary64()
  let downward = BinaryContext::binary64(
    rounding=BinaryRoundingMode::RoundTowardNegative,
  )
  let one = fma_value(1, 0)
  let minus_one = fma_value(-1, 0)
  let zero = BinFloat::zero()
  let negative_zero = BinFloat::negative_zero()
  inspect(
    fma_show(one.fma_ctx(one, minus_one, nearest)),
    content=(
      #|0 flags=0
    ),
  )
  inspect(
    fma_show(one.fma_ctx(one, minus_one, downward)),
    content=(
      #|-0 flags=0
    ),
  )
  inspect(
    fma_show(negative_zero.fma_ctx(one, negative_zero, nearest)),
    content=(
      #|-0 flags=0
    ),
  )
  inspect(
    fma_show(negative_zero.fma_ctx(one, zero, nearest)),
    content=(
      #|0 flags=0
    ),
  )
  inspect(
    fma_show(negative_zero.fma_ctx(one, zero, downward)),
    content=(
      #|-0 flags=0
    ),
  )
}

///|
test "fma products beyond the exponent range" {
  let unbounded = BinaryContext::unbounded(53)
  let upward = BinaryContext::unbounded(
    53,
    rounding=BinaryRoundingMode::RoundTowardPositive,
  )
  let huge = BinFloat::make(BinCoeff::one(), 1000000000, 53)
  let tiny = BinFloat::make(BinCoeff::one(), -1000000000, 53)
  let one = fma_value(1, 0)
  inspect(
    fma_show(huge.fma_ctx(huge, one, unbounded)),
    content=(
      #|inf flags=5
    ),
  )
  inspect(
    fma_show(tiny.fma_ctx(tiny, one, unbounded)),
    content=(
      #|1p0 flags=1
    ),
  )
  inspect(
    fma_show(tiny.fma_ctx(tiny, one, upward)),
    content=(
      #|4503599627370497p-52 flags=1
    ),
  )
  inspect(
    fma_show(tiny.neg().fma_ctx(tiny, one, upward)),
    content=(
      #|1p0 flags=1
    ),
  )
  inspect(
    fma_show(tiny.fma_ctx(tiny, BinFloat::zero(), upward)),
    content=(
      #|1p-1073741875 flags=3
    ),
  )
}

///|
/// Independent reference: build the exact sum from coefficients with every
/// bit retained, then round once with `round_ctx`.
fn fma_reference(
  a : BinFloat,
  b : BinFloat,
  c : BinFloat,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  let product_negative = a.negative != b.negative
  let product = a.coefficient_.mul(b.coefficient_)
  let product_exponent = a.exponent2 + b.exponent2
  if product.is_zero() && c.is_zero() {
    return a.mul_ctx(b, BinaryContext::unbounded(106)).0.add_ctx(c, context)
  }
  let target = Int::min(product_exponent, c.exponent2)
  let left = product.shift_left(product_exponent - target)
  let right = c.coefficient_.shift_left(c.exponent2 - target)
  let (negative, magnitude) = if product_negative == c.negative {
    (c.negative, left.add(right))
  } else if left.compare(right) >= 0 {
    (product_negative, left.sub_checked(right).unwrap())
  } else {
    (c.negative, right.sub_checked(left).unwrap())
  }
  if magnitude.is_zero() {
    return (
      finite_zero(
        context.rounding == BinaryRoundingMode::RoundTowardNegative,
        context.precision,
      ),
      BinaryFlags::new(),
    )
  }
  finite_normalized(
    negative,
    magnitude.shift_right(magnitude.ctz()),
    target + magnitude.ctz(),
    magnitude.bit_length(),
  ).round_ctx(context)
}

///|
test "fma agrees with an exact-sum reference on random operands" {
  let modes = [
    BinaryRoundingMode::RoundTiesToEven,
    BinaryRoundingMode::RoundTiesToAway,
    BinaryRoundingMode::RoundTowardZero,
    BinaryRoundingMode::RoundTowardPositive,
    BinaryRoundingMode::RoundTowardNegative,
  ]
  let mut state = 0x9E3779B97F4A7C15UL
  let next = fn() {
    state = state * 6364136223846793005UL + 1442695040888963407UL
    state >> 11
  }
  let operand = fn(spread : Int) {
    let bits = next()
    let coefficient = (bits & ((1UL << 53) - 1UL)) | 1UL
    let exponent = (next() % (2UL * spread.to_uint64() + 1UL)).to_int() -
      spread -
      52
    BinFloat::make(
      BinCoeff::from_uint64(coefficient),
      exponent,
      53,
      negative=(bits >> 60) % 2UL == 1UL,
    )
  }
  let mut checked = 0
  for index in 0..<4000 {
    let spread = if index % 4 == 0 { 400 } else { 40 }
    let a = operand(spread)
    let b = operand(spread)
    let c = operand(spread * 2)
    for mode_index, mode in modes {
      let precision = if index % 3 == 0 { 24 } else { 53 }
      let context = BinaryContext::new(
        precision,
        rounding=mode,
        e_min=-1022,
        e_max=1023,
      )
      let expected = fma_reference(a, b, c, context)
      let actual = a.fma_ctx(b, c, context)
      assert_eq(
        actual,
        expected,
        msg="\{a} * \{b} + \{c} under mode \{mode_index}",
      )
      checked += 1
    }
  }
  inspect(checked, content="20000")
}
