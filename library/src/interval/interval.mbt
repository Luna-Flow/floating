///|
/// An interval of `precision_` bits: the closed interval `[lo_, hi_]` of two
/// `Binary`s, or the empty set.
///
/// The bounds. Every stored bound is a number of the format of `precision_` bits
/// (at most `precision_` significant bits, on the grid of `precision_` bits, the
/// band below the range floor included, in the exponent range of the library) or an
/// infinity, and its `precision()` is `precision_`: the format of a bound is the
/// format of the interval (the inf-sup type of IEEE 1788-2015 12.5.2). A constructor
/// or an operation whose exact end is not such a number rounds it outward (the lower
/// end down, the upper end up). `Binary`'s `==` agrees with `compare`; the `==` of
/// `Interval` compares the bounds by value and `identical` compares the bounds by value
/// and the precision of the interval.
/// The sign of a stored zero is unspecified: the accessors decide.
/// `store_interval` and `empty_interval` are the only writers of the fields.
#derive(Debug)
pub struct Interval {
  priv lo_ : @binary.Binary
  priv hi_ : @binary.Binary
  priv precision_ : Int32
  priv empty_ : Bool
}

///|
/// The relative position of two intervals: the 16 overlapping states of
/// IEEE 1788-2015 Table 10.7 (10.6.4). The state names the position of the first interval
/// with respect to the second: `Before` when the first ends below the start of
/// the second, `Meets` when its upper bound equals the other's lower bound, and
/// so on; `BothEmpty`, `FirstEmpty` and `SecondEmpty` cover empty operands.
#derive(Eq, Debug)
pub(all) enum OverlapState {
  BothEmpty
  FirstEmpty
  SecondEmpty
  Before
  Meets
  Overlaps
  Starts
  ContainedBy
  Finishes
  Equals
  After
  MetBy
  OverlappedBy
  StartedBy
  Contains
  FinishedBy
}

///|
fn neg_inf(precision : Int32) -> @binary.Binary {
  @binary.Binary::inf(negative=true, precision~)
}

///|
fn pos_inf(precision : Int32) -> @binary.Binary {
  @binary.Binary::inf(precision~)
}

///|
fn is_neg_inf(x : @binary.Binary) -> Bool {
  x.classify() == FpClass::Infinity && x.signum() == Sign::Negative
}

///|
fn is_pos_inf(x : @binary.Binary) -> Bool {
  x.classify() == FpClass::Infinity && x.signum() == Sign::Positive
}

///|
/// The error for a precision outside `1..=binary_precision_max`, the limits of
/// a binary format (`BinaryContext`).
fn precision_error(precision : Int32) -> String? {
  if precision < 1 {
    Some("interval precision must be at least 1")
  } else if precision > @binary.binary_precision_max {
    Some("interval precision exceeds binary_precision_max")
  } else {
    None
  }
}

///|
/// `precision` itself, or an abort naming the limits: a precision is never
/// replaced silently.
fn checked_precision(precision : Int32) -> Int32 {
  match precision_error(precision) {
    Some(message) => abort(message)
    None => precision
  }
}

///|
fn interval_validation_error(
  lo : @binary.Binary,
  hi : @binary.Binary,
) -> String? {
  if lo.classify() == FpClass::NaN || hi.classify() == FpClass::NaN {
    Some("interval bounds must not be NaN")
  } else if is_pos_inf(lo) {
    Some("interval lower bound must not be positive infinity")
  } else if is_neg_inf(hi) {
    Some("interval upper bound must not be negative infinity")
  } else if lo.compare(hi) > 0 {
    Some("interval lower bound must not exceed upper bound")
  } else {
    None
  }
}

///|
fn validate_interval(lo : @binary.Binary, hi : @binary.Binary) -> Unit {
  match interval_validation_error(lo, hi) {
    Some(message) => abort(message)
    None => ()
  }
}

///|
fn checked_interval(
  lo : @binary.Binary,
  hi : @binary.Binary,
  precision : Int32,
) -> Result[Interval, String] {
  if precision_error(precision) is Some(message) {
    return Err(message)
  }
  match interval_validation_error(lo, hi) {
    Some(message) => Err(message)
    None => Ok(store_interval(lo, hi, precision))
  }
}

///|
fn checked_exact(
  value : @binary.Binary,
  precision : Int32,
) -> Result[Interval, String] {
  if precision_error(precision) is Some(message) {
    return Err(message)
  }
  guard value.classify() == FpClass::Finite else {
    return Err("interval exact source must be finite")
  }
  Ok(zero_radius_interval(value, precision))
}

///|
/// `coefficient * 2^exponent2` as a `Binary`, exactly. `exact_range`: the value is made at
/// `max(bit length, e_min - exponent2 + 1)` bits, so that the quantum below the normal range of
/// the make, `2^(e_min - bits + 1)`, is at most the lowest bit of the value and nothing is rounded
/// (made at its own bit length, a value of a few bits below the normal range is rounded to the
/// quantum of those few bits). A value outside the exponent range of the library is clamped by
/// the make, on the side `mode` says (to the infinity or the largest finite value, to zero or the
/// smallest positive value).
fn exact_value(
  coefficient : @binary.BinCoeff,
  exponent2 : Int32,
  negative~ : Bool = false,
  exact_range~ : Bool = false,
  mode~ : BinaryRoundingMode = BinaryRoundingMode::RoundTiesToEven,
) -> @binary.Binary {
  let bits = Int32::max(1, coefficient.bit_length())
  let bits = if exact_range && !coefficient.is_zero() {
    Int32::min(
      @binary.binary_precision_max,
      Int32::max(bits, @binary.binary_value_e_min - exponent2 + 1),
    )
  } else {
    bits
  }
  @binary.Binary::make(coefficient, exponent2, bits, negative~, mode~)
}

///|
fn exponent_top(x : @binary.Binary) -> Int64 {
  x.ilogb().unwrap().to_int64()
}

///|
/// `a + b` of two finite values rounded once to `precision` bits in the direction `mode`: the
/// directed `add_ctx` of `binary` in the exponent range of the library. A zero operand
/// returns the other one rounded; an exact cancellation is a zero (the sign of a stored zero is
/// not part of the interval).
fn directed_add(
  a : @binary.Binary,
  b : @binary.Binary,
  precision : Int32,
  mode : BinaryRoundingMode,
) -> @binary.Binary {
  a.add_ctx(b, @binary.BinaryContext::new(precision~, rounding=mode)).0
}

///|
/// `a - b` rounded once to `precision` bits in the direction `mode` (`sub_ctx`).
fn directed_sub(
  a : @binary.Binary,
  b : @binary.Binary,
  precision : Int32,
  mode : BinaryRoundingMode,
) -> @binary.Binary {
  a.sub_ctx(b, @binary.BinaryContext::new(precision~, rounding=mode)).0
}

///|
/// `a * b` of two finite non-zero values rounded once to `precision` bits in the direction
/// `mode` (`mul_ctx`; a product rounded to zero keeps its sign).
fn directed_mul(
  a : @binary.Binary,
  b : @binary.Binary,
  precision : Int32,
  mode : BinaryRoundingMode,
) -> @binary.Binary {
  a.mul_ctx(b, @binary.BinaryContext::new(precision~, rounding=mode)).0
}

///|
/// `x / 2`, exactly (the exponent is lowered by one; the value is made wide enough that nothing
/// is rounded below the normal range).
fn halve(x : @binary.Binary) -> @binary.Binary {
  exact_value(
    x.coefficient(),
    x.exponent2() - 1,
    negative=x.is_sign_minus(),
    exact_range=true,
  )
}

///|
/// Bits kept by the sum of the exact center: the sum of two bounds of `precision` bits whose
/// exponents differ by more than this is not formed exactly (the part below is a sticky bit).
let center_margin : Int32 = 65536

///|
fn center_bits(precision : Int32) -> Int32 {
  Int32::min(
    @binary.binary_precision_max,
    Int32::max(precision, 1) + center_margin + 2,
  )
}

///|
/// `a + b` of two finite values, rounded toward zero to `bits` bits and, when that rounding was
/// inexact, made odd (round to odd: the last of the `bits` bits is set). A later rounding to at
/// most `bits - 2` bits in any direction is then the rounding of the exact sum, once (no double
/// rounding). The sum is exact when it has at most `bits` bits.
fn odd_sum(
  a : @binary.Binary,
  b : @binary.Binary,
  bits : Int32,
) -> @binary.Binary {
  let (sum, flags) = a.add_ctx(
    b,
    @binary.BinaryContext::new(
      precision=bits,
      rounding=BinaryRoundingMode::RoundTowardZero,
    ),
  )
  if !flags.inexact() || sum.is_zero() {
    return sum
  }
  // the coefficient is odd (normalized): place a final bit below its `bits` bits
  let shift = bits - sum.coefficient().bit_length()
  if shift <= 0 {
    return sum
  }
  exact_value(
    coeff_add(coeff_shift_left(sum.coefficient(), shift), coeff_one()),
    sum.exponent2() - shift,
    negative=sum.is_sign_minus(),
    exact_range=true,
  )
}

///|
/// The hull in the format of `precision` bits of `[center - radius, center + radius]`
/// (IEEE 1788-2015 12.12.7, `midRadToInterval`): the exact `center - radius` rounded down
/// and the exact `center + radius` rounded up, once each.
fn midpoint_radius_interval(
  center : @binary.Binary,
  radius : @binary.Binary,
  precision : Int32,
) -> Interval {
  guard center.classify() == FpClass::Finite else {
    abort("interval center must be finite")
  }
  guard radius.classify() == FpClass::Finite else {
    abort("interval radius must be finite")
  }
  guard radius.signum() != Sign::Negative else {
    abort("interval radius must be non-negative")
  }
  let precision = checked_precision(precision)
  let lo = center.sub_ctx(
      radius,
      @binary.BinaryContext::new(
        precision~,
        rounding=BinaryRoundingMode::RoundTowardNegative,
      ),
    ).0
  let hi = center.add_ctx(
      radius,
      @binary.BinaryContext::new(
        precision~,
        rounding=BinaryRoundingMode::RoundTowardPositive,
      ),
    ).0
  store_interval(lo, hi, precision)
}

///|
fn lower_round_bound(x : @binary.Binary, precision : Int32) -> @binary.Binary {
  let precision = checked_precision(precision)
  match x.classify() {
    FpClass::Finite =>
      if x.precision() == precision {
        x
      } else {
        x.with_precision(
          precision,
          @binary.BinaryRoundingMode::RoundTowardNegative,
        )
      }
    FpClass::Infinity =>
      if x.precision() == precision {
        x
      } else {
        @binary.Binary::inf(negative=x.is_sign_minus(), precision~)
      }
    FpClass::NaN => abort("interval bounds must not be NaN")
  }
}

///|
fn upper_round_bound(x : @binary.Binary, precision : Int32) -> @binary.Binary {
  let precision = checked_precision(precision)
  match x.classify() {
    FpClass::Finite =>
      if x.precision() == precision {
        x
      } else {
        x.with_precision(
          precision,
          @binary.BinaryRoundingMode::RoundTowardPositive,
        )
      }
    FpClass::Infinity =>
      if x.precision() == precision {
        x
      } else {
        @binary.Binary::inf(negative=x.is_sign_minus(), precision~)
      }
    FpClass::NaN => abort("interval bounds must not be NaN")
  }
}

///|
/// The interval `[lo, hi]` in the format of `precision` bits. A bound that is already a
/// number of that format (the case of every result of an operation) is only relabelled,
/// which does not change its value; any other bound is rounded outward (`lo` down, `hi` up).
fn store_interval(
  lo : @binary.Binary,
  hi : @binary.Binary,
  precision : Int32,
) -> Interval {
  validate_interval(lo, hi)
  let precision = checked_precision(precision)
  {
    lo_: lower_round_bound(lo, precision),
    hi_: upper_round_bound(hi, precision),
    precision_: precision,
    empty_: false,
  }
}

///|
fn empty_interval(precision : Int32) -> Interval {
  let precision = checked_precision(precision)
  {
    lo_: pos_inf(precision),
    hi_: neg_inf(precision),
    precision_: precision,
    empty_: true,
  }
}

///|
/// Whether a bound is so large that the sum or difference of two such bounds can leave the
/// exponent range (the halves are then formed first: they are exact there).
fn near_range_top(x : @binary.Binary) -> Bool {
  !x.is_zero() && exponent_top(x) >= @binary.binary_value_e_max.to_int64() - 1L
}

///|
/// The exact center `(lower + upper) / 2` of a bounded nonempty interval: the half of the sum
/// of the bounds, the sum made odd when it has more than `center_bits` bits (an exponent gap
/// of more than 65,536 places), so that the caller rounds the result once, to at most `bits`
/// bits. Near the top of the range the sum of the halves is formed instead (the sum of the
/// bounds could overflow).
fn interval_center(x : Interval, bits : Int32) -> @binary.Binary {
  guard !x.is_empty() else {
    abort("interval center is undefined for an empty interval")
  }
  guard x.is_common_interval() else {
    abort("interval center is undefined for unbounded intervals")
  }
  let w = center_bits(bits)
  if near_range_top(x.lo_) || near_range_top(x.hi_) {
    odd_sum(halve(x.lo_), halve(x.hi_), w)
  } else {
    halve(odd_sum(x.lo_, x.hi_, w))
  }
}

///|
fn zero_radius_interval(x : @binary.Binary, precision : Int32) -> Interval {
  store_interval(x, x, precision)
}

///|
fn whole_real(precision : Int32) -> Interval {
  store_interval(neg_inf(precision), pos_inf(precision), precision)
}

///|
/// One directed quotient: `upper` selects round-toward-positive, otherwise
/// round-toward-negative. An interval division needs exactly one directed
/// quotient per bound, so this performs one `div_ctx` instead of the two
/// (down and up) of which half used to be discarded.
fn directed_division(
  numerator : @binary.Binary,
  denominator : @binary.Binary,
  precision : Int32,
  upper : Bool,
) -> @binary.Binary {
  let rounding = if upper {
    @binary.BinaryRoundingMode::RoundTowardPositive
  } else {
    @binary.BinaryRoundingMode::RoundTowardNegative
  }
  numerator.div_ctx(
    denominator,
    @binary.BinaryContext::new(precision~, rounding~),
  ).0
}

///|
fn extended_division_bound(
  numerator : @binary.Binary,
  denominator : @binary.Binary,
  precision : Int32,
  upper : Bool,
) -> @binary.Binary {
  if numerator.is_zero() || denominator.classify() == FpClass::Infinity {
    return @binary.Binary::zero(precision~)
  }
  if numerator.classify() == FpClass::Infinity {
    let negative = numerator.signum() != denominator.signum()
    return @binary.Binary::inf(negative~, precision~)
  }
  directed_division(numerator, denominator, precision, upper)
}

///|
fn quotient_interval_nonzero_denominator(
  numerator : Interval,
  denominator : Interval,
  precision : Int32,
) -> Interval {
  let numerator_nonnegative = numerator.lo_.is_zero() ||
    numerator.lo_.signum() == Sign::Positive
  let numerator_nonpositive = numerator.hi_.is_zero() ||
    numerator.hi_.signum() == Sign::Negative
  let denominator_positive = denominator.lo_.signum() == Sign::Positive
  let lower = if denominator_positive {
    if numerator_nonnegative || numerator_nonpositive {
      extended_division_bound(
        numerator.lo_,
        if numerator_nonnegative {
          denominator.hi_
        } else {
          denominator.lo_
        },
        precision,
        false,
      )
    } else {
      extended_division_bound(numerator.lo_, denominator.lo_, precision, false)
    }
  } else if numerator_nonnegative {
    extended_division_bound(numerator.hi_, denominator.hi_, precision, false)
  } else if numerator_nonpositive {
    extended_division_bound(numerator.hi_, denominator.lo_, precision, false)
  } else {
    extended_division_bound(numerator.hi_, denominator.hi_, precision, false)
  }
  let upper = if denominator_positive {
    if numerator_nonnegative {
      extended_division_bound(numerator.hi_, denominator.lo_, precision, true)
    } else if numerator_nonpositive {
      extended_division_bound(numerator.hi_, denominator.hi_, precision, true)
    } else {
      extended_division_bound(numerator.hi_, denominator.lo_, precision, true)
    }
  } else if numerator_nonnegative {
    extended_division_bound(numerator.lo_, denominator.lo_, precision, true)
  } else if numerator_nonpositive {
    extended_division_bound(numerator.lo_, denominator.hi_, precision, true)
  } else {
    extended_division_bound(numerator.lo_, denominator.hi_, precision, true)
  }
  store_interval(lower, upper, precision)
}

///|
fn pow_nat(base : Interval, exponent : UInt32, precision : Int32) -> Interval {
  if base.is_empty() {
    return empty_interval(precision)
  }
  let mut n = exponent
  let mut result = Interval::from_int(1, precision~)
  let mut factor = base.with_precision(precision)
  while n > 0U {
    if (n & 1U) == 1U {
      result = (result * factor).with_precision(precision)
    }
    n = n >> 1
    if n > 0U {
      factor = (factor * factor).with_precision(precision)
    }
  }
  result
}

///|
fn add_interval_impl(a : Interval, b : Interval) -> Interval {
  let precision = Int32::max(a.precision_, b.precision_)
  if a.is_empty() || b.is_empty() {
    return empty_interval(precision)
  }
  if a.is_common_interval() && b.is_common_interval() {
    return store_interval(
      directed_add(
        a.lo_,
        b.lo_,
        precision,
        BinaryRoundingMode::RoundTowardNegative,
      ),
      directed_add(
        a.hi_,
        b.hi_,
        precision,
        BinaryRoundingMode::RoundTowardPositive,
      ),
      precision,
    )
  }
  // Lower endpoints are finite or -inf and upper ones finite or +inf, so the
  // extended sums never meet opposite infinities.
  store_interval(
    extended_directed_add(
      a.lo_,
      b.lo_,
      precision,
      BinaryRoundingMode::RoundTowardNegative,
    ),
    extended_directed_add(
      a.hi_,
      b.hi_,
      precision,
      BinaryRoundingMode::RoundTowardPositive,
    ),
    precision,
  )
}

///|
fn sub_interval_impl(a : Interval, b : Interval) -> Interval {
  let precision = Int32::max(a.precision_, b.precision_)
  if a.is_empty() || b.is_empty() {
    return empty_interval(precision)
  }
  if a.is_common_interval() && b.is_common_interval() {
    return store_interval(
      directed_sub(
        a.lo_,
        b.hi_,
        precision,
        BinaryRoundingMode::RoundTowardNegative,
      ),
      directed_sub(
        a.hi_,
        b.lo_,
        precision,
        BinaryRoundingMode::RoundTowardPositive,
      ),
      precision,
    )
  }
  store_interval(
    extended_directed_sub(
      a.lo_,
      b.hi_,
      precision,
      BinaryRoundingMode::RoundTowardNegative,
    ),
    extended_directed_sub(
      a.hi_,
      b.lo_,
      precision,
      BinaryRoundingMode::RoundTowardPositive,
    ),
    precision,
  )
}

///|
fn bin_min(a : @binary.Binary, b : @binary.Binary) -> @binary.Binary {
  if a.compare(b) <= 0 {
    a
  } else {
    b
  }
}

///|
fn bin_max(a : @binary.Binary, b : @binary.Binary) -> @binary.Binary {
  if a.compare(b) >= 0 {
    a
  } else {
    b
  }
}

///|
/// Set-based interval endpoints identify both signed zeros with the real 0.
fn canonical_interval_endpoint(
  value : @binary.Binary,
  precision : Int32,
) -> @binary.Binary {
  if value.is_zero() {
    @binary.Binary::zero(precision~)
  } else {
    value
  }
}

///|
fn extended_mul(
  a : @binary.Binary,
  b : @binary.Binary,
  precision : Int32,
  mode : BinaryRoundingMode,
) -> @binary.Binary {
  if a.is_zero() || b.is_zero() {
    return @binary.Binary::zero(precision~)
  }
  if a.classify() == FpClass::Infinity || b.classify() == FpClass::Infinity {
    let negative = a.signum() != b.signum()
    return @binary.Binary::inf(negative~, precision~)
  }
  directed_mul(a, b, precision, mode)
}

///|
/// Both directed products of `extended_mul`, each rounded once to `precision` bits: the
/// coefficient product is formed once and rounded by `Binary::make`, the rounding of the binary
/// layer (gradual underflow and overflow included), toward negative and toward positive (two
/// `mul_ctx` of the same operands would multiply twice; measured cheaper at 53, 128 and 512 bits).
fn extended_mul_both(
  a : @binary.Binary,
  b : @binary.Binary,
  precision : Int32,
) -> (@binary.Binary, @binary.Binary) {
  if a.is_zero() ||
    b.is_zero() ||
    a.classify() == FpClass::Infinity ||
    b.classify() == FpClass::Infinity {
    let r = extended_mul(
      a,
      b,
      precision,
      BinaryRoundingMode::RoundTowardNegative,
    )
    return (r, r)
  }
  // the exponent sum saturates, so that one beyond 32 bits keeps its direction
  let exponent = a.exponent2().to_int64() + b.exponent2().to_int64()
  let exponent = if exponent > 2147483647L {
    2147483647
  } else if exponent < -2147483648L {
    -2147483648
  } else {
    exponent.to_int()
  }
  let coefficient = coeff_mul(a.coefficient(), b.coefficient())
  let negative = a.is_sign_minus() != b.is_sign_minus()
  (
    @binary.Binary::make(
      coefficient,
      exponent,
      precision,
      negative~,
      mode=BinaryRoundingMode::RoundTowardNegative,
    ),
    @binary.Binary::make(
      coefficient,
      exponent,
      precision,
      negative~,
      mode=BinaryRoundingMode::RoundTowardPositive,
    ),
  )
}

///|
/// An interval endpoint sum rounded once to `precision` bits in `mode`: an infinite
/// addend is the result.
fn extended_directed_add(
  a : @binary.Binary,
  b : @binary.Binary,
  precision : Int32,
  mode : BinaryRoundingMode,
) -> @binary.Binary {
  if a.classify() == FpClass::Infinity {
    return a
  }
  if b.classify() == FpClass::Infinity {
    return b
  }
  directed_add(a, b, precision, mode)
}

///|
/// `extended_directed_add(a, -b)`.
fn extended_directed_sub(
  a : @binary.Binary,
  b : @binary.Binary,
  precision : Int32,
  mode : BinaryRoundingMode,
) -> @binary.Binary {
  if a.classify() == FpClass::Infinity {
    return a
  }
  if b.classify() == FpClass::Infinity {
    return b.neg()
  }
  directed_sub(a, b, precision, mode)
}

///|
fn multiplication_bounds(
  a : Interval,
  b : Interval,
  precision : Int32,
) -> (@binary.Binary, @binary.Binary) {
  if a.is_common_interval() && b.is_common_interval() {
    let a_nonnegative = a.lo_.is_zero() || a.lo_.signum() == Sign::Positive
    let a_nonpositive = a.hi_.is_zero() || a.hi_.signum() == Sign::Negative
    let b_nonnegative = b.lo_.is_zero() || b.lo_.signum() == Sign::Positive
    let b_nonpositive = b.hi_.is_zero() || b.hi_.signum() == Sign::Negative
    if a_nonnegative && b_nonnegative {
      return (
        extended_mul(
          a.lo_,
          b.lo_,
          precision,
          BinaryRoundingMode::RoundTowardNegative,
        ),
        extended_mul(
          a.hi_,
          b.hi_,
          precision,
          BinaryRoundingMode::RoundTowardPositive,
        ),
      )
    }
    if a_nonpositive && b_nonpositive {
      return (
        extended_mul(
          a.hi_,
          b.hi_,
          precision,
          BinaryRoundingMode::RoundTowardNegative,
        ),
        extended_mul(
          a.lo_,
          b.lo_,
          precision,
          BinaryRoundingMode::RoundTowardPositive,
        ),
      )
    }
    if a_nonnegative && b_nonpositive {
      return (
        extended_mul(
          a.hi_,
          b.lo_,
          precision,
          BinaryRoundingMode::RoundTowardNegative,
        ),
        extended_mul(
          a.lo_,
          b.hi_,
          precision,
          BinaryRoundingMode::RoundTowardPositive,
        ),
      )
    }
    if a_nonpositive && b_nonnegative {
      return (
        extended_mul(
          a.lo_,
          b.hi_,
          precision,
          BinaryRoundingMode::RoundTowardNegative,
        ),
        extended_mul(
          a.hi_,
          b.lo_,
          precision,
          BinaryRoundingMode::RoundTowardPositive,
        ),
      )
    }
    // One operand straddles zero, the other is sign-definite and not [0, 0]:
    // the extreme products are fixed by the signs, 2 products instead of 4.
    let a_straddles = !a_nonnegative && !a_nonpositive
    let b_straddles = !b_nonnegative && !b_nonpositive
    let a_zero = a.lo_.is_zero() && a.hi_.is_zero()
    let b_zero = b.lo_.is_zero() && b.hi_.is_zero()
    if a_straddles && b_nonnegative && !b_zero {
      return (
        extended_mul(
          a.lo_,
          b.hi_,
          precision,
          BinaryRoundingMode::RoundTowardNegative,
        ),
        extended_mul(
          a.hi_,
          b.hi_,
          precision,
          BinaryRoundingMode::RoundTowardPositive,
        ),
      )
    }
    if a_straddles && b_nonpositive && !b_zero {
      return (
        extended_mul(
          a.hi_,
          b.lo_,
          precision,
          BinaryRoundingMode::RoundTowardNegative,
        ),
        extended_mul(
          a.lo_,
          b.lo_,
          precision,
          BinaryRoundingMode::RoundTowardPositive,
        ),
      )
    }
    if b_straddles && a_nonnegative && !a_zero {
      return (
        extended_mul(
          a.hi_,
          b.lo_,
          precision,
          BinaryRoundingMode::RoundTowardNegative,
        ),
        extended_mul(
          a.hi_,
          b.hi_,
          precision,
          BinaryRoundingMode::RoundTowardPositive,
        ),
      )
    }
    if b_straddles && a_nonpositive && !a_zero {
      return (
        extended_mul(
          a.lo_,
          b.hi_,
          precision,
          BinaryRoundingMode::RoundTowardNegative,
        ),
        extended_mul(
          a.lo_,
          b.lo_,
          precision,
          BinaryRoundingMode::RoundTowardPositive,
        ),
      )
    }
    let lower_left = extended_mul(
      a.lo_,
      b.hi_,
      precision,
      BinaryRoundingMode::RoundTowardNegative,
    )
    let lower_right = extended_mul(
      a.hi_,
      b.lo_,
      precision,
      BinaryRoundingMode::RoundTowardNegative,
    )
    let upper_left = extended_mul(
      a.lo_,
      b.lo_,
      precision,
      BinaryRoundingMode::RoundTowardPositive,
    )
    let upper_right = extended_mul(
      a.hi_,
      b.hi_,
      precision,
      BinaryRoundingMode::RoundTowardPositive,
    )
    return (bin_min(lower_left, lower_right), bin_max(upper_left, upper_right))
  }
  // Unbounded operand: every corner is needed in both directions, but the
  // coefficient product of a finite pair is shared between them (the
  // direction only matters when the exponent clamps), so each corner costs
  // one big-integer product instead of two.
  let corners = [(a.lo_, b.lo_), (a.lo_, b.hi_), (a.hi_, b.lo_), (a.hi_, b.hi_)]
  let mut lower : @binary.Binary? = None
  let mut upper : @binary.Binary? = None
  for corner in corners {
    let (x, y) = corner
    let (d, u) = extended_mul_both(x, y, precision)
    lower = match lower {
      None => Some(d)
      Some(m) => Some(bin_min(m, d))
    }
    upper = match upper {
      None => Some(u)
      Some(m) => Some(bin_max(m, u))
    }
  }
  (lower.unwrap(), upper.unwrap())
}

///|
fn mul_interval_impl(a : Interval, b : Interval) -> Interval {
  let precision = Int32::max(a.precision_, b.precision_)
  if a.is_empty() || b.is_empty() {
    return empty_interval(precision)
  }
  let (lo, hi) = multiplication_bounds(a, b, precision)
  store_interval(lo, hi, precision)
}

///|
fn div_interval_impl(a : Interval, b : Interval) -> Interval {
  let precision = Int32::max(a.precision_, b.precision_)
  if a.is_empty() || b.is_empty() {
    return empty_interval(precision)
  }
  if b.lo_.is_zero() && b.hi_.is_zero() {
    return empty_interval(precision)
  }
  if a.lo_.is_zero() && a.hi_.is_zero() {
    return zero_radius_interval(@binary.Binary::zero(precision~), precision)
  }
  if !b.contains_zero() {
    return quotient_interval_nonzero_denominator(a, b, precision)
  }
  if b.lo_.signum() == Sign::Negative && b.hi_.signum() == Sign::Positive {
    return whole_real(precision)
  }
  if a.lo_.signum() == Sign::Negative && a.hi_.signum() == Sign::Positive {
    return whole_real(precision)
  }
  if b.lo_.is_zero() {
    let zero = @binary.Binary::zero(precision~)
    let finite = if is_pos_inf(b.hi_) {
      zero_radius_interval(zero, precision)
    } else {
      let one_sided = Interval::from_bounds(b.hi_, b.hi_, precision~)
      quotient_interval_nonzero_denominator(a, one_sided, precision)
    }
    if a.hi_.signum() == Sign::Positive {
      return store_interval(finite.lo_, pos_inf(precision), precision)
    }
    return store_interval(neg_inf(precision), finite.hi_, precision)
  }
  if b.hi_.is_zero() {
    let zero = @binary.Binary::zero(precision~)
    let finite = if is_neg_inf(b.lo_) {
      zero_radius_interval(zero, precision)
    } else {
      let one_sided = Interval::from_bounds(b.lo_, b.lo_, precision~)
      quotient_interval_nonzero_denominator(a, one_sided, precision)
    }
    if a.hi_.signum() == Sign::Positive {
      return store_interval(neg_inf(precision), finite.hi_, precision)
    }
    return store_interval(finite.lo_, pos_inf(precision), precision)
  }
  whole_real(precision)
}

///|
/// The interval `[center - radius, center + radius]` in a format of `precision`
/// bits (`midRadToInterval` of IEEE 1788-2015 12.12.7): the lower bound is
/// `center - radius` rounded down and the upper bound `center + radius`
/// rounded up, once each. `precision` defaults to the larger of the two
/// precisions. Aborts when `center` or `radius` is not finite, `radius` is
/// negative or `precision` is outside `1..=binary_precision_max`; the
/// `try_` form returns an `Err` instead.
pub fn Interval::from_midpoint_radius(
  center : @binary.Binary,
  radius : @binary.Binary,
  precision~ : Int32 = Int32::max(center.precision(), radius.precision()),
) -> Interval {
  midpoint_radius_interval(center, radius, precision)
}

///|
/// `from_midpoint_radius` that reports an invalid center or radius as an error: a center that
/// is not finite, a radius that is not finite or is negative.
pub fn Interval::try_from_midpoint_radius(
  center : @binary.Binary,
  radius : @binary.Binary,
  precision~ : Int32 = Int32::max(center.precision(), radius.precision()),
) -> Result[Interval, @def.ArithmeticError] {
  guard center.classify() == FpClass::Finite else {
    return Err(
      @def.ArithmeticError::domain_error("interval center must be finite"),
    )
  }
  guard radius.classify() == FpClass::Finite else {
    return Err(
      @def.ArithmeticError::domain_error("interval radius must be finite"),
    )
  }
  guard radius.signum() != Sign::Negative else {
    return Err(
      @def.ArithmeticError::domain_error("interval radius must be non-negative"),
    )
  }
  if precision_error(precision) is Some(message) {
    return Err(@def.ArithmeticError::domain_error(message))
  }
  Ok(midpoint_radius_interval(center, radius, precision))
}

///|
/// The interval `[lo, hi]` in a format of `precision` bits, which defaults to
/// the larger of the two precisions. A bound that is not a number of that
/// format is rounded outward (`lo` down, `hi` up). An infinite bound makes an
/// unbounded interval. Aborts when a bound is NaN, `lo` is positive infinity,
/// `hi` is negative infinity, `lo` exceeds `hi`, or `precision` is outside
/// `1..=binary_precision_max`; `try_from_bounds` returns an `Err` instead.
///
/// ```mbt check
/// test {
///   let one = @binary.Binary::from_int(1, precision=53)
///   let three = @binary.Binary::from_int(3, precision=53)
///   inspect(
///     @interval.Interval::from_bounds(one, three).to_string(),
///     content="[1, 3]",
///   )
/// }
/// ```
pub fn Interval::from_bounds(
  lo : @binary.Binary,
  hi : @binary.Binary,
  precision~ : Int32 = Int32::max(lo.precision(), hi.precision()),
) -> Interval {
  match Interval::try_from_bounds(lo, hi, precision~) {
    Ok(value) => value
    Err(error) => abort(error.message)
  }
}

///|
pub fn Interval::try_from_bounds(
  lo : @binary.Binary,
  hi : @binary.Binary,
  precision~ : Int32 = Int32::max(lo.precision(), hi.precision()),
) -> Result[Interval, @def.ArithmeticError] {
  checked_interval(lo, hi, precision).map_err(fn(message) {
    @def.ArithmeticError::domain_error(message)
  })
}

///|
/// The singleton interval `[x, x]` in a format of `precision` bits, which
/// defaults to the precision of `x`. When `x` does not fit the format the
/// interval is widened outward so that it still contains `x`. Aborts when `x`
/// is not finite or `precision` is outside `1..=binary_precision_max`;
/// `try_exact` returns an `Err` instead.
pub fn Interval::exact(
  x : @binary.Binary,
  precision~ : Int32 = x.precision(),
) -> Interval {
  match Interval::try_exact(x, precision~) {
    Ok(value) => value
    Err(error) => abort(error.message)
  }
}

///|
pub fn Interval::try_exact(
  value : @binary.Binary,
  precision~ : Int32 = value.precision(),
) -> Result[Interval, @def.ArithmeticError] {
  checked_exact(value, precision).map_err(fn(message) {
    @def.ArithmeticError::domain_error(message)
  })
}

///|
/// The interval that contains the integer `n`, in a format of `precision`
/// bits: `n` is built exactly and the interval rounds outward, so a `precision`
/// below the bit length of `n` gives a non-singleton interval that still
/// contains `n`. `precision` has no default. Aborts when it is outside
/// `1..=binary_precision_max`.
///
/// ```mbt check
/// test {
///   inspect(
///     @interval.Interval::from_int(7, precision=53).to_string(),
///     content="[7, 7]",
///   )
/// }
/// ```
pub fn Interval::from_int(n : Int32, precision~ : Int32) -> Interval {
  // Build the integer exactly and let the interval round outward. Rounding it
  // to `precision` first produced a singleton that excluded its own input.
  Interval::exact(@binary.Binary::from_int(n, precision=32), precision~)
}

///|
pub fn Interval::from_coefficient(
  coefficient : @binary.BinCoeff,
  precision~ : Int32 = 53,
  negative~ : Bool = false,
) -> Interval {
  // As in `from_int`: keep the coefficient exact and round the interval
  // outward, so the result always contains the requested value.
  Interval::exact(
    @binary.Binary::from_coefficient(
      coefficient,
      precision=Int32::max(1, coefficient.bit_length()),
      negative~,
    ),
    precision~,
  )
}

///|
/// The interval that contains the double `x`, in a format of `precision` bits
/// (default 53): every double is held exactly first and the interval rounds
/// outward, so a double that does not fit `precision` gives a proper interval. Aborts when `x` is NaN or infinite or `precision` is
/// outside `1..=binary_precision_max`; `try_from_double` returns an `Err`
/// instead.
pub fn Interval::from_double(x : Double, precision~ : Int32 = 53) -> Interval {
  match Interval::try_from_double(x, precision~) {
    Ok(value) => value
    Err(error) => abort(error.message)
  }
}

///|
pub fn Interval::try_from_double(
  value : Double,
  precision~ : Int32 = 53,
) -> Result[Interval, @def.ArithmeticError] {
  // 53 bits hold every double exactly; the interval rounds outward to `precision`.
  let bin = @binary.Binary::from_double(value, precision=53)
  guard bin.classify() == FpClass::Finite else {
    return Err(
      @def.ArithmeticError::domain_error(
        "interval double source must be finite",
      ),
    )
  }
  checked_exact(bin, precision).map_err(fn(message) {
    @def.ArithmeticError::domain_error(message)
  })
}

///|
pub fn Interval::from_float(x : Float, precision~ : Int32 = 24) -> Interval {
  match Interval::try_from_float(x, precision~) {
    Ok(value) => value
    Err(error) => abort(error.message)
  }
}

///|
pub fn Interval::try_from_float(
  value : Float,
  precision~ : Int32 = 24,
) -> Result[Interval, @def.ArithmeticError] {
  // 24 bits hold every float exactly; the interval rounds outward to `precision`.
  let bin = @binary.Binary::from_float(value, precision=24)
  guard bin.classify() == FpClass::Finite else {
    return Err(
      @def.ArithmeticError::domain_error("interval float source must be finite"),
    )
  }
  checked_exact(bin, precision).map_err(fn(message) {
    @def.ArithmeticError::domain_error(message)
  })
}

///|
/// The whole real line `[-inf, +inf]` in a format of `precision` bits (default
/// 53). `is_entire` tests for it.
pub fn Interval::entire(precision~ : Int32 = 53) -> Interval {
  whole_real(precision)
}

///|
/// The empty set in a format of `precision` bits (default 53), which has no bounds; `to_string` gives
/// `[empty]`.
pub fn Interval::empty(precision~ : Int32 = 53) -> Interval {
  empty_interval(precision)
}

///|
/// `inf` of IEEE 1788-2015 12.12.8: the lower bound. In a format with a signed zero (`Binary`
/// has one) "a Level 1 value of 0 shall be returned as -0 by inf, and +0 by all other functions
/// in this subclause", so a zero lower bound is returned as -0 whatever sign the stored bound
/// has. Library code that needs the stored bound reads `lo_`: it does not depend on the sign of a
/// stored zero.
pub fn Interval::lower_bound(self : Interval) -> @binary.Binary {
  if self.lo_.is_zero() {
    @binary.Binary::negative_zero(precision=self.lo_.precision())
  } else {
    self.lo_
  }
}

///|
/// `sup` of IEEE 1788-2015 12.12.8: the upper bound; a zero upper bound is returned as +0
/// (see `lower_bound`).
pub fn Interval::upper_bound(self : Interval) -> @binary.Binary {
  if self.hi_.is_zero() {
    @binary.Binary::zero(precision=self.hi_.precision())
  } else {
    self.hi_
  }
}

///|
/// Whether the interval is the whole real line `[-inf, +inf]`.
pub fn Interval::is_entire(self : Interval) -> Bool {
  !self.empty_ && is_neg_inf(self.lo_) && is_pos_inf(self.hi_)
}

///|
/// Whether the interval is the empty set.
pub fn Interval::is_empty(self : Interval) -> Bool {
  self.empty_
}

///|
fn Interval::contains_zero(self : Interval) -> Bool {
  if self.is_empty() {
    return false
  }
  self.is_member(@binary.Binary::zero(precision=self.precision_))
}

///|
/// The context in which the observers of IEEE 1788-2015 12.12.8 return their
/// result: the precision of the interval and the widest exponent range.
fn observer_context(precision : Int32) -> IntervalContext {
  IntervalContext::new(precision~, e_max=@binary.binary_value_e_max)
}

///|
/// 12.12.8: a Level 1 value of 0 is returned as +0 by every function of the subclause but
/// `inf`, whatever sign the intermediate result has.
fn observer_zero(x : @binary.Binary) -> @binary.Binary {
  if x.is_zero() {
    @binary.Binary::zero(precision=x.precision())
  } else {
    x
  }
}

///|
/// `mid` of IEEE 1788-2015 12.12.8 (Table 9.2: `mid(x) = (lower + upper) / 2`),
/// total: NaN for Empty, 0 for Entire, the largest finite number of the format
/// (precision, widest exponent range) with the sign of the unbounded side for a
/// half-bounded interval, and for a bounded interval the exact midpoint rounded
/// once to nearest at the precision (the standard asks the implementation to
/// document how it handles this case: ties go to the even neighbour, 4.3.1 of
/// IEEE 754; a midpoint of 0 is +0). The exact midpoint is formed without
/// rounding, also below the normal range. `midpoint_ctx` takes the format.
pub fn Interval::midpoint(self : Interval) -> @binary.Binary {
  self.midpoint_ctx(observer_context(self.precision_)).0
}

///|
/// `rad` of IEEE 1788-2015 12.12.8, total: NaN for Empty, +infinity for an
/// unbounded interval, and otherwise "the smallest F-number r such that x is
/// contained in the exact interval [m - r, m + r], where m is the value
/// returned by mid(x)" (F: the format of the precision and the widest exponent
/// range; `m` is the value `midpoint` returns, not the exact center). The
/// distances `m - lower` and `upper - m` are formed exactly and the larger one
/// is rounded upward once to the precision, which is that smallest number.
pub fn Interval::radius(self : Interval) -> @binary.Binary {
  if self.is_empty() {
    return @binary.Binary::nan(precision=self.precision_)
  }
  if !self.is_common_interval() {
    return pos_inf(self.precision_)
  }
  let m = self.midpoint()
  let below = directed_sub(
    m,
    self.lo_,
    self.precision_,
    BinaryRoundingMode::RoundTowardPositive,
  )
  let above = directed_sub(
    self.hi_,
    m,
    self.precision_,
    BinaryRoundingMode::RoundTowardPositive,
  )
  observer_zero(bin_max(below, above))
}

///|
/// `wid` of IEEE 1788-2015 12.12.8: NaN for Empty, +infinity for an unbounded
/// interval, and otherwise "the Level 1 value rounded toward +infinity": the
/// exact difference `upper - lower` rounded upward once to the precision (the
/// smallest number of the format that is at least the width).
pub fn Interval::width(self : Interval) -> @binary.Binary {
  if self.is_empty() {
    return @binary.Binary::nan(precision=self.precision_)
  }
  if !self.is_common_interval() {
    return pos_inf(self.precision_)
  }
  observer_zero(
    directed_sub(
      self.hi_,
      self.lo_,
      self.precision_,
      BinaryRoundingMode::RoundTowardPositive,
    ),
  )
}

///|
/// `mag` of IEEE 1788-2015 12.12.8: the largest absolute value of a member,
/// `max(|lower|, |upper|)`, NaN for an empty interval and +infinity for an
/// unbounded one. A zero result is +0.
pub fn Interval::magnitude(self : Interval) -> @binary.Binary {
  if self.is_empty() {
    return @binary.Binary::nan(precision=self.precision_)
  }
  observer_zero(bin_max(self.lo_.abs(), self.hi_.abs()))
}

///|
/// `mig` of IEEE 1788-2015 12.12.8: the smallest absolute value of a member,
/// 0 when the interval contains 0, NaN for an empty interval. A zero result is
/// +0.
pub fn Interval::mignitude(self : Interval) -> @binary.Binary {
  if self.is_empty() {
    return @binary.Binary::nan(precision=self.precision_)
  }
  if self.contains_zero() {
    return @binary.Binary::zero(precision=self.precision_)
  }
  observer_zero(bin_min(self.lo_.abs(), self.hi_.abs()))
}

///|
/// The precision in bits of the format of the interval: every bound is a
/// number of that format.
pub fn Interval::precision(self : Interval) -> Int32 {
  self.precision_
}

///|
pub fn Interval::normalized(self : Interval) -> Interval {
  if self.is_empty() {
    self
  } else {
    // Normalize the endpoints themselves; rebuilding the interval from its
    // center and radius would round outward a second time and widen it.
    store_interval(
      self.lo_.normalized(),
      self.hi_.normalized(),
      self.precision_,
    )
  }
}

///|
/// Re-quantizes the interval at `precision`. The endpoints are rounded outward
/// so the result encloses the input at every precision; `mode` is accepted for
/// signature compatibility and cannot narrow an enclosure.
///
/// A bounded interval used to be rebuilt from `center()` and `radius()`. The
/// center adds the endpoints in round-to-nearest mode, which replaces a far
/// addend with a sticky surrogate, while the radius drops that addend; once the
/// new precision stored the surrogate exactly the rebuilt interval no longer
/// contained the original lower endpoint.
pub fn Interval::with_precision(self : Interval, precision : Int32) -> Interval {
  if self.is_empty() {
    empty_interval(precision)
  } else {
    store_interval(self.lo_, self.hi_, precision)
  }
}

///|
pub fn Interval::neg(self : Interval) -> Interval {
  if self.is_empty() {
    return self
  }
  store_interval(self.hi_.neg(), self.lo_.neg(), self.precision_)
}

///|
pub fn Interval::abs(self : Interval) -> Interval {
  if self.is_empty() {
    return self
  }
  if self.lo_.signum() == Sign::Positive || self.lo_.is_zero() {
    self
  } else if self.hi_.signum() == Sign::Negative || self.hi_.is_zero() {
    self.neg()
  } else {
    let upper = if is_pos_inf(self.hi_) || is_neg_inf(self.lo_) {
      pos_inf(self.precision_)
    } else {
      let lo_abs = self.lo_.abs()
      let hi_abs = self.hi_.abs()
      if lo_abs.compare(hi_abs) >= 0 {
        lo_abs
      } else {
        hi_abs
      }
    }
    store_interval(
      @binary.Binary::zero(precision=self.precision_),
      upper,
      self.precision_,
    )
  }
}

///|
pub fn Interval::recip(self : Interval) -> Interval {
  Interval::from_int(1, precision=self.precision_) / self
}

///|
/// The square `x * x`, tighter than `x * x` computed as a product when the
/// interval contains both signs (the lower bound is then 0). An empty interval
/// stays empty. The bounds are rounded outward at the precision of the interval.
pub fn Interval::sqr(self : Interval) -> Interval {
  if self.is_empty() {
    return self
  }
  let lo_abs = self.lo_.abs()
  let hi_abs = self.hi_.abs()
  let upper_abs = bin_max(lo_abs, hi_abs)
  let upper = extended_mul(
    upper_abs,
    upper_abs,
    self.precision_,
    BinaryRoundingMode::RoundTowardPositive,
  )
  let lower = if self.contains_zero() {
    @binary.Binary::zero(precision=self.precision_)
  } else {
    let lower_abs = bin_min(lo_abs, hi_abs)
    extended_mul(
      lower_abs,
      lower_abs,
      self.precision_,
      BinaryRoundingMode::RoundTowardNegative,
    )
  }
  store_interval(lower, upper, self.precision_)
}

///|
fn pown_exponent_is_odd(exponent : Int32) -> Bool {
  let magnitude = if exponent < 0 {
    (-(exponent + 1)).reinterpret_as_uint() + 1U
  } else {
    exponent.reinterpret_as_uint()
  }
  (magnitude & 1U) == 1U
}

///|
fn pown_endpoint(
  value : @binary.Binary,
  exponent : Int32,
  precision : Int32,
  rounding : @binary.BinaryRoundingMode,
) -> @binary.Binary {
  value.pown_ctx(exponent, @binary.BinaryContext::new(precision~, rounding~)).0
}

///|
fn pown_positive(
  value : Interval,
  exponent : Int32,
  precision : Int32,
) -> Interval {
  let down = @binary.BinaryRoundingMode::RoundTowardNegative
  let up = @binary.BinaryRoundingMode::RoundTowardPositive
  if pown_exponent_is_odd(exponent) {
    return store_interval(
      pown_endpoint(value.lo_, exponent, precision, down),
      pown_endpoint(value.hi_, exponent, precision, up),
      precision,
    )
  }
  if value.contains_zero() {
    return store_interval(
      @binary.Binary::zero(precision~),
      bin_max(
        pown_endpoint(value.lo_, exponent, precision, up),
        pown_endpoint(value.hi_, exponent, precision, up),
      ),
      precision,
    )
  }
  if value.hi_.signum() == Sign::Negative {
    store_interval(
      pown_endpoint(value.hi_, exponent, precision, down),
      pown_endpoint(value.lo_, exponent, precision, up),
      precision,
    )
  } else {
    store_interval(
      pown_endpoint(value.lo_, exponent, precision, down),
      pown_endpoint(value.hi_, exponent, precision, up),
      precision,
    )
  }
}

///|
fn pown_negative(
  value : Interval,
  exponent : Int32,
  precision : Int32,
) -> Interval {
  let lo_is_zero = value.lo_.is_zero()
  let hi_is_zero = value.hi_.is_zero()
  if lo_is_zero && hi_is_zero {
    return empty_interval(precision)
  }
  if !value.contains_zero() {
    if value.hi_.signum() == Sign::Negative && !pown_exponent_is_odd(exponent) {
      return store_interval(
        pown_endpoint(
          value.lo_,
          exponent,
          precision,
          @binary.BinaryRoundingMode::RoundTowardNegative,
        ),
        pown_endpoint(
          value.hi_,
          exponent,
          precision,
          @binary.BinaryRoundingMode::RoundTowardPositive,
        ),
        precision,
      )
    }
    return store_interval(
      pown_endpoint(
        value.hi_,
        exponent,
        precision,
        @binary.BinaryRoundingMode::RoundTowardNegative,
      ),
      pown_endpoint(
        value.lo_,
        exponent,
        precision,
        @binary.BinaryRoundingMode::RoundTowardPositive,
      ),
      precision,
    )
  }
  if pown_exponent_is_odd(exponent) {
    if lo_is_zero {
      return store_interval(
        pown_endpoint(
          value.hi_,
          exponent,
          precision,
          @binary.BinaryRoundingMode::RoundTowardNegative,
        ),
        pos_inf(precision),
        precision,
      )
    }
    if hi_is_zero {
      return store_interval(
        neg_inf(precision),
        pown_endpoint(
          value.lo_,
          exponent,
          precision,
          @binary.BinaryRoundingMode::RoundTowardPositive,
        ),
        precision,
      )
    }
    return whole_real(precision)
  }
  let lower = if lo_is_zero {
    pown_endpoint(
      value.hi_,
      exponent,
      precision,
      @binary.BinaryRoundingMode::RoundTowardNegative,
    )
  } else if hi_is_zero {
    pown_endpoint(
      value.lo_,
      exponent,
      precision,
      @binary.BinaryRoundingMode::RoundTowardNegative,
    )
  } else {
    bin_min(
      pown_endpoint(
        value.lo_,
        exponent,
        precision,
        @binary.BinaryRoundingMode::RoundTowardNegative,
      ),
      pown_endpoint(
        value.hi_,
        exponent,
        precision,
        @binary.BinaryRoundingMode::RoundTowardNegative,
      ),
    )
  }
  store_interval(lower, pos_inf(precision), precision)
}

///|
pub fn Interval::pown(self : Interval, exponent : Int32) -> Interval {
  if self.is_empty() {
    return self
  }
  if exponent == 0 {
    return Interval::from_int(1, precision=self.precision_)
  }
  let magnitude = if exponent < 0 {
    (-(exponent + 1)).reinterpret_as_uint() + 1U
  } else {
    exponent.reinterpret_as_uint()
  }
  if exponent < 0 &&
    magnitude > 4096U &&
    self.contains_zero() &&
    !self.lo_.is_zero() &&
    !self.hi_.is_zero() {
    return whole_real(self.precision_)
  }
  if exponent > 0 {
    pown_positive(self, exponent, self.precision_)
  } else {
    pown_negative(self, exponent, self.precision_)
  }
}

///|
pub fn Interval::min(self : Interval, other : Interval) -> Interval {
  let precision = Int32::max(self.precision_, other.precision_)
  if self.is_empty() || other.is_empty() {
    return empty_interval(precision)
  }
  store_interval(
    bin_min(self.lo_, other.lo_),
    bin_min(self.hi_, other.hi_),
    precision,
  )
}

///|
pub fn Interval::max(self : Interval, other : Interval) -> Interval {
  let precision = Int32::max(self.precision_, other.precision_)
  if self.is_empty() || other.is_empty() {
    return empty_interval(precision)
  }
  store_interval(
    bin_max(self.lo_, other.lo_),
    bin_max(self.hi_, other.hi_),
    precision,
  )
}

///|
/// One directed square root of a non-negative endpoint (one `sqrt_ctx`
/// instead of a down/up pair of directed square roots, half of which
/// was discarded).
fn directed_sqrt(
  x : @binary.Binary,
  precision : Int32,
  upper : Bool,
) -> @binary.Binary {
  let rounding = if upper {
    @binary.BinaryRoundingMode::RoundTowardPositive
  } else {
    @binary.BinaryRoundingMode::RoundTowardNegative
  }
  x.sqrt_ctx(@binary.BinaryContext::new(precision~, rounding~)).0
}

///|
/// The square root of the part of the
/// interval that is not below zero: the result for `[-4, 9]` is the root of
/// `[0, 9]`. An interval entirely below zero or an empty one gives the empty
/// interval. The lower bound is rounded down and the upper bound up at the
/// precision of the interval.
pub fn Interval::sqrt(self : Interval) -> Interval {
  if self.is_empty() {
    return self
  }
  if self.hi_.signum() == Sign::Negative {
    return empty_interval(self.precision_)
  }
  let lower = if self.lo_.signum() == Sign::Negative || self.lo_.is_zero() {
    @binary.Binary::zero(precision=self.precision_)
  } else {
    directed_sqrt(self.lo_, self.precision_, false)
  }
  let upper = if is_pos_inf(self.hi_) {
    pos_inf(self.precision_)
  } else {
    directed_sqrt(self.hi_, self.precision_, true)
  }
  store_interval(lower, upper, self.precision_)
}

///|
pub fn Interval::is_member(self : Interval, x : @binary.Binary) -> Bool {
  if self.is_empty() {
    return false
  }
  guard x.classify() == FpClass::Finite else { return false }
  self.lo_.compare(x) <= 0 && self.hi_.compare(x) >= 0
}

///|
/// `equal` of IEEE 1788-2015 Table 10.3 (12.12.9): the two intervals are the
/// same set, whatever their precision tags and the representation of their
/// endpoints; two empty intervals are equal. This is `==`.
pub impl Eq for Interval with fn equal(self, other) {
  (self.is_empty() && other.is_empty()) ||
  (
    !self.is_empty() &&
    !other.is_empty() &&
    self.lo_.compare(other.lo_) == 0 &&
    self.hi_.compare(other.hi_) == 0
  )
}

///|
/// Identical datums (12.3): the same set and the same precision (the type of
/// the interval at Level 2).
pub fn Interval::identical(self : Interval, other : Interval) -> Bool {
  self == other && self.precision_ == other.precision_
}

///|
/// Whether every member of `self` is a member of `other`. The empty interval is a subset of every
/// interval; no non-empty interval is a subset of the empty one.
pub fn Interval::subset(self : Interval, other : Interval) -> Bool {
  self.is_empty() ||
  (
    !other.is_empty() &&
    other.lo_.compare(self.lo_) <= 0 &&
    self.hi_.compare(other.hi_) <= 0
  )
}

///|
pub fn Interval::interior(self : Interval, other : Interval) -> Bool {
  if self.is_empty() {
    return true
  }
  if other.is_empty() {
    return false
  }
  let lower_is_interior = other.lo_.compare(self.lo_) < 0 ||
    (is_neg_inf(other.lo_) && is_neg_inf(self.lo_))
  let upper_is_interior = self.hi_.compare(other.hi_) < 0 ||
    (is_pos_inf(self.hi_) && is_pos_inf(other.hi_))
  lower_is_interior && upper_is_interior
}

///|
pub fn Interval::less(self : Interval, other : Interval) -> Bool {
  (self.is_empty() && other.is_empty()) ||
  (
    !self.is_empty() &&
    !other.is_empty() &&
    self.lo_.compare(other.lo_) <= 0 &&
    self.hi_.compare(other.hi_) <= 0
  )
}

///|
pub fn Interval::strict_less(self : Interval, other : Interval) -> Bool {
  if self.is_empty() || other.is_empty() {
    return self.is_empty() && other.is_empty()
  }
  let lower_is_less = self.lo_.compare(other.lo_) < 0 ||
    (is_neg_inf(self.lo_) && is_neg_inf(other.lo_))
  let upper_is_less = self.hi_.compare(other.hi_) < 0 ||
    (is_pos_inf(self.hi_) && is_pos_inf(other.hi_))
  lower_is_less && upper_is_less
}

///|
pub fn Interval::precedes(self : Interval, other : Interval) -> Bool {
  self.is_empty() || other.is_empty() || self.hi_.compare(other.lo_) <= 0
}

///|
pub fn Interval::strict_precedes(self : Interval, other : Interval) -> Bool {
  self.is_empty() || other.is_empty() || self.hi_.compare(other.lo_) < 0
}

///|
pub fn Interval::disjoint(self : Interval, other : Interval) -> Bool {
  self.is_empty() ||
  other.is_empty() ||
  self.hi_.compare(other.lo_) < 0 ||
  other.hi_.compare(self.lo_) < 0
}

///|
/// Whether the interval is non-empty and bounded (a common interval in the
/// terms of IEEE 1788-2015).
pub fn Interval::is_common_interval(self : Interval) -> Bool {
  !self.empty_ &&
  self.lo_.classify() == FpClass::Finite &&
  self.hi_.classify() == FpClass::Finite
}

///|
/// Whether the interval is non-empty with equal bounds.
pub fn Interval::is_singleton(self : Interval) -> Bool {
  !self.is_empty() && self.lo_.compare(self.hi_) == 0
}

///|
pub fn Interval::intersection(self : Interval, other : Interval) -> Interval {
  let precision = Int32::max(self.precision_, other.precision_)
  if self.is_empty() || other.is_empty() {
    return empty_interval(precision)
  }
  let lo = bin_max(self.lo_, other.lo_)
  let hi = bin_min(self.hi_, other.hi_)
  if lo.compare(hi) > 0 {
    empty_interval(precision)
  } else {
    store_interval(lo, hi, precision)
  }
}

///|
pub fn Interval::convex_hull(self : Interval, other : Interval) -> Interval {
  let precision = Int32::max(self.precision_, other.precision_)
  if self.is_empty() {
    return other.with_precision(precision)
  }
  if other.is_empty() {
    return self.with_precision(precision)
  }
  store_interval(
    bin_min(self.lo_, other.lo_),
    bin_max(self.hi_, other.hi_),
    precision,
  )
}

///|
/// `a + b` made exactly, with no surrogate for a far addend: a term of an exact
/// sign test is never replaced.
fn exact_add_full(
  a : @binary.Binary,
  b : @binary.Binary,
  mode~ : BinaryRoundingMode = BinaryRoundingMode::RoundTiesToEven,
) -> @binary.Binary {
  if a.is_zero() {
    return b
  }
  if b.is_zero() {
    return a
  }
  let target = Int32::min(a.exponent2(), b.exponent2())
  let left = coeff_shift_left(a.coefficient(), a.exponent2() - target)
  let right = coeff_shift_left(b.coefficient(), b.exponent2() - target)
  if a.is_sign_minus() == b.is_sign_minus() {
    exact_value(
      coeff_add(left, right),
      target,
      negative=a.is_sign_minus(),
      exact_range=true,
      mode~,
    )
  } else {
    let comparison = left.compare(right)
    if comparison == 0 {
      @binary.Binary::zero(precision=1)
    } else if comparison > 0 {
      exact_value(
        coeff_sub(left, right),
        target,
        negative=a.is_sign_minus(),
        exact_range=true,
        mode~,
      )
    } else {
      exact_value(
        coeff_sub(right, left),
        target,
        negative=b.is_sign_minus(),
        exact_range=true,
        mode~,
      )
    }
  }
}

///|
/// Whether `x1 - x2 - y1 + y2 >= 0`, the sum of four finite values taken
/// exactly: `width(y) <= width(x)` for `x = [x2, x1]` and `y = [y2, y1]`, the
/// condition under which `cancelMinus(x, y)` and `cancelPlus(x, y)` have a Level
/// 1 value (IEEE 1788-2015 10.5.6, 12.12.5). The terms are added from the
/// largest leading bit down; once the partial sum is not zero and every term to
/// come has its leading bit more than 2 places below the lowest bit of the sum,
/// the sign of the sum is the sign of the whole (a term billions of places away
/// is never aligned).
fn width_not_less(
  x1 : @binary.Binary,
  x2 : @binary.Binary,
  y1 : @binary.Binary,
  y2 : @binary.Binary,
) -> Bool {
  let terms : Array[@binary.Binary] = []
  for t in [x1, x2.neg(), y1.neg(), y2] {
    if !t.is_zero() {
      terms.push(t)
    }
  }
  // insertion sort by leading bit, largest first
  for i in 1..<terms.length() {
    let mut j = i
    while j > 0 && exponent_top(terms[j - 1]) < exponent_top(terms[j]) {
      let t = terms[j]
      terms[j] = terms[j - 1]
      terms[j - 1] = t
      j -= 1
    }
  }
  let mut acc = @binary.Binary::zero(precision=1)
  for t in terms {
    if !acc.is_zero() && exponent_top(t) + 3L < acc.exponent2().to_int64() {
      return !acc.is_sign_minus()
    }
    acc = exact_add_full(acc, t)
  }
  acc.is_zero() || !acc.is_sign_minus()
}

///|
/// `cancelMinus` and `cancelPlus` of IEEE 1788-2015 (9.2, 10.5.6, 12.12.5): for
/// nonempty bounded `x = [x1, x2]` and `y = [y1, y2]` the Level 1 value of
/// `cancelMinus(x, y)` is defined "if and only if the width of x is not less
/// than that of y, i.e., x2 - x1 >= y2 - y1", and is `[x1 - y1, x2 - y2]`;
/// `cancelPlus(x, y)` is `cancelMinus(x, -y)`. The T-version "shall return an
/// enclosure of the Level 1 value if the latter is defined, and Entire
/// otherwise. It shall return Empty if the Level 1 value is Empty": Entire when
/// either operand is unbounded, when `x` is nonempty and `y` empty, and when
/// `width(x) < width(y)`; Empty when `x` is empty and `y` bounded. The decision
/// `width(x) < width(y)` is the exact sign of `(x2 - x1) - (y2 - y1)`
/// (`width_not_less`: no rounding), so equal
/// widths give a point and a width smaller by less than a unit of the end
/// values is Entire; the ends are the end values rounded outward once at the
/// precision (the directed `add_ctx` and `sub_ctx`).
fn cancel_result(
  x : Interval,
  y : Interval,
  lo : @binary.Binary,
  hi : @binary.Binary,
  precision : Int32,
) -> Interval {
  if width_not_less(x.hi_, x.lo_, y.hi_, y.lo_) {
    store_interval(lo, hi, precision)
  } else {
    whole_real(precision)
  }
}

///|
pub fn Interval::cancel_plus(self : Interval, other : Interval) -> Interval {
  let precision = Int32::max(self.precision_, other.precision_)
  if self.is_empty() {
    return if other.is_empty() || other.is_common_interval() {
      empty_interval(precision)
    } else {
      whole_real(precision)
    }
  }
  if other.is_empty() ||
    !self.is_common_interval() ||
    !other.is_common_interval() {
    return whole_real(precision)
  }
  let down = @binary.BinaryContext::new(
    precision~,
    rounding=BinaryRoundingMode::RoundTowardNegative,
  )
  let up = @binary.BinaryContext::new(
    precision~,
    rounding=BinaryRoundingMode::RoundTowardPositive,
  )
  let lo = self.lo_.add_ctx(other.hi_, down).0
  let hi = self.hi_.add_ctx(other.lo_, up).0
  cancel_result(self, other, lo, hi, precision)
}

///|
pub fn Interval::cancel_minus(self : Interval, other : Interval) -> Interval {
  let precision = Int32::max(self.precision_, other.precision_)
  if self.is_empty() {
    return if other.is_empty() || other.is_common_interval() {
      empty_interval(precision)
    } else {
      whole_real(precision)
    }
  }
  if other.is_empty() ||
    !self.is_common_interval() ||
    !other.is_common_interval() {
    return whole_real(precision)
  }
  let down = @binary.BinaryContext::new(
    precision~,
    rounding=BinaryRoundingMode::RoundTowardNegative,
  )
  let up = @binary.BinaryContext::new(
    precision~,
    rounding=BinaryRoundingMode::RoundTowardPositive,
  )
  let lo = self.lo_.sub_ctx(other.lo_, down).0
  let hi = self.hi_.sub_ctx(other.hi_, up).0
  cancel_result(self, other, lo, hi, precision)
}

///|
pub fn Interval::overlap(self : Interval, other : Interval) -> OverlapState {
  if self.is_empty() {
    return if other.is_empty() { BothEmpty } else { FirstEmpty }
  }
  if other.is_empty() {
    return SecondEmpty
  }
  let lo_cmp = self.lo_.compare(other.lo_)
  let hi_cmp = self.hi_.compare(other.hi_)
  let self_hi_other_lo = self.hi_.compare(other.lo_)
  let self_lo_other_hi = self.lo_.compare(other.hi_)
  if lo_cmp == 0 && hi_cmp == 0 {
    Equals
  } else if lo_cmp == 0 && hi_cmp < 0 {
    Starts
  } else if lo_cmp == 0 {
    StartedBy
  } else if hi_cmp == 0 && lo_cmp > 0 {
    Finishes
  } else if hi_cmp == 0 {
    FinishedBy
  } else if self_hi_other_lo < 0 {
    Before
  } else if self_hi_other_lo == 0 && hi_cmp < 0 {
    Meets
  } else if self_lo_other_hi > 0 {
    After
  } else if self_lo_other_hi == 0 && lo_cmp > 0 {
    MetBy
  } else if lo_cmp > 0 && hi_cmp < 0 {
    ContainedBy
  } else if lo_cmp < 0 && hi_cmp > 0 {
    Contains
  } else if lo_cmp < 0 {
    Overlaps
  } else {
    OverlappedBy
  }
}

///|
/// The sum, rounded outward: the lower bound is the sum of the lower bounds
/// rounded down and the upper bound the sum of the upper bounds rounded up.
/// The result has the larger of the two precisions; an empty operand gives
/// the empty interval. This is the `+` operator.
pub fn Interval::add(self : Interval, other : Interval) -> Interval {
  add_interval_impl(self, other)
}

///|
/// The difference `self - other`, rounded outward at the larger of the two
/// precisions; an empty operand gives the empty interval. This is the `-`
/// operator.
pub fn Interval::sub(self : Interval, other : Interval) -> Interval {
  sub_interval_impl(self, other)
}

///|
/// The product, rounded outward at the larger of the two precisions; an empty
/// operand gives the empty interval. This is the `*` operator.
pub fn Interval::mul(self : Interval, other : Interval) -> Interval {
  mul_interval_impl(self, other)
}

///|
/// The quotient `self / other`, rounded outward at the larger of the two
/// precisions. When `other` contains zero the result is the hull of the
/// quotients of its non-zero members; the quotient by `[0, 0]` is the empty interval, and so is a quotient with an
/// empty operand. This is the `/` operator.
pub fn Interval::div(self : Interval, other : Interval) -> Interval {
  div_interval_impl(self, other)
}

///|
/// The sign class of an interval for the corners of a product: 0 when it is not
/// below zero (`lo >= 0`, a zero of either sign counts), 1 when it is not above zero
/// (`hi <= 0`, and not class 0), 2 when it contains both signs in its interior.
fn product_class(x : Interval) -> Int32 {
  let lo_nonnegative = x.lo_.is_zero() || x.lo_.signum() == Sign::Positive
  let hi_nonpositive = x.hi_.is_zero() || x.hi_.signum() == Sign::Negative
  if lo_nonnegative {
    0
  } else if hi_nonpositive {
    1
  } else {
    2
  }
}

///|
/// The corners `(x, y)` of the box `a x b` (0 selects the lower end, 1 the upper) at
/// which `x * y` is smallest (`lower = true`) or largest, by the sign classes of
/// `a` and `b`: one corner, except two (the minimum is the smaller of `a.lo * b.hi`
/// and `a.hi * b.lo`, the maximum the larger of `a.lo * b.lo` and `a.hi * b.hi`)
/// when both contain both signs. The nine cases are those of `mul`. A corner is the
/// two bits `x * 2 + y`; the result is the first corner in bits 0 and 1, the second
/// in bits 2 and 3, and bit 4 says that there is a second one.
fn product_corners(class_a : Int32, class_b : Int32, lower : Bool) -> Int32 {
  match (class_a, class_b, lower) {
    (0, 0, true) => 0b00
    (0, 0, false) => 0b11
    (0, 1, true) => 0b10
    (0, 1, false) => 0b01
    (0, _, true) => 0b10
    (0, _, false) => 0b11
    (1, 0, true) => 0b01
    (1, 0, false) => 0b10
    (1, 1, true) => 0b11
    (1, 1, false) => 0b00
    (1, _, true) => 0b01
    (1, _, false) => 0b00
    (_, 0, true) => 0b01
    (_, 0, false) => 0b11
    (_, 1, true) => 0b10
    (_, 1, false) => 0b00
    (_, _, true) => 0b10000 + (0b10 << 2) + 0b01
    (_, _, false) => 0b10000 + (0b11 << 2) + 0b00
  }
}

///|
/// `x * y + z` of three endpoints, rounded once to `precision` bits in `mode` (the
/// directed `fma_ctx`), with the conventions of interval arithmetic: an endpoint
/// product 0 times infinity is 0 (the result is `z` rounded); an infinite product is
/// the result. An infinite product never meets an infinite addend of the opposite
/// sign: the corners of `product_corners` give a lower product that is never `+inf`
/// beside a lower addend that is never `+inf`, and an upper product that is never
/// `-inf` beside an upper addend that is never `-inf`, so the NaN of `inf - inf`
/// is not reachable.
fn fma_corner(
  x : @binary.Binary,
  y : @binary.Binary,
  z : @binary.Binary,
  precision : Int32,
  mode : BinaryRoundingMode,
) -> @binary.Binary {
  if x.is_zero() || y.is_zero() {
    return if mode == BinaryRoundingMode::RoundTowardNegative {
      lower_round_bound(z, precision)
    } else {
      upper_round_bound(z, precision)
    }
  }
  if x.classify() == FpClass::Infinity || y.classify() == FpClass::Infinity {
    return @binary.Binary::inf(negative=x.signum() != y.signum(), precision~)
  }
  x.fma_ctx(y, z, @binary.BinaryContext::new(precision~, rounding=mode)).0
}

///|
/// `fma` of IEEE 1788-2015 (tightest, 12.10.2): over the box of `a`, `b` and `c`
/// the product is bilinear, so its smallest and largest values are at corners that
/// the signs select (`product_corners`), and the sum with `c` is increasing in `c`, so
/// the smallest value of `a * b + c` is the smallest product plus `c.lo` and the
/// largest is the largest product plus `c.hi`. A directed rounding is monotone, so the
/// lower bound is the minimum, over the candidate corners, of the downward `fma_ctx`
/// of the corner with `c.lo`, and the upper bound the maximum of the upward `fma_ctx`
/// with `c.hi`: each rounds the exact `x * y + z` of three endpoints of any bit length
/// once, in the implementation range. The bounds are those of `fma_ctx`.
pub fn Interval::fma(
  self : Interval,
  multiplier : Interval,
  addend : Interval,
) -> Interval {
  let precision = Int32::max(
    self.precision_,
    Int32::max(multiplier.precision_, addend.precision_),
  )
  if self.is_empty() || multiplier.is_empty() || addend.is_empty() {
    return empty_interval(precision)
  }
  let class_a = product_class(self)
  let class_b = product_class(multiplier)
  let corner = fn(code : Int32, z : @binary.Binary, mode) {
    fma_corner(
      if ((code >> 1) & 1) == 0 {
        self.lo_
      } else {
        self.hi_
      },
      if (code & 1) == 0 {
        multiplier.lo_
      } else {
        multiplier.hi_
      },
      z,
      precision,
      mode,
    )
  }
  let lower_corners = product_corners(class_a, class_b, true)
  let mut lo = corner(
    lower_corners & 3,
    addend.lo_,
    BinaryRoundingMode::RoundTowardNegative,
  )
  if lower_corners >= 16 {
    let other = corner(
      (lower_corners >> 2) & 3,
      addend.lo_,
      BinaryRoundingMode::RoundTowardNegative,
    )
    if other.compare(lo) < 0 {
      lo = other
    }
  }
  let upper_corners = product_corners(class_a, class_b, false)
  let mut hi = corner(
    upper_corners & 3,
    addend.hi_,
    BinaryRoundingMode::RoundTowardPositive,
  )
  if upper_corners >= 16 {
    let other = corner(
      (upper_corners >> 2) & 3,
      addend.hi_,
      BinaryRoundingMode::RoundTowardPositive,
    )
    if other.compare(hi) > 0 {
      hi = other
    }
  }
  store_interval(lo, hi, precision)
}

///|
pub impl @lf_arith.Contains for Interval with fn contains(self, other) {
  other.subset(self)
}

///|
pub impl @lf_arith.Overlaps for Interval with fn overlaps(self, other) {
  if self.is_empty() || other.is_empty() {
    return false
  }
  self.lo_.compare(other.hi_) <= 0 && self.hi_.compare(other.lo_) >= 0
}

///|
pub impl @lf_arith.DefinitelyLt for Interval with fn definitely_lt(self, other) {
  if self.is_empty() || other.is_empty() {
    return false
  }
  self.hi_.compare(other.lo_) < 0
}

///|
pub impl @lf_arith.DefinitelyLe for Interval with fn definitely_le(self, other) {
  if self.is_empty() || other.is_empty() {
    return false
  }
  self.hi_.compare(other.lo_) <= 0
}

///|
pub impl @lf_arith.MaybeEq for Interval with fn maybe_eq(self, other) {
  @lf_arith.Overlaps::overlaps(self, other)
}

///|
pub impl @lf_arith.DivChecked for Interval with fn div_checked(self, other, ctx) {
  let precision = ctx.precision
  let lhs = self.with_precision(precision)
  let rhs = other.with_precision(precision)
  Ok(lhs.div(rhs).with_precision(precision))
}

///|
pub impl @lf_arith.PowNatChecked for Interval with fn pow_nat_checked(
  self,
  exponent,
  ctx,
) {
  let precision = ctx.precision
  let base = self.with_precision(precision)
  Ok(pow_nat(base, exponent, precision))
}

///|
pub impl @lf_arith.PowIntChecked for Interval with fn pow_int_checked(
  self,
  exponent,
  ctx,
) {
  let precision = ctx.precision
  let base = self.with_precision(precision)
  Ok(base.pown(exponent).with_precision(precision))
}

///|
pub impl Add for Interval with fn add(self, other) {
  add_interval_impl(self, other)
}

///|
pub impl Sub for Interval with fn sub(self, other) {
  sub_interval_impl(self, other)
}

///|
pub impl Mul for Interval with fn mul(self, other) {
  mul_interval_impl(self, other)
}

///|
pub impl Div for Interval with fn div(self, other) {
  div_interval_impl(self, other)
}

///|
pub impl Neg for Interval with fn neg(self) {
  self.neg()
}

///|
pub impl Show for Interval with fn to_string(self) {
  interval_portable_text(self)
}

///|
pub extend Interval with Show::{to_string}

///|
pub extend Interval with Eq::{not_equal, equal}

///|
pub extend Interval with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend OverlapState with Eq::{not_equal, equal}

///|
pub extend OverlapState with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Interval with @Luna-Flow/arithmetic.DivChecked::{div_checked}

///|
pub extend Interval with @Luna-Flow/arithmetic.PowNatChecked::{pow_nat_checked}

///|
pub extend Interval with @Luna-Flow/arithmetic.PowIntChecked::{pow_int_checked}

///|
pub extend Interval with Show::{output}
