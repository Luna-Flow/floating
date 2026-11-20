///|
/// `powRev1(b, c, x)` of IEEE 1788-2015 Table 10.1: the hull of
/// `{ x in x | exists beta in b : x^beta is defined and in c }`, where `x^beta` is
/// defined for `x > 0` and for `x = 0` with `beta > 0` (then 0).
///
/// For `x > 0`, `x^beta in c` is `beta ln x in ln c`, so the set is
/// `exp(L /set b)` with `L = ln(c inter (0, +inf))`, the set division of
/// `mul_rev` in logarithm coordinates, plus the point 0 when `0 in c` and `b`
/// has a positive point. Every end of a piece is `c_end^(1/b_end)`, 0, 1 or infinite.
///
/// Exactness of `x = c^(1/beta)` for finite `c > 0`, `beta != 0`: write
/// `beta = s u 2^j` and `c = C 2^gamma` (u, C odd), `p = 2^max(-j, 0)`,
/// `q = u 2^max(j, 0)`; then `x = c^(s p / q)` with `gcd(p, q) = 1`, which is
/// rational iff `c` is a perfect `q`-th power in Q: `C = m^q` and `q | gamma`. The
/// value is then `(m 2^(gamma/q))^(s p)`. Three classes:
/// - dyadic (`s = +1` or `m = 1`): an exact integer times a power of two, compared
///   and rounded exactly;
/// - rational and not dyadic (`s = -1`, `m > 1`): `2^E / m^p`, never a float,
///   compared by cross-multiplication and rounded by integer division;
/// - irrational: it differs from every float, and a loop raises the working
///   precision until an enclosure decides (as in `sin_rev`).
/// A value outside the budgets below goes to the loop, with its documented fallback.

///|
/// The largest integer (bits) on which the exactness test runs a root: one call at
/// the budget (an exact 65,535-bit square, `q = 2`) takes about 80 ms, against about
/// 20 ms for the forward `sqrt` of the same operand.
let pow_int_budget : Int32 = 65536

///|
/// The largest exact value (bits) that is materialised: a value of millions of bits
/// would be built only to be rounded to `p` bits; at 262,144 bits one call is a few
/// times the cost of the forward `pow` of the same magnitude.
let pow_value_budget : Int32 = 262144

///|
/// An exponent of 2 beyond this magnitude would overflow the 32-bit exponent of a datum
/// (the stored range, decided from the leading bit below, is narrower): the end goes to
/// the loop, which clamps.
let pow_exponent_range : Int64 = 2000000000L

///|
priv enum PowEnd {
  PZero
  POne
  PInf
  PNegInf
  PPow(@bin_float.BinFloat, @bin_float.BinFloat, PowClass)
  // `pow_rev2`: the quotient `ln(c) / ln(a)` of two float ends
  PQuot(@bin_float.BinFloat, @bin_float.BinFloat, QuotClass)
}

///|
priv struct PowPiece {
  lo : PowEnd
  lo_open : Bool
  hi : PowEnd
  hi_open : Bool
}

///|
priv enum PowClass {
  Dyadic(@bin_float.BinFloat)
  // value = 2^exp2 / den, den odd and greater than 1: (den, exp2)
  Rational(@bin_float.BinCoeff, Int32)
  Irrational
  // outside the budgets: decided by the loop, with the documented fallback
  Unknown
}

///|
fn pow_trailing_zeros(value : @bin_float.BinCoeff) -> Int32 {
  let mut zeros = 0
  let bits = value.bit_length()
  while zeros < bits && !coeff_test_bit(value, zeros) {
    zeros += 1
  }
  zeros
}

///|
/// `x` as `odd * 2^exp` with `odd` odd: returns `(odd, exp)`.
fn pow_split(x : @bin_float.BinFloat) -> (@bin_float.BinCoeff, Int64) {
  let coefficient = x.coefficient()
  let zeros = pow_trailing_zeros(coefficient)
  (
    coeff_shift_right(coefficient, zeros),
    x.exponent2().to_int64() + zeros.to_int64(),
  )
}

///|
/// `value * 2^exponent` as `odd * 2^low` with `odd` odd (the coefficient of the float and
/// its exponent are not normalised the same way everywhere, so the exactness check compares
/// this form).
fn pow_split_coeff(
  value : @bin_float.BinCoeff,
  exponent : Int64,
) -> (@bin_float.BinCoeff, Int64) {
  let zeros = pow_trailing_zeros(value)
  (coeff_shift_right(value, zeros), exponent + zeros.to_int64())
}

///|
fn coeff_pow_two_power(
  base : @bin_float.BinCoeff,
  squarings : Int32,
) -> @bin_float.BinCoeff {
  let mut result = base
  for _ in 0..<squarings {
    result = coeff_mul(result, result)
  }
  result
}

///|
fn coeff_pow_small(
  base : @bin_float.BinCoeff,
  exponent : Int32,
) -> @bin_float.BinCoeff {
  let mut result = coeff_one()
  let mut factor = base
  let mut remaining = exponent
  while remaining > 0 {
    if remaining % 2 == 1 {
      result = coeff_mul(result, factor)
    }
    remaining = remaining / 2
    if remaining > 0 {
      factor = coeff_mul(factor, factor)
    }
  }
  result
}

///|
/// `m` with `m^q = value`, if there is one: integer Newton iteration from a power of
/// two above the root, `x <- ((q - 1) x + value / x^(q-1)) / q` while it decreases,
/// then an exact check `m^q = value`.
fn coeff_exact_root(
  value : @bin_float.BinCoeff,
  q : Int32,
) -> @bin_float.BinCoeff? {
  if q == 1 {
    return Some(value)
  }
  let q_coeff = @bin_float.BinCoeff::from_uint64(q.to_uint64())
  let q_minus_one = @bin_float.BinCoeff::from_uint64((q - 1).to_uint64())
  let mut x = coeff_shift_left(coeff_one(), (value.bit_length() + q - 1) / q)
  while true {
    let power = coeff_pow_small(x, q - 1)
    let (quotient, _) = coeff_div_rem(value, power)
    let (next, _) = coeff_div_rem(
      coeff_add(coeff_mul(q_minus_one, x), quotient),
      q_coeff,
    )
    if coeff_compare(next, x) >= 0 {
      break
    }
    x = next
  }
  if coeff_compare(coeff_pow_small(x, q), value) == 0 {
    Some(x)
  } else {
    None
  }
}

///|
/// The class of `c^(1/beta)`; `c > 0` and `beta != 0` finite.
fn pow_end_class(
  c : @bin_float.BinFloat,
  beta : @bin_float.BinFloat,
  precision : Int32,
) -> PowClass {
  let one = @bin_float.BinFloat::one(precision~)
  if c.compare(one) == 0 {
    return Dyadic(one)
  }
  let (big_c, gamma) = pow_split(c)
  let (u, j) = pow_split(beta)
  let negative = beta.is_negative()
  // q = u * 2^max(j, 0): a q beyond the range a root or a divisor of gamma can
  // have decides "not rational" at once
  if j > 62L {
    return Irrational
  }
  let shift = if j > 0L { j.to_int() } else { 0 }
  let q_coeff = coeff_shift_left(u, shift)
  let q64 : Int64 = match q_coeff.to_uint64() {
    Some(value) if value <= 2147483647UL => value.reinterpret_as_int64()
    _ => return Irrational
  }
  let q = q64.to_int()
  let c_is_one = big_c.bit_length() == 1
  let m : @bin_float.BinCoeff = if c_is_one {
    big_c
  } else {
    if big_c.bit_length() > pow_int_budget {
      return Unknown
    }
    if q > big_c.bit_length() {
      return Irrational
    }
    match coeff_exact_root(big_c, q) {
      Some(root) => root
      None => return Irrational
    }
  }
  if gamma % q64 != 0L {
    return Irrational
  }
  let g = gamma / q64
  let squarings = if j < 0L { (-j).to_int() } else { 0 }
  // the exponent g * 2^squarings of 2 must stay inside the exponent range
  if squarings > 30 {
    return Unknown
  }
  let scaled = g * (1L << squarings)
  if scaled > pow_exponent_range || scaled < -pow_exponent_range {
    return Unknown
  }
  let m_is_one = m.bit_length() == 1
  if !m_is_one {
    // m^p has bitlen(m) * 2^squarings bits at most
    let bits = m.bit_length().to_int64() * (1L << squarings)
    if bits > pow_value_budget.to_int64() {
      return Unknown
    }
  }
  let power = coeff_pow_two_power(m, squarings)
  // a value outside the normal range [2^e_min, 2^(e_max + 1)) cannot be stored exactly:
  // its end is decided by the loop, which stops at the limits of the range
  let e_max = @bin_float.binary_implementation_e_max.to_int64()
  let e_min = @bin_float.binary_implementation_e_min.to_int64()
  if !negative || m_is_one {
    let exponent = if negative { -scaled } else { scaled }
    let top = exponent + power.bit_length().to_int64() - 1L
    if top > e_max {
      return Unknown
    }
    if top < e_min {
      // A stored subnormal value: the stored values at `P` bits are the multiples of the
      // quantum `2^(e_min - P + 1)`, so the value `power * 2^exponent` is stored exactly iff
      // its LOWEST bit is at or above the quantum, `exponent >= e_min - P + 1`, that is
      // `P >= e_min - exponent + 1` (conservative when `power` is even: its lowest set bit is
      // then higher). `exact_make` would pick the coefficient's own width and round.
      let needed = Int64::max(
        power.bit_length().to_int64(),
        e_min - exponent + 1L,
      )
      if needed > pow_value_budget.to_int64() {
        return Unknown
      }
      let datum = @bin_float.BinFloat::make(
        power,
        exponent.to_int(),
        needed.to_int(),
      )
      // an exact class never carries a rounded value: check what was built
      let (odd, low) = pow_split(datum)
      let (want_odd, want_low) = pow_split_coeff(power, exponent)
      if coeff_compare(odd, want_odd) != 0 || low != want_low {
        return Unknown
      }
      return Dyadic(datum)
    }
    Dyadic(exact_make(power, exponent.to_int()))
  } else {
    // 2^(-scaled) / m^p: its leading bit is -scaled - bitlen(m^p) + 1 or -scaled - bitlen(m^p)
    let top = -scaled - power.bit_length().to_int64()
    if -scaled > e_max || top < e_min {
      return Unknown
    }
    Rational(power, (-scaled).to_int())
  }
}

///|
/// An enclosure of a value with the information whether each end is excluded.
priv struct PowEnc {
  lo : @bin_float.BinFloat
  lo_open : Bool
  hi : @bin_float.BinFloat
  hi_open : Bool
  // the value is outside the exponent range: the enclosure is final, no precision helps
  clamped : Bool
}

///|
fn pow_adjusted_exponent(x : @bin_float.BinFloat) -> Int64 {
  if x.is_zero() {
    return -1000000000000L
  }
  x.exponent2().to_int64() + x.coefficient().bit_length().to_int64() - 1L
}

///|
/// `+1` if `c^(1/beta) > 1`, `-1` if `< 1` (for `c != 1`).
fn pow_side(c : @bin_float.BinFloat, beta : @bin_float.BinFloat) -> Int32 {
  let above = c.compare(@bin_float.BinFloat::one()) > 0
  if above == (beta.sign() == Sign::Positive) {
    1
  } else {
    -1
  }
}

///|
/// The first working precision for an irrational or unknown end: the result needs
/// the absolute error of `t = ln(c) / beta` below `2^-precision`, so the bits of
/// the integer part of `t` are added to the precision.
fn pow_start_work(
  c : @bin_float.BinFloat,
  beta : @bin_float.BinFloat,
  precision : Int32,
) -> Int32 {
  let coarse = BallFloat::exact(c, precision=Int32::max(64, c.precision())).ln() /
    BallFloat::exact(beta, precision=Int32::max(64, beta.precision()))
  let magnitude = coarse.magnitude()
  let e = Int64::max(0L, pow_adjusted_exponent(magnitude))
  if e > 40L {
    // |t| > 2^40: the value is beyond the exponent range (see `pow_enclosure`), no precision is needed
    return precision + 64
  }
  precision + 64 + e.to_int()
}

///|
/// An enclosure of `c^(1/beta)` at `w` bits, strict on the side of 1 the value is
/// known to be on (`exp(t) > 1` iff `t > 0`, decided exactly by the sign). A value
/// whose exponent leaves the exponent range clamps outward.
fn pow_enclosure(
  c : @bin_float.BinFloat,
  beta : @bin_float.BinFloat,
  w : Int32,
) -> PowEnc {
  let one = @bin_float.BinFloat::one(precision=w)
  let side = pow_side(c, beta)
  let t = BallFloat::exact(c, precision=Int32::max(w, c.precision())).ln() /
    BallFloat::exact(beta, precision=Int32::max(w, beta.precision()))
  // The value is beyond the stored range when the enclosure of `t` lies wholly past a
  // limit; the limits are decided with a certified upper bound of ln 2, so the test is
  // sufficient (a value near a limit goes through `exp`), never wrong.
  // Above: every finite float is below `2^(e_max + 1)` (`e_max` is the exponent of the
  // leading bit), so `t >= (e_max + 1) ln 2` puts the value above the largest finite float
  // at `w` bits, and the enclosure is [largest finite float at w bits, +inf]: a lower end
  // then rounds down to the largest finite float of the result precision.
  // Below: the stored values at `w` bits go down to the leading bit `e_min - w + 1`, so
  // `t <= (e_min - w) ln 2` puts the value below the smallest positive stored value
  // `2^(e_min - w + 1)`, and the enclosure is [0, that value]: an upper end then rounds up
  // to the smallest positive stored value of the result precision.
  let ln2_up = BallFloat::exact(@bin_float.BinFloat::from_int(2), precision=64).ln().hi_
  let times_ln2 = fn(n : Int32) {
    BallFloat::exact(@bin_float.BinFloat::from_int(n), precision=64) *
    BallFloat::exact(ln2_up, precision=64)
  }
  let beyond = if side > 0 {
    t.lo_.compare(times_ln2(@bin_float.binary_implementation_e_max + 1).hi_) >=
    0
  } else {
    t.hi_.compare(times_ln2(@bin_float.binary_implementation_e_min - w).lo_) <=
    0
  }
  if beyond {
    return if side > 0 {
      let largest = @bin_float.BinFloat::make(
        coeff_sub(coeff_shift_left(coeff_one(), w), coeff_one()),
        @bin_float.binary_implementation_e_max - w + 1,
        w,
      )
      {
        lo: largest,
        lo_open: false,
        hi: pos_inf(w),
        hi_open: false,
        clamped: true,
      }
    } else {
      let smallest = @bin_float.BinFloat::make(
        coeff_one(),
        @bin_float.binary_implementation_e_min - w + 1,
        w,
      )
      {
        lo: @bin_float.BinFloat::zero(precision=w),
        lo_open: false,
        hi: smallest,
        hi_open: false,
        clamped: true,
      }
    }
  }
  // `exp` of an interval whose end leaves the range returns the range of the function,
  // [0, +inf] (issue 569), where the point `exp` of each end is a valid bound (a lower end
  // at the largest finite float, an upper end +inf, or the one-quantum subnormal enclosure
  // [0, 2^(e_min - w + 1)]); exp is monotone, so the two ends give the enclosure
  let whole = t.exp()
  let value = if whole.lo_.is_zero() &&
    whole.hi_.classify() == FpClass::Infinity {
    let low = BallFloat::exact(t.lo_, precision=w).exp()
    let high = BallFloat::exact(t.hi_, precision=w).exp()
    BallFloat::from_bounds(low.lo_, high.hi_, precision=w)
  } else {
    whole
  }
  // Above, the enclosure of `t` may straddle the limit: `exp` then returns an infinite upper
  // end. The enclosure is final only if its lower end is at least
  // `2^(e_max + 1) (1 - 2^-(w - 64))` (checked below, built as the largest finite float at
  // `w - 64` bits): then the upper end is +inf (the value is above the largest p-bit float
  // for every `p <= w - 64`, the largest being `2^(e_max + 1) (1 - 2^-p)`) and the lower end
  // rounds down to the largest finite float of the result precision at every further
  // precision, so the loops stop (`clamped`). Otherwise the loops go on to their cap.
  // Below, a straddling enclosure is the subnormal enclosure of `exp` (at most one
  // quantum `2^(e_min - w + 1)` wide, lower end 0): the loops go on, and terminate, since
  // the quantum shrinks with `w` while the value is fixed.
  let certified_floor = @bin_float.BinFloat::make(
    coeff_sub(coeff_shift_left(coeff_one(), w - 64), coeff_one()),
    @bin_float.binary_implementation_e_max - (w - 64) + 1,
    w,
  )
  let straddles = side > 0 &&
    value.hi_.classify() == FpClass::Infinity &&
    value.lo_.compare(certified_floor) >= 0
  if side > 0 {
    let lo_below = value.lo_.compare(one) <= 0
    {
      lo: if lo_below {
        one
      } else {
        value.lo_
      },
      lo_open: lo_below,
      hi: value.hi_,
      hi_open: false,
      clamped: straddles,
    }
  } else {
    let hi_above = value.hi_.compare(one) >= 0
    {
      lo: value.lo_,
      lo_open: false,
      hi: if hi_above {
        one
      } else {
        value.hi_
      },
      hi_open: hi_above,
      clamped: straddles,
    }
  }
}

///|
/// Compares an exact value `2^exp2 / den` (den odd, > 1) with the finite float `d`.
fn pow_rational_compare(
  den : @bin_float.BinCoeff,
  exp2 : Int32,
  d : @bin_float.BinFloat,
) -> Int32 {
  if d.sign() != Sign::Positive {
    return 1
  }
  let (dc, de) = (d.coefficient(), d.exponent2())
  // log2(value) is in (exp2 - bl(den), exp2 - bl(den) + 1); log2(d) in
  // [de + bl(dc) - 1, de + bl(dc))
  let value_low = exp2.to_int64() - den.bit_length().to_int64()
  let d_low = de.to_int64() + dc.bit_length().to_int64() - 1L
  if value_low + 1L <= d_low {
    return -1
  }
  if d_low + 1L <= value_low {
    return 1
  }
  // within one bit: compare 2^(exp2 - de) with dc * den exactly
  let product = coeff_mul(dc, den)
  let shift = exp2.to_int64() - de.to_int64()
  if shift >= 0L {
    coeff_compare(coeff_shift_left(coeff_one(), shift.to_int()), product)
  } else {
    coeff_compare(coeff_one(), coeff_shift_left(product, (-shift).to_int()))
  }
}

///|
/// `RD` or `RU` to `precision` bits of `2^exp2 / den`.
fn pow_rational_round(
  den : @bin_float.BinCoeff,
  exp2 : Int32,
  upper : Bool,
  precision : Int32,
) -> @bin_float.BinFloat {
  let scale = precision + 2 + den.bit_length()
  let (quotient, remainder) = coeff_div_rem(
    coeff_shift_left(coeff_one(), scale),
    den,
  )
  let exponent = exp2 - scale
  if upper {
    let top = if remainder.is_zero() {
      quotient
    } else {
      coeff_increment(quotient)
    }
    exact_make(top, exponent).with_precision(
      precision,
      BinaryRoundingMode::RoundTowardPositive,
    )
  } else {
    exact_make(quotient, exponent).with_precision(
      precision,
      BinaryRoundingMode::RoundTowardNegative,
    )
  }
}

///|
fn pow_end_compare(
  end : PowEnd,
  d : @bin_float.BinFloat,
  precision : Int32,
  cap : Int32,
) -> RevOrder {
  fn order_of(value : Int32) -> RevOrder {
    if value < 0 {
      Below
    } else if value > 0 {
      Above
    } else {
      Equal
    }
  }

  match end {
    PZero => order_of(@bin_float.BinFloat::zero(precision~).compare(d))
    POne => order_of(@bin_float.BinFloat::one(precision~).compare(d))
    PInf => Above
    PNegInf => Below
    PQuot(c, a, cls) => quot_end_compare(c, a, cls, d, precision, cap)
    PPow(c, beta, cls) =>
      match cls {
        Dyadic(value) => order_of(value.compare(d))
        Rational(den, exp2) => order_of(pow_rational_compare(den, exp2, d))
        Irrational | Unknown =>
          pow_loop_compare(
            pow_start_work(c, beta, precision),
            fn(w) { pow_enclosure(c, beta, w) },
            d,
            cap,
          )
      }
  }
}

///|
/// The directed rounding of an end to `precision` bits (`RD` for a lower end).
fn pow_end_rounded(
  end : PowEnd,
  upper : Bool,
  precision : Int32,
  cap : Int32,
) -> @bin_float.BinFloat {
  match end {
    PZero => @bin_float.BinFloat::zero(precision~)
    POne => @bin_float.BinFloat::one(precision~)
    PInf => pos_inf(precision)
    PNegInf => neg_inf(precision)
    PQuot(c, a, cls) => quot_end_rounded(c, a, cls, upper, precision, cap)
    PPow(c, beta, cls) =>
      match cls {
        Dyadic(value) =>
          value.with_precision(
            precision,
            if upper {
              BinaryRoundingMode::RoundTowardPositive
            } else {
              BinaryRoundingMode::RoundTowardNegative
            },
          )
        Rational(den, exp2) => pow_rational_round(den, exp2, upper, precision)
        Irrational | Unknown =>
          pow_loop_round(
            pow_start_work(c, beta, precision),
            fn(w) { pow_enclosure(c, beta, w) },
            upper,
            precision,
            cap,
          )
      }
  }
}

///|
/// Compares the value of an enclosure family with the finite float `d`: the first
/// working precision `start`, doubled up to `cap` times; `enclosure(w)` is an
/// enclosure of the value at `w` bits.
fn pow_loop_compare(
  start : Int32,
  enclosure : (Int32) -> PowEnc,
  d : @bin_float.BinFloat,
  cap : Int32,
) -> RevOrder {
  let mut w = start
  for _ in 0..<cap {
    let enc = enclosure(w)
    let hi_order = enc.hi.compare(d)
    if hi_order < 0 || (hi_order == 0 && enc.hi_open) {
      return Below
    }
    let lo_order = enc.lo.compare(d)
    if lo_order > 0 || (lo_order == 0 && enc.lo_open) {
      return Above
    }
    if enc.clamped {
      break
    }
    w = w * 2
  }
  Undecided
}

///|
/// The directed rounding to `precision` bits of the value of an enclosure family:
/// the working precision doubles (at most `cap` times) until no float of the
/// precision lies inside the enclosure, and the end of the enclosure is written.
fn pow_loop_round(
  start : Int32,
  enclosure : (Int32) -> PowEnc,
  upper : Bool,
  precision : Int32,
  cap : Int32,
) -> @bin_float.BinFloat {
  let down = BinaryRoundingMode::RoundTowardNegative
  let up = BinaryRoundingMode::RoundTowardPositive
  let context = @bin_float.BinaryContext::new(precision~)
  let mut w = start
  let mut enc = enclosure(w)
  for _ in 0..<cap {
    // the least float inside the enclosure (excluding an open lower end)
    let floor_lo = enc.lo.with_precision(precision, down)
    let first = if enc.lo_open {
      floor_lo.next_up_ctx(context).0
    } else {
      enc.lo.with_precision(precision, up)
    }
    let order = first.compare(enc.hi)
    if enc.clamped || order > 0 || (order == 0 && enc.hi_open) {
      break
    }
    w = w * 2
    enc = enclosure(w)
  }
  if upper {
    enc.hi.with_precision(precision, up)
  } else {
    enc.lo.with_precision(precision, down)
  }
}

///|
fn pow_piece(
  lo : PowEnd,
  lo_open : Bool,
  hi : PowEnd,
  hi_open : Bool,
) -> PowPiece {
  { lo, lo_open, hi, hi_open, }
}

///|
/// The pieces of `S_pos = exp(L /set b)` and the zero part, `L = ln(c inter (0, inf))`.
/// An end is open when it is not attained: 0 (from `t -> -inf`) and 1 (the limit of a
/// quotient by an unbounded `b`).
fn pow_pieces(
  b : BallFloat,
  c : BallFloat,
  precision : Int32,
) -> Array[PowPiece] {
  let pieces : Array[PowPiece] = []
  let zero = @bin_float.BinFloat::zero(precision~)
  let one = @bin_float.BinFloat::one(precision~)
  let c1 = c.lo_
  let c2 = c.hi_
  let b1 = b.lo_
  let b2 = b.hi_
  let pow_end = fn(ce : @bin_float.BinFloat, be : @bin_float.BinFloat) {
    PPow(ce, be, pow_end_class(ce, be, precision))
  }
  if c2.compare(zero) > 0 {
    let l_lo_inf = c1.compare(zero) <= 0
    let l_hi_inf = is_pos_inf(c2)
    let zero_l = c1.compare(one) <= 0 && c2.compare(one) >= 0
    let zero_b = b1.compare(zero) <= 0 && b2.compare(zero) >= 0
    if zero_l && zero_b {
      pieces.push(pow_piece(PZero, true, PInf, true))
    } else if zero_l {
      if b1.compare(zero) > 0 {
        let lo = if l_lo_inf { PZero } else { pow_end(c1, b1) }
        let hi = if l_hi_inf { PInf } else { pow_end(c2, b1) }
        pieces.push(pow_piece(lo, l_lo_inf, hi, l_hi_inf))
      } else {
        let lo = if l_hi_inf { PZero } else { pow_end(c2, b2) }
        let hi = if l_lo_inf { PInf } else { pow_end(c1, b2) }
        pieces.push(pow_piece(lo, l_hi_inf, hi, l_lo_inf))
      }
    } else if !zero_b {
      let positive_l = c1.compare(one) > 0
      if positive_l && b1.compare(zero) > 0 {
        let (lo, lo_open) = if is_pos_inf(b2) {
          (POne, true)
        } else {
          (pow_end(c1, b2), false)
        }
        let (hi, hi_open) = if l_hi_inf {
          (PInf, true)
        } else {
          (pow_end(c2, b1), false)
        }
        pieces.push(pow_piece(lo, lo_open, hi, hi_open))
      } else if positive_l {
        let (lo, lo_open) = if l_hi_inf {
          (PZero, true)
        } else {
          (pow_end(c2, b2), false)
        }
        let (hi, hi_open) = if is_neg_inf(b1) {
          (POne, true)
        } else {
          (pow_end(c1, b1), false)
        }
        pieces.push(pow_piece(lo, lo_open, hi, hi_open))
      } else if b1.compare(zero) > 0 {
        let (lo, lo_open) = if l_lo_inf {
          (PZero, true)
        } else {
          (pow_end(c1, b1), false)
        }
        let (hi, hi_open) = if is_pos_inf(b2) {
          (POne, true)
        } else {
          (pow_end(c2, b2), false)
        }
        pieces.push(pow_piece(lo, lo_open, hi, hi_open))
      } else {
        let (lo, lo_open) = if is_neg_inf(b1) {
          (POne, true)
        } else {
          (pow_end(c2, b1), false)
        }
        let (hi, hi_open) = if l_lo_inf {
          (PInf, true)
        } else {
          (pow_end(c1, b2), false)
        }
        pieces.push(pow_piece(lo, lo_open, hi, hi_open))
      }
    } else if !(b1.is_zero() && b2.is_zero()) {
      // 0 not in L, 0 in b, b != {0}: only beta != 0 contributes, the two half-lines
      let positive_l = c1.compare(one) > 0
      let n = if positive_l { c1 } else { c2 }
      let neg_piece : PowPiece? = if b1.compare(zero) < 0 {
        if positive_l {
          let (hi, hi_open) = if is_neg_inf(b1) {
            (POne, true)
          } else {
            (pow_end(n, b1), false)
          }
          Some(pow_piece(PZero, true, hi, hi_open))
        } else {
          let (lo, lo_open) = if is_neg_inf(b1) {
            (POne, true)
          } else {
            (pow_end(n, b1), false)
          }
          Some(pow_piece(lo, lo_open, PInf, true))
        }
      } else {
        None
      }
      let pos_piece : PowPiece? = if b2.compare(zero) > 0 {
        if positive_l {
          let (lo, lo_open) = if is_pos_inf(b2) {
            (POne, true)
          } else {
            (pow_end(n, b2), false)
          }
          Some(pow_piece(lo, lo_open, PInf, true))
        } else {
          let (hi, hi_open) = if is_pos_inf(b2) {
            (POne, true)
          } else {
            (pow_end(n, b2), false)
          }
          Some(pow_piece(PZero, true, hi, hi_open))
        }
      } else {
        None
      }
      let ordered = if positive_l {
        [neg_piece, pos_piece]
      } else {
        [pos_piece, neg_piece]
      }
      for piece in ordered {
        if piece is Some(value) {
          pieces.push(value)
        }
      }
    }
  }
  // 0^beta = 0 for beta > 0
  if b2.compare(zero) > 0 && c1.compare(zero) <= 0 && c2.compare(zero) >= 0 {
    pieces.push(pow_piece(PZero, false, PZero, false))
  }
  pieces
}

///|
/// The hull of the part of the pieces inside the closed prior; every comparison of an
/// end with a prior end is exact (see `pow_end_class`), and the end written is the
/// exact directed rounding of the piece end. An undecided comparison (at the cap)
/// counts as met and the prior's own end is written for such a piece.
fn pow_reverse_hull(
  pieces : Array[PowPiece],
  prior : BallFloat,
  precision : Int32,
  cap : Int32,
) -> BallFloat {
  if prior.is_empty() {
    return empty_interval(precision)
  }
  let xl = prior.lo_
  let xh = prior.hi_
  let lower_infinite = is_neg_inf(xl)
  let upper_infinite = is_pos_inf(xh)
  let mut lower : @bin_float.BinFloat? = None
  let mut upper : @bin_float.BinFloat? = None
  for piece in pieces {
    // the piece meets the prior iff lo <= xh and xl <= hi; an open end equal to a
    // prior end does not meet it
    let order_lo = if upper_infinite {
      Below
    } else {
      pow_end_compare(piece.lo, xh, precision, cap)
    }
    let order_hi = if lower_infinite {
      Above
    } else {
      pow_end_compare(piece.hi, xl, precision, cap)
    }
    let starts = match order_lo {
      Above => false
      Equal => !piece.lo_open
      Below | Undecided => true
    }
    let reaches = match order_hi {
      Below => false
      Equal => !piece.hi_open
      Above | Undecided => true
    }
    if !(starts && reaches) {
      continue
    }
    let value = if lower_infinite {
      pow_end_rounded(piece.lo, false, precision, cap)
    } else {
      match pow_end_compare(piece.lo, xl, precision, cap) {
        Below | Equal | Undecided => xl
        Above => pow_end_rounded(piece.lo, false, precision, cap)
      }
    }
    let top = match piece.hi {
      PInf => xh
      _ =>
        if upper_infinite {
          pow_end_rounded(piece.hi, true, precision, cap)
        } else {
          match pow_end_compare(piece.hi, xh, precision, cap) {
            Above | Equal | Undecided => xh
            Below => pow_end_rounded(piece.hi, true, precision, cap)
          }
        }
    }
    lower = match lower {
      Some(current) if current.compare(value) <= 0 => Some(current)
      _ => Some(value)
    }
    upper = match upper {
      Some(current) if current.compare(top) >= 0 => Some(current)
      _ => Some(top)
    }
  }
  match (lower, upper) {
    (Some(l), Some(u)) =>
      if l.compare(u) <= 0 {
        BallFloat::from_bounds(l, u, precision~)
      } else {
        // not reachable for a nonempty set; the prior itself is a valid answer
        prior
      }
    _ => empty_interval(precision)
  }
}

///|
/// `pow_rev1` with the number of refinements allowed as a parameter (the tests of
/// the fallback set it to 0 and 1).
fn BallFloat::pow_rev1_capped(
  self : BallFloat,
  c : BallFloat,
  x : BallFloat?,
  cap : Int32,
) -> BallFloat {
  let (precision0, prior) = rev_prior_precision(c, x)
  let precision = Int32::max(precision0, self.precision_)
  if self.is_empty() || c.is_empty() || prior.is_empty() {
    return empty_interval(precision)
  }
  pow_reverse_hull(pow_pieces(self, c, precision), prior, precision, cap)
}

///|
/// `powRev1(b, c, x)` of Table 10.1: the hull of
/// `{ x in x | exists beta in b : x^beta is defined and in c }` for the optional prior
/// `x` (default Entire); the receiver is `b`, the exponent. `x^beta` is defined for
/// `x > 0`, and for `x = 0` with `beta > 0` (value 0).
pub fn BallFloat::pow_rev1(
  self : BallFloat,
  c : BallFloat,
  x? : BallFloat,
) -> BallFloat {
  self.pow_rev1_capped(c, x, rev_refinements)
}

///|
/// Trivial decorated version (11.7.1): NaI if any input is NaI, else the bare result
/// decorated `Trv`.
pub fn BallFloatDecorated::pow_rev1(
  self : BallFloatDecorated,
  c : BallFloatDecorated,
  x? : BallFloatDecorated,
) -> BallFloatDecorated {
  let precision = Int32::max(self.interval_.precision_, c.interval_.precision_)
  if self.is_nai() || c.is_nai() || (x is Some(prior) && prior.is_nai()) {
    return BallFloatDecorated::nai(precision~)
  }
  let result = match x {
    Some(prior) => self.interval_.pow_rev1(c.interval_, x=prior.interval_)
    None => self.interval_.pow_rev1(c.interval_)
  }
  BallFloatDecorated::new(result, decoration=Trv)
}
