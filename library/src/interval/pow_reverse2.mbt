///|
/// `powRev2(a, c, x)` of IEEE 1788-2015 Table 10.1: the hull of
/// `{ beta in x | exists a0 in a : a0^beta is defined and in c }`, where `a0^beta` is
/// defined for `a0 > 0` and for `a0 = 0` with `beta > 0` (then 0). The unknown is the
/// exponent.
///
/// For `a0 > 0`, `a0^beta in c` is `beta ln a0 in ln c`, so the set is the set
/// division `L /set M` with `L = ln(c inter (0, +inf))` and `M = ln(a inter (0, +inf))`
/// (the same division as `mul_rev`, in logarithm coordinates), plus `(0, +inf)` when
/// `0 in a` and `0 in c`. `1 in a` is the branch "0 in the divisor", and `1 in c` the
/// branch "0 in the dividend". Every end of a piece is `ln(c_end) / ln(a_end)`, 0 or
/// infinite.
///
/// Exactness of `r = ln(C) / ln(A)` for floats `A != 1` and `C > 0`: write
/// `A = alpha 2^i` and `C = gamma 2^j` with `alpha`, `gamma` odd and positive (the
/// exponents `i`, `j` carry the sign of the logarithms). `r` is rational iff `A` and `C`
/// are multiplicatively dependent (`A^p = C^q`), and then:
/// - `C = 1`: `r = 0`;
/// - `alpha = gamma = 1`: `r = j / i`;
/// - exactly one of `alpha`, `gamma` is 1: `r` is irrational (`C != 1`);
/// - both exceed 1: the multiplicative Euclidean algorithm (divide the larger odd
///   integer by the smaller; an inexact division proves independence) gives `B` with
///   `alpha = B^i'`, `gamma = B^j'`, `gcd(i', j') = 1`, and `r = j' / i'` iff
///   `i j' = j i'`, else `r` is irrational.
/// The value is a float iff the reduced denominator is a power of two (class
/// `QDyadic`), else a rational that is not a float (class `QRational`, compared by
/// cross-multiplication and rounded by integer division). Odd parts beyond
/// `pow_int_budget` bits give `QUnknown`, decided by the loop like `QIrrational`.

///|
priv enum QuotClass {
  QDyadic(@bin_float.BinFloat)
  // value = (-1)^neg * num / den, den not a power of two, gcd(num, den) = 1
  QRational(Bool, @bin_float.BinCoeff, @bin_float.BinCoeff)
  QIrrational
  QUnknown
}

///|
fn quot_gcd(a : Int64, b : Int64) -> Int64 {
  let mut x = if a < 0L { -a } else { a }
  let mut y = if b < 0L { -b } else { b }
  while y != 0L {
    let t = x % y
    x = y
    y = t
  }
  x
}

///|
fn quot_coeff(n : Int64) -> @bin_float.BinCoeff {
  @bin_float.BinCoeff::from_uint64(
    (if n < 0L { -n } else { n }).reinterpret_as_uint64(),
  )
}

///|
/// A rational `num / den` (`num != 0`, `den > 0`, both reduced) as a class: a float iff
/// `den` is a power of two.
fn quot_rational_class(
  negative : Bool,
  num : @bin_float.BinCoeff,
  den : @bin_float.BinCoeff,
) -> QuotClass {
  let zeros = pow_trailing_zeros(den)
  if den.bit_length() == zeros + 1 {
    // den = 2^zeros
    let value = exact_make(num, -zeros)
    QDyadic(if negative { value.neg() } else { value })
  } else {
    QRational(negative, num, den)
  }
}

///|
/// The class of `ln(c) / ln(a)`, `c > 0` finite and `a > 0` finite, `a != 1`.
fn quot_end_class(
  c : @bin_float.BinFloat,
  a : @bin_float.BinFloat,
) -> QuotClass {
  let one = @bin_float.BinFloat::one()
  if c.compare(one) == 0 {
    return QDyadic(@bin_float.BinFloat::zero())
  }
  if a.compare(one) == 0 {
    return QUnknown
  }
  let (alpha, i) = pow_split(a)
  let (gamma, j) = pow_split(c)
  let alpha_one = alpha.bit_length() == 1
  let gamma_one = gamma.bit_length() == 1
  if alpha_one && gamma_one {
    // A = 2^i, C = 2^j, i != 0, j != 0
    let g = quot_gcd(i, j)
    let negative = (i < 0L) != (j < 0L)
    return quot_rational_class(negative, quot_coeff(j / g), quot_coeff(i / g))
  }
  if alpha_one || gamma_one {
    return QIrrational
  }
  if alpha.bit_length() > pow_int_budget || gamma.bit_length() > pow_int_budget {
    return QUnknown
  }
  // the multiplicative Euclidean algorithm on (alpha, gamma): divide the larger by a
  // power of the smaller, `y^k` with `k = floor((bits(x) - 1) / bits(y))` (so `y^k <= x`),
  // which is a divisor of `x` whenever both are powers of one base; an inexact division
  // proves independence. A high power of a small base takes a few steps, not one per
  // factor.
  let mut x = alpha
  let mut y = gamma
  let steps : Array[(Bool, Int32)] = []
  while x.bit_length() > 1 && y.bit_length() > 1 {
    if steps.length() > pow_int_budget.to_int() {
      return QUnknown
    }
    let x_larger = coeff_compare(x, y) >= 0
    let (big, small) = if x_larger { (x, y) } else { (y, x) }
    let k = Int32::max(1, (big.bit_length() - 1) / small.bit_length())
    let (quotient, remainder) = coeff_div_rem(big, coeff_pow_small(small, k))
    if !remainder.is_zero() {
      return QIrrational
    }
    if x_larger {
      x = quotient
    } else {
      y = quotient
    }
    steps.push((!x_larger, k))
  }
  // one of x, y is 1 and the other is B
  let base = if x.bit_length() == 1 { y } else { x }
  let mut u : Int64 = if x.bit_length() == 1 { 0L } else { 1L }
  let mut v : Int64 = if x.bit_length() == 1 { 1L } else { 0L }
  let mut index = steps.length() - 1
  while index >= 0 {
    let (second, k) = steps[index]
    if second {
      v = v + k.to_int64() * u
    } else {
      u = u + k.to_int64() * v
    }
    index -= 1
  }
  // exact check: alpha = B^u and gamma = B^v
  if coeff_compare(coeff_pow_small(base, u.to_int()), alpha) != 0 ||
    coeff_compare(coeff_pow_small(base, v.to_int()), gamma) != 0 {
    return QUnknown
  }
  // A = 2^i B^u, C = 2^j B^v with 2 and B independent: r is rational iff
  // i v = j u, and then r = v / u
  if i * v != j * u {
    return QIrrational
  }
  let g = quot_gcd(u, v)
  quot_rational_class(false, quot_coeff(v / g), quot_coeff(u / g))
}

///|
/// An enclosure of `ln(c) / ln(a)` at `w` bits.
fn quot_enclosure(
  c : @bin_float.BinFloat,
  a : @bin_float.BinFloat,
  w : Int32,
) -> PowEnc {
  let t = Interval::exact(c, precision=Int32::max(w, c.precision())).ln() /
    Interval::exact(a, precision=Int32::max(w, a.precision())).ln()
  { lo: t.lo_, lo_open: false, hi: t.hi_, hi_open: false, clamped: false, }
}

///|
/// The first working precision: the quotient `t` needs an absolute error below
/// `2^(adjusted exponent of t - precision)`, and `ln` has a relative error of about
/// `2^-w` (also for an argument next to 1), so the bits of the integer part of `t` are
/// added to the precision.
fn quot_start_work(
  c : @bin_float.BinFloat,
  a : @bin_float.BinFloat,
  precision : Int32,
) -> Int32 {
  let coarse = Interval::exact(c, precision=Int32::max(64, c.precision())).ln() /
    Interval::exact(a, precision=Int32::max(64, a.precision())).ln()
  let e = Int64::max(0L, pow_adjusted_exponent(coarse.magnitude()))
  precision + 64 + e.to_int()
}

///|
/// Compares `num / den` (`num`, `den` positive) with the finite positive `d`.
fn quot_magnitude_compare(
  num : @bin_float.BinCoeff,
  den : @bin_float.BinCoeff,
  d : @bin_float.BinFloat,
) -> Int32 {
  let (dc, de) = (d.coefficient(), d.exponent2())
  // log2(num/den) is in (bl(num) - bl(den) - 1, bl(num) - bl(den) + 1); log2(d) in
  // [de + bl(dc) - 1, de + bl(dc))
  let value_mid = num.bit_length().to_int64() - den.bit_length().to_int64()
  let d_low = de.to_int64() + dc.bit_length().to_int64() - 1L
  if value_mid + 1L <= d_low {
    return -1
  }
  if d_low + 1L <= value_mid - 1L {
    return 1
  }
  // within a few bits: compare num * 2^(-de) with dc * den exactly
  let product = coeff_mul(dc, den)
  let shift = -de.to_int64()
  if shift >= 0L {
    coeff_compare(coeff_shift_left(num, shift.to_int()), product)
  } else {
    coeff_compare(num, coeff_shift_left(product, (-shift).to_int()))
  }
}

///|
/// The sign-aware comparison of `(-1)^neg num / den` with the finite float `d`.
fn quot_rational_compare(
  negative : Bool,
  num : @bin_float.BinCoeff,
  den : @bin_float.BinCoeff,
  d : @bin_float.BinFloat,
) -> Int32 {
  if d.is_zero() {
    return if negative { -1 } else { 1 }
  }
  let d_negative = d.sign() == Sign::Negative
  if negative && !d_negative {
    return -1
  }
  if !negative && d_negative {
    return 1
  }
  let order = quot_magnitude_compare(num, den, d)
  if negative {
    -order
  } else {
    order
  }
}

///|
/// `RD` or `RU` to `precision` bits of `(-1)^neg num / den`.
fn quot_rational_round(
  negative : Bool,
  num : @bin_float.BinCoeff,
  den : @bin_float.BinCoeff,
  upper : Bool,
  precision : Int32,
) -> @bin_float.BinFloat {
  // the magnitude is rounded in the other direction for a negative value
  let magnitude_up = upper != negative
  let scale = Int32::max(0, precision + 3 + den.bit_length() - num.bit_length())
  let (quotient, remainder) = coeff_div_rem(coeff_shift_left(num, scale), den)
  let exponent = -scale
  let rounded = if magnitude_up {
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
  if negative {
    rounded.neg()
  } else {
    rounded
  }
}

///|
fn quot_end_compare(
  c : @bin_float.BinFloat,
  a : @bin_float.BinFloat,
  cls : QuotClass,
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

  match cls {
    QDyadic(value) => order_of(value.compare(d))
    QRational(negative, num, den) =>
      order_of(quot_rational_compare(negative, num, den, d))
    QIrrational | QUnknown =>
      pow_loop_compare(
        quot_start_work(c, a, precision),
        fn(w) { quot_enclosure(c, a, w) },
        d,
        cap,
      )
  }
}

///|
fn quot_end_rounded(
  c : @bin_float.BinFloat,
  a : @bin_float.BinFloat,
  cls : QuotClass,
  upper : Bool,
  precision : Int32,
  cap : Int32,
) -> @bin_float.BinFloat {
  match cls {
    QDyadic(value) =>
      value.with_precision(
        precision,
        if upper {
          BinaryRoundingMode::RoundTowardPositive
        } else {
          BinaryRoundingMode::RoundTowardNegative
        },
      )
    QRational(negative, num, den) =>
      quot_rational_round(negative, num, den, upper, precision)
    QIrrational | QUnknown =>
      pow_loop_round(
        quot_start_work(c, a, precision),
        fn(w) { quot_enclosure(c, a, w) },
        upper,
        precision,
        cap,
      )
  }
}

///|
/// The pieces of `L /set M` and the part for the base 0, `L = ln(c inter (0, inf))`,
/// `M = ln(a inter (0, inf))`. The sign of a logarithm is the position of the float end
/// against 1; an end of `L` or `M` is infinite when the float end is not positive
/// (`ln -> -inf`) or infinite. An end of a piece is open when it is not attained: 0 (the
/// limit of a quotient by an unbounded divisor) and the infinities.
fn pow2_pieces(
  a : Interval,
  c : Interval,
  precision : Int32,
) -> Array[PowPiece] {
  let pieces : Array[PowPiece] = []
  let zero = @bin_float.BinFloat::zero(precision~)
  let one = @bin_float.BinFloat::one(precision~)
  let c1 = c.lo_
  let c2 = c.hi_
  let a1 = a.lo_
  let a2 = a.hi_
  let quot = fn(ce : @bin_float.BinFloat, ae : @bin_float.BinFloat) {
    PQuot(ce, ae, quot_end_class(ce, ae))
  }
  if c2.compare(zero) > 0 && a2.compare(zero) > 0 {
    let l_lo_inf = c1.compare(zero) <= 0
    let l_hi_inf = is_pos_inf(c2)
    let m_lo_inf = a1.compare(zero) <= 0
    let m_hi_inf = is_pos_inf(a2)
    // sign of the ends of M
    let m_lo_pos = a1.compare(one) > 0
    let m_lo_neg = a1.compare(one) < 0
    let m_hi_pos = a2.compare(one) > 0
    let zero_l = c1.compare(one) <= 0 && c2.compare(one) >= 0
    let zero_m = a1.compare(one) <= 0 && a2.compare(one) >= 0
    if zero_l && zero_m {
      pieces.push(pow_piece(PNegInf, true, PInf, true))
    } else if zero_l {
      // 0 in L, 0 not in M: beta = l / m with m of one sign
      if m_lo_pos {
        // m > 0: beta in [l1 / m1', l2 / m1'] with the nearer M end
        let lo = if l_lo_inf { PNegInf } else { quot(c1, a1) }
        let hi = if l_hi_inf { PInf } else { quot(c2, a1) }
        pieces.push(pow_piece(lo, l_lo_inf, hi, l_hi_inf))
      } else {
        // m < 0: the nearer end is a2 and the order reverses
        let lo = if l_hi_inf { PNegInf } else { quot(c2, a2) }
        let hi = if l_lo_inf { PInf } else { quot(c1, a2) }
        pieces.push(pow_piece(lo, l_hi_inf, hi, l_lo_inf))
      }
    } else if !zero_m {
      let positive_l = c1.compare(one) > 0
      if positive_l && m_lo_pos {
        let (lo, lo_open) = if m_hi_inf {
          (PZero, true)
        } else {
          (quot(c1, a2), false)
        }
        let (hi, hi_open) = if l_hi_inf {
          (PInf, true)
        } else {
          (quot(c2, a1), false)
        }
        pieces.push(pow_piece(lo, lo_open, hi, hi_open))
      } else if positive_l {
        // l > 0, m < 0: beta < 0
        let (lo, lo_open) = if l_hi_inf {
          (PNegInf, true)
        } else {
          (quot(c2, a2), false)
        }
        let (hi, hi_open) = if m_lo_inf {
          (PZero, true)
        } else {
          (quot(c1, a1), false)
        }
        pieces.push(pow_piece(lo, lo_open, hi, hi_open))
      } else if m_lo_pos {
        // l < 0, m > 0: beta < 0
        let (lo, lo_open) = if l_lo_inf {
          (PNegInf, true)
        } else {
          (quot(c1, a1), false)
        }
        let (hi, hi_open) = if m_hi_inf {
          (PZero, true)
        } else {
          (quot(c2, a2), false)
        }
        pieces.push(pow_piece(lo, lo_open, hi, hi_open))
      } else {
        // l < 0, m < 0: beta > 0
        let (lo, lo_open) = if m_lo_inf {
          (PZero, true)
        } else {
          (quot(c2, a1), false)
        }
        let (hi, hi_open) = if l_lo_inf {
          (PInf, true)
        } else {
          (quot(c1, a2), false)
        }
        pieces.push(pow_piece(lo, lo_open, hi, hi_open))
      }
    } else if !(a1.compare(one) == 0 && a2.compare(one) == 0) {
      // 0 not in L, 0 in M, M != {0}: the two half-lines of m != 0
      let positive_l = c1.compare(one) > 0
      let n = if positive_l { c1 } else { c2 }
      let neg_piece : PowPiece? = if m_lo_neg {
        if positive_l {
          // l > 0, m < 0: beta <= l1 / m1 < 0
          let (hi, hi_open) = if m_lo_inf {
            (PZero, true)
          } else {
            (quot(n, a1), false)
          }
          Some(pow_piece(PNegInf, true, hi, hi_open))
        } else {
          // l < 0, m < 0: beta >= l2 / m1 > 0
          let (lo, lo_open) = if m_lo_inf {
            (PZero, true)
          } else {
            (quot(n, a1), false)
          }
          Some(pow_piece(lo, lo_open, PInf, true))
        }
      } else {
        None
      }
      let pos_piece : PowPiece? = if m_hi_pos {
        if positive_l {
          // l > 0, m > 0: beta >= l1 / m2 > 0
          let (lo, lo_open) = if m_hi_inf {
            (PZero, true)
          } else {
            (quot(n, a2), false)
          }
          Some(pow_piece(lo, lo_open, PInf, true))
        } else {
          // l < 0, m > 0: beta <= l2 / m2 < 0
          let (hi, hi_open) = if m_hi_inf {
            (PZero, true)
          } else {
            (quot(n, a2), false)
          }
          Some(pow_piece(PNegInf, true, hi, hi_open))
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
  if a1.compare(zero) <= 0 &&
    a2.compare(zero) >= 0 &&
    c1.compare(zero) <= 0 &&
    c2.compare(zero) >= 0 {
    pieces.push(pow_piece(PZero, true, PInf, true))
  }
  pieces
}

///|
/// `pow_rev2` with the number of refinements allowed as a parameter (the tests of the
/// fallback set it to 0 and 1).
fn Interval::pow_rev2_capped(
  self : Interval,
  c : Interval,
  x : Interval?,
  cap : Int32,
) -> Interval {
  let (precision0, prior) = rev_prior_precision(c, x)
  let precision = Int32::max(precision0, self.precision_)
  if self.is_empty() || c.is_empty() || prior.is_empty() {
    return empty_interval(precision)
  }
  pow_reverse_hull(pow2_pieces(self, c, precision), prior, precision, cap)
}

///|
/// `powRev2(a, c, x)` of Table 10.1: the hull of
/// `{ beta in x | exists a0 in a : a0^beta is defined and in c }` for the optional prior
/// `x` (default Entire); the receiver is `a`, the base. `a0^beta` is defined for
/// `a0 > 0`, and for `a0 = 0` with `beta > 0` (value 0).
pub fn Interval::pow_rev2(
  self : Interval,
  c : Interval,
  x? : Interval,
) -> Interval {
  self.pow_rev2_capped(c, x, rev_refinements)
}

///|
/// The trivial decorated version of 11.7.1: NaI if any input is NaI, else the bare
/// result decorated `Trv`.
pub fn DecoratedInterval::pow_rev2(
  self : DecoratedInterval,
  c : DecoratedInterval,
  x? : DecoratedInterval,
) -> DecoratedInterval {
  let precision = Int32::max(self.interval_.precision_, c.interval_.precision_)
  if self.is_nai() || c.is_nai() || (x is Some(prior) && prior.is_nai()) {
    return DecoratedInterval::nai(precision~)
  }
  let result = match x {
    Some(prior) => self.interval_.pow_rev2(c.interval_, x=prior.interval_)
    None => self.interval_.pow_rev2(c.interval_)
  }
  DecoratedInterval::new(result, decoration=Trv)
}
