///|
/// Fixed-point toolkit shared by the enclosure kernels of `exp`, `ln`, `sin`,
/// `cos` and the constants `ln 2`, `ln 10`, `pi` (issue #368). Everything here
/// is private to `bin_float`. The error bound of each piece is stated once, at
/// the piece; the kernels refer to it and add only what is specific to their
/// series. `doc/manual/design/bin_float.md` (section "Shared fixed-point
/// toolkit") describes the pieces and lists what was kept apart on purpose.
///
/// A fixed-point value is a nonnegative `BinCoeff` `N` standing for
/// `N / 2^F`, with `F` the number of fractional bits of the kernel. A pair
/// `(low, high)` of such integers encloses a real `y` when
/// `low <= 2^F y <= high`.
///
/// Piece 1: directed conversion between `BinFloat` and fixed-point integers.
///
/// `floor(value * 2^shift)` of a non-negative finite value, `None` when the
/// scaling is not exact (`value` has bits below `2^-shift`).
fn fixed_scaled_exact(value : BinFloat, shift : Int32) -> BinCoeff? {
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
/// `floor(value * 2^shift)` of a non-negative finite value: rounds toward
/// negative infinity, so `fixed_scaled_floor(v, F) / 2^F <= v` and the loss is
/// below one unit.
fn fixed_scaled_floor(value : BinFloat, shift : Int32) -> BinCoeff {
  if value.is_zero() {
    return BinCoeff::zero()
  }
  fixed_shift(value.coefficient(), value.exponent2() + shift)
}

///|
/// `floor(value * 2^shift)` of an integer, for a shift of either sign.
fn fixed_shift(value : BinCoeff, shift : Int32) -> BinCoeff {
  if shift >= 0 {
    value.shift_left(shift)
  } else {
    value.shift_right(-shift)
  }
}

///|
/// The enclosure `[low, high] * 2^exponent` of a positive real, or of a
/// negative one when `negative` (then `low` and `high` bound the magnitude, and
/// the ends swap), as a pair of floats of `precision` bits rounded outward: the
/// lower end toward negative infinity, the upper end toward positive infinity.
fn fixed_enclosure(
  low : BinCoeff,
  high : BinCoeff,
  exponent : Int32,
  precision : Int32,
  negative~ : Bool = false,
) -> (BinFloat, BinFloat) {
  (
    BinFloat::make(
      if negative {
        high
      } else {
        low
      },
      exponent,
      precision,
      negative~,
      mode=RoundingMode::TowardNegative,
    ),
    BinFloat::make(
      if negative {
        low
      } else {
        high
      },
      exponent,
      precision,
      negative~,
      mode=RoundingMode::TowardPositive,
    ),
  )
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
/// Piece 2: a bounded cache. Entries are kept in insertion order and the oldest
/// one is dropped when `capacity` is reached. A cached value is a pure function
/// of its key, so a hit returns the very value a recomputation returns and only
/// the time changes.
priv struct BoundedCache[V] {
  items : Array[V]
  capacity : Int32
}

///|
fn[V] BoundedCache::new(capacity : Int32) -> BoundedCache[V] {
  { items: [], capacity, }
}

///|
fn[V] BoundedCache::length(self : BoundedCache[V]) -> Int32 {
  self.items.length()
}

///|
fn[V] BoundedCache::find(self : BoundedCache[V], matches : (V) -> Bool) -> V? {
  for item in self.items {
    if matches(item) {
      return Some(item)
    }
  }
  None
}

///|
fn[V] BoundedCache::insert(self : BoundedCache[V], item : V) -> Unit {
  if self.length() >= self.capacity {
    ignore(self.items.remove(0))
  }
  self.items.push(item)
}

///|
/// Piece 3: the term-by-term fixed-point step of `exp`-type series.
///
/// With `y = N / 2^s` the recurrence `t_0 = 2^F`,
/// `t_i = floor(floor(t_{i-1} N / 2^s) / i)` (no second floor for `i = 1`)
/// gives `t_i <= tau_i = 2^F y^i / i!` and, for `y < 1`, a deficit
/// `tau_i - t_i < 3`: with `d_i = tau_i - t_i`, the first floor loses less than
/// 1 before the division and the second less than 1 after it, so
/// `d_i < d_{i-1} y / i + 1 / i + 1` and `d_i < 2.3` by induction. The kernels
/// of `exp` (fixed and burst) and of the real and imaginary parts of
/// `exp(i y)` (burst `sin`/`cos`) all use this step.
fn fixed_series_step(
  term : BinCoeff,
  numerator : BinCoeff,
  s : Int32,
  index : Int32,
) -> BinCoeff {
  let product = term.mul(numerator).shift_right(s)
  if index > 1 {
    product.div_rem_checked(BinCoeff::from_uint64(index.to_uint64())).unwrap().0
  } else {
    product
  }
}

///|
/// Sum of the series `sum_i t_i` of `fixed_series_step` up to the first term
/// below `2^8`, as `(sum, last_term, index)`, `None` after `max_index` terms.
/// With the bound of `fixed_series_step`, the omitted terms sum to less than
/// the exact term `tau_n < t_n + 3` (they decrease by at least a factor of 2),
/// so `sum <= 2^F exp(y) <= sum + t_n + 3 n + 3`; the caller adds the slack it
/// needs (the constants differ by caller and are stated there).
fn fixed_exp_series(
  numerator : BinCoeff,
  s : Int32,
  f : Int32,
  max_index : Int32,
) -> (BinCoeff, BinCoeff, Int32)? {
  let stop = BinCoeff::one().shift_left(8)
  let mut term = BinCoeff::one().shift_left(f)
  let mut sum = term
  let mut index = 0
  while index < max_index {
    index += 1
    term = fixed_series_step(term, numerator, s, index)
    sum = sum.add(term)
    if term.compare(stop) < 0 {
      return Some((sum, term, index))
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
fn fixed_split_terms(numerator : BinCoeff, s : Int32, f : Int32) -> Int32 {
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
/// Piece 4: binary splitting. A signed integer as sign and magnitude, which is
/// all the splitting recurrences need: `BinCoeff` is unsigned.
priv struct SplitInt {
  negative : Bool
  magnitude : BinCoeff
}

///|
fn SplitInt::make(negative : Bool, magnitude : BinCoeff) -> SplitInt {
  { negative: negative && !magnitude.is_zero(), magnitude, }
}

///|
/// Binary splitting state of a series `sum_n prod_{k<=n} p(k) / q(k)` on the
/// index range `[from, to)`, with `q(k) = q'(k) 2^e(k)`: `p = prod p(k)`,
/// `q = prod q'(k)`, `q_shift = sum e(k)` and `t = q 2^q_shift (partial sum)`.
/// The power of two is kept apart in `q_shift` because multiplying by it is a
/// shift; the constants use `q_shift = 0`, the series of `exp(N / 2^s)` and of
/// `exp(i N / 2^s)` use `q_shift = s` per index from 1. Everything is exact
/// integer arithmetic, so the partial sum is the exact rational
/// `t / (q 2^q_shift)` and a caller derives its error bound from the number of
/// terms alone. `t` is stored as sign and magnitude in flat fields (not as a
/// `SplitInt`) because one allocation fewer per tree node is measurable.
priv struct SplitState {
  p : BinCoeff
  q : BinCoeff
  q_shift : Int32
  t_negative : Bool
  t : BinCoeff
}

///|
/// The merge step of the `t` component of two adjacent ranges,
/// `t = t_left q_right 2^(q_shift_right) + p_left t_right`, on sign and
/// magnitude. It builds no intermediate `SplitInt`: it runs at every node of the
/// splitting tree, mostly on small operands, where an allocation per node is
/// measurable.
fn split_combine_t(
  left_t : SplitInt,
  left_p : BinCoeff,
  right_t : SplitInt,
  right_q : BinCoeff,
  right_q_shift : Int32,
) -> SplitInt {
  let scaled = left_t.magnitude.mul(right_q).shift_left(right_q_shift)
  let added = right_t.magnitude.mul(left_p)
  if left_t.negative == right_t.negative {
    SplitInt::make(left_t.negative, scaled.add(added))
  } else if scaled.compare(added) >= 0 {
    SplitInt::make(left_t.negative, scaled.sub_checked(added).unwrap())
  } else {
    SplitInt::make(right_t.negative, added.sub_checked(scaled).unwrap())
  }
}

///|
fn split_combine(left : SplitState, right : SplitState) -> SplitState {
  let scaled = left.t.mul(right.q).shift_left(right.q_shift)
  let added = right.t.mul(left.p)
  let (negative, t) = if left.t_negative == right.t_negative {
    (left.t_negative, scaled.add(added))
  } else if scaled.compare(added) >= 0 {
    (left.t_negative, scaled.sub_checked(added).unwrap())
  } else {
    (right.t_negative, added.sub_checked(scaled).unwrap())
  }
  {
    p: left.p.mul(right.p),
    q: left.q.mul(right.q),
    q_shift: left.q_shift + right.q_shift,
    t_negative: negative && !t.is_zero(),
    t,
  }
}

///|
/// Splitting state of `sum_{k<n} N^k / (k! 2^(s k))` on `[from, to)`, the
/// series of `exp(N / 2^s)`: `p = N^len`, `q = prod i`, `q_shift = s` per index
/// from 1 and `t = q 2^q_shift sum`.
fn split_exp_state(
  from : Int32,
  to : Int32,
  numerator : BinCoeff,
  s : Int32,
) -> SplitState {
  if to - from == 1 {
    if from == 0 {
      return {
        p: BinCoeff::one(),
        q: BinCoeff::one(),
        q_shift: 0,
        t_negative: false,
        t: BinCoeff::one(),
      }
    }
    return {
      p: numerator,
      q: BinCoeff::from_uint64(from.to_uint64()),
      q_shift: s,
      t_negative: false,
      t: numerator,
    }
  }
  let middle = from + (to - from) / 2
  split_combine(
    split_exp_state(from, middle, numerator, s),
    split_exp_state(middle, to, numerator, s),
  )
}

///|
/// Piece 5: rectangular (Paterson-Stockmeyer) splitting with collected integer
/// coefficients, for a series `sum_{i < N} c_i r^i` with nonnegative integer
/// coefficients `c_i` and `r = a / 2^f < 2^-k`. The coefficient sequence is a
/// parameter: `rect_inverse_factorials` supplies `c_i = N! / i!` for `exp`; the
/// next kernels pass their own (`c_i = D / (2i + 1)` with a common multiple `D`
/// for the odd reciprocals of `ln` and `atan`, `c_i = N! / (2i)!` or
/// `N! / (2i + 1)!` for `sin`/`cos`, whose alternating signs the caller splits
/// into a positive and a negative series in `r^2`, each with nonnegative
/// coefficients, and subtracts). The caller divides by the common denominator.
priv struct RectPlan {
  /// Number of terms summed, `blocks * block`.
  terms : Int32
  block : Int32
  blocks : Int32
}

///|
/// Block size `m` of the rectangular splitting for `needed` terms: the one with
/// the lowest estimated cost, `2 N'` for the small-coefficient products and
/// `3 + f / 256` for each full-size product (`m - 1` powers, `b - 1` Horner
/// steps), where `N' = b m >= needed` is the number of terms actually summed.
fn rect_block_size(needed : Int32, f : Int32) -> Int32 {
  let weight = 3 + f / 256
  let mut best = 1
  let mut best_cost = 2147483647
  for m in 1..<=needed {
    let blocks = (needed + m - 1) / m
    let cost = 2 * blocks * m + (m - 1 + blocks - 1) * weight
    if cost < best_cost {
      best_cost = cost
      best = m
    }
  }
  best
}

///|
fn rect_plan(needed : Int32, f : Int32) -> RectPlan {
  let block = rect_block_size(needed, f)
  let blocks = (needed + block - 1) / block
  { terms: blocks * block, block, blocks, }
}

///|
/// Number of terms `N` (before rounding up to whole blocks) so that
/// `K N + sum_{i <= N} (bits(i) - 1) >= f + 1`, which gives
/// `2 r^N / N! <= 2^-f` for `0 <= r < 2^-K`: the terms of a series with
/// factorial decay (`exp`, `sin`, `cos`). Series with only geometric decay
/// (`ln`, `atan`) need their own count.
fn rect_factorial_terms(k : Int32, f : Int32) -> Int32 {
  let mut n = 1
  let mut log_factorial = 0
  while k * n + log_factorial < f + 1 {
    n += 1
    log_factorial += bit_length_int(n) - 1
  }
  n
}

///|
/// The powers `p_0 = 2^f`, `p_1 = a` and `p_j = floor(p_u p_v / 2^f)` with
/// `u + v = j`, `u = ceil(j / 2)`, for `j <= m`. They satisfy
/// `p_j <= 2^f r^j` and `2^f r^j - p_j < 2` for `a < 2^(f - k)`, `k >= 4`
/// (induction: `e_j < 1 + (e_u + e_v) 2^-k + e_u e_v 2^-f < 2`).
fn rect_powers(a : BinCoeff, f : Int32, m : Int32) -> Array[BinCoeff] {
  let powers : Array[BinCoeff] = [BinCoeff::one().shift_left(f), a]
  for j in 2..<=m {
    let u = (j + 1) / 2
    let v = j / 2
    powers.push(powers[u.to_int()].mul(powers[v.to_int()]).shift_right(f))
  }
  powers
}

///|
/// `acc = sum_{i < N} c_i r^i` evaluated on integers, `N = blocks * block`
/// (`coefficients.length() >= N`): `P_beta = sum_(j < m) c_(beta m + j) p_j`,
/// `Acc_(b-1) = P_(b-1)` and `Acc_beta = P_beta + floor(p_m Acc_(beta+1) / 2^f)`.
/// Then `acc <= 2^f sum c_i r^i`, and the deficit is
/// `eps_beta < 2 sum_j c_(beta m + j) + 2 Acc_(beta+1) / 2^f + 1 +
/// r^m eps_(beta+1)` in the units of the common denominator `D` of the
/// coefficients: the powers are short by less than 2 each, the product by
/// `p_m` is short by less than `2 Acc_(beta+1) / 2^f`, one floor loses 1, and
/// the previous deficit is multiplied by `r^m < 2^-(k m)`. A kernel states the
/// resulting constant for its coefficients (`exp` with `c_i = N! / i!`:
/// `eps < 8` in units of `N!`, from `1.44 + 3.4 + 1 + eps / 16`, see
/// `binary_exp_taylor_fixed`).
fn rect_sum(
  coefficients : Array[BinCoeff],
  powers : Array[BinCoeff],
  plan : RectPlan,
  f : Int32,
) -> BinCoeff {
  let m = plan.block
  let mut acc = BinCoeff::zero()
  let mut beta = plan.blocks - 1
  while beta >= 0 {
    let base = (beta * m).to_int()
    let mut block = coefficients[base].mul(powers[0])
    for j in 1..<m.to_int() {
      block = block.add(coefficients[base + j].mul(powers[j]))
    }
    if beta == plan.blocks - 1 {
      acc = block
    } else {
      acc = block.add(powers[m.to_int()].mul(acc).shift_right(f))
    }
    beta -= 1
  }
  acc
}

///|
/// `N! / i!` for `i < N`, and `N!`: the coefficients of the series of `exp`
/// with the common denominator `N!`, memoized per `N`.
priv struct RectFactorialCoefficients {
  terms : Int32
  coefficients : Array[BinCoeff]
  factorial : BinCoeff
}

///|
let rect_factorial_cache : BoundedCache[RectFactorialCoefficients] = BoundedCache::new(
  64,
)

///|
fn rect_inverse_factorials(terms : Int32) -> RectFactorialCoefficients {
  match rect_factorial_cache.find(fn(entry) { entry.terms == terms }) {
    Some(entry) => return entry
    None => ()
  }
  let coefficients : Array[BinCoeff] = Array::make(
    terms.to_int(),
    BinCoeff::one(),
  )
  let mut running = BinCoeff::one()
  let mut i = terms - 1
  while i >= 0 {
    // running = N! / (i + 1)!  ->  N! / i!
    running = running.mul(BinCoeff::from_uint64((i + 1).to_uint64()))
    coefficients[i.to_int()] = running
    i -= 1
  }
  let entry = { terms, coefficients, factorial: running, }
  rect_factorial_cache.insert(entry)
  entry
}

///|
/// Piece 6: argument reduction of `exp` by `ln 2` on integers, shared by the
/// bit-burst and the table kernels.
///
/// For finite `value = x` with `2^-64 <= |x| < 2^30` and the fixed-point
/// precision `F`, with `G = F + bits(n) + 2` and
/// `n_bits = max(1, top(x) + 2)`: `n = floor(|x| / ln 2)` (rounded up for a
/// negative `x` that is not an exact multiple), `R = |x| - n L` with
/// `L = floor(2^G ln 2) / 2^G` (so `0 <= ln 2 - L < 2^(1-G)`), `0 <= R < L` by
/// Euclidean division (`R` becomes `L - R` when `n` was rounded up) and
/// `R_t = floor(2^F R) / 2^F`; `delta = x - n ln 2 - R_t` satisfies
/// `|delta| <= 1.5 * 2^-F`, so `exp(x) = 2^n exp(R_t) exp(delta)` with
/// `1 - 2^-F <= exp(delta) <= 1 + 2^(1-F)`, which costs at most 3 units below
/// and 6 above because `exp(R_t) < 3` (`fixed_exp_finish`).
/// `ln2_drop_bits` is a test hook that takes `ln 2` with fewer bits than the
/// reduction needs. `None` when a precondition fails.
priv struct FixedExpReduction {
  n_magnitude : Int32
  n_negative : Bool
  /// `R_t` in units of `2^-F`, `0 <= reduced < 2^F ln 2`.
  reduced : BinCoeff
}

///|
fn fixed_exp_reduce(
  value : BinFloat,
  f : Int32,
  ln2_drop_bits~ : Int32 = 0,
) -> FixedExpReduction? {
  guard value.classify() == FpClass::Finite && !value.is_zero() else {
    return None
  }
  let top = binary_top_bound(value)
  guard top <= 30L && top >= -64L else { return None }
  let n_bits = Int32::max(1, top.to_int() + 2)
  let g = f + n_bits + 2
  guard binary_ln2_bounds(
      Int32::max(64, (g + 2 + 63) / 64 * 64 - ln2_drop_bits),
    )
    is Some((ln2_low, _)) else {
    return None
  }
  let ln2_int = fixed_scaled_floor(ln2_low, g)
  guard fixed_scaled_exact(value.abs(), g) is Some(magnitude) else {
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
  Some({
    n_magnitude: n_magnitude.to_int(),
    n_negative,
    reduced: residual.shift_right(g - f),
  })
}

///|
/// Closes the `exp` kernels: with `exp(R_t)` enclosed by `[lower, upper]` (in
/// units of `2^-F`), `exp(x)` lies in `2^n [lower - 3, upper + 6]` units
/// (`fixed_exp_reduce`). A result wider than `2^-(w + 6)` of the value, the
/// width of the series enclosure, is declined (`None`: the caller then runs the
/// series).
fn fixed_exp_finish(
  lower : BinCoeff,
  upper : BinCoeff,
  reduction : FixedExpReduction,
  f : Int32,
  work_precision : Int32,
  drop_delta~ : Bool = false,
) -> (BinFloat, BinFloat)? {
  let (lower_final, upper_final) = if drop_delta {
    (lower, upper)
  } else {
    (
      lower.sub_checked(BinCoeff::from_uint64(3UL)).unwrap(),
      upper.add(BinCoeff::from_uint64(6UL)),
    )
  }
  guard upper_final.sub_checked(lower_final) is Ok(width) &&
    width.bit_length() <= f - work_precision - 6 else {
    return None
  }
  let exponent = if reduction.n_negative {
    -reduction.n_magnitude - f
  } else {
    reduction.n_magnitude - f
  }
  Some(fixed_enclosure(lower_final, upper_final, exponent, work_precision))
}

///|
/// Piece 7: the chunk schedule of the bit-burst. The fraction `R_t` of `F` bits
/// is cut at the bit positions `b_1 = min(first_chunk, F)`,
/// `b_(j+1) = min(F, factor b_j)` into chunks `y_j = N_j / 2^(b_j)` with
/// `N_j < 2^(b_j - b_(j-1))`, so `y_j < 2^-b_(j-1)` and `R_t = sum y_j` exactly.
/// `visit(N_j, b_j)` is called for each nonzero chunk in order and returns
/// `false` to abandon the schedule (the result is then `false`).
fn fixed_burst_chunks(
  fraction : BinCoeff,
  f : Int32,
  first_chunk : Int32,
  chunk_factor : Int32,
  visit : (BinCoeff, Int32) -> Bool,
) -> Bool {
  let mut previous_bits = 0
  let mut previous_prefix = BinCoeff::zero()
  let mut boundary = Int32::min(first_chunk, f)
  while previous_bits < f {
    let prefix = fraction.shift_right(f - boundary)
    let chunk = prefix
      .sub_checked(previous_prefix.shift_left(boundary - previous_bits))
      .unwrap()
    if !chunk.is_zero() && !visit(chunk, boundary) {
      return false
    }
    previous_bits = boundary
    previous_prefix = prefix
    boundary = Int32::min(f, boundary * chunk_factor)
  }
  true
}
