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
  /// Swap the two ends of the sine ball in the square root of the cosine.
  cos_swap_ends : Bool
  /// Omit the `+ 1` of the upper end of the cosine ball.
  cos_no_plus_one : Bool
}

///|
let burst_trig_no_mutation : BurstTrigMutation = {
  mid_bias_bits: 0,
  split_reduce_terms: 0,
  pi_drop_bits: 0,
  cos_swap_ends: false,
  cos_no_plus_one: false,
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
/// Real binary-splitting state of `S(y^2) = sum_{k < n} (-y^2)^k / (2k+1)!` on the
/// index range `[from, to)`, `y = N / 2^s`: `q = prod (2k)(2k+1)`,
/// `q_shift = 2 s` per index from 1, `leaves` the number of indices from 1 and
/// `t = q 2^q_shift (partial sum)` a signed integer. Merged as
/// `t = t_left q_right 2^q_shift_right + (-1)^leaves_left (N^2)^leaves_left t_right`.
priv struct SplitSinState {
  leaves : Int32
  q : Coeff
  q_shift : Int32
  t : SplitInt
}

///|
fn split_sin_state(
  from : Int32,
  to : Int32,
  powers : SplitPowers,
  s : Int32,
) -> SplitSinState {
  if to - from == 1 {
    if from == 0 {
      return {
        leaves: 0,
        q: Coeff::one(),
        q_shift: 0,
        t: SplitInt::make(false, Coeff::one()),
      }
    }
    let k = from.to_uint64()
    return {
      leaves: 1,
      q: Coeff::from_uint64(2UL * k * (2UL * k + 1UL)),
      q_shift: 2 * s,
      t: SplitInt::make(true, powers.numerator),
    }
  }
  let middle = from + (to - from) / 2
  let left = split_sin_state(from, middle, powers, s)
  let right = split_sin_state(middle, to, powers, s)
  let signed_right = if left.leaves % 2 == 1 {
    SplitInt::make(!right.t.negative, right.t.magnitude)
  } else {
    right.t
  }
  {
    leaves: left.leaves + right.leaves,
    q: left.q.mul(right.q),
    q_shift: left.q_shift + right.q_shift,
    t: split_combine_t(
      left.t,
      powers.get(left.leaves),
      signed_right,
      right.q,
      right.q_shift,
    ),
  }
}

///|
/// Enclosure `[low, high]` in units of `2^-f` of `c = sqrt(2^(2f) - s^2)` for
/// every `s` in `[s_low, s_high]`, `0 <= s_low <= s_high <= 2^f`: `c` decreases
/// in `s`, so `low = floor(sqrt(2^(2f) - s_high^2))` and
/// `high = floor(sqrt(2^(2f) - s_low^2)) + 1`, both exact integer operations;
/// `s_low = 0` gives `2^f` (the cosine is at most 1). `None` when
/// `s_high > 2^f`.
fn burst_cos_from_sine_bounds(
  s_low : Coeff,
  s_high : Coeff,
  f : Int32,
  mutation : BurstTrigMutation,
) -> (Coeff, Coeff)? {
  let one_unit = Coeff::one().shift_left(f)
  guard s_high.compare(one_unit) <= 0 else { return None }
  let square_one = Coeff::one().shift_left(2 * f)
  let (low_arg, high_arg) = if mutation.cos_swap_ends {
    (s_low, s_high)
  } else {
    (s_high, s_low)
  }
  let low = bin_coeff_sqrt_rem_kernel(
      square_one.sub_checked(low_arg.square()).unwrap(),
    ).0
  let root = bin_coeff_sqrt_rem_kernel(
      square_one.sub_checked(high_arg.square()).unwrap(),
    ).0
  let high = if s_low.is_zero() && !mutation.cos_swap_ends {
    one_unit
  } else if mutation.cos_no_plus_one {
    root
  } else {
    root.add(Coeff::one())
  }
  Some((low, high))
}

///|
/// Binary-splitting stage by the real series of the sine: balls for `cos y` and
/// `sin y` for `y = N / 2^s < 1` and `y <= pi / 2`. `sin y = y S(y^2)`, the
/// partial sum over `n'` terms is the exact rational `T / (Q 2^q_shift)`,
/// `n' = floor(n / 2)` with `n` the term count of the exponential series
/// (`fixed_split_terms`), so that the first omitted term of the sine series,
/// of exponent `2 n' + 1 >= n`, is below one unit (the bound of `n` holds for
/// every larger count because `bits(N) <= s`); the series alternates and its
/// terms decrease, so the tail is below 1 unit, the floor loses less than 1,
/// and the quotient plus 1 with radius 2 contains `sin y`. The cosine ball is
/// that of `sqrt(2^(2f) - s^2)` over the sine ball.
fn burst_trig_split_stage_real(
  numerator : Coeff,
  s : Int32,
  f : Int32,
  mutation : BurstTrigMutation,
) -> BurstRotation? {
  let terms = Int32::max(
    2,
    fixed_split_terms(numerator, s, f) - mutation.split_reduce_terms,
  )
  let leaves = Int32::max(1, terms / 2)
  let powers = SplitPowers::new(numerator.square(), leaves)
  let state = split_sin_state(0, leaves, powers, s)
  guard !state.t.negative else { return None }
  let scaled = fixed_shift(
    numerator.mul(state.t.magnitude),
    f - s - state.q_shift,
  )
  let bias = burst_trig_bias(mutation)
  let radius = Coeff::from_uint64(2UL)
  let sine_mid = scaled.div_rem_checked(state.q).unwrap().0
    .add(Coeff::one())
    .add(bias)
  let one_unit = Coeff::one().shift_left(f)
  let s_high = {
    let value = sine_mid.add(radius)
    if value.compare(one_unit) > 0 {
      one_unit
    } else {
      value
    }
  }
  let s_low = match sine_mid.sub_checked(radius) {
    Ok(value) => value
    Err(_) => Coeff::zero()
  }
  guard burst_cos_from_sine_bounds(s_low, s_high, f, mutation)
    is Some((cos_low, cos_high)) else {
    return None
  }
  let cos_mid = cos_low.add(cos_high).shift_right(1)
  guard cos_high.sub_checked(cos_mid) is Ok(cos_radius) else { return None }
  Some({
    cos: { mid: cos_mid, rad: cos_radius, },
    sin: { mid: sine_mid, rad: radius, },
  })
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
/// The one component of `burst_trig_fold` that the caller reads: the sine
/// `S' = S c + C s` (`sine`) or the cosine `C' = C c - S s`, with the same
/// integers as in `burst_trig_fold`; the other component of the result is zero
/// and must not be read. Two ball products instead of four.
fn burst_trig_fold_one(
  running : BurstRotation,
  stage : BurstRotation,
  f : Int32,
  sine : Bool,
) -> BurstRotation? {
  let zero = { mid: Coeff::zero(), rad: Coeff::zero(), }
  if sine {
    let sin_cos = burst_ball_mul(running.sin, stage.cos, f)
    let cos_sin = burst_ball_mul(running.cos, stage.sin, f)
    Some({
      cos: zero,
      sin: {
        mid: sin_cos.mid.add(cos_sin.mid),
        rad: sin_cos.rad.add(cos_sin.rad),
      },
    })
  } else {
    let cos_cos = burst_ball_mul(running.cos, stage.cos, f)
    let sin_sin = burst_ball_mul(running.sin, stage.sin, f)
    guard cos_cos.mid.sub_checked(sin_sin.mid) is Ok(cos_mid) else {
      return None
    }
    Some({
      cos: { mid: cos_mid, rad: cos_cos.rad.add(sin_sin.rad), },
      sin: zero,
    })
  }
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
  value : Binary,
  cosine : Bool,
  work_precision : Int32,
  mutation~ : BurstTrigMutation = burst_trig_no_mutation,
  first_chunk? : Int32,
  chunk_factor? : Int32,
  split_min_terms? : Int32,
) -> (Binary, Binary)? {
  let first_chunk = first_chunk.unwrap_or(
    binary_burst_first_chunk(work_precision),
  )
  let chunk_factor = chunk_factor.unwrap_or(
    binary_burst_chunk_factor(work_precision),
  )
  let split_min_terms = split_min_terms.unwrap_or(
    binary_burst_split_min_terms(work_precision),
  )
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
      burst_trig_split_stage_real(chunk, boundary, f, mutation)
    } else {
      burst_trig_fixed_stage(chunk, boundary, f, mutation)
    }
    guard stage is Some(stage_rotation) else { return false }
    if identity {
      running = stage_rotation
      identity = false
    } else {
      // The last fold is needed in the one component the result reads.
      let folded = if boundary == f {
        burst_trig_fold_one(running, stage_rotation, f, uses_sine)
      } else {
        burst_trig_fold(running, stage_rotation, f)
      }
      match folded {
        Some(value) => running = value
        None => return false
      }
    }
    true
  })
  guard chunks_ok else { return None }
  let mut negative = negative_quadrant
  if !cosine && value.is_sign_minus() {
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
