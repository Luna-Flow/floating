// Binary::class_of and the predicates (IEEE Std 754-2019 5.7.2 class,
// 5.7.2 isNormal / isSubnormal / isFinite / isInfinite / isNaN).
//
// 5.7.2: class(x) is one of signalingNaN, quietNaN, negativeInfinity,
// negativeNormal, negativeSubnormal, negativeZero, positiveZero,
// positiveSubnormal, positiveNormal, positiveInfinity. Normal and subnormal
// depend on the format's emin, so every case below is an encoding of an
// interchange format decoded and classified in that format's context.

///|
fn cls_bits(
  format : BinaryInterchangeFormat,
  negative : Bool,
  exponent_field : Coeff,
  fraction : Coeff,
) -> Binary {
  let sign = if negative {
    Coeff::one().shift_left(format.total_bits() - 1)
  } else {
    Coeff::zero()
  }
  let bits = sign
    .bit_or(exponent_field.shift_left(format.fraction_bits()))
    .bit_or(fraction)
  BinaryInterchange::from_bits(bits, format).to_binary()
}

///|
fn cls_all_ones(width : Int32) -> Coeff {
  Coeff::one().shift_left(width).sub_checked(Coeff::one()).unwrap()
}

///|
fn cls_formats() -> Array[BinaryInterchangeFormat] {
  [
    BinaryInterchangeFormat::Binary16,
    BinaryInterchangeFormat::Binary32,
    BinaryInterchangeFormat::Binary64,
    BinaryInterchangeFormat::Binary128,
  ]
}

///|
test "class_of reaches all ten classes in every interchange format" {
  for format in cls_formats() {
    let ctx = format.context()
    let fb = format.fraction_bits()
    let zero = Coeff::zero()
    let one = Coeff::one()
    let frac_max = cls_all_ones(fb)
    let exp_max = cls_all_ones(format.exponent_bits())
    let exp_top_finite = exp_max.sub_checked(one).unwrap()
    let quiet_bit = one.shift_left(fb - 1)
    // (negative, exponent field, fraction, class)
    let rows : Array[(Bool, Coeff, Coeff, IeeeClass)] = [
      (false, zero, zero, PositiveZero),
      (true, zero, zero, NegativeZero),
      (false, zero, one, PositiveSubnormal),
      (true, zero, one, NegativeSubnormal),
      (false, zero, frac_max, PositiveSubnormal),
      (true, zero, frac_max, NegativeSubnormal),
      (false, one, zero, PositiveNormal),
      (true, one, zero, NegativeNormal),
      (false, exp_top_finite, frac_max, PositiveNormal),
      (true, exp_top_finite, frac_max, NegativeNormal),
      (false, exp_max, zero, PositiveInfinity),
      (true, exp_max, zero, NegativeInfinity),
      (false, exp_max, quiet_bit, QuietNaN),
      (true, exp_max, quiet_bit, QuietNaN),
      (false, exp_max, frac_max, QuietNaN),
      (false, exp_max, one, SignalingNaN),
      (true, exp_max, one, SignalingNaN),
      (false, exp_max, quiet_bit.sub_checked(one).unwrap(), SignalingNaN),
    ]
    for row in rows {
      let (negative, e, f, expected) = row
      let x = cls_bits(format, negative, e, f)
      inspect(x.class_of(ctx) == expected, content="true")
      // The predicates are projections of the class.
      let finite = match expected {
        SignalingNaN | QuietNaN | NegativeInfinity | PositiveInfinity => false
        _ => true
      }
      let nan = expected == SignalingNaN || expected == QuietNaN
      let infinite = expected == NegativeInfinity ||
        expected == PositiveInfinity
      let normal = expected == NegativeNormal || expected == PositiveNormal
      let subnormal = expected == NegativeSubnormal ||
        expected == PositiveSubnormal
      assert_eq(x.is_finite(), finite)
      assert_eq(x.is_nan(), nan)
      assert_eq(x.is_infinite(), infinite)
      assert_eq(x.is_normal(ctx), normal)
      assert_eq(x.is_subnormal(ctx), subnormal)
    }
  }
}

///|
test "class_of boundary between subnormal and normal follows emin" {
  // binary32: emin = -126. 2^-126 is the smallest normal, 2^-127 is
  // subnormal, and the value just below 2^-126 is the largest subnormal.
  let ctx = BinaryInterchangeFormat::Binary32.context()
  let smallest_normal = Binary::make_coeff(Coeff::one(), -126, 24)
  let half = Binary::make_coeff(Coeff::one(), -127, 24)
  inspect(smallest_normal.class_of(ctx) == PositiveNormal, content="true")
  inspect(half.class_of(ctx) == PositiveSubnormal, content="true")
  inspect(smallest_normal.neg().class_of(ctx) == NegativeNormal, content="true")
  inspect(half.neg().class_of(ctx) == NegativeSubnormal, content="true")
  // The same value is normal in a context with a lower emin.
  let wide = BinaryContext::new(precision=24, e_max=201)
  inspect(half.class_of(wide) == PositiveNormal, content="true")
  let narrow = BinaryContext::new(precision=24, e_max=101)
  inspect(smallest_normal.class_of(narrow) == PositiveSubnormal, content="true")
}

///|
test "class_of in an unbounded context treats ordinary values as normal" {
  let ctx = BinaryContext::new(precision=53)
  inspect(
    Binary::from_int(3, precision=53).class_of(ctx) == PositiveNormal,
    content="true",
  )
  inspect(
    Binary::from_int(-3, precision=53).class_of(ctx) == NegativeNormal,
    content="true",
  )
  inspect(
    Binary::zero(precision=53).class_of(ctx) == PositiveZero,
    content="true",
  )
  inspect(
    Binary::inf(negative=true, precision=53).class_of(ctx) == NegativeInfinity,
    content="true",
  )
}
