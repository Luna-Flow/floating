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
let binary_exp_burst_first_chunk : Int32 = 16 // the setting at large working precision; see `binary_exp_first_chunk_for`

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
/// Fixed-point stage: with `y = N / 2^s < 1`, the pair `(lo, hi)` in units of
/// `2^-f` encloses `exp(y)`. `t_0 = 2^f`, `t_i = floor(floor(t_{i-1} N / 2^s) / i)`
/// (no second floor for `i = 1`); `t_i <= tau_i = 2^f y^i / i!`, the deficit
/// `tau_i - t_i` is below 3, the terms after the last one `t_n < 2^8` sum to
/// less than `tau_n < t_n + 3`; so `sum <= exp(y) 2^f <= sum + t_n + 3n + 3`.
fn burst_fixed_stage(
  numerator : Coeff,
  s : Int32,
  f : Int32,
  mutation : BurstMutation,
) -> (Coeff, Coeff)? {
  guard fixed_exp_series(numerator, s, f, 20000) is Some((sum, term, index)) else {
    return None
  }
  let slack = term.add(Coeff::from_uint64((3 * index + 3).to_uint64()))
  Some(
    (
      sum.add(Coeff::from_uint64(mutation.lower_bias.to_uint64())),
      sum.add(slack),
    ),
  )
}

///|
/// Binary-splitting stage: `(lo, hi)` in units of `2^-f` enclosing `exp(N/2^s)`
/// for `N / 2^s < 1`. The partial sum over `n` terms is the exact rational
/// `t / (q 2^(s n))`, so `lo = floor(2^f t / (q 2^(s n)))` is below it by less
/// than 1 unit, and the tail is below 2 units by the choice of `n`.
fn burst_split_stage(
  numerator : Coeff,
  s : Int32,
  f : Int32,
  mutation : BurstMutation,
) -> (Coeff, Coeff)? {
  let terms = Int32::max(
    2,
    fixed_split_terms(numerator, s, f) - mutation.split_reduce_terms,
  )
  let state = split_exp_state(0, terms, SplitPowers::new(numerator, terms), s)
  let scaled = fixed_shift(state.t, f - state.q_shift)
  let lo = scaled.div_rem_checked(state.q).unwrap().0
  Some(
    (
      lo.add(Coeff::from_uint64(mutation.lower_bias.to_uint64())),
      lo.add(Coeff::from_uint64(3UL)),
    ),
  )
}

///|
/// Folds a stage into the running pair `(L, U)` of units of `2^-f` with one full
/// product: `(floor(L l / 2^f), floor(U u / 2^f) + 1)` where the stage is
/// `[l, u]`. With `w = U - L` and `r = u - l` (both short), `U u = L l + L r + w u`
/// exactly, so the upper end is formed from the product `P = L l` of the lower
/// end plus two products by short numbers, instead of a second full product.
/// The integers are those of the two separate products; no error term arises.
fn burst_exp_fold(
  lower : Coeff,
  spread : Coeff,
  stage_low : Coeff,
  stage_spread : Coeff,
  stage_high : Coeff,
  f : Int32,
) -> (Coeff, Coeff) {
  let product = lower.mul(stage_low)
  let total = product.add(lower.mul(stage_spread)).add(spread.mul(stage_high))
  (product.shift_right(f), total.shift_right(f).add(Coeff::one()))
}

///|
/// Enclosure of `exp(value)` for finite `value` with `2^-64 <= |value| < 2^30`
/// by argument reduction with `ln 2` and bit-burst, `None` when a
/// precondition fails (the caller then runs the series).
///
/// The reduction `x = n ln 2 + R_t + delta` and the closing units are those of
/// `fixed_exp_reduce` and `fixed_exp_finish` (toolkit); `F = w + g` with `g`
/// `binary_exp_burst_guard_bits`. `R_t` is split into chunks
/// `y_j = N_j / 2^(b_j)` (`fixed_burst_chunks`), each enclosed by a stage and
/// folded into the running product by monotone integer operations.
fn binary_exp_bounds_burst(
  value : BinFloat,
  work_precision : Int32,
  mutation~ : BurstMutation = burst_no_mutation,
  first_chunk? : Int32,
  chunk_factor? : Int32,
  split_min_terms? : Int32,
) -> (BinFloat, BinFloat)? {
  let first_chunk = first_chunk.unwrap_or(
    binary_exp_first_chunk_for(work_precision),
  )
  let chunk_factor = chunk_factor.unwrap_or(
    binary_exp_chunk_factor_for(work_precision),
  )
  let split_min_terms = split_min_terms.unwrap_or(
    binary_exp_split_min_terms_for(work_precision),
  )
  let f = work_precision + binary_exp_burst_guard_bits
  guard fixed_exp_reduce(value, f, ln2_drop_bits=mutation.ln2_drop_bits)
    is Some(reduction) else {
    return None
  }
  let reduced = reduction.reduced
  let one_unit = Coeff::one().shift_left(f)
  // Chunks of the reduced argument.
  let mut lower = one_unit
  let mut upper = one_unit
  let mut first = true
  let chunks_ok = fixed_burst_chunks(reduced, f, first_chunk, chunk_factor, fn(
    chunk,
    boundary,
  ) {
    let terms = fixed_split_terms(chunk, boundary, f)
    let stage = if terms >= split_min_terms {
      burst_split_stage(chunk, boundary, f, mutation)
    } else {
      burst_fixed_stage(chunk, boundary, f, mutation)
    }
    guard stage is Some((stage_low, stage_high)) else { return false }
    if first {
      // The running pair is `(2^f, 2^f)`: the products are the stage itself.
      lower = stage_low
      upper = stage_high.add(Coeff::one())
      first = false
      return true
    }
    guard upper.sub_checked(lower) is Ok(spread) &&
      stage_high.sub_checked(stage_low) is Ok(stage_spread) else {
      return false
    }
    let (new_lower, new_upper) = burst_exp_fold(
      lower, spread, stage_low, stage_spread, stage_high, f,
    )
    lower = new_lower
    upper = new_upper
    true
  })
  guard chunks_ok else { return None }
  // exp(delta) with |delta| <= 1.5 * 2^-F and exp(R_t) < 3.
  fixed_exp_finish(
    lower,
    upper,
    reduction,
    f,
    work_precision,
    drop_delta=mutation.drop_delta,
  )
}
