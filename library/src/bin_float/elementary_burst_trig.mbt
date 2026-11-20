///|
/// `binary_trig_burst_min_precision`, the working precision from which the
/// bit-burst enclosure of `sin` and `cos` replaces the reduction and the series,
/// is per-target policy and lives with the coefficient-kernel thresholds.

///|
/// Test hooks that make the kernel wrong on purpose.
priv struct BurstTrigMutation {
  /// Add `2^mid_bias_bits` units to the midpoint of every stage (0: none). The
  /// guard bits absorb a bias below about `2^40` units in the final rounding.
  mid_bias_bits : Int32
  /// Use fewer terms in the binary-splitting stages than the bound requires.
  split_reduce_terms : Int32
  /// Take `pi` with this many bits fewer than the reduction needs.
  pi_drop_bits : Int32
}

///|
let burst_trig_no_mutation : BurstTrigMutation = {
  mid_bias_bits: 0,
  split_reduce_terms: 0,
  pi_drop_bits: 0,
}

///|
/// Enclosure as a midpoint and a radius in units of `2^-F`: the value lies in
/// `[mid - rad, mid + rad]`.
priv struct BurstBall {
  mid : Coeff
  rad : Coeff
}

///|
/// A cosine and a sine ball.
priv struct BurstRotation {
  cos : BurstBall
  sin : BurstBall
}

///|
/// Fixed-point stage for `y = N / 2^s < 1`: the real and imaginary parts of the
/// series of `exp(i y)`. With `t_0 = 2^f`, `t_i = floor(floor(t_{i-1} N / 2^s) / i)`
/// (no second floor for `i = 1`), the cosine series sums the even terms with
/// signs `+ - + ...` and the sine series the odd ones with signs `+ - + ...`.
/// As for `exp` (`fixed_series_step`), `t_i <= tau_i`, the deficit is below 3, and the first omitted
/// term of each of the two alternating series, which decrease in size, is at
/// most `tau_n < t_n + 3`; so each sum is within `3n + t_n + 3` of its value.
fn burst_trig_fixed_stage(
  numerator : Coeff,
  s : Int32,
  f : Int32,
  mutation : BurstTrigMutation,
) -> BurstRotation? {
  let stop = Coeff::one().shift_left(8)
  let mut term = Coeff::one().shift_left(f)
  let mut cos_positive = term
  let mut cos_negative = Coeff::zero()
  let mut sin_positive = Coeff::zero()
  let mut sin_negative = Coeff::zero()
  let mut index = 0
  while index < 20000 {
    index += 1
    term = fixed_series_step(term, numerator, s, index)
    match index % 4 {
      0 => cos_positive = cos_positive.add(term)
      1 => sin_positive = sin_positive.add(term)
      2 => cos_negative = cos_negative.add(term)
      _ => sin_negative = sin_negative.add(term)
    }
    if term.compare(stop) < 0 {
      guard cos_positive.sub_checked(cos_negative) is Ok(cos_sum) &&
        sin_positive.sub_checked(sin_negative) is Ok(sin_sum) else {
        return None
      }
      let radius = term.add(Coeff::from_uint64((3 * index + 3).to_uint64()))
      let bias = burst_trig_bias(mutation)
      return Some({
        cos: { mid: cos_sum.add(bias), rad: radius, },
        sin: { mid: sin_sum.add(bias), rad: radius, },
      })
    }
  }
  None
}

///|
fn burst_trig_bias(mutation : BurstTrigMutation) -> Coeff {
  if mutation.mid_bias_bits > 0 {
    Coeff::one().shift_left(mutation.mid_bias_bits)
  } else {
    Coeff::zero()
  }
}

///|
fn burst_trig_rotate(value : SplitInt, quarter_turns : Int32) -> SplitInt {
  // Multiplication by i^quarter_turns on one component is a sign change.
  if quarter_turns % 4 >= 2 {
    SplitInt::make(!value.negative, value.magnitude)
  } else {
    value
  }
}

///|
/// Binary splitting state of the series of `exp(i y)`, `y = N / 2^s`: the
/// real-valued state of `SplitState` (`p`, `q`, `q_shift`) with two components
/// `t = (re, im)` and the number of `i` factors `leaves`. The merge of each
/// component is `split_combine_t`, applied to the right component rotated by
/// `i^leaves_left`; this rotation is the only difference from `SplitState`, and
/// the reason the state is not shared with it.
priv struct SplitComplexState {
  leaves : Int32
  q : Coeff
  q_shift : Int32
  re : SplitInt
  im : SplitInt
}

///|
/// Binary splitting of `sum_{k<n} prod_{i<=k} (i N) / (i 2^s)` on `[from, to)`
/// (the series of `exp(i y)` with `i` the imaginary unit and the factor `i`
/// written as the leaf `(0, N)`): `p = N^leaves`, `q = prod i`,
/// `q_shift = s` per index from 1, `t = (re, im)` with `t = q 2^q_shift sum`,
/// merged as `t = t_left q_right 2^q_shift_right + i^leaves_left p_left t_right`.
fn split_trig_state(
  from : Int32,
  to : Int32,
  powers : SplitPowers,
  s : Int32,
) -> SplitComplexState {
  let numerator = powers.numerator
  if to - from == 1 {
    if from == 0 {
      return {
        leaves: 0,
        q: Coeff::one(),
        q_shift: 0,
        re: SplitInt::make(false, Coeff::one()),
        im: SplitInt::make(false, Coeff::zero()),
      }
    }
    return {
      leaves: 1,
      q: Coeff::from_uint64(from.to_uint64()),
      q_shift: s,
      re: SplitInt::make(false, Coeff::zero()),
      im: SplitInt::make(false, numerator),
    }
  }
  if to - from == 2 && from >= 1 {
    // Two leaves directly (the merge below with the leaf states
    // `re = 0, im = N`): the right leaf is rotated by `i`, so `re = -N N` and
    // `im = N (from + 1) 2^s`, `q = from (from + 1)`, `q_shift = 2 s`.
    let next = Coeff::from_uint64((from + 1).to_uint64())
    return {
      leaves: 2,
      q: Coeff::from_uint64(from.to_uint64() * (from + 1).to_uint64()),
      q_shift: 2 * s,
      re: SplitInt::make(true, powers.get(2)),
      im: SplitInt::make(false, numerator.mul(next).shift_left(s)),
    }
  }
  let middle = from + (to - from) / 2
  let left = split_trig_state(from, middle, powers, s)
  let right = split_trig_state(middle, to, powers, s)
  // i^m (a + b i) = (a + b i), (-b + a i), (-a - b i), (b - a i) for m = 0..3.
  let (rotated_re, rotated_im) = match left.leaves % 4 {
    0 => (right.re, right.im)
    1 => (burst_trig_rotate(right.im, 2), right.re)
    2 => (burst_trig_rotate(right.re, 2), burst_trig_rotate(right.im, 2))
    _ => (right.im, burst_trig_rotate(right.re, 2))
  }
  let left_power = powers.get(left.leaves)
  {
    leaves: left.leaves + right.leaves,
    q: left.q.mul(right.q),
    q_shift: left.q_shift + right.q_shift,
    re: split_combine_t(left.re, left_power, rotated_re, right.q, right.q_shift),
    im: split_combine_t(left.im, left_power, rotated_im, right.q, right.q_shift),
  }
}

///|
/// Binary-splitting stage: balls for `cos y` and `sin y` for `y = N / 2^s < 1`.
/// The partial sums over `n` terms are the exact rationals `re / (q 2^(s(n-1)))`
/// and `im / (q 2^(s(n-1)))`; with the choice of `n` of `burst_split_terms` the
/// omitted terms of each alternating series are below 2 units in size, and the
/// floor loses less than 1, so the quotient plus 1 with radius 2 contains each.
fn burst_trig_split_stage(
  numerator : Coeff,
  s : Int32,
  f : Int32,
  mutation : BurstTrigMutation,
) -> BurstRotation? {
  let terms = Int32::max(
    2,
    fixed_split_terms(numerator, s, f) - mutation.split_reduce_terms,
  )
  let state = split_trig_state(0, terms, SplitPowers::new(numerator, terms), s)
  guard !state.re.negative && !state.im.negative else { return None }
  let bias = burst_trig_bias(mutation)
  let ball = fn(value : Coeff) -> BurstBall {
    let scaled = fixed_shift(value, f - state.q_shift)
    {
      mid: scaled.div_rem_checked(state.q).unwrap().0
      .add(Coeff::one())
      .add(bias),
      rad: Coeff::from_uint64(2UL),
    }
  }
  Some({ cos: ball(state.re.magnitude), sin: ball(state.im.magnitude), })
}

///|
/// `a * b` of two balls of the same scale `2^-f`: the midpoint of the product
/// is `floor(a.mid b.mid / 2^f)` and the radius covers the floor and the cross
/// terms, `(a.mid b.rad + b.mid a.rad + a.rad b.rad) / 2^f` rounded up, plus 1.
fn burst_ball_mul(left : BurstBall, right : BurstBall, f : Int32) -> BurstBall {
  let cross = left.mid
    .mul(right.rad)
    .add(right.mid.mul(left.rad))
    .add(left.rad.mul(right.rad))
  {
    mid: left.mid.mul(right.mid).shift_right(f),
    rad: cross.shift_right(f).add(Coeff::from_uint64(2UL)),
  }
}

///|
/// Folds the stage rotation `(c, s)` into the running `(C, S)`:
/// `C' = C c - S s`, `S' = S c + C s`; all four factors are non-negative, the
/// midpoint of the difference must not be negative (else `None`).
fn burst_trig_fold(
  running : BurstRotation,
  stage : BurstRotation,
  f : Int32,
) -> BurstRotation? {
  let cos_cos = burst_ball_mul(running.cos, stage.cos, f)
  let sin_sin = burst_ball_mul(running.sin, stage.sin, f)
  let sin_cos = burst_ball_mul(running.sin, stage.cos, f)
  let cos_sin = burst_ball_mul(running.cos, stage.sin, f)
  guard cos_cos.mid.sub_checked(sin_sin.mid) is Ok(cos_mid) else { return None }
  Some({
    cos: { mid: cos_mid, rad: cos_cos.rad.add(sin_sin.rad), },
    sin: {
      mid: sin_cos.mid.add(cos_sin.mid),
      rad: sin_cos.rad.add(cos_sin.rad),
    },
  })
}

///|
/// Enclosure of `sin(value)` (`cosine = false`) or `cos(value)` for a finite
/// nonzero `value` with `2^-64 <= |value| < 2^4096` by reduction with `pi / 2`
/// and bit-burst, `None` when a precondition fails (the caller then runs the
/// reduction and the series).
///
/// With `x = |value|`, `G = F0 + max(1, top) + 2` and `F0 = w + 112`: `n` is the
/// nearest integer to `x / H`, `H = floor(2^G pi/2) / 2^G`
/// (`0 <= pi/2 - H < 2^(1-G)`), and `R = x - n H`, `|R| <= H / 2`, are computed
/// exactly in integers (one Euclidean division), so the true reduced argument
/// `r = x - n pi/2` satisfies `|r - R| <= n 2^(1-G) <= 2^(-F0-1)`. With
/// `F = w + 48 + lz` (`2^-lz <= |R|`) and `R_t = floor(2^F |R|) / 2^F`, we get
/// `|r - sign(R) R_t| <= 1.5 * 2^-F`, and sine and cosine are 1-Lipschitz, so the
/// sine and cosine of `r` are within 2 units of those of `sign(R) R_t`. The
/// quadrant `n mod 4` and the signs of `x` and `R` map them to the result.
/// `R_t` is cut into chunks, each enclosed by a stage as balls, and the balls are
/// folded by rotation.
fn binary_trig_bounds_burst(
  value : BinFloat,
  cosine : Bool,
  work_precision : Int32,
  mutation~ : BurstTrigMutation = burst_trig_no_mutation,
  first_chunk~ : Int32 = binary_exp_burst_first_chunk,
  chunk_factor~ : Int32 = binary_exp_burst_chunk_factor,
  split_min_terms~ : Int32 = binary_exp_burst_split_min_terms,
) -> (BinFloat, BinFloat)? {
  guard value.classify() == FpClass::Finite && !value.is_zero() else {
    return None
  }
  let top = binary_top_bound(value)
  guard top <= 4096L && top >= -64L else { return None }
  let top_bits = top.to_int()
  let f_max = work_precision + binary_exp_burst_guard_bits + 64
  let n_bits = Int32::max(1, top_bits)
  let g = f_max + n_bits + 2
  guard binary_pi_bounds(
      Int32::max(64, (g + 3 + 63) / 64 * 64 - mutation.pi_drop_bits),
    )
    is Some((pi_low, _)) else {
    return None
  }
  let half_pi = fixed_scaled_floor(pi_low, g - 1)
  guard fixed_scaled_exact(value.abs(), g) is Some(magnitude) else {
    return None
  }
  let (quotient, remainder) = magnitude.div_rem_checked(half_pi).unwrap()
  // Nearest integer: the remainder above half of H rounds up.
  let round_up = remainder.shift_left(1).compare(half_pi) > 0
  let (n, reduced, reduced_negative) = if round_up {
    (quotient.add(Coeff::one()), half_pi.sub_checked(remainder).unwrap(), true)
  } else {
    (quotient, remainder, false)
  }
  guard reduced.bit_length() >= 1 else { return None }
  let reduced_top = reduced.bit_length() - g
  let lz = Int32::max(0, 2 - reduced_top)
  guard lz <= 64 else { return None }
  let f = work_precision + binary_exp_burst_guard_bits + lz
  let fraction = reduced.shift_right(g - f)
  guard !fraction.is_zero() else { return None }
  // Chunks of R_t.
  let mut running : BurstRotation = {
    cos: { mid: Coeff::one().shift_left(f), rad: Coeff::zero(), },
    sin: { mid: Coeff::zero(), rad: Coeff::zero(), },
  }
  // The first stage is folded into the identity rotation: it is the stage.
  let mut identity = true
  let chunks_ok = fixed_burst_chunks(fraction, f, first_chunk, chunk_factor, fn(
    chunk,
    boundary,
  ) {
    let terms = fixed_split_terms(chunk, boundary, f)
    let stage = if terms >= split_min_terms {
      burst_trig_split_stage(chunk, boundary, f, mutation)
    } else {
      burst_trig_fixed_stage(chunk, boundary, f, mutation)
    }
    guard stage is Some(stage_rotation) else { return false }
    if identity {
      running = stage_rotation
      identity = false
    } else {
      match burst_trig_fold(running, stage_rotation, f) {
        Some(folded) => running = folded
        None => return false
      }
    }
    true
  })
  guard chunks_ok else { return None }
  // Map the sine and cosine of the reduced argument to the result.
  let quarter = (if n.test_bit(0) { 1 } else { 0 }) +
    (if n.test_bit(1) { 2 } else { 0 })
  let (uses_sine, negative_quadrant) = if !cosine {
    match quarter {
      0 => (true, false)
      1 => (false, false)
      2 => (true, true)
      _ => (false, true)
    }
  } else {
    match quarter {
      0 => (false, false)
      1 => (true, true)
      2 => (false, true)
      _ => (true, false)
    }
  }
  let mut negative = negative_quadrant
  if !cosine && value.is_negative() {
    negative = !negative
  }
  if uses_sine && reduced_negative {
    negative = !negative
  }
  let ball = if uses_sine { running.sin } else { running.cos }
  // The angle error adds 2 units.
  let radius = ball.rad.add(Coeff::from_uint64(2UL))
  guard ball.mid.sub_checked(radius) is Ok(low) && !low.is_zero() else {
    return None
  }
  let high = ball.mid.add(radius)
  guard high.sub_checked(low) is Ok(width) &&
    width.bit_length() <= f - lz - work_precision - 6 else {
    return None
  }
  Some(fixed_enclosure(low, high, -f, work_precision, negative~))
}
