///|
fn agm_test_values(
  work : Int32,
  count : Int32,
  seed0 : UInt64,
) -> Array[BinFloat] {
  let values : Array[BinFloat] = []
  let mut seed = seed0
  let bits = Int32::min(work, 1500)
  for _ in 0..<count {
    values.push(burst_test_value(bits, 1, false, seed))
    seed += 1UL
  }
  for k in [17, 18, 20, 40, 100] {
    let offset = BinFloat::make_coeff(
      burst_test_coefficient(60, seed),
      -k - 60,
      60,
    )
    seed += 1UL
    let context = BinaryContext::new(precision=bits + k + 80)
    values.push(BinFloat::one_raw(precision=2).add_ctx(offset, context).0)
    values.push(
      BinFloat::from_int_raw(2, precision=2).sub_ctx(offset, context).0,
    )
  }
  values.push(BinFloat::from_int_raw(2, precision=2))
  values.push(BinFloat::make_coeff(Coeff::from_uint64(3UL), -1, 2))
  values.push(BinFloat::make_coeff(Coeff::from_uint64(4097UL), -12, 13))
  values.push(BinFloat::make_coeff(Coeff::from_uint64(65537UL), -16, 17))
  values.push(BinFloat::make_coeff(Coeff::from_uint64(131073UL), -17, 18))
  values
}

///|
test "ln AGM enclosure contains the series enclosure at higher precision" {
  let mut checked = 0
  for work in [256, 1024, 2048, 4096] {
    let count = if work <= 1024 { 8 } else { 2 }
    for value in agm_test_values(work, count, 5000UL + work.to_uint64()) {
      match binary_ln_unit_agm_bounds(value, work) {
        Some(bounds) => {
          let reference = binary_ln_unit_bounds_series(value, work + 256).unwrap()
          assert_true(burst_test_contains(bounds, reference))
          checked += 1
        }
        None => ()
      }
    }
  }
  assert_true(checked > 40)
}

///|
test "ln AGM enclosure at 8192 bits contains the series enclosure" {
  let value = burst_test_value(8192, 1, false, 8192UL)
  let bounds = binary_ln_unit_agm_bounds(value, 8192).unwrap()
  let reference = binary_ln_unit_bounds_series(value, 8192 + 256).unwrap()
  assert_true(burst_test_contains(bounds, reference))
}

///|
test "ln AGM enclosure is no wider than the Newton enclosure" {
  for work in [384, 1024, 2048] {
    for value in agm_test_values(work, 4, 77UL + work.to_uint64()) {
      match
        (
          binary_ln_unit_agm_bounds(value, work),
          binary_ln_unit_burst_bounds(value, work),
        ) {
        (Some(agm), Some(newton)) =>
          assert_true(agm.1.sub(agm.0).compare(newton.1.sub(newton.0)) <= 0)
        _ => ()
      }
    }
  }
}

///|
test "ln AGM declines outside its range" {
  let work = 512
  assert_true(
    binary_ln_unit_agm_bounds(BinFloat::one(precision=64), work) is None,
  )
  assert_true(
    binary_ln_unit_agm_bounds(BinFloat::from_int(3, precision=64), work) is None,
  )
  assert_true(
    binary_ln_unit_agm_bounds(
      BinFloat::make_coeff(
        Coeff::one().shift_left(20).add(Coeff::one()),
        -20,
        21,
      ),
      work,
    )
    is None,
  )
  assert_true(binary_ln_unit_agm_bounds(BinFloat::nan(), work) is None)
  assert_true(
    binary_ln_unit_agm_bounds(BinFloat::inf(Sign::Positive), work) is None,
  )
  assert_true(
    binary_ln_unit_agm_bounds(BinFloat::from_int(-3, precision=64), work)
    is None,
  )
}

///|
test "ln AGM iteration counts" {
  // `x = 4 / 2^(p / 2 + 2)` for `v = 1`-ish arguments: the count of the mean.
  for pair in [(2140, 18, 19), (8288, 22, 23), (512, 13, 15)] {
    let (p, low, high) = pair
    let x = BinFloat::make_coeff(Coeff::one(), -((p + 1) / 2), 1)
    let (_, n) = binary_agm_one(x, p).unwrap()
    assert_true(n >= low && n <= high)
  }
}

///|
test "mutated ln AGM kernels are caught by the containment test" {
  let value = burst_test_value(1500, 1, false, 4242UL)
  let work = 1536
  let reference = binary_ln_unit_bounds_series(value, work + 256).unwrap()
  assert_true(
    burst_test_contains(
      binary_ln_unit_agm_bounds(value, work).unwrap(),
      reference,
    ),
  )
  for cap in [4, 8, 12] {
    let capped = {
      precision_drop: 0,
      drop_model: false,
      iteration_cap: cap,
      ln2_drop: 0,
    }
    assert_true(
      burst_test_caught(
        binary_ln_unit_agm_bounds(value, work, mutation=capped),
        reference,
      ),
    )
  }
  // Too few bits in the working precision and in `ln 2`: declined or valid.
  let short = {
    precision_drop: 60,
    drop_model: false,
    iteration_cap: 0,
    ln2_drop: 80,
  }
  match binary_ln_unit_agm_bounds(value, work, mutation=short) {
    Some(bounds) => assert_true(burst_test_contains(bounds, reference))
    None => ()
  }
}

///|
test "ln keeps its results when the AGM kernel runs" {
  let mut seed = 909UL
  for precision in [1000, 1100, 2000] {
    for _ in 0..<3 {
      let value = burst_test_value(precision, 1, false, seed)
      seed += 1UL
      let result = value.ln()
      let (low, high) = binary_ln_unit_bounds_series(value, precision + 320).unwrap()
      assert_identical(
        result,
        low.with_precision(precision, BinaryRoundingMode::RoundTiesToEven),
      )
      assert_identical(
        result,
        high.with_precision(precision, BinaryRoundingMode::RoundTiesToEven),
      )
    }
  }
}

///|
/// The iteration as it was before the limb-array root, the exact halving without
/// a copy and the exponent test before the difference: kept as the reference
/// (every operation through the context forms, the difference at every step).
fn binary_agm_one_reference(x : BinFloat, p : Int32) -> (BinFloat, Int32)? {
  let context = binary_working_context(p)
  let mut u = x
  let mut v = BinFloat::one_raw(precision=p)
  let mut n = 0
  while n < 64 {
    let next_u = u.mul_ctx(v, context).0.sqrt_ctx(context).0
    let next_v = binary_scale_pow2(u.add_ctx(v, context).0, -1)
    u = next_u
    v = next_v
    n += 1
    let difference = if u.compare(v) <= 0 {
      v.sub_ctx(u, context).0
    } else {
      u.sub_ctx(v, context).0
    }
    if difference.is_zero() ||
      binary_top_bound(difference) <= binary_top_bound(v) - p.to_int64() + 3 {
      return Some((v, n))
    }
  }
  None
}

///|
test "AGM iteration equals the reference iteration" {
  let mut seed = 1234UL
  let mut compared = 0
  for p in [64, 65, 100, 128, 200, 256, 640, 1100, 2140, 4200, 8288] {
    for shift in [10, 33, p / 2, p / 2 + 7, p] {
      for bits in [Int32::min(p, 3), Int32::min(p, 40), p] {
        seed += 1UL
        let x = BinFloat::make_coeff(
          burst_test_coefficient(bits, seed),
          -shift - bits,
          p,
        )
        match (binary_agm_one(x, p), binary_agm_one_reference(x, p)) {
          (Some((a, n)), Some((b, m))) => {
            assert_eq(n, m)
            assert_eq(a.compare(b), 0)
            compared += 1
          }
          (None, None) => ()
          _ => fail("iterations disagree on settling")
        }
      }
    }
  }
  assert_true(compared > 100)
}
