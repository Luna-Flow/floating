///|
/// `[low, high] / 2^f` as a pair of floats at a generous precision.
fn table_test_pair(
  low : Coeff,
  high : Coeff,
  f : Int32,
) -> (BinFloat, BinFloat) {
  (
    BinFloat::make_coeff(low, -f, f + 8, mode=RoundingMode::TowardNegative),
    BinFloat::make_coeff(high, -f, f + 8, mode=RoundingMode::TowardPositive),
  )
}

///|
test "table exp contains the series enclosure at higher precision" {
  let mut checked = 0
  let tops = [-60, -20, -8, -3, -1, 0, 1, 2, 3, 5, 8, 12, 20, 28, 29, 30]
  let mut seed = 5UL
  for work in [53, 64, 100, 160, 200, 300, 520, 1000] {
    for top in tops {
      for negative in [false, true] {
        seed += 1UL
        let value = burst_test_value(Int32::min(work, 120), top, negative, seed)
        match binary_exp_bounds_table(value, work) {
          Some(bounds) => {
            let reference = binary_exp_bounds_series(value, work + 256).unwrap()
            assert_true(burst_test_contains(bounds, reference))
            checked += 1
          }
          None => ()
        }
      }
    }
  }
  assert_true(checked > 200)
}

///|
test "table exp is within a few ulps" {
  for work in [53, 160, 512] {
    let value = burst_test_value(Int32::min(work, 100), 1, false, 99UL)
    let (low, high) = binary_exp_bounds_table(value, work).unwrap()
    // high - low <= 2^-(w+3) low.
    let width = high.sub(low)
    let limit = high.mul(BinFloat::make_coeff(Coeff::one(), -(work - 2), 64))
    assert_true(width.compare(limit) <= 0)
  }
}

///|
test "table exp declines out-of-range arguments" {
  assert_true(
    binary_exp_bounds_table(BinFloat::zero(precision=64), 160) is None,
  )
  assert_true(binary_exp_bounds_table(BinFloat::nan(), 160) is None)
  assert_true(
    binary_exp_bounds_table(BinFloat::from_int(1073741824, precision=64), 160)
    is None,
  )
  assert_true(
    binary_exp_bounds_table(BinFloat::make_coeff(Coeff::one(), -200, 1), 160)
    is None,
  )
}

///|
/// Arguments whose reduced remainder sits at the table boundaries: `x` equal
/// to `j / 2^k1` and `j / 2^(k1+k2)` (remainder 0), one unit below and above.
test "table exp near the table boundaries" {
  for work in [64, 160, 400] {
    let f = work + binary_exp_table_guard_bits
    let (k1, k2) = binary_exp_table_shape(f)
    let k = k1 + k2
    for j in [1, 2, 3, 7, 11, 15, 16, 17, 21] {
      for (shift, count) in [(k1, 22), (k, 16)] {
        if j < count {
          let base = BinFloat::make_coeff(
            Coeff::from_uint64(j.to_uint64()),
            -shift,
            work + 40,
          )
          let tiny = BinFloat::make_coeff(Coeff::one(), -(work + 20), 1)
          for value in [base, base.add(tiny), base.sub(tiny)] {
            match binary_exp_bounds_table(value, work + 40) {
              Some(bounds) => {
                let reference = binary_exp_bounds_series(value, work + 296).unwrap()
                assert_true(burst_test_contains(bounds, reference))
              }
              None => ()
            }
          }
        }
      }
    }
  }
}

///|
test "table exp: large n and multiples of ln 2" {
  let ln2 = binary_ln2_bounds(400).unwrap().0
  for n in [1, 2, 3, 100, 1000, 100000, 1000000] {
    let value = ln2
      .mul(BinFloat::from_int(n, precision=40))
      .with_precision(200, RoundingMode::TowardNegative)
    let work = 160
    match binary_exp_bounds_table(value, work) {
      Some(bounds) => {
        let reference = binary_exp_bounds_series(value, work + 256).unwrap()
        assert_true(burst_test_contains(bounds, reference))
      }
      None => ()
    }
  }
}

///|
test "taylor kernel encloses exp(a / 2^f) for extreme and random remainders" {
  for (f, k) in [(80, 8), (180, 8), (300, 8), (500, 10), (1100, 11), (2100, 11)] {
    let limit = Coeff::one().shift_left(f - k)
    let candidates = [
      Coeff::zero(),
      Coeff::one(),
      Coeff::from_uint64(2UL),
      limit.sub_checked(Coeff::one()).unwrap(),
      limit.shift_right(1),
      burst_test_coefficient(f - k, 3UL).shift_right(1),
      burst_test_coefficient(f - k, 4UL),
      burst_test_coefficient(f - k - 5, 5UL),
    ]
    for a in candidates {
      guard a.compare(limit) < 0 else { continue }
      let (low, high) = binary_exp_taylor_fixed(a, f, k)
      let argument = BinFloat::make_coeff(a, -f, f + 8)
      let reference = binary_exp_bounds_series(argument, f + 256).unwrap()
      let pair = table_test_pair(low, high, f)
      assert_true(burst_test_contains(pair, reference))
      // And it is tight: at most 10 units wide.
      assert_true(
        high.sub_checked(low).unwrap().compare(Coeff::from_uint64(10UL)) <= 0,
      )
    }
  }
}

///|
test "table entries enclose exp(j / 2^k)" {
  for precision in [128, 192] {
    let table = binary_exp_table_get(precision, 4, 4).unwrap()
    for j in 0..<table.first_low.length() {
      let value = BinFloat::make_coeff(
        Coeff::from_uint64(j.to_uint64()),
        -4,
        64,
      )
      let reference = binary_exp_bounds_series(value, precision + 256).unwrap()
      let pair = table_test_pair(
        table.first_low[j],
        table.first_high[j],
        precision,
      )
      assert_true(burst_test_contains(pair, reference))
    }
    for j in 0..<table.second_low.length() {
      let value = BinFloat::make_coeff(
        Coeff::from_uint64(j.to_uint64()),
        -8,
        64,
      )
      let reference = binary_exp_bounds_series(value, precision + 256).unwrap()
      let pair = table_test_pair(
        table.second_low[j],
        table.second_high[j],
        precision,
      )
      assert_true(burst_test_contains(pair, reference))
    }
  }
}
