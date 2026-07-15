///|
// Exact rational arithmetic used only by certified elementary-function kernels.
priv struct CertifiedRat {
  num : SignedBinCoeff
  den : @bin_float.BinCoeff
}

///|
fn certified_refinement_budget(
  initial_work_bits : Int,
) -> CertifiedRefinementBudget {
  @internal.CertifiedRefinementBudget::new(initial_work_bits)
}

///|
fn certified_rat_coeff(
  num : SignedBinCoeff,
  den : @bin_float.BinCoeff,
) -> CertifiedRat {
  guard !coeff_is_zero(den) else {
    abort("certified rational denominator must be non-zero")
  }
  if signed_coeff_is_zero(num) {
    return { num, den: coeff_one() }
  }
  let divisor = coeff_gcd(signed_coeff_magnitude(num), den)
  {
    num: signed_coeff_div_exact(num, divisor),
    den: coeff_div_exact(den, divisor),
  }
}

///|
fn rat_from_fraction_int(numerator : Int, denominator : Int) -> CertifiedRat {
  guard denominator > 0 else {
    abort("certified rational denominator must be positive")
  }
  certified_rat_coeff(
    signed_coeff_from_int(numerator),
    coeff_from_nonnegative_int(denominator),
  )
}

///|
fn rat_from_int(value : Int) -> CertifiedRat {
  { num: signed_coeff_from_int(value), den: coeff_one() }
}

///|
fn rat_sign(value : CertifiedRat) -> Int {
  signed_coeff_sign(value.num)
}

///|
fn rat_is_zero(value : CertifiedRat) -> Bool {
  signed_coeff_is_zero(value.num)
}

///|
fn rat_neg(value : CertifiedRat) -> CertifiedRat {
  { num: signed_coeff_neg(value.num), den: value.den }
}

///|
fn rat_abs(value : CertifiedRat) -> CertifiedRat {
  { num: signed_coeff_abs(value.num), den: value.den }
}

///|
fn rat_add(left : CertifiedRat, right : CertifiedRat) -> CertifiedRat {
  let common = coeff_gcd(left.den, right.den)
  let left_scale = coeff_div_exact(right.den, common)
  let right_scale = coeff_div_exact(left.den, common)
  let numerator = signed_coeff_add(
    signed_coeff_mul_magnitude(left.num, left_scale),
    signed_coeff_mul_magnitude(right.num, right_scale),
  )
  if signed_coeff_is_zero(numerator) {
    return rat_from_int(0)
  }
  let cancellation = coeff_gcd(signed_coeff_magnitude(numerator), common)
  {
    num: signed_coeff_div_exact(numerator, cancellation),
    den: coeff_mul(right_scale, coeff_div_exact(right.den, cancellation)),
  }
}

///|
fn rat_sub(left : CertifiedRat, right : CertifiedRat) -> CertifiedRat {
  rat_add(left, rat_neg(right))
}

///|
fn rat_mul(left : CertifiedRat, right : CertifiedRat) -> CertifiedRat {
  let left_cross = coeff_gcd(signed_coeff_magnitude(left.num), right.den)
  let right_cross = coeff_gcd(signed_coeff_magnitude(right.num), left.den)
  {
    num: signed_coeff_mul(
      signed_coeff_div_exact(left.num, left_cross),
      signed_coeff_div_exact(right.num, right_cross),
    ),
    den: coeff_mul(
      coeff_div_exact(left.den, right_cross),
      coeff_div_exact(right.den, left_cross),
    ),
  }
}

///|
fn rat_mul_int(value : CertifiedRat, multiplier : Int) -> CertifiedRat {
  rat_mul(value, rat_from_int(multiplier))
}

///|
fn rat_div(left : CertifiedRat, right : CertifiedRat) -> CertifiedRat {
  guard !signed_coeff_is_zero(right.num) else {
    abort("certified rational division by zero")
  }
  let numerator_cross = coeff_gcd(
    signed_coeff_magnitude(left.num),
    signed_coeff_magnitude(right.num),
  )
  let denominator_cross = coeff_gcd(left.den, right.den)
  let numerator = signed_coeff_mul_magnitude(
    signed_coeff_div_exact(left.num, numerator_cross),
    coeff_div_exact(right.den, denominator_cross),
  )
  let numerator = if signed_coeff_sign(right.num) < 0 {
    signed_coeff_neg(numerator)
  } else {
    numerator
  }
  {
    num: numerator,
    den: coeff_mul(
      coeff_div_exact(left.den, denominator_cross),
      coeff_div_exact(signed_coeff_magnitude(right.num), numerator_cross),
    ),
  }
}

///|
fn rat_div_int(value : CertifiedRat, divisor : Int) -> CertifiedRat {
  guard divisor > 0 else {
    abort("certified rational divisor must be positive")
  }
  let coefficient = coeff_from_nonnegative_int(divisor)
  let cancellation = coeff_gcd(signed_coeff_magnitude(value.num), coefficient)
  {
    num: signed_coeff_div_exact(value.num, cancellation),
    den: coeff_mul(value.den, coeff_div_exact(coefficient, cancellation)),
  }
}

///|
fn rat_div_pow2(value : CertifiedRat, shift : Int) -> CertifiedRat {
  guard shift >= 0 else {
    abort("certified rational shift must be non-negative")
  }
  let factor = coeff_shift_left(coeff_one(), shift)
  let cancellation = coeff_gcd(signed_coeff_magnitude(value.num), factor)
  {
    num: signed_coeff_div_exact(value.num, cancellation),
    den: coeff_mul(value.den, coeff_div_exact(factor, cancellation)),
  }
}

///|
fn rat_compare(left : CertifiedRat, right : CertifiedRat) -> Int {
  signed_coeff_compare(
    signed_coeff_mul_magnitude(left.num, right.den),
    signed_coeff_mul_magnitude(right.num, left.den),
  )
}

///|
fn rat_compare_pow2(value : CertifiedRat, exponent : Int) -> Int {
  guard rat_sign(value) > 0 else {
    abort("power comparison requires a positive rational")
  }
  if exponent >= 0 {
    coeff_compare(
      signed_coeff_magnitude(value.num),
      coeff_shift_left(value.den, exponent),
    )
  } else {
    coeff_compare(
      coeff_shift_left(signed_coeff_magnitude(value.num), -exponent),
      value.den,
    )
  }
}

///|
fn rat_floor_log2(value : CertifiedRat) -> Int {
  guard rat_sign(value) > 0 else { abort("log2 requires a positive rational") }
  let mut exponent = coeff_bits(signed_coeff_magnitude(value.num)) -
    coeff_bits(value.den)
  if rat_compare_pow2(value, exponent) < 0 {
    exponent -= 1
  }
  exponent
}

///|
fn positive_rat_dyadic_bounds(
  value : CertifiedRat,
  precision : Int,
) -> (@bin_float.BinFloat, @bin_float.BinFloat) {
  guard rat_sign(value) >= 0 else {
    abort("positive dyadic conversion received a negative rational")
  }
  let precision = Int::max(1, precision)
  if rat_is_zero(value) {
    let zero = @bin_float.BinFloat::zero(precision~)
    return (zero, zero)
  }
  let exponent = rat_floor_log2(value)
  let shift = precision - 1 - exponent
  let (quotient, remainder) = if shift >= 0 {
    coeff_div_rem(
      coeff_shift_left(signed_coeff_magnitude(value.num), shift),
      value.den,
    )
  } else {
    coeff_div_rem(
      signed_coeff_magnitude(value.num),
      coeff_shift_left(value.den, -shift),
    )
  }
  let lower = @bin_float.BinFloat::make(quotient, -shift, precision)
  if coeff_is_zero(remainder) {
    (lower, lower)
  } else {
    let upper = @bin_float.BinFloat::make(
      coeff_increment(quotient),
      -shift,
      precision,
    )
    (lower, upper)
  }
}

///|
fn rat_dyadic_bounds(
  value : CertifiedRat,
  precision : Int,
) -> (@bin_float.BinFloat, @bin_float.BinFloat) {
  if rat_sign(value) < 0 {
    let (positive_lower, positive_upper) = positive_rat_dyadic_bounds(
      rat_neg(value),
      precision,
    )
    (positive_upper.neg(), positive_lower.neg())
  } else {
    positive_rat_dyadic_bounds(value, precision)
  }
}

///|
fn rat_from_finite_bin(value : @bin_float.BinFloat) -> CertifiedRat {
  guard value.classify() == FpClass::Finite else {
    abort("certified rational conversion requires a finite value")
  }
  if value.exponent2() >= 0 {
    certified_rat_coeff(
      signed_coeff_from_parts(
        value.sign() == Sign::Negative,
        coeff_shift_left(value.coefficient(), value.exponent2()),
      ),
      coeff_one(),
    )
  } else {
    certified_rat_coeff(
      signed_coeff_from_parts(value.is_negative(), value.coefficient()),
      coeff_shift_left(coeff_one(), -value.exponent2()),
    )
  }
}

///|
fn finite_bin_exact_int(value : @bin_float.BinFloat) -> Int? {
  guard value.classify() == FpClass::Finite else { return None }
  let source = value.coefficient()
  if coeff_is_zero(source) {
    return Some(0)
  }
  let magnitude = if value.exponent2() >= 0 {
    coeff_shift_left(source, value.exponent2())
  } else {
    let shift = -value.exponent2()
    guard shift < coeff_bits(source) else { return None }
    let divisor = coeff_shift_left(coeff_one(), shift)
    let (quotient, remainder) = coeff_div_rem(source, divisor)
    guard coeff_is_zero(remainder) else { return None }
    quotient
  }
  let limit = if value.sign() == Sign::Negative {
    2147483648UL
  } else {
    2147483647UL
  }
  guard coeff_to_uint64(magnitude) is Some(integer) && integer <= limit else {
    return None
  }
  if value.sign() == Sign::Negative {
    if integer == 2147483648UL {
      Some(-2147483647 - 1)
    } else {
      Some(-integer.to_int())
    }
  } else {
    Some(integer.to_int())
  }
}

///|
fn exact_exp2_endpoint(
  value : @bin_float.BinFloat,
  precision : Int,
) -> BallFloat? {
  guard finite_bin_exact_int(value) is Some(exponent) else { return None }
  Some(
    zero_radius_interval(
      @bin_float.BinFloat::make(@bin_float.BinCoeff::one(), exponent, precision),
      precision,
    ),
  )
}

///|
fn exact_exp10_endpoint(
  value : @bin_float.BinFloat,
  precision : Int,
) -> BallFloat? {
  guard finite_bin_exact_int(value) is Some(exponent) &&
    exponent >= 0 &&
    exponent <= 100000 else {
    return None
  }
  let power = @bin_float.BinCoeff::from_uint64(10UL).pow_nat(
    exponent.reinterpret_as_uint(),
  )
  Some(
    quantize_interval(
      @bin_float.BinFloat::make(power, 0, power.bit_length()),
      @bin_float.BinFloat::make(power, 0, power.bit_length()),
      precision,
    ),
  )
}

///|
fn exact_log10_endpoint(
  value : @bin_float.BinFloat,
  precision : Int,
) -> BallFloat? {
  guard value.classify() == FpClass::Finite && value.sign() == Sign::Positive else {
    return None
  }
  let integer = finite_bin_exact_int(value)
  guard integer is Some(candidate) && candidate > 0 else { return None }
  let mut power = 1
  let mut exponent = 0
  while power < candidate && exponent < 9 {
    power *= 10
    exponent += 1
  }
  guard power == candidate else { return None }
  Some(
    zero_radius_interval(
      @bin_float.BinFloat::from_int(exponent, precision~),
      precision,
    ),
  )
}

///|
fn certified_exp_series(
  argument : CertifiedRat,
  work_bits : Int,
) -> (CertifiedRat, CertifiedRat) {
  guard rat_sign(argument) >= 0 &&
    rat_compare(argument, rat_from_fraction_int(1, 8)) <= 0 else {
    abort("certified exp series requires 0 <= x <= 1/8")
  }
  let one = rat_from_int(1)
  if rat_is_zero(argument) {
    return (one, one)
  }
  let precision = work_bits + 32
  let downward = directed_context(
    precision,
    @bin_float.BinaryRoundingMode::RoundTowardNegative,
  )
  let upward = directed_context(
    precision,
    @bin_float.BinaryRoundingMode::RoundTowardPositive,
  )
  let argument_lower = rat_dyadic_bounds(argument, precision).0
  let argument_upper = rat_dyadic_bounds(argument, precision).1
  let one_bin = @bin_float.BinFloat::one(precision~)
  let two_bin = @bin_float.BinFloat::from_int(2, precision~)
  let mut sum_lower = one_bin
  let mut sum_upper = one_bin
  let mut term_lower = one_bin
  let mut term_upper = one_bin
  let threshold = @bin_float.BinFloat::make(
    @bin_float.BinCoeff::one(),
    -(work_bits + 8),
    precision,
  )
  let mut index = 0
  while index < 10000 {
    index += 1
    let index_bin = @bin_float.BinFloat::from_int(index, precision~)
    term_lower = directed_div(
      directed_mul(term_lower, argument_lower, downward),
      index_bin,
      downward,
    )
    term_upper = directed_div(
      directed_mul(term_upper, argument_upper, upward),
      index_bin,
      upward,
    )
    sum_lower = directed_add(sum_lower, term_lower, downward)
    sum_upper = directed_add(sum_upper, term_upper, upward)
    let next_index = @bin_float.BinFloat::from_int(index + 1, precision~)
    let next_upper = directed_div(
      directed_mul(term_upper, argument_upper, upward),
      next_index,
      upward,
    )
    let tail_upper = directed_mul(next_upper, two_bin, upward)
    if tail_upper.compare(threshold) < 0 {
      return (
        rat_from_finite_bin(sum_lower),
        rat_from_finite_bin(directed_add(sum_upper, tail_upper, upward)),
      )
    }
  }
  abort("certified exp series did not converge")
}

///|
fn certified_log_unit_series(
  value : CertifiedRat,
  work_bits : Int,
) -> (CertifiedRat, CertifiedRat) {
  let one = rat_from_int(1)
  let two = rat_from_int(2)
  guard rat_compare(value, one) >= 0 && rat_compare(value, two) <= 0 else {
    abort("certified log unit series requires 1 <= x <= 2")
  }
  if rat_compare(value, one) == 0 {
    let zero = rat_from_int(0)
    return (zero, zero)
  }
  let precision = work_bits + 32
  let downward = directed_context(
    precision,
    @bin_float.BinaryRoundingMode::RoundTowardNegative,
  )
  let upward = directed_context(
    precision,
    @bin_float.BinaryRoundingMode::RoundTowardPositive,
  )
  let value_lower = rat_dyadic_bounds(value, precision).0
  let value_upper = rat_dyadic_bounds(value, precision).1
  let one_bin = @bin_float.BinFloat::one(precision~)
  let two_bin = @bin_float.BinFloat::from_int(2, precision~)
  let three_bin = @bin_float.BinFloat::from_int(3, precision~)
  let numerator_lower = directed_sub(value_lower, one_bin, downward)
  let numerator_upper = directed_sub(value_upper, one_bin, upward)
  let denominator_lower = directed_add(value_lower, one_bin, downward)
  let denominator_upper = directed_add(value_upper, one_bin, upward)
  let z_lower = directed_div(numerator_lower, denominator_upper, downward)
  let z_upper = directed_div(numerator_upper, denominator_lower, upward)
  let squared_lower = directed_mul(z_lower, z_lower, downward)
  let squared_upper = directed_mul(z_upper, z_upper, upward)
  let mut term_lower = z_lower
  let mut term_upper = z_upper
  let mut denominator = 1
  let mut sum_lower = @bin_float.BinFloat::zero(precision~)
  let mut sum_upper = sum_lower
  let threshold = @bin_float.BinFloat::make(
    @bin_float.BinCoeff::one(),
    -(work_bits + 8),
    precision,
  )
  while denominator < 20000 {
    sum_lower = directed_add(sum_lower, term_lower, downward)
    sum_upper = directed_add(sum_upper, term_upper, upward)
    let next_denominator = denominator + 2
    let denominator_bin = @bin_float.BinFloat::from_int(denominator, precision~)
    let next_denominator_bin = @bin_float.BinFloat::from_int(
      next_denominator,
      precision~,
    )
    term_lower = directed_div(
      directed_mul(
        directed_mul(term_lower, squared_lower, downward),
        denominator_bin,
        downward,
      ),
      next_denominator_bin,
      downward,
    )
    term_upper = directed_div(
      directed_mul(
        directed_mul(term_upper, squared_upper, upward),
        denominator_bin,
        upward,
      ),
      next_denominator_bin,
      upward,
    )
    let tail_upper = directed_mul(term_upper, three_bin, upward)
    if tail_upper.compare(threshold) < 0 {
      let lower = directed_mul(sum_lower, two_bin, downward)
      let upper = directed_add(
        directed_mul(sum_upper, two_bin, upward),
        tail_upper,
        upward,
      )
      return (rat_from_finite_bin(lower), rat_from_finite_bin(upper))
    }
    denominator = next_denominator
  }
  abort("certified log series did not converge")
}

///|
fn certified_ln2_rational(work_bits : Int) -> (CertifiedRat, CertifiedRat) {
  certified_log_unit_series(rat_from_int(2), work_bits)
}

///|
fn certified_ln_finite_rational(
  value : @bin_float.BinFloat,
  work_bits : Int,
) -> (CertifiedRat, CertifiedRat) {
  guard value.classify() == FpClass::Finite && value.sign() == Sign::Positive else {
    abort("certified log requires a positive finite value")
  }
  let coefficient = value.coefficient()
  let coefficient_bits = coefficient.bit_length()
  let unit = certified_rat_coeff(
    signed_coeff_from_parts(false, coefficient),
    coeff_shift_left(coeff_one(), coefficient_bits - 1),
  )
  let exponent = value.exponent2() + coefficient_bits - 1
  let (unit_lower, unit_upper) = certified_log_unit_series(unit, work_bits)
  if exponent == 0 {
    return (unit_lower, unit_upper)
  }
  let (ln2_lower, ln2_upper) = certified_ln2_rational(work_bits)
  if exponent > 0 {
    (
      rat_add(unit_lower, rat_mul_int(ln2_lower, exponent)),
      rat_add(unit_upper, rat_mul_int(ln2_upper, exponent)),
    )
  } else {
    let magnitude = -exponent
    (
      rat_sub(unit_lower, rat_mul_int(ln2_upper, magnitude)),
      rat_sub(unit_upper, rat_mul_int(ln2_lower, magnitude)),
    )
  }
}

///|
fn certified_ln_endpoint_bounds(
  value : @bin_float.BinFloat,
  precision : Int,
) -> (@bin_float.BinFloat, @bin_float.BinFloat) {
  if value.classify() == FpClass::Infinity {
    let infinity = pos_inf(precision)
    return (infinity, infinity)
  }
  let (lower, upper) = certified_ln_finite_rational(value, precision + 24)
  let lower_bound = rat_dyadic_bounds(lower, precision).0
  let upper_bound = rat_dyadic_bounds(upper, precision).1
  (lower_bound, upper_bound)
}

///|
fn certified_log2_endpoint_bounds(
  value : @bin_float.BinFloat,
  precision : Int,
) -> (@bin_float.BinFloat, @bin_float.BinFloat) {
  if value.classify() == FpClass::Infinity {
    let infinity = pos_inf(precision)
    return (infinity, infinity)
  }
  guard value.sign() == Sign::Positive else {
    abort("certified log2 requires a positive value")
  }
  let coefficient = value.coefficient()
  let coefficient_bits = coefficient.bit_length()
  let exponent = value.exponent2() + coefficient_bits - 1
  let unit = certified_rat_coeff(
    signed_coeff_from_parts(false, coefficient),
    coeff_shift_left(coeff_one(), coefficient_bits - 1),
  )
  let work = precision + 32
  let (unit_lower, unit_upper) = certified_log_unit_series(unit, work)
  let (ln2_lower, ln2_upper) = certified_ln2_rational(work)
  let lower = rat_add(rat_from_int(exponent), rat_div(unit_lower, ln2_upper))
  let upper = rat_add(rat_from_int(exponent), rat_div(unit_upper, ln2_lower))
  (rat_dyadic_bounds(lower, precision).0, rat_dyadic_bounds(upper, precision).1)
}

///|
fn certified_exp_rational(value : CertifiedRat, precision : Int) -> BallFloat {
  let precision = Int::max(1, precision)
  if rat_is_zero(value) {
    return zero_radius_interval(@bin_float.BinFloat::one(precision~), precision)
  }
  let negative = rat_sign(value) < 0
  let magnitude = rat_abs(value)
  let adjusted = rat_floor_log2(magnitude)
  if adjusted > 29 {
    if negative {
      return store_interval(
        @bin_float.BinFloat::zero(precision~),
        @bin_float.BinFloat::one(precision~),
        precision,
      )
    }
    return store_interval(
      @bin_float.BinFloat::zero(precision~),
      pos_inf(precision),
      precision,
    )
  }
  if adjusted < -(precision + 16) {
    let one = @bin_float.BinFloat::one(precision~)
    let step = @bin_float.BinFloat::make(
      @bin_float.BinCoeff::one(),
      -precision,
      precision,
    )
    if negative {
      return quantize_interval(exact_sub(one, step), one, precision)
    }
    return quantize_interval(one, exact_add(one, step), precision)
  }
  let reductions = Int::max(0, adjusted + 4)
  let work = precision + 64 + 2 * reductions
  let reduced = rat_div_pow2(magnitude, reductions)
  let (series_lower, series_upper) = certified_exp_series(reduced, work + 16)
  let (lower_rat, upper_rat) = if negative {
    (
      rat_div(rat_from_int(1), series_upper),
      rat_div(rat_from_int(1), series_lower),
    )
  } else {
    (series_lower, series_upper)
  }
  let mut result = quantize_interval(
    rat_dyadic_bounds(lower_rat, work).0,
    rat_dyadic_bounds(upper_rat, work).1,
    work,
  )
  for _ in 0..<reductions {
    result = result.square()
  }
  quantize_interval(result.lo_, result.hi_, precision)
}

///|
fn certified_exp_endpoint(
  value : @bin_float.BinFloat,
  precision : Int,
) -> BallFloat {
  match value.classify() {
    FpClass::Infinity =>
      if value.sign() == Sign::Negative {
        zero_radius_interval(@bin_float.BinFloat::zero(precision~), precision)
      } else {
        store_interval(
          @bin_float.BinFloat::zero(precision~),
          pos_inf(precision),
          precision,
        )
      }
    FpClass::Finite =>
      certified_exp_rational(rat_from_finite_bin(value), precision)
    FpClass::NaN => abort("ball endpoint must not be NaN")
  }
}

///|
fn exp_interval_at_precision(value : BallFloat, precision : Int) -> BallFloat {
  if value.is_empty() {
    return empty_interval(precision)
  }
  let lower = certified_exp_endpoint(value.lo_, precision)
  let upper = certified_exp_endpoint(value.hi_, precision)
  store_interval(lower.lo_, upper.hi_, precision)
}

///|
fn ln_interval_at_precision(value : BallFloat, precision : Int) -> BallFloat {
  if value.is_empty() ||
    (
      value.hi_.classify() == FpClass::Finite &&
      (value.hi_.sign() == Sign::Negative || value.hi_.is_zero())
    ) {
    return empty_interval(precision)
  }
  let lower = if value.lo_.classify() == FpClass::Infinity ||
    value.lo_.sign() == Sign::Negative ||
    value.lo_.is_zero() {
    neg_inf(precision)
  } else {
    certified_ln_endpoint_bounds(value.lo_, precision).0
  }
  let upper = certified_ln_endpoint_bounds(value.hi_, precision).1
  store_interval(lower, upper, precision)
}

///|
fn scale_by_log_constant(
  value : BallFloat,
  constant : Int,
  precision : Int,
) -> BallFloat {
  if value.is_empty() {
    return empty_interval(precision)
  }
  let work = precision + 96
  let constant_bin = @bin_float.BinFloat::from_int(constant, precision=work)
  let (constant_lower, constant_upper) = certified_ln_endpoint_bounds(
    constant_bin, work,
  )
  let constant_interval = store_interval(constant_lower, constant_upper, work)
  let source = if value.is_empty() {
    empty_interval(work)
  } else {
    quantize_interval(value.lo_, value.hi_, work)
  }
  let scaled = source * constant_interval
  let result = exp_interval_at_precision(scaled, work)
  let exact_lower = if constant == 2 {
    exact_exp2_endpoint(value.lo_, work)
  } else {
    exact_exp10_endpoint(value.lo_, work)
  }
  let exact_upper = if constant == 2 {
    exact_exp2_endpoint(value.hi_, work)
  } else {
    exact_exp10_endpoint(value.hi_, work)
  }
  let lower = match exact_lower {
    Some(exact) => exact.lo_
    None => result.lo_
  }
  let upper = match exact_upper {
    Some(exact) => exact.hi_
    None => result.hi_
  }
  quantize_interval(lower, upper, precision)
}

///|
fn log_with_base_constant(
  value : BallFloat,
  constant : Int,
  precision : Int,
) -> BallFloat {
  if value.is_empty() {
    return empty_interval(precision)
  }
  if value.hi_.classify() == FpClass::Finite &&
    (value.hi_.sign() == Sign::Negative || value.hi_.is_zero()) {
    return empty_interval(precision)
  }
  let work = precision + 96
  if constant == 2 {
    let lower = if value.lo_.classify() == FpClass::Infinity ||
      value.lo_.sign() == Sign::Negative ||
      value.lo_.is_zero() {
      neg_inf(precision)
    } else {
      certified_log2_endpoint_bounds(value.lo_, precision).0
    }
    let upper = certified_log2_endpoint_bounds(value.hi_, precision).1
    return store_interval(lower, upper, precision)
  }
  let numerator = ln_interval_at_precision(value, work)
  if numerator.is_empty() {
    return empty_interval(precision)
  }
  let constant_bin = @bin_float.BinFloat::from_int(constant, precision=work)
  let (constant_lower, constant_upper) = certified_ln_endpoint_bounds(
    constant_bin, work,
  )
  let denominator = store_interval(constant_lower, constant_upper, work)
  let result = numerator / denominator
  let exact_lower = exact_log10_endpoint(value.lo_, precision)
  let exact_upper = exact_log10_endpoint(value.hi_, precision)
  quantize_interval(
    match exact_lower {
      Some(exact) => exact.lo_
      None => result.lo_
    },
    match exact_upper {
      Some(exact) => exact.hi_
      None => result.hi_
    },
    precision,
  )
}

///|
pub fn BallFloat::exp_interval(self : BallFloat) -> BallFloat {
  exp_interval_at_precision(self, self.precision_)
}

///|
pub fn BallFloat::exp2_interval(self : BallFloat) -> BallFloat {
  scale_by_log_constant(self, 2, self.precision_)
}

///|
pub fn BallFloat::exp10_interval(self : BallFloat) -> BallFloat {
  scale_by_log_constant(self, 10, self.precision_)
}

///|
/// Certified interval for exp(x) - 1.
pub fn BallFloat::expm1_interval(self : BallFloat) -> BallFloat {
  match self.try_expm1_interval() {
    Ok(result) => result
    Err(_) =>
      store_interval(
        @bin_float.BinFloat::from_int(-1, precision=self.precision_),
        pos_inf(self.precision_),
        self.precision_,
      )
  }
}

///|
pub fn BallFloat::ln_interval(self : BallFloat) -> BallFloat {
  ln_interval_at_precision(self, self.precision_)
}

///|
pub fn BallFloat::log2_interval(self : BallFloat) -> BallFloat {
  log_with_base_constant(self, 2, self.precision_)
}

///|
pub fn BallFloat::log10_interval(self : BallFloat) -> BallFloat {
  log_with_base_constant(self, 10, self.precision_)
}

///|
/// Certified interval for ln(1 + x).
pub fn BallFloat::log1p_interval(self : BallFloat) -> BallFloat {
  match self.try_log1p_interval() {
    Ok(result) => result
    Err(_) => whole_real(self.precision_)
  }
}

///|
pub fn BallFloat::exp_ctx(
  self : BallFloat,
  ctx : BallContext,
) -> (BallFloat, BallFlags) {
  exp_interval_at_precision(self, ctx.precision + 32).apply_ctx(ctx)
}

///|
pub fn BallFloat::ln_ctx(
  self : BallFloat,
  ctx : BallContext,
) -> (BallFloat, BallFlags) {
  ln_interval_at_precision(self, ctx.precision + 32).apply_ctx(ctx)
}

///|
fn ball_certification_failure(
  operation : String,
  precision : Int,
  initial_work_precision : Int,
) -> @def.ArithmeticError {
  let mut budget = certified_refinement_budget(initial_work_precision)
  while budget.available() {
    budget = budget.next()
  }
  @internal.certified_failure(
    operation,
    @def.CertificationStage::TargetRounding,
    @def.CertificationFailureReason::RefinementBudgetExhausted,
    precision,
    budget,
  )
}

///|
fn ball_range_resource_failure(
  operation : String,
  precision : Int,
  required_work_precision : Int,
) -> @def.ArithmeticError {
  @def.ArithmeticError::certification_failure(
    @def.CertificationFailureDetail::new(
      operation,
      @def.CertificationStage::RangeReduction,
      @def.CertificationFailureReason::ResourceLimit,
      precision,
      required_work_precision,
      0,
    ),
  )
}

///|
pub fn BallFloat::try_exp_interval(
  self : BallFloat,
) -> Result[BallFloat, @def.ArithmeticError] {
  self.try_certified_monotone(true, fn(value, context) {
    value.try_exp_ctx(context)
  })
}

///|
pub fn BallFloat::try_expm1_interval(
  self : BallFloat,
) -> Result[BallFloat, @def.ArithmeticError] {
  if self.is_empty() {
    return Ok(self)
  }
  let downward = @bin_float.BinaryContext::unbounded(
    self.precision_,
    rounding=@bin_float.BinaryRoundingMode::RoundTowardNegative,
  )
  let upward = @bin_float.BinaryContext::unbounded(
    self.precision_,
    rounding=@bin_float.BinaryRoundingMode::RoundTowardPositive,
  )
  let lower = if is_neg_inf(self.lo_) {
    Ok(@bin_float.BinFloat::from_int(-1, precision=self.precision_))
  } else {
    self.lo_.try_expm1_ctx(downward).map(fn(result) { result.0 })
  }
  let upper = if is_pos_inf(self.hi_) {
    Ok(pos_inf(self.precision_))
  } else {
    self.hi_.try_expm1_ctx(upward).map(fn(result) { result.0 })
  }
  lower.bind(fn(lower_bound) {
    upper.map(fn(upper_bound) {
      store_interval(lower_bound, upper_bound, self.precision_)
    })
  })
}

///|
pub fn BallFloat::try_ln_interval(
  self : BallFloat,
) -> Result[BallFloat, @def.ArithmeticError] {
  if self.is_empty() {
    return Ok(self)
  }
  let zero = @bin_float.BinFloat::zero(precision=self.precision_)
  if self.hi_.compare(zero) <= 0 {
    return Ok(empty_interval(self.precision_))
  }
  let upward = @bin_float.BinaryContext::unbounded(
    self.precision_,
    rounding=@bin_float.BinaryRoundingMode::RoundTowardPositive,
  )
  let upper = self.hi_.try_ln_ctx(upward)
  if self.lo_.compare(zero) <= 0 {
    return upper.map(fn(result) {
      store_interval(neg_inf(self.precision_), result.0, self.precision_)
    })
  }
  let downward = @bin_float.BinaryContext::unbounded(
    self.precision_,
    rounding=@bin_float.BinaryRoundingMode::RoundTowardNegative,
  )
  self.lo_
  .try_ln_ctx(downward)
  .bind(fn(lower) {
    upper.map(fn(upper_result) {
      store_interval(lower.0, upper_result.0, self.precision_)
    })
  })
}

///|
pub fn BallFloat::try_log1p_interval(
  self : BallFloat,
) -> Result[BallFloat, @def.ArithmeticError] {
  if self.is_empty() {
    return Ok(self)
  }
  let minus_one = @bin_float.BinFloat::from_int(-1, precision=self.precision_)
  if self.hi_.compare(minus_one) < 0 {
    return Ok(empty_interval(self.precision_))
  }
  let downward = @bin_float.BinaryContext::unbounded(
    self.precision_,
    rounding=@bin_float.BinaryRoundingMode::RoundTowardNegative,
  )
  let upward = @bin_float.BinaryContext::unbounded(
    self.precision_,
    rounding=@bin_float.BinaryRoundingMode::RoundTowardPositive,
  )
  let lower = if self.lo_.compare(minus_one) <= 0 {
    Ok(neg_inf(self.precision_))
  } else {
    self.lo_.try_log1p_ctx(downward).map(fn(result) { result.0 })
  }
  let upper = if is_pos_inf(self.hi_) {
    Ok(pos_inf(self.precision_))
  } else {
    self.hi_.try_log1p_ctx(upward).map(fn(result) { result.0 })
  }
  lower.bind(fn(lower_bound) {
    upper.map(fn(upper_bound) {
      store_interval(lower_bound, upper_bound, self.precision_)
    })
  })
}

///|
pub fn BallFloat::try_sin_interval(
  self : BallFloat,
) -> Result[BallFloat, @def.ArithmeticError] {
  if self.is_empty() {
    return Ok(self)
  }
  if !self.is_bounded() {
    return Ok(unit_interval(self.precision_))
  }
  let initial_work = Int::max(
    trig_initial_work(self.lo_, self.precision_),
    trig_initial_work(self.hi_, self.precision_),
  )
  guard !trig_cutoff_exceeded(self) else {
    return Err(
      ball_range_resource_failure("sin", self.precision_, initial_work),
    )
  }
  match certified_sin_cos_interval_bounds(self) {
    Some(bounds) => {
      let lower = if index_range_contains_residue(bounds.8, bounds.9, 3) {
        @bin_float.BinFloat::from_int(-1, precision=self.precision_)
      } else {
        bin_min(bounds.0, bounds.4)
      }
      let upper = if index_range_contains_residue(bounds.8, bounds.9, 1) {
        @bin_float.BinFloat::one(precision=self.precision_)
      } else {
        bin_max(bounds.1, bounds.5)
      }
      Ok(store_interval(lower, upper, self.precision_))
    }
    None =>
      Err(ball_certification_failure("sin", self.precision_, initial_work))
  }
}

///|
pub fn BallFloat::try_cos_interval(
  self : BallFloat,
) -> Result[BallFloat, @def.ArithmeticError] {
  if self.is_empty() {
    return Ok(self)
  }
  if !self.is_bounded() {
    return Ok(unit_interval(self.precision_))
  }
  let initial_work = Int::max(
    trig_initial_work(self.lo_, self.precision_),
    trig_initial_work(self.hi_, self.precision_),
  )
  guard !trig_cutoff_exceeded(self) else {
    return Err(
      ball_range_resource_failure("cos", self.precision_, initial_work),
    )
  }
  match certified_sin_cos_interval_bounds(self) {
    Some(bounds) => {
      let lower = if index_range_contains_residue(bounds.8, bounds.9, 2) {
        @bin_float.BinFloat::from_int(-1, precision=self.precision_)
      } else {
        bin_min(bounds.2, bounds.6)
      }
      let upper = if index_range_contains_residue(bounds.8, bounds.9, 0) {
        @bin_float.BinFloat::one(precision=self.precision_)
      } else {
        bin_max(bounds.3, bounds.7)
      }
      Ok(store_interval(lower, upper, self.precision_))
    }
    None =>
      Err(ball_certification_failure("cos", self.precision_, initial_work))
  }
}

///|
pub fn BallFloat::try_tan_interval(
  self : BallFloat,
) -> Result[BallFloat, @def.ArithmeticError] {
  if self.is_empty() {
    return Ok(self)
  }
  if !self.is_bounded() {
    return Ok(whole_real(self.precision_))
  }
  let initial_work = Int::max(
    trig_initial_work(self.lo_, self.precision_),
    trig_initial_work(self.hi_, self.precision_),
  )
  guard !trig_cutoff_exceeded(self) else {
    return Err(
      ball_range_resource_failure("tan", self.precision_, initial_work),
    )
  }
  match certified_tan_interval_bounds(self) {
    Bounds(lower, upper) => Ok(store_interval(lower, upper, self.precision_))
    Pole => Ok(whole_real(self.precision_))
    Failure =>
      Err(ball_certification_failure("tan", self.precision_, initial_work))
  }
}

///|
