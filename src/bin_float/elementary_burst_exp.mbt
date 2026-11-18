///|
/// `binary_exp_burst_min_precision`, the working precision from which the
/// bit-burst enclosure of `exp` replaces the series of `elementary_fixed_exp.mbt`,
/// is per-target policy and lives with the coefficient-kernel thresholds.

///|
/// Guard bits of the bit-burst enclosure below the working precision.
let binary_exp_burst_guard_bits : Int32 = 48

///|
/// Position (bits after the binary point) at which the first chunk of the
/// reduced argument ends, and the growth factor of the chunk boundaries.
let binary_exp_burst_first_chunk : Int32 = 16

///|
let binary_exp_burst_chunk_factor : Int32 = 4

///|
/// A chunk with at least this many series terms is evaluated by binary
/// splitting, a chunk with fewer by the fixed-point series.
let binary_exp_burst_split_min_terms : Int32 = 40

///|
/// Test hooks that make the kernel wrong on purpose, so a test can show that
/// the proof obligations are checked and not just assumed.
priv struct BurstMutation {
  /// Add this many units to the lower end of every stage (an arithmetic bias:
  /// the enclosure then misses the value from below).
  lower_bias : Int32
  /// Use fewer terms in the binary-splitting stages than the bound requires.
  split_reduce_terms : Int32
  /// Drop the units for the residual `delta` at the end.
  drop_delta : Bool
  /// Take `ln 2` with this many bits fewer than the reduction needs.
  ln2_drop_bits : Int32
}

///|
let burst_no_mutation : BurstMutation = {
  lower_bias: 0,
  split_reduce_terms: 0,
  drop_delta: false,
  ln2_drop_bits: 0,
}

///|
/// `floor(value * 2^shift)` of a non-negative finite value, `None` when the
/// scaling is not exact (`value` has bits below `2^-shift`).
fn burst_scaled_exact(value : BinFloat, shift : Int32) -> BinCoeff? {
  if value.is_zero() {
    return Some(BinCoeff::zero())
  }
  let total = value.exponent2() + shift
  if total >= 0 {
    Some(value.coefficient().shift_left(total))
  } else {
    None
  }
}

///|
/// `floor(value * 2^shift)` of a non-negative finite value.
fn burst_scaled_floor(value : BinFloat, shift : Int32) -> BinCoeff {
  if value.is_zero() {
    return BinCoeff::zero()
  }
  let total = value.exponent2() + shift
  if total >= 0 {
    value.coefficient().shift_left(total)
  } else {
    value.coefficient().shift_right(-total)
  }
}

///|
/// Fixed-point stage: with `y = N / 2^s < 1`, the pair `(lo, hi)` in units of
/// `2^-f` encloses `exp(y)`. `t_0 = 2^f`, `t_i = floor(floor(t_{i-1} N / 2^s) / i)`
/// (no second floor for `i = 1`); `t_i <= tau_i = 2^f y^i / i!`, the deficit
/// `tau_i - t_i` is below 3, the terms after the last one `t_n < 2^8` sum to
/// less than `tau_n < t_n + 3`; so `sum <= exp(y) 2^f <= sum + t_n + 3n + 3`.
fn burst_fixed_stage(
  numerator : BinCoeff,
  s : Int32,
  f : Int32,
  mutation : BurstMutation,
) -> (BinCoeff, BinCoeff)? {
  let stop = BinCoeff::one().shift_left(8)
  let mut term = BinCoeff::one().shift_left(f)
  let mut sum = term
  let mut index = 0
  while index < 20000 {
    index += 1
    term = term.mul(numerator).shift_right(s)
    if index > 1 {
      term = term
        .div_rem_checked(BinCoeff::from_uint64(index.to_uint64()))
        .unwrap().0
    }
    sum = sum.add(term)
    if term.compare(stop) < 0 {
      let slack = term.add(BinCoeff::from_uint64((3 * index + 3).to_uint64()))
      return Some(
        (
          sum.add(BinCoeff::from_uint64(mutation.lower_bias.to_uint64())),
          sum.add(slack),
        ),
      )
    }
  }
  None
}

///|
/// Smallest number of terms `n` for which the omitted terms of
/// `sum_k N^k / (k! 2^(s k))` are provably below `2^-f` each in size, so that
/// the tail is below 2 units: `2^f N^n < n! 2^(s n)` follows from
/// `f + m n <= L(n) + s n` with `m = bits(N)` (so `N < 2^m`) and
/// `L(n) = sum_{i <= n} (bits(i) - 1) <= log2 n!`.
fn burst_split_terms(numerator : BinCoeff, s : Int32, f : Int32) -> Int32 {
  let m = numerator.bit_length().to_int64()
  let target = f.to_int64()
  let step = s.to_int64()
  let mut log_factorial = 0L
  let mut n = 1
  // Index 0 and 1 contribute nothing to L.
  while n < 1000000 {
    if target + m * n.to_int64() <= log_factorial + step * n.to_int64() {
      return n
    }
    n += 1
    log_factorial += (bit_length_int(n) - 1).to_int64()
  }
  n
}

///|
fn bit_length_int(value : Int32) -> Int32 {
  let mut bits = 0
  let mut rest = value
  while rest > 0 {
    bits += 1
    rest = rest / 2
  }
  bits
}

///|
priv struct BurstSplit {
  p : BinCoeff
  q : BinCoeff
  t : BinCoeff
}

///|
/// Binary splitting of `sum_{k<n} prod_{i<=k} N / (i 2^s)` on `[from, to)`:
/// `p = N^len`, `q = prod i`, `t = q 2^(s len) sum`, merged as
/// `t = t_left q_right 2^(s len_right) + p_left t_right`.
fn burst_split_state(
  from : Int32,
  to : Int32,
  numerator : BinCoeff,
  s : Int32,
) -> BurstSplit {
  if to - from == 1 {
    if from == 0 {
      return { p: BinCoeff::one(), q: BinCoeff::one(), t: BinCoeff::one(), }
    }
    return {
      p: numerator,
      q: BinCoeff::from_uint64(from.to_uint64()),
      t: numerator,
    }
  }
  let middle = from + (to - from) / 2
  let left = burst_split_state(from, middle, numerator, s)
  let right = burst_split_state(middle, to, numerator, s)
  {
    p: left.p.mul(right.p),
    q: left.q.mul(right.q),
    t: left.t
    .mul(right.q)
    .shift_left(s * (to - middle))
    .add(left.p.mul(right.t)),
  }
}

///|
/// Binary-splitting stage: `(lo, hi)` in units of `2^-f` enclosing `exp(N/2^s)`
/// for `N / 2^s < 1`. The partial sum over `n` terms is the exact rational
/// `t / (q 2^(s n))`, so `lo = floor(2^f t / (q 2^(s n)))` is below it by less
/// than 1 unit, and the tail is below 2 units by the choice of `n`.
fn burst_split_stage(
  numerator : BinCoeff,
  s : Int32,
  f : Int32,
  mutation : BurstMutation,
) -> (BinCoeff, BinCoeff)? {
  let terms = Int32::max(
    2,
    burst_split_terms(numerator, s, f) - mutation.split_reduce_terms,
  )
  let state = burst_split_state(0, terms, numerator, s)
  let shift = s * (terms - 1) - f
  let scaled = if shift >= 0 {
    state.t.shift_right(shift)
  } else {
    state.t.shift_left(-shift)
  }
  let lo = scaled.div_rem_checked(state.q).unwrap().0
  Some(
    (
      lo.add(BinCoeff::from_uint64(mutation.lower_bias.to_uint64())),
      lo.add(BinCoeff::from_uint64(3UL)),
    ),
  )
}

///|
/// Enclosure of `exp(value)` for finite `value` with `2^-64 <= |value| < 2^30`
/// by argument reduction with `ln 2` and bit-burst, `None` when a
/// precondition fails (the caller then runs the series).
///
/// With `F = w + g` and `G = F + bits(n) + 2`: `n = floor(x / ln 2)`, `R = x - n L`
/// with `L = floor(2^G ln 2) / 2^G` (so `0 <= ln 2 - L < 2^(1-G)`), `0 <= R < ln 2`
/// by Euclidean division, `R_t = floor(2^F R) / 2^F` and
/// `delta = x - n ln 2 - R_t` with `|delta| <= 1.5 * 2^-F`; hence
/// `exp(x) = 2^n exp(R_t) exp(delta)` and `1 - 2^-F <= exp(delta) <= 1 + 2^(1-F)`,
/// which costs at most 3 units below and 6 above because `exp(R_t) < 3`.
/// `R_t` is split into chunks `y_j = N_j / 2^(b_(j+1))`, each enclosed by a
/// stage and folded into the running product by monotone integer operations.
fn binary_exp_bounds_burst(
  value : BinFloat,
  work_precision : Int32,
  mutation~ : BurstMutation = burst_no_mutation,
  first_chunk~ : Int32 = binary_exp_burst_first_chunk,
  chunk_factor~ : Int32 = binary_exp_burst_chunk_factor,
  split_min_terms~ : Int32 = binary_exp_burst_split_min_terms,
) -> (BinFloat, BinFloat)? {
  guard value.classify() == FpClass::Finite && !value.is_zero() else {
    return None
  }
  let top = binary_top_bound(value)
  guard top <= 30L && top >= -64L else { return None }
  let top_bits = top.to_int()
  let f = work_precision + binary_exp_burst_guard_bits
  let n_bits = Int32::max(1, top_bits + 2)
  let g = f + n_bits + 2
  guard binary_ln2_bounds(
      Int32::max(64, (g + 2 + 63) / 64 * 64 - mutation.ln2_drop_bits),
    )
    is Some((ln2_low, _)) else {
    return None
  }
  let ln2_int = burst_scaled_floor(ln2_low, g)
  guard burst_scaled_exact(value.abs(), g) is Some(magnitude) else {
    return None
  }
  // Euclidean division: x = n L + R with 0 <= R < L.
  let (quotient, remainder) = magnitude.div_rem_checked(ln2_int).unwrap()
  let negative = value.is_negative()
  guard quotient.to_uint64() is Some(quotient_value) &&
    quotient_value < 536870912UL else {
    return None
  }
  let (n_magnitude, n_negative, residual) = if !negative {
    (quotient_value, false, remainder)
  } else if remainder.is_zero() {
    (quotient_value, true, remainder)
  } else {
    (quotient_value + 1UL, true, ln2_int.sub_checked(remainder).unwrap())
  }
  guard bit_length_int(n_magnitude.to_int()) <= n_bits else { return None }
  let reduced = residual.shift_right(g - f)
  let one_unit = BinCoeff::one().shift_left(f)
  // Chunks of the reduced argument.
  let mut lower = one_unit
  let mut upper = one_unit
  let mut previous_bits = 0
  let mut previous_prefix = BinCoeff::zero()
  let mut boundary = Int32::min(first_chunk, f)
  while previous_bits < f {
    let prefix = reduced.shift_right(f - boundary)
    let chunk = prefix
      .sub_checked(previous_prefix.shift_left(boundary - previous_bits))
      .unwrap()
    if !chunk.is_zero() {
      let terms = burst_split_terms(chunk, boundary, f)
      let stage = if terms >= split_min_terms {
        burst_split_stage(chunk, boundary, f, mutation)
      } else {
        burst_fixed_stage(chunk, boundary, f, mutation)
      }
      guard stage is Some((stage_low, stage_high)) else { return None }
      lower = lower.mul(stage_low).shift_right(f)
      upper = upper.mul(stage_high).shift_right(f).add(BinCoeff::one())
    }
    previous_bits = boundary
    previous_prefix = prefix
    boundary = Int32::min(f, boundary * chunk_factor)
  }
  // exp(delta) with |delta| <= 1.5 * 2^-F and exp(R_t) < 3.
  let (lower_final, upper_final) = if mutation.drop_delta {
    (lower, upper)
  } else {
    (
      lower.sub_checked(BinCoeff::from_uint64(3UL)).unwrap(),
      upper.add(BinCoeff::from_uint64(6UL)),
    )
  }
  // Width check: at most 2^-(w + 6) of the value, the width of the series
  // enclosure; a wider result is left to the series.
  guard upper_final.sub_checked(lower_final) is Ok(width) &&
    width.bit_length() <= f - work_precision - 6 else {
    return None
  }
  let exponent = if n_negative {
    -n_magnitude.to_int() - f
  } else {
    n_magnitude.to_int() - f
  }
  Some(
    (
      BinFloat::make(
        lower_final,
        exponent,
        work_precision,
        mode=RoundingMode::TowardNegative,
      ),
      BinFloat::make(
        upper_final,
        exponent,
        work_precision,
        mode=RoundingMode::TowardPositive,
      ),
    ),
  )
}
