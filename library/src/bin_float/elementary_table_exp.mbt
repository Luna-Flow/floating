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
  first_low : Array[Coeff]
  first_high : Array[Coeff]
  second_low : Array[Coeff]
  second_high : Array[Coeff]
}

///|
let binary_exp_table_cache : BoundedCache[BinaryExpTable] = BoundedCache::new(
  binary_exp_table_cache_entries.to_int(),
)

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
) -> (Coeff, Coeff)? {
  if j == 0 {
    let one = Coeff::one().shift_left(precision)
    return Some((one, one))
  }
  let value = BinFloat::make_coeff(
    Coeff::from_uint64(j.to_uint64()),
    -shift,
    precision + 8,
  )
  guard binary_exp_bounds_untabled(value, precision + 8) is Some((low, high)) else {
    return None
  }
  Some(
    (
      fixed_scaled_floor(low, precision),
      fixed_scaled_floor(high, precision).add(Coeff::one()),
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
  let first_count = fixed_scaled_floor(ln2_high, k1)
    .to_uint64()
    .unwrap()
    .to_int() +
    1
  let first_low : Array[Coeff] = []
  let first_high : Array[Coeff] = []
  for j in 0..<first_count {
    guard binary_exp_table_entry(j, k1, precision) is Some((low, high)) else {
      return None
    }
    first_low.push(low)
    first_high.push(high)
  }
  let second_low : Array[Coeff] = []
  let second_high : Array[Coeff] = []
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
  match
    binary_exp_table_cache.find(fn(table) {
      table.precision == precision && table.k1 == k1 && table.k2 == k2
    }) {
    Some(table) => return Some(table)
    None => ()
  }
  guard binary_exp_table_build(precision, k1, k2) is Some(table) else {
    return None
  }
  binary_exp_table_cache.insert(table)
  Some(table)
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
fn binary_exp_taylor_fixed(a : Coeff, f : Int32, k : Int32) -> (Coeff, Coeff) {
  let plan = rect_plan(rect_factorial_terms(k, f), f)
  let table = rect_inverse_factorials(plan.terms)
  let powers = rect_powers(a, f, plan.block)
  let acc = rect_sum(table.coefficients, powers, plan, f)
  let low = acc.div_rem_checked(table.factorial).unwrap().0
  (low, low.add(Coeff::from_uint64(10UL)))
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
  let f = binary_exp_table_fixed_precision(work_precision)
  guard fixed_exp_reduce(value, f) is Some(reduction) else { return None }
  let reduced = reduction.reduced
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
    .add(Coeff::one())
    .mul(series_high)
    .shift_right(f)
    .add(Coeff::one())
  fixed_exp_finish(low, high, reduction, f, work_precision)
}
