///|
fn fma_show(result : (Binary, BinaryFlags)) -> String {
  let (value, flags) = result
  "\{value} flags=\{flags.to_testfloat_bits()}"
}

///|
fn fma_value(coefficient : Int32, exponent : Int32) -> Binary {
  let magnitude = BinCoeff::from_uint64(coefficient.abs().to_uint64())
  Binary::make(magnitude, exponent, 53, negative=coefficient < 0)
}

///|
// oracle: A
// source: written out: (1 + 2^-52)(1 - 2^-52) = 1 - 2^-104 exactly, so the fused (a * b) - 1 is -2^-104 with no flag (IEEE Std 754-2019 5.4.1: one rounding of the exact result), while the separate multiplication rounds to 1 and the sum is 0
// shares: Binary::make builds the operands; fma_ctx, mul_ctx and add_ctx are the code under test; fma_show prints value and flag bits
test "fma rounds the exact sum once" {
  let context = BinaryContext::binary64()
  // a * b = 1 - 2^-104 is not representable; a * b - 1 is exact only when fused.
  let a = Binary::make(BinCoeff::from_uint64((1UL << 52) + 1UL), -52, 53)
  let b = Binary::make(BinCoeff::from_uint64((1UL << 52) - 1UL), -52, 53)
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
// oracle: A, S
// source: A: written out from IEEE Std 754-2019 6.2 and 7.2 c) and d) (checked against the pdftotext of the PDF): fma(inf, 0, 1) and the signaling NaN input are invalid (flags 16), a quiet NaN input gives a quiet NaN with no flag, inf * 1 + (-inf) is invalid, inf * 1 + inf is +inf and 1 * 1 + (-inf) is -inf, with no flag; S: for fma(0, inf, qNaN) the standard leaves it implementation defined whether invalid is signaled, and the block records the choice of the library (invalid, flags 16, the choice of SoftFloat)
// shares: Binary::inf, zero, nan, signaling_nan and fma_value build the operands; fma_ctx is the code under test; fma_show prints value and flag bits
test "fma special values follow IEEE 754 and SoftFloat" {
  let context = BinaryContext::binary64()
  let inf = Binary::inf()
  let zero = Binary::zero()
  let one = fma_value(1, 0)
  let qnan = Binary::nan()
  let snan = Binary::signaling_nan()
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
// oracle: A
// source: written out from IEEE Std 754-2019 6.3 (an exact zero sum is +0 in every direction except round toward negative, where it is -0; (-0) + (-0) is -0): 1 * 1 + (-1) is +0 (nearest) and -0 (downward), (-0) * 1 + (-0) is -0, (-0) * 1 + (+0) is +0 in nearest and -0 downward, no flag
// shares: fma_value, Binary::zero and negative_zero build the operands; fma_ctx is the code under test; fma_show prints value and flag bits
test "fma exact zero sums use the IEEE sign rules" {
  let nearest = BinaryContext::binary64()
  let downward = BinaryContext::binary64(
    rounding=BinaryRoundingMode::RoundTowardNegative,
  )
  let one = fma_value(1, 0)
  let minus_one = fma_value(-1, 0)
  let zero = Binary::zero()
  let negative_zero = Binary::negative_zero()
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
// oracle: A
// source: written out from IEEE Std 754-2019 5.4.1, 7.4 and 7.5: (2^1000000000)^2 + 1 overflows the unbounded range to +inf (overflow and inexact, flags 5); (2^-1000000000)^2 + 1 = 1 + 2^-2000000000 rounds to 1 (inexact), to 1 + 2^-52 = 4503599627370497p-52 upward and the negated product gives 1 upward; (2^-1000000000)^2 + 0 upward is the smallest subnormal 1p-1073741874 (underflow and inexact, flags 3)
// shares: Binary::make and fma_value build the operands; fma_ctx is the code under test; fma_show prints value and flag bits; the limit of the smallest subnormal is the library's e_min as in arith_rows_wbtest.mbt
test "fma products beyond the exponent range" {
  let unbounded = BinaryContext::new(precision=53)
  let upward = BinaryContext::new(
    precision=53,
    rounding=BinaryRoundingMode::RoundTowardPositive,
  )
  let huge = Binary::make(BinCoeff::one(), 1000000000, 53)
  let tiny = Binary::make(BinCoeff::one(), -1000000000, 53)
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
    fma_show(tiny.fma_ctx(tiny, Binary::zero(), upward)),
    content=(
      #|1p-1073741874 flags=3
    ),
  )
}

///|
/// Independent reference: build the exact sum from coefficients with every
/// bit retained, then round once with `apply_ctx`.
fn fma_reference(
  a : Binary,
  b : Binary,
  c : Binary,
  context : BinaryContext,
) -> (Binary, BinaryFlags) {
  let product_negative = a.negative() != b.negative()
  let product = a.coefficient_().mul(b.coefficient_())
  let product_exponent = a.exponent2_() + b.exponent2_()
  if product.is_zero() && c.is_zero() {
    return a.mul_ctx(b, BinaryContext::new(precision=106)).0.add_ctx(c, context)
  }
  let target = Int32::min(product_exponent, c.exponent2_())
  let left = product.shift_left(product_exponent - target)
  let right = c.coefficient_().shift_left(c.exponent2_() - target)
  let (negative, magnitude) = if product_negative == c.negative() {
    (c.negative(), left.add(right))
  } else if left.compare(right) >= 0 {
    (product_negative, left.sub_checked(right).unwrap())
  } else {
    (c.negative(), right.sub_checked(left).unwrap())
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
  ).apply_ctx(context)
}

///|
// oracle: B
// source: fma_reference: the exact product of the two coefficients added to the third operand after aligning the exponents, with one rounding by Binary::apply_ctx (a different algorithm from the fused kernel under test), on 4000 operand triples from a fixed linear congruential sequence, five directions, precision 24 and 53, e_max 1023
// shares: Binary::make, finite_normalized and Coeff arithmetic build and add the exact sum; Binary::apply_ctx rounds it; the fused fma_ctx is the code under test
// primitives: Coeff::mul, Coeff::add, Coeff::sub_checked, Coeff::shift_left (level A through the coefficient tests), Binary::apply_ctx (rounds through binary_round_dyadic; level A through round_rows_wbtest.mbt)
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
  let operand = fn(spread : Int32) {
    let bits = next()
    let coefficient = (bits & ((1UL << 53) - 1UL)) | 1UL
    let exponent = (next() % (2UL * spread.to_uint64() + 1UL)).to_int() -
      spread -
      52
    Binary::make(
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
      let context = BinaryContext::new(precision~, rounding=mode, e_max=1023)
      let expected = fma_reference(a, b, c, context)
      let actual = a.fma_ctx(b, c, context)
      assert_identical_with_flags(
        actual,
        expected,
        msg="\{a} * \{b} + \{c} under mode \{mode_index}",
      )
      checked += 1
    }
  }
  inspect(checked, content="20000")
}
