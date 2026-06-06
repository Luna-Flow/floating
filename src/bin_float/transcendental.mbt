fn exact_make(significand : BigInt, exponent2 : Int) -> BinFloat {
  BinFloat::make(significand, exponent2, Int::max(1, abs_bigint(significand).bit_length()))
}

fn exact_add(a : BinFloat, b : BinFloat) -> BinFloat {
  let target = Int::min(a.exponent2(), b.exponent2())
  let sa = a.significand() << (a.exponent2() - target)
  let sb = b.significand() << (b.exponent2() - target)
  exact_make(sa + sb, target)
}

fn exact_half(x : BinFloat) -> BinFloat {
  exact_make(x.significand(), x.exponent2() - 1)
}

fn integer_sqrt_floor(n : BigInt) -> BigInt {
  guard n >= 0N else { abort("integer sqrt requires non-negative input") }
  if n <= 1N {
    return n
  }
  let mut x = 1N << ((n.bit_length() + 1) / 2)
  let mut y = (x + n / x) / 2N
  while y < x {
    x = y
    y = (x + n / x) / 2N
  }
  x
}

fn work_precision(precision : Int) -> Int {
  Int::max(precision + 24, precision * 2 + 12)
}

fn tiny_threshold(precision : Int) -> BinFloat {
  BinFloat::make(1N, -(precision + 8), precision)
}

fn ratio(num : BigInt, den : BigInt, precision : Int) -> BinFloat {
  guard den > 0N else { abort("ratio denominator must be positive") }
  let p = Int::max(precision, 1)
  let shift = p + 8
  let q = round_positive_div(abs_bigint(num) << shift, den, num < 0N, RoundingMode::ToNearestEven)
  let signed = if num < 0N { -q } else { q }
  BinFloat::make(signed, -shift, p)
}

fn small_positive_atan(x : BinFloat, precision : Int) -> BinFloat {
  let work = work_precision(precision)
  let x = x.with_precision(work, RoundingMode::ToNearestEven)
  let x2 = (x * x).with_precision(work, RoundingMode::ToNearestEven)
  let threshold = tiny_threshold(work)
  let mut term = x
  let mut sum = x
  let mut n = 1
  let mut negative = true
  while term.abs().compare(threshold) > 0 && n < work * 4 {
    term = (term * x2).with_precision(work, RoundingMode::ToNearestEven)
    let piece = (term / BinFloat::from_int(2 * n + 1, precision=work)).with_precision(
      work,
      RoundingMode::ToNearestEven,
    )
    sum =
      if negative {
        (sum - piece).with_precision(work, RoundingMode::ToNearestEven)
      } else {
        (sum + piece).with_precision(work, RoundingMode::ToNearestEven)
      }
    negative = !negative
    n += 1
  }
  sum.with_precision(precision, RoundingMode::ToNearestEven)
}

fn positive_exp_small(x : BinFloat, precision : Int) -> BinFloat {
  let work = work_precision(precision)
  let x = x.with_precision(work, RoundingMode::ToNearestEven)
  let threshold = tiny_threshold(work)
  let mut sum = BinFloat::one(precision=work)
  let mut term = BinFloat::one(precision=work)
  let mut n = 1
  while term.compare(threshold) > 0 && n < work * 6 {
    term = ((term * x) / BinFloat::from_int(n, precision=work)).with_precision(
      work,
      RoundingMode::ToNearestEven,
    )
    sum = (sum + term).with_precision(work, RoundingMode::ToNearestEven)
    n += 1
  }
  sum.with_precision(precision, RoundingMode::ToNearestEven)
}

fn positive_ln_near_one(x : BinFloat, precision : Int) -> BinFloat {
  let work = work_precision(precision)
  let one = BinFloat::one(precision=work)
  let u = ((x - one) / (x + one)).with_precision(work, RoundingMode::ToNearestEven)
  let u2 = (u * u).with_precision(work, RoundingMode::ToNearestEven)
  let threshold = tiny_threshold(work)
  let mut term = u
  let mut sum = u
  let mut n = 1
  while term.abs().compare(threshold) > 0 && n < work * 6 {
    term = (term * u2).with_precision(work, RoundingMode::ToNearestEven)
    let piece = (term / BinFloat::from_int(2 * n + 1, precision=work)).with_precision(
      work,
      RoundingMode::ToNearestEven,
    )
    sum = (sum + piece).with_precision(work, RoundingMode::ToNearestEven)
    n += 1
  }
  (sum * BinFloat::from_int(2, precision=work)).with_precision(precision, RoundingMode::ToNearestEven)
}

pub fn bin_floor_integer(x : BinFloat) -> BigInt {
  guard x.classify() == FpClass::Finite else { abort("floor requires finite input") }
  let sig = x.significand()
  let exp = x.exponent2()
  if exp >= 0 {
    sig << exp
  } else {
    let shift = -exp
    if sig >= 0N {
      sig >> shift
    } else {
      let mag = abs_bigint(sig)
      let q = mag >> shift
      let r = mag - (q << shift)
      if r.is_zero() { -q } else { -(q + 1N) }
    }
  }
}

pub fn bin_ceil_integer(x : BinFloat) -> BigInt {
  guard x.classify() == FpClass::Finite else { abort("ceil requires finite input") }
  let sig = x.significand()
  let exp = x.exponent2()
  if exp >= 0 {
    sig << exp
  } else {
    let shift = -exp
    if sig >= 0N {
      let q = sig >> shift
      let r = sig - (q << shift)
      if r.is_zero() { q } else { q + 1N }
    } else {
      -((abs_bigint(sig)) >> shift)
    }
  }
}

pub fn bin_nearest_integer(x : BinFloat) -> BigInt {
  guard x.classify() == FpClass::Finite else { abort("nearest integer requires finite input") }
  let sig = x.significand()
  let exp = x.exponent2()
  if exp >= 0 {
    return sig << exp
  }
  let shift = -exp
  let mag = abs_bigint(sig)
  let q = mag >> shift
  let r = mag - (q << shift)
  let half = 1N << (shift - 1)
  let rounded =
    if r > half {
      q + 1N
    } else if r < half {
      q
    } else if (q % 2N).is_zero() {
      q
    } else {
      q + 1N
    }
  if sig < 0N { -rounded } else { rounded }
}

fn big_pow_nat(base : BinFloat, exponent : BigInt, precision : Int) -> BinFloat {
  let mut n = exponent
  let mut result = BinFloat::one(precision=precision)
  let mut factor = base.with_precision(precision, RoundingMode::ToNearestEven)
  while n > 0N {
    if !(n % 2N).is_zero() {
      result = (result * factor).with_precision(precision, RoundingMode::ToNearestEven)
    }
    n = n / 2N
    if n > 0N {
      factor = (factor * factor).with_precision(precision, RoundingMode::ToNearestEven)
    }
  }
  result
}

pub fn sqrt_bounds_for_precision(
  x : BinFloat,
  precision : Int,
) -> (BinFloat, BinFloat) {
  guard x.classify() == FpClass::Finite else { abort("sqrt bounds require finite input") }
  guard x.sign() != Sign::Negative else { abort("sqrt requires non-negative input") }
  if x.is_zero() {
    let z = BinFloat::zero(precision=precision)
    return (z, z)
  }
  let e = x.exponent2()
  let extra = if e < 0 { (-e + 1) / 2 } else { 0 }
  let work_bits = precision + extra + 6
  let shift = e + 2 * work_bits
  let n = x.significand() << shift
  let q = integer_sqrt_floor(n)
  let lower0 = BinFloat::make(q, -work_bits, Int::max(1, q.bit_length()))
  let lower = lower0.with_precision(precision, RoundingMode::TowardNegative)
  if q * q == n {
    return (lower, lower)
  }
  let qu = q + 1N
  let upper0 = BinFloat::make(qu, -work_bits, Int::max(1, qu.bit_length()))
  let upper = upper0.with_precision(precision, RoundingMode::TowardPositive)
  (lower, upper)
}

pub fn pi_for_precision(precision : Int) -> BinFloat {
  let work = work_precision(precision)
  let a = small_positive_atan(ratio(1N, 5N, work), work)
  let b = small_positive_atan(ratio(1N, 239N, work), work)
  (
    (a * BinFloat::from_int(16, precision=work)) -
    (b * BinFloat::from_int(4, precision=work))
  ).with_precision(precision, RoundingMode::ToNearestEven)
}

pub fn tau_for_precision(precision : Int) -> BinFloat {
  (pi_for_precision(work_precision(precision)) * BinFloat::from_int(2, precision=work_precision(precision))).with_precision(
    precision,
    RoundingMode::ToNearestEven,
  )
}

pub fn half_pi_for_precision(precision : Int) -> BinFloat {
  exact_half(pi_for_precision(work_precision(precision))).with_precision(
    precision,
    RoundingMode::ToNearestEven,
  )
}

pub fn quarter_pi_for_precision(precision : Int) -> BinFloat {
  exact_half(half_pi_for_precision(work_precision(precision))).with_precision(
    precision,
    RoundingMode::ToNearestEven,
  )
}

pub fn ln2_for_precision(precision : Int) -> BinFloat {
  let work = work_precision(precision)
  positive_ln_near_one(BinFloat::from_int(2, precision=work), precision)
}

pub fn exp_for_precision(x : BinFloat, precision : Int) -> BinFloat {
  match x.classify() {
    FpClass::NaN => BinFloat::nan(precision=precision)
    FpClass::Infinity =>
      if x.sign() == Sign::Negative {
        BinFloat::zero(precision=precision)
      } else {
        BinFloat::inf(Sign::Positive, precision=precision)
      }
    FpClass::Finite => {
      if x.is_zero() {
        return BinFloat::one(precision=precision)
      }
      if x.sign() == Sign::Negative {
        return (BinFloat::one(precision=work_precision(precision)) /
          exp_for_precision(x.neg(), work_precision(precision))).with_precision(
          precision,
          RoundingMode::ToNearestEven,
        )
      }
      let work = work_precision(precision)
      let ln2 = ln2_for_precision(work)
      let k_big = bin_nearest_integer((x / ln2).with_precision(work, RoundingMode::ToNearestEven))
      let k = k_big.to_int()
      let remainder = (x - BinFloat::from_int(k, precision=work) * ln2).with_precision(
        work,
        RoundingMode::ToNearestEven,
      )
      let small = positive_exp_small(remainder, work)
      let scaled = exact_make(small.significand(), small.exponent2() + k)
      scaled.with_precision(precision, RoundingMode::ToNearestEven)
    }
  }
}

pub fn exp2_for_precision(x : BinFloat, precision : Int) -> BinFloat {
  exp_for_precision((x * ln2_for_precision(work_precision(precision))).with_precision(
    work_precision(precision),
    RoundingMode::ToNearestEven,
  ), precision)
}

pub fn ln_for_precision(x : BinFloat, precision : Int) -> BinFloat {
  match x.classify() {
    FpClass::NaN => BinFloat::nan(precision=precision)
    FpClass::Infinity =>
      if x.sign() == Sign::Negative {
        BinFloat::nan(precision=precision)
      } else {
        BinFloat::inf(Sign::Positive, precision=precision)
      }
    FpClass::Finite => {
      guard x.sign() == Sign::Positive else { abort("ln requires a positive finite input") }
      if x.compare(BinFloat::one(precision=x.precision())) == 0 {
        return BinFloat::zero(precision=precision)
      }
      let work = work_precision(precision)
      let sig = x.significand()
      let bits = abs_bigint(sig).bit_length()
      let exponent = x.exponent2() + bits - 1
      let mantissa = BinFloat::make(sig, -(bits - 1), work)
      let ln_m = positive_ln_near_one(mantissa, work)
      let scaled = (ln2_for_precision(work) * BinFloat::from_int(exponent, precision=work)).with_precision(
        work,
        RoundingMode::ToNearestEven,
      )
      (scaled + ln_m).with_precision(precision, RoundingMode::ToNearestEven)
    }
  }
}

pub fn log2_for_precision(x : BinFloat, precision : Int) -> BinFloat {
  (ln_for_precision(x, work_precision(precision)) /
    ln2_for_precision(work_precision(precision))).with_precision(
    precision,
    RoundingMode::ToNearestEven,
  )
}

pub fn log10_for_precision(x : BinFloat, precision : Int) -> BinFloat {
  (ln_for_precision(x, work_precision(precision)) /
    ln_for_precision(BinFloat::from_int(10, precision=work_precision(precision)), work_precision(precision))).with_precision(
    precision,
    RoundingMode::ToNearestEven,
  )
}

pub fn sqrt_for_precision(x : BinFloat, precision : Int) -> BinFloat {
  match x.classify() {
    FpClass::NaN => BinFloat::nan(precision=precision)
    FpClass::Infinity =>
      if x.sign() == Sign::Negative {
        BinFloat::nan(precision=precision)
      } else {
        BinFloat::inf(Sign::Positive, precision=precision)
      }
    FpClass::Finite => {
      let (lo, hi) = sqrt_bounds_for_precision(x, work_precision(precision))
      exact_half(exact_add(lo, hi)).with_precision(precision, RoundingMode::ToNearestEven)
    }
  }
}

pub fn cbrt_for_precision(x : BinFloat, precision : Int) -> BinFloat {
  match x.classify() {
    FpClass::NaN => BinFloat::nan(precision=precision)
    FpClass::Infinity => BinFloat::inf(x.sign(), precision=precision)
    FpClass::Finite =>
      if x.is_zero() {
        BinFloat::zero(precision=precision)
      } else if x.sign() == Sign::Negative {
        cbrt_for_precision(x.neg(), precision).neg()
      } else {
        exp_for_precision(
          (ln_for_precision(x, work_precision(precision)) /
            BinFloat::from_int(3, precision=work_precision(precision))).with_precision(
            work_precision(precision),
            RoundingMode::ToNearestEven,
          ),
          precision,
        )
      }
  }
}

fn small_sin(x : BinFloat, precision : Int) -> BinFloat {
  let work = work_precision(precision)
  let x = x.with_precision(work, RoundingMode::ToNearestEven)
  let x2 = (x * x).with_precision(work, RoundingMode::ToNearestEven)
  let threshold = tiny_threshold(work)
  let mut term = x
  let mut sum = x
  let mut n = 1
  let mut negative = true
  while term.abs().compare(threshold) > 0 && n < work * 6 {
    let a = BinFloat::from_int(2 * n, precision=work)
    let b = BinFloat::from_int(2 * n + 1, precision=work)
    term = (((term * x2) / a) / b).with_precision(work, RoundingMode::ToNearestEven)
    sum =
      if negative {
        (sum - term).with_precision(work, RoundingMode::ToNearestEven)
      } else {
        (sum + term).with_precision(work, RoundingMode::ToNearestEven)
      }
    negative = !negative
    n += 1
  }
  sum.with_precision(precision, RoundingMode::ToNearestEven)
}

fn small_cos(x : BinFloat, precision : Int) -> BinFloat {
  let work = work_precision(precision)
  let x = x.with_precision(work, RoundingMode::ToNearestEven)
  let x2 = (x * x).with_precision(work, RoundingMode::ToNearestEven)
  let threshold = tiny_threshold(work)
  let mut term = BinFloat::one(precision=work)
  let mut sum = BinFloat::one(precision=work)
  let mut n = 1
  let mut negative = true
  while term.abs().compare(threshold) > 0 && n < work * 6 {
    let a = BinFloat::from_int(2 * n - 1, precision=work)
    let b = BinFloat::from_int(2 * n, precision=work)
    term = (((term * x2) / a) / b).with_precision(work, RoundingMode::ToNearestEven)
    sum =
      if negative {
        (sum - term).with_precision(work, RoundingMode::ToNearestEven)
      } else {
        (sum + term).with_precision(work, RoundingMode::ToNearestEven)
      }
    negative = !negative
    n += 1
  }
  sum.with_precision(precision, RoundingMode::ToNearestEven)
}

fn reduce_half_pi(x : BinFloat, precision : Int) -> (Int, BinFloat) {
  let work = work_precision(precision)
  let half_pi = half_pi_for_precision(work)
  let q = bin_nearest_integer((x / half_pi).with_precision(work, RoundingMode::ToNearestEven))
  let q_int = ((q % 4N) + 4N) % 4N
  let r = (x - (BinFloat::from_bigint(q, precision=work) * half_pi)).with_precision(
    work,
    RoundingMode::ToNearestEven,
  )
  (q_int.to_int(), r)
}

pub fn sin_for_precision(x : BinFloat, precision : Int) -> BinFloat {
  match x.classify() {
    FpClass::NaN => BinFloat::nan(precision=precision)
    FpClass::Infinity => BinFloat::nan(precision=precision)
    FpClass::Finite => {
      if x.is_zero() {
        return BinFloat::zero(precision=precision)
      }
      let (quadrant, r) = reduce_half_pi(x, precision)
      let y = match quadrant {
        0 => small_sin(r, work_precision(precision))
        1 => small_cos(r, work_precision(precision))
        2 => small_sin(r, work_precision(precision)).neg()
        _ => small_cos(r, work_precision(precision)).neg()
      }
      y.with_precision(precision, RoundingMode::ToNearestEven)
    }
  }
}

pub fn cos_for_precision(x : BinFloat, precision : Int) -> BinFloat {
  match x.classify() {
    FpClass::NaN => BinFloat::nan(precision=precision)
    FpClass::Infinity => BinFloat::nan(precision=precision)
    FpClass::Finite => {
      let (quadrant, r) = reduce_half_pi(x, precision)
      let y = match quadrant {
        0 => small_cos(r, work_precision(precision))
        1 => small_sin(r, work_precision(precision)).neg()
        2 => small_cos(r, work_precision(precision)).neg()
        _ => small_sin(r, work_precision(precision))
      }
      y.with_precision(precision, RoundingMode::ToNearestEven)
    }
  }
}

pub fn tan_for_precision(x : BinFloat, precision : Int) -> BinFloat {
  let work = work_precision(precision)
  let c = cos_for_precision(x, work)
  guard !c.is_zero() else { abort("tan is undefined at odd multiples of pi/2") }
  (sin_for_precision(x, work) / c).with_precision(precision, RoundingMode::ToNearestEven)
}

pub fn atan_for_precision(x : BinFloat, precision : Int) -> BinFloat {
  match x.classify() {
    FpClass::NaN => BinFloat::nan(precision=precision)
    FpClass::Infinity =>
      if x.sign() == Sign::Negative {
        half_pi_for_precision(precision).neg()
      } else {
        half_pi_for_precision(precision)
      }
    FpClass::Finite => {
      if x.is_zero() {
        return BinFloat::zero(precision=precision)
      }
      if x.sign() == Sign::Negative {
        return atan_for_precision(x.neg(), precision).neg()
      }
      let one = BinFloat::one(precision=work_precision(precision))
      let half = ratio(1N, 2N, work_precision(precision))
      if x.compare(half) <= 0 {
        return small_positive_atan(x, precision)
      }
      if x.compare(one) <= 0 {
        let t = ((x - one) / (x + one)).with_precision(work_precision(precision), RoundingMode::ToNearestEven)
        return (quarter_pi_for_precision(work_precision(precision)) +
          small_positive_atan(t, work_precision(precision))).with_precision(
          precision,
          RoundingMode::ToNearestEven,
        )
      }
      (half_pi_for_precision(work_precision(precision)) -
        atan_for_precision(
          (one / x).with_precision(work_precision(precision), RoundingMode::ToNearestEven),
          work_precision(precision),
        )).with_precision(precision, RoundingMode::ToNearestEven)
    }
  }
}

pub fn atan2_for_precision(y : BinFloat, x : BinFloat, precision : Int) -> BinFloat {
  guard y.classify() != FpClass::NaN && x.classify() != FpClass::NaN else {
    return BinFloat::nan(precision=precision)
  }
  if x.is_zero() {
    if y.sign() == Sign::Positive {
      return half_pi_for_precision(precision)
    } else if y.sign() == Sign::Negative {
      return half_pi_for_precision(precision).neg()
    } else {
      return BinFloat::zero(precision=precision)
    }
  }
  let work = work_precision(precision)
  let theta = atan_for_precision((y / x).with_precision(work, RoundingMode::ToNearestEven), work)
  if x.sign() == Sign::Positive {
    theta.with_precision(precision, RoundingMode::ToNearestEven)
  } else if y.sign() == Sign::Negative {
    (theta - pi_for_precision(work)).with_precision(precision, RoundingMode::ToNearestEven)
  } else {
    (theta + pi_for_precision(work)).with_precision(precision, RoundingMode::ToNearestEven)
  }
}

pub fn asin_for_precision(x : BinFloat, precision : Int) -> BinFloat {
  guard x.classify() == FpClass::Finite else { return BinFloat::nan(precision=precision) }
  guard x.abs().compare(BinFloat::one(precision=x.precision())) <= 0 else {
    abort("asin requires input inside [-1, 1]")
  }
  let work = work_precision(precision)
  let root = sqrt_for_precision((BinFloat::one(precision=work) - x * x).with_precision(
    work,
    RoundingMode::ToNearestEven,
  ), work)
  atan2_for_precision(x.with_precision(work, RoundingMode::ToNearestEven), root, precision)
}

pub fn acos_for_precision(x : BinFloat, precision : Int) -> BinFloat {
  guard x.classify() == FpClass::Finite else { return BinFloat::nan(precision=precision) }
  guard x.abs().compare(BinFloat::one(precision=x.precision())) <= 0 else {
    abort("acos requires input inside [-1, 1]")
  }
  let work = work_precision(precision)
  let root = sqrt_for_precision((BinFloat::one(precision=work) - x * x).with_precision(
    work,
    RoundingMode::ToNearestEven,
  ), work)
  atan2_for_precision(root, x.with_precision(work, RoundingMode::ToNearestEven), precision)
}

pub fn pow_for_precision(base : BinFloat, exponent : BinFloat, precision : Int) -> BinFloat {
  match exponent.classify() {
    FpClass::Finite => {
      let nearest = bin_nearest_integer(exponent)
      let exact = BinFloat::from_bigint(nearest, precision=work_precision(precision))
      if exact.compare(exponent.with_precision(work_precision(precision), RoundingMode::ToNearestEven)) == 0 {
        if nearest == 0N {
          return BinFloat::one(precision=precision)
        }
        if nearest > 0N {
          return big_pow_nat(base, nearest, precision)
        }
        return (BinFloat::one(precision=work_precision(precision)) /
          big_pow_nat(base, -nearest, work_precision(precision))).with_precision(
          precision,
          RoundingMode::ToNearestEven,
        )
      }
      guard base.sign() == Sign::Positive else {
        abort("non-integer pow requires a positive base")
      }
      exp_for_precision(
        (exponent.with_precision(work_precision(precision), RoundingMode::ToNearestEven) *
          ln_for_precision(base, work_precision(precision))).with_precision(
          work_precision(precision),
          RoundingMode::ToNearestEven,
        ),
        precision,
      )
    }
    FpClass::Infinity => BinFloat::nan(precision=precision)
    FpClass::NaN => BinFloat::nan(precision=precision)
  }
}

pub fn sinh_for_precision(x : BinFloat, precision : Int) -> BinFloat {
  let work = work_precision(precision)
  let ex = exp_for_precision(x, work)
  let enx = exp_for_precision(x.neg(), work)
  ((ex - enx) / BinFloat::from_int(2, precision=work)).with_precision(
    precision,
    RoundingMode::ToNearestEven,
  )
}

pub fn cosh_for_precision(x : BinFloat, precision : Int) -> BinFloat {
  let work = work_precision(precision)
  let ex = exp_for_precision(x, work)
  let enx = exp_for_precision(x.neg(), work)
  ((ex + enx) / BinFloat::from_int(2, precision=work)).with_precision(
    precision,
    RoundingMode::ToNearestEven,
  )
}

pub fn tanh_for_precision(x : BinFloat, precision : Int) -> BinFloat {
  let work = work_precision(precision)
  let sh = sinh_for_precision(x, work)
  let ch = cosh_for_precision(x, work)
  (sh / ch).with_precision(precision, RoundingMode::ToNearestEven)
}

pub fn asinh_for_precision(x : BinFloat, precision : Int) -> BinFloat {
  let work = work_precision(precision)
  ln_for_precision(
    (x.with_precision(work, RoundingMode::ToNearestEven) +
      sqrt_for_precision((x * x + BinFloat::one(precision=work)).with_precision(
        work,
        RoundingMode::ToNearestEven,
      ), work)).with_precision(work, RoundingMode::ToNearestEven),
    precision,
  )
}

pub fn acosh_for_precision(x : BinFloat, precision : Int) -> BinFloat {
  guard x.compare(BinFloat::one(precision=x.precision())) >= 0 else {
    abort("acosh requires input >= 1")
  }
  let work = work_precision(precision)
  let left = sqrt_for_precision((x - BinFloat::one(precision=work)).with_precision(
    work,
    RoundingMode::ToNearestEven,
  ), work)
  let right = sqrt_for_precision((x + BinFloat::one(precision=work)).with_precision(
    work,
    RoundingMode::ToNearestEven,
  ), work)
  ln_for_precision((x.with_precision(work, RoundingMode::ToNearestEven) + left * right).with_precision(
    work,
    RoundingMode::ToNearestEven,
  ), precision)
}

pub fn atanh_for_precision(x : BinFloat, precision : Int) -> BinFloat {
  guard x.abs().compare(BinFloat::one(precision=x.precision())) < 0 else {
    abort("atanh requires input inside (-1, 1)")
  }
  let work = work_precision(precision)
  let num = (BinFloat::one(precision=work) + x.with_precision(work, RoundingMode::ToNearestEven)).with_precision(
    work,
    RoundingMode::ToNearestEven,
  )
  let den = (BinFloat::one(precision=work) - x.with_precision(work, RoundingMode::ToNearestEven)).with_precision(
    work,
    RoundingMode::ToNearestEven,
  )
  exact_half(ln_for_precision((num / den).with_precision(work, RoundingMode::ToNearestEven), work)).with_precision(
    precision,
    RoundingMode::ToNearestEven,
  )
}

pub fn e_for_precision(precision : Int) -> BinFloat {
  exp_for_precision(BinFloat::one(precision=work_precision(precision)), precision)
}
