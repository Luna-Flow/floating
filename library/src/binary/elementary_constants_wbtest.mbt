///|
fn binary_constant_test_same(
  left : (Binary, Binary)?,
  right : (Binary, Binary)?,
) -> Bool {
  match (left, right) {
    (Some((left_low, left_high)), Some((right_low, right_high))) =>
      left_low.identical(right_low) &&
      left_high.identical(right_high) &&
      left_low.precision() == right_low.precision() &&
      left_high.precision() == right_high.precision()
    (None, None) => true
    _ => false
  }
}

///|
// oracle: S
// source: the uncached binary_ln2_compute, binary_ln10_bounds_compute and binary_pi_bounds_compute at the same precisions; the claim is that the cache returns what the computation returns (hit, miss and eviction paths)
// shares: the compute functions are the code under test on both sides; binary_constant_test_same compares
test "certified constant caches return the uncached enclosures" {
  // More distinct precisions than cache entries, visited twice and in a
  // different order, so every lookup path (hit, miss, eviction) is exercised.
  let precisions = [53, 117, 128, 181, 256, 261, 400, 117, 53, 1024, 181, 128]
  for work in precisions {
    assert_true(
      binary_constant_test_same(
        binary_ln2_bounds(work),
        binary_ln2_compute(work),
      ),
    )
    assert_true(
      binary_constant_test_same(
        binary_ln10_bounds(work),
        binary_ln10_bounds_compute(work),
      ),
    )
    assert_true(
      binary_constant_test_same(
        binary_pi_bounds(work),
        binary_pi_bounds_compute(work),
      ),
    )
  }
  for _ in 0..<2 {
    for work in precisions.rev() {
      assert_true(
        binary_constant_test_same(
          binary_ln2_bounds(work),
          binary_ln2_compute(work),
        ),
      )
    }
  }
}

///|
// oracle: S
// source: the cache length against binary_constant_cache_entries and the uncached binary_ln2_compute for the value; sizes, not an external value
// shares: BoundedCache, binary_cached_constant and the compute function (the code under test)
test "certified constant caches stay bounded and skip very large precisions" {
  for work in 40..<80 {
    ignore(binary_ln2_bounds(work))
  }
  assert_true(
    binary_ln2_cache.length() <= binary_constant_cache_entries.to_int(),
  )
  // Above the cache limit a constant is computed but not kept.
  let cache : BoundedCache[BinaryConstantEntry] = BoundedCache::new(
    binary_constant_cache_entries.to_int(),
  )
  let first = binary_cached_constant(
    cache,
    117,
    binary_ln2_compute,
    max_precision=100,
  )
  assert_eq(cache.length(), 0)
  assert_true(binary_constant_test_same(first, binary_ln2_compute(117)))
  ignore(
    binary_cached_constant(cache, 90, binary_ln2_compute, max_precision=100),
  )
  assert_eq(cache.length(), 1)
}

///|
test "certified constants are tight enclosures of the true values" {
  let tiny = Binary::make(BinCoeff::one(), -100, 128)
  let (ln2_low, ln2_high) = binary_ln2_bounds(128).unwrap()
  assert_true(ln2_low < ln2_high)
  assert_true(ln2_high.sub(ln2_low) < tiny)
  assert_true(ln2_low > Binary::from_double(0.6931471805599452, precision=128))
  assert_true(ln2_high < Binary::from_double(0.6931471805599454, precision=128))
  let (pi_low, pi_high) = binary_pi_bounds(128).unwrap()
  assert_true(pi_low < pi_high)
  assert_true(pi_high.sub(pi_low) < tiny)
  assert_true(pi_low > Binary::from_double(3.14159265358979, precision=128))
  assert_true(pi_high < Binary::from_double(3.1415926535898, precision=128))
}

///|
test "elementary functions are unchanged by cache state and call order" {
  let context = BinaryContext::binary64()
  let inputs = [
    Binary::from_double(0.7, precision=53),
    Binary::from_double(3.5, precision=53),
    Binary::from_double(100.25, precision=53),
    Binary::from_double(0.0009765625, precision=53),
  ]
  let first_ln = inputs.map(value => value.ln_ctx(context))
  let first_sin = inputs.map(value => value.sin_ctx(context))
  let first_cos = inputs.map(value => value.cos_ctx(context))
  // Fill the caches with other precisions, then repeat.
  for work in 200..<230 {
    ignore(binary_pi_bounds(work))
    ignore(binary_ln2_bounds(work))
  }
  let second_ln = inputs.map(value => value.ln_ctx(context))
  let second_sin = inputs.map(value => value.sin_ctx(context))
  let second_cos = inputs.map(value => value.cos_ctx(context))
  for index in 0..<inputs.length() {
    assert_identical_with_flags(first_ln[index], second_ln[index])
    assert_identical_with_flags(first_sin[index], second_sin[index])
    assert_identical_with_flags(first_cos[index], second_cos[index])
  }
}
