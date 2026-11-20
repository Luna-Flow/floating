///|
/// A certified constant enclosure computed at one working precision.
priv struct BinaryConstantEntry {
  work_precision : Int32
  bounds : (BinFloat, BinFloat)?
}

///|
/// Constants above this working precision are recomputed instead of kept, so
/// the caches hold a bounded amount of memory.
let binary_constant_cache_max_precision : Int32 = 65536

///|
/// Entries kept per constant: the working precisions of one operation and its
/// few refinements.
let binary_constant_cache_entries : Int32 = 6

///|
let binary_ln2_cache : BoundedCache[BinaryConstantEntry] = BoundedCache::new(
  binary_constant_cache_entries.to_int(),
)

///|
let binary_ln10_cache : BoundedCache[BinaryConstantEntry] = BoundedCache::new(
  binary_constant_cache_entries.to_int(),
)

///|
let binary_pi_cache : BoundedCache[BinaryConstantEntry] = BoundedCache::new(
  binary_constant_cache_entries.to_int(),
)

///|
/// Memoizes `compute` per working precision. `compute` is a pure function of
/// its argument, so a cached enclosure is the very value a recomputation
/// returns; only the time changes.
fn binary_cached_constant(
  cache : BoundedCache[BinaryConstantEntry],
  work_precision : Int32,
  compute : (Int32) -> (BinFloat, BinFloat)?,
  max_precision~ : Int32 = binary_constant_cache_max_precision,
) -> (BinFloat, BinFloat)? {
  match cache.find(fn(entry) { entry.work_precision == work_precision }) {
    Some(entry) => return entry.bounds
    None => ()
  }
  let bounds = compute(work_precision)
  if work_precision <= max_precision {
    cache.insert({ work_precision, bounds, })
  }
  bounds
}

///|
fn binary_ln2_series_compute(work_precision : Int32) -> (BinFloat, BinFloat)? {
  binary_ln_unit_bounds(
    BinFloat::from_int_raw(2, precision=work_precision),
    work_precision,
  )
}

///|
/// Certified bounds on `ln 2` at `work_precision`.
fn binary_ln2_bounds(work_precision : Int32) -> (BinFloat, BinFloat)? {
  binary_cached_constant(binary_ln2_cache, work_precision, binary_ln2_compute)
}

///|
/// Certified bounds on `ln 10` at `work_precision`.
fn binary_ln10_bounds(work_precision : Int32) -> (BinFloat, BinFloat)? {
  binary_cached_constant(
    binary_ln10_cache, work_precision, binary_ln10_bounds_compute,
  )
}

///|
/// Certified bounds on `pi` at `work_precision`.
fn binary_pi_bounds(work_precision : Int32) -> (BinFloat, BinFloat)? {
  binary_cached_constant(
    binary_pi_cache, work_precision, binary_pi_bounds_compute,
  )
}
