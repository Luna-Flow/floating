///|
fn burst_ln_test_corpus() -> Array[BinFloat] {
  let values : Array[BinFloat] = []
  let mut seed = 31UL
  for bits in [60, 130, 256, 400, 700, 1100, 2000] {
    // Random values in [1, 2).
    for _ in 0..<12 {
      values.push(burst_test_value(bits, 1, false, seed))
      seed += 1UL
    }
    // Values close to 1 and to 2.
    for k in [17, 18, 24, 40, 100] {
      let offset = BinFloat::make_coeff(
        burst_test_coefficient(Int32::min(bits, 60), seed),
        -k - Int32::min(bits, 60),
        Int32::min(bits, 60),
      )
      seed += 1UL
      let context = BinaryContext::unbounded(bits + k + 80)
      values.push(BinFloat::one(precision=2).add_ctx(offset, context).0)
      values.push(BinFloat::from_int(2, precision=2).sub_ctx(offset, context).0)
    }
  }
  values.push(BinFloat::from_int(2, precision=2))
  values.push(BinFloat::make_coeff(Coeff::from_uint64(3UL), -1, 2))
  values.push(BinFloat::make_coeff(Coeff::from_uint64(5UL), -2, 3))
  values.push(BinFloat::make_coeff(Coeff::from_uint64(4097UL), -12, 13))
  values
}

///|
test "ln Newton step contains the series enclosure at higher precision" {
  let mut checked = 0
  for value in burst_ln_test_corpus() {
    let work = burst_test_work(value.precision())
    match binary_ln_unit_burst_bounds(value, work) {
      Some(bounds) => {
        let reference = binary_ln_unit_bounds_series(value, work + 256).unwrap()
        assert_true(burst_test_contains(bounds, reference))
        checked += 1
      }
      None => ()
    }
  }
  assert_true(checked > 60)
}

///|
test "ln Newton step is no wider than the series enclosure" {
  for value in burst_ln_test_corpus() {
    let work = burst_test_work(value.precision())
    match binary_ln_unit_burst_bounds(value, work) {
      Some((low, high)) => {
        let (series_low, series_high) = binary_ln_unit_bounds_series(
          value, work,
        ).unwrap()
        assert_true(high.sub(low).compare(series_high.sub(series_low)) <= 0)
      }
      None => ()
    }
  }
}

///|
test "ln Newton step declines outside its range" {
  let work = 512
  assert_true(
    binary_ln_unit_burst_bounds(BinFloat::one(precision=64), work) is None,
  )
  assert_true(
    binary_ln_unit_burst_bounds(BinFloat::from_int(3, precision=64), work)
    is None,
  )
  assert_true(
    binary_ln_unit_burst_bounds(
      BinFloat::make_coeff(Coeff::from_uint64(1UL), -1, 1),
      work,
    )
    is None,
  )
  // Closer to 1 than 2^-16.
  assert_true(
    binary_ln_unit_burst_bounds(
      BinFloat::make_coeff(
        Coeff::one().shift_left(30).add(Coeff::one()),
        -30,
        31,
      ),
      work,
    )
    is None,
  )
  assert_true(
    binary_ln_unit_burst_bounds(BinFloat::inf(Sign::Positive), work) is None,
  )
}

///|
test "mutated ln Newton steps are caught by the containment test" {
  let value = burst_test_value(2000, 1, false, 4242UL)
  let work = 2064
  let reference = binary_ln_unit_bounds_series(value, work + 256).unwrap()
  assert_true(
    burst_test_contains(
      binary_ln_unit_burst_bounds(value, work).unwrap(),
      reference,
    ),
  )
  // A bias of 8 units of the last place in the lower end.
  let biased = { start_bits_drop: 0, drop_quadratic: false, lower_bias: 8, }
  assert_true(
    burst_test_caught(
      binary_ln_unit_burst_bounds(value, work, mutation=biased),
      reference,
    ),
  )
  // A poor start value (about work / 8 bits) with the quadratic term dropped.
  let poor = {
    start_bits_drop: work / 2 + 16 - work / 8,
    drop_quadratic: true,
    lower_bias: 0,
  }
  assert_true(
    burst_test_caught(
      binary_ln_unit_burst_bounds(value, work, mutation=poor),
      reference,
    ),
  )
  // The poor start value alone only widens the enclosure; the quadratic term
  // keeps it valid (or the width check declines it).
  let wide = {
    start_bits_drop: work / 2 + 16 - work / 8,
    drop_quadratic: false,
    lower_bias: 0,
  }
  match binary_ln_unit_burst_bounds(value, work, mutation=wide) {
    Some(bounds) => assert_true(burst_test_contains(bounds, reference))
    None => ()
  }
}

///|
/// The result of `ln_ctx` computed with the series enclosures only.
fn burst_ln_test_series(
  value : BinFloat,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags)? {
  let mut work = context.precision + 64
  let mut attempt = 0
  while attempt < 12 {
    match binary_ln_bounds(value, work, series_only=true) {
      Some(bounds) => {
        let (result, unique, flags) = binary_certified_inexact_target_rounding(
          bounds.0,
          bounds.1,
          context,
        )
        if unique {
          return Some((result, flags))
        }
      }
      None => return None
    }
    work += Int32::max(32, work / 2)
    attempt += 1
  }
  None
}

///|
test "ln results are identical with and without the Newton step" {
  let modes = [
    RoundTiesToEven,
    RoundTowardZero,
    RoundTowardPositive,
    RoundTowardNegative,
  ]
  let mut seed = 700UL
  let mut compared = 0
  for bits in [200, 300, 513, 640, 1000, 1024, 2048] {
    for top in [-20, -3, -1, 0, 1, 2, 5, 12, 40] {
      seed += 1UL
      let value = burst_test_value(bits, top, false, seed)
      for mode in modes {
        let context = BinaryContext::unbounded(bits, rounding=mode)
        match
          (burst_ln_test_series(value, context), value.try_ln_ctx(context)) {
          (Some((expected, expected_flags)), Ok((result, flags))) => {
            assert_true(result == expected)
            assert_true(flags == expected_flags)
            compared += 1
          }
          _ => ()
        }
      }
    }
  }
  assert_true(compared > 150)
}

///|
test "ln entry step on the table kernel contains the series enclosure" {
  let mut checked = 0
  let mut seed = 977UL
  for work in [384, 448, 576, 704, 832, 1000, 1100, 1151, 1152, 1400, 2112] {
    for _ in 0..<6 {
      let value = burst_test_value(Int32::min(work, 1100), 1, false, seed)
      seed += 1UL
      match binary_ln_unit_bounds(value, work, entry=true) {
        Some(bounds) => {
          let reference = binary_ln_unit_bounds_series(value, work + 256).unwrap()
          assert_true(burst_test_contains(bounds, reference))
          checked += 1
        }
        None => ()
      }
    }
  }
  assert_true(checked > 60)
}

///|
test "ln keeps its results when the Newton step starts at the entry threshold" {
  let mut seed = 131UL
  for precision in [300, 330, 450, 600, 900, 1000] {
    for _ in 0..<4 {
      let value = burst_test_value(precision, 1, false, seed)
      seed += 1UL
      let result = value.ln()
      let work = precision + 320
      let (low, high) = binary_ln_unit_bounds_series(value, work).unwrap()
      assert_eq(
        result,
        low.with_precision(precision, RoundingMode::ToNearestEven),
      )
      assert_eq(
        result,
        high.with_precision(precision, RoundingMode::ToNearestEven),
      )
    }
  }
}
