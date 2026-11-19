///|
/// Medium-precision `exp` enclosure: reduction by `ln 2`, two levels of
/// precomputed tables `exp(j / 2^k)` and a rectangular-splitting Taylor series
/// of the small remainder on fixed-point integers. The error analysis is in
/// `doc/manual/design/bin_float.md` (section "Table-based exp kernel").
///
/// Guard bits of the kernel below the working precision.
let binary_exp_table_guard_bits : Int32 = 16

///|
/// Number of table sets kept (one per precision bucket).
let binary_exp_table_cache_entries : Int32 = 24

///|
/// Tables of `exp(j / 2^k1)` for `j <= floor(2^k1 ln 2)` and of
/// `exp(j / 2^(k1 + k2))` for `j < 2^k2`, as integer enclosures in units of
/// `2^-precision`: `low <= 2^precision exp(.) <= high`.
priv struct BinaryExpTable {
  precision : Int32
  k1 : Int32
  k2 : Int32
  first_low : Array[BinCoeff]
  first_high : Array[BinCoeff]
  second_low : Array[BinCoeff]
  second_high : Array[BinCoeff]
}

///|
let binary_exp_table_cache : Array[BinaryExpTable] = []

///|
/// The enclosure the tables are built from: the bit-burst kernel at and above
/// its threshold, the series below. Never the table kernel itself.
fn binary_exp_bounds_untabled(
  value : BinFloat,
  work_precision : Int32,
) -> (BinFloat, BinFloat)? {
  if work_precision >= binary_exp_burst_min_precision {
    match binary_exp_bounds_burst(value, work_precision) {
      Some(bounds) => return Some(bounds)
      None => ()
    }
  }
  binary_exp_bounds_series(value, work_precision)
}

///|
/// The fixed-point precision `F` the kernel works at for a working precision:
/// `w + g` rounded up to a multiple of 64 (128 at least), so that few table
/// sets exist and every table entry is already in units of `2^-F`.
fn binary_exp_table_fixed_precision(work_precision : Int32) -> Int32 {
  let f = work_precision + binary_exp_table_guard_bits
  if f <= 128 {
    128
  } else if f <= 1024 {
    (f + 63) / 64 * 64
  } else {
    (f + 255) / 256 * 256
  }
}

///|
/// Table shape `(k1, k2)` for a fixed-point precision.
fn binary_exp_table_shape(f : Int32) -> (Int32, Int32) {
  if f <= 256 {
    (7, 7)
  } else if f <= 1024 {
    (6, 6)
  } else {
    (6, 5)
  }
}

///|
/// Integer enclosure of `2^precision exp(j / 2^shift)`.
fn binary_exp_table_entry(
  j : Int32,
  shift : Int32,
  precision : Int32,
) -> (BinCoeff, BinCoeff)? {
  if j == 0 {
    let one = BinCoeff::one().shift_left(precision)
    return Some((one, one))
  }
  let value = BinFloat::make(
    BinCoeff::from_uint64(j.to_uint64()),
    -shift,
    precision + 8,
  )
  guard binary_exp_bounds_untabled(value, precision + 8) is Some((low, high)) else {
    return None
  }
  Some(
    (
      burst_scaled_floor(low, precision),
      burst_scaled_floor(high, precision).add(BinCoeff::one()),
    ),
  )
}

///|
fn binary_exp_table_build(
  precision : Int32,
  k1 : Int32,
  k2 : Int32,
) -> BinaryExpTable? {
  let ln2 = binary_ln2_bounds(precision + 8)
  guard ln2 is Some((_, ln2_high)) else { return None }
  // j <= floor(2^k1 R) with R < ln 2 <= ln2_high.
  let first_count = burst_scaled_floor(ln2_high, k1)
    .to_uint64()
    .unwrap()
    .to_int() +
    1
  let first_low : Array[BinCoeff] = []
  let first_high : Array[BinCoeff] = []
  for j in 0..<first_count {
    guard binary_exp_table_entry(j, k1, precision) is Some((low, high)) else {
      return None
    }
    first_low.push(low)
    first_high.push(high)
  }
  let second_low : Array[BinCoeff] = []
  let second_high : Array[BinCoeff] = []
  for j in 0..<(1 << k2) {
    guard binary_exp_table_entry(j, k1 + k2, precision) is Some((low, high)) else {
      return None
    }
    second_low.push(low)
    second_high.push(high)
  }
  Some({ precision, k1, k2, first_low, first_high, second_low, second_high, })
}

///|
fn binary_exp_table_get(
  precision : Int32,
  k1 : Int32,
  k2 : Int32,
) -> BinaryExpTable? {
  for table in binary_exp_table_cache {
    if table.precision == precision && table.k1 == k1 && table.k2 == k2 {
      return Some(table)
    }
  }
  guard binary_exp_table_build(precision, k1, k2) is Some(table) else {
    return None
  }
  if binary_exp_table_cache.length() >= binary_exp_table_cache_entries.to_int() {
    ignore(binary_exp_table_cache.remove(0))
  }
  binary_exp_table_cache.push(table)
  Some(table)
}

///|
/// Number of Taylor terms `N` (before rounding up to whole blocks) so that
/// `K N + sum_{i <= N} (bits(i) - 1) >= f + 1`, which gives
/// `2 r^N / N! <= 2^-f` for `0 <= r < 2^-K`.
fn binary_exp_taylor_terms(k : Int32, f : Int32) -> Int32 {
  let mut n = 1
  let mut log_factorial = 0
  while k * n + log_factorial < f + 1 {
    n += 1
    log_factorial += bit_length_int(n) - 1
  }
  n
}

///|
/// Block size `m` of the rectangular splitting for `needed` terms: the one with
/// the lowest estimated cost, `2 N'` for the small-coefficient products and
/// `3 + f / 256` for each full-size product (`m - 1` powers, `b - 1` Horner
/// steps), where `N' = b m >= needed` is the number of terms actually summed.
fn binary_exp_block_size(needed : Int32, f : Int32) -> Int32 {
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
/// `N! / i!` for `i < N`, and `N!`, memoized per `N`.
priv struct BinaryExpTaylorCoefficients {
  terms : Int32
  coefficients : Array[BinCoeff]
  factorial : BinCoeff
}

///|
let binary_exp_taylor_cache : Array[BinaryExpTaylorCoefficients] = []

///|
fn binary_exp_taylor_coefficients(terms : Int32) -> BinaryExpTaylorCoefficients {
  for entry in binary_exp_taylor_cache {
    if entry.terms == terms {
      return entry
    }
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
  if binary_exp_taylor_cache.length() >= 64 {
    ignore(binary_exp_taylor_cache.remove(0))
  }
  binary_exp_taylor_cache.push(entry)
  entry
}

///|
/// Enclosure `(low, high)` in units `2^-f` of `exp(a / 2^f)` for
/// `0 <= a < 2^(f - k)`, `k >= 4`, by rectangular splitting of the series
/// with integer coefficients and one final division.
///
/// With `r = a / 2^f < 2^-k`, the powers `p_j = floor(p_u p_v / 2^f)`
/// (`u + v = j`, `p_0 = 2^f`, `p_1 = a`) satisfy `p_j <= 2^f r^j` and
/// `2^f r^j - p_j < 2` (induction:
/// `e_j < 1 + (e_u + e_v) 2^-k + e_u e_v 2^-f < 2` for `k >= 4`). Take `N = b m` terms,
/// `C_i = N! / i!`, `P_beta = sum_(j < m) C_(beta m + j) p_j` and
/// `Acc_(b-1) = P_(b-1)`, `Acc_beta = P_beta + floor(p_m Acc_(beta+1) / 2^f)`.
/// Then `Acc_0 <= N! 2^f sum_(i < N) r^i / i!`, and the deficit
/// `eps_beta` (in units of `N!`) obeys
/// `eps_beta < 2 sum_(j >= 2) 1/(beta m + j)! + 2 e^r + 1 + eps_(beta+1) / 16`
/// `< 1.44 + 3.4 + 1 + eps_(beta+1) / 16`, hence `eps < 8`. Dividing by `N!`
/// with `floor` loses less than one more unit, and the omitted tail is at most
/// one unit by the choice of `N`, so
/// `E <= 2^f exp(r) < E + 10` for `E = floor(Acc_0 / N!)`.
fn binary_exp_taylor_fixed(
  a : BinCoeff,
  f : Int32,
  k : Int32,
) -> (BinCoeff, BinCoeff) {
  let needed = binary_exp_taylor_terms(k, f)
  let m = binary_exp_block_size(needed, f)
  let blocks = (needed + m - 1) / m
  let terms = blocks * m
  let table = binary_exp_taylor_coefficients(terms)
  let powers : Array[BinCoeff] = [BinCoeff::one().shift_left(f), a]
  for j in 2..<=m {
    let u = (j + 1) / 2
    let v = j / 2
    powers.push(powers[u.to_int()].mul(powers[v.to_int()]).shift_right(f))
  }
  let mut acc = BinCoeff::zero()
  let mut beta = blocks - 1
  while beta >= 0 {
    let base = (beta * m).to_int()
    let mut block = table.coefficients[base].mul(powers[0])
    for j in 1..<m.to_int() {
      block = block.add(table.coefficients[base + j].mul(powers[j]))
    }
    if beta == blocks - 1 {
      acc = block
    } else {
      acc = block.add(powers[m.to_int()].mul(acc).shift_right(f))
    }
    beta -= 1
  }
  let low = acc.div_rem_checked(table.factorial).unwrap().0
  (low, low.add(BinCoeff::from_uint64(10UL)))
}

///|
/// `binary_exp_bounds` by the table kernel: `None` when a precondition fails
/// (the caller then uses the older paths).
///
/// With `F = w + g`: `x = n L + R` and `R_t = floor(2^F R) / 2^F` exactly as
/// in `binary_exp_bounds_burst`, so `exp(x) = 2^n exp(R_t) exp(delta)` with
/// `1 - 2^-F <= exp(delta) <= 1 + 2^(1-F)` (3 units below, 6 above because
/// `exp(R_t) < 3`). Then `R_t = j1 / 2^k1 + j2 / 2^(k1+k2) + r` with
/// `j1 = floor(2^k1 R_t)`, `j2 = floor(2^(k1+k2) (R_t - j1/2^k1))` and
/// `0 <= r < 2^-(k1+k2)` exact multiples of `2^-F`, so
/// `exp(R_t) = T1[j1] T2[j2] exp(r)`. Table entries are enclosures at a
/// precision `P >= F`, brought to `2^-F` units by `floor` (low) and
/// `floor + 1` (high). Products of enclosures are folded by `floor` (low) and
/// `floor + 1` (high), which is monotone because every factor is positive.
fn binary_exp_bounds_table(
  value : BinFloat,
  work_precision : Int32,
) -> (BinFloat, BinFloat)? {
  guard value.classify() == FpClass::Finite && !value.is_zero() else {
    return None
  }
  let top = binary_top_bound(value)
  guard top <= 30L && top >= -64L else { return None }
  let top_bits = top.to_int()
  let f = binary_exp_table_fixed_precision(work_precision)
  let n_bits = Int32::max(1, top_bits + 2)
  let g = f + n_bits + 2
  guard binary_ln2_bounds((g + 2 + 63) / 64 * 64) is Some((ln2_low, _)) else {
    return None
  }
  let ln2_int = burst_scaled_floor(ln2_low, g)
  guard burst_scaled_exact(value.abs(), g) is Some(magnitude) else {
    return None
  }
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
  let (k1, k2) = binary_exp_table_shape(f)
  let k = k1 + k2
  guard f > k + 8 else { return None }
  guard binary_exp_table_get(f, k1, k2) is Some(table) else { return None }
  let j1 = reduced.shift_right(f - k1)
  let rest1 = reduced.sub_checked(j1.shift_left(f - k1)).unwrap()
  let j2 = rest1.shift_right(f - k)
  let a = rest1.sub_checked(j2.shift_left(f - k)).unwrap()
  guard j1.to_uint64() is Some(j1_value) &&
    j1_value.to_int() < table.first_low.length() &&
    j2.to_uint64() is Some(j2_value) &&
    j2_value.to_int() < table.second_low.length() else {
    return None
  }
  let (series_low, series_high) = binary_exp_taylor_fixed(a, f, k)
  let first_low = table.first_low[j1_value.to_int()]
  let first_high = table.first_high[j1_value.to_int()]
  let second_low = table.second_low[j2_value.to_int()]
  let second_high = table.second_high[j2_value.to_int()]
  let low = first_low
    .mul(second_low)
    .shift_right(f)
    .mul(series_low)
    .shift_right(f)
  let high = first_high
    .mul(second_high)
    .shift_right(f)
    .add(BinCoeff::one())
    .mul(series_high)
    .shift_right(f)
    .add(BinCoeff::one())
  let lower_final = low.sub_checked(BinCoeff::from_uint64(3UL)).unwrap()
  let upper_final = high.add(BinCoeff::from_uint64(6UL))
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
