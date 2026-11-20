///|
fn burst_trig_test_corpus() -> Array[BinFloat] {
  let values : Array[BinFloat] = []
  let mut seed = 5000UL
  for bits in [60, 130, 256, 400, 700, 1100, 2000] {
    for top in [-60, -20, -8, -3, -1, 0, 1, 2, 3, 5, 8, 12, 20, 40, 100] {
      values.push(burst_test_value(bits, top, false, seed))
      seed += 1UL
      values.push(burst_test_value(bits, top, true, seed))
      seed += 1UL
    }
  }
  // Arguments next to multiples of pi / 2.
  let (pi_low, _) = binary_pi_bounds(2400).unwrap()
  for bits in [100, 300, 700, 1500] {
    let half_pi = pi_low.mul_ctx(
      BinFloat::make_coeff(Coeff::one(), -1, 1),
      BinaryContext::unbounded(2400),
    ).0.with_precision(bits, RoundingMode::TowardNegative)
    for k in [1, 2, 3, 4, 5, 7, 100, 12345, 1000003] {
      let product = half_pi.mul_ctx(
          BinFloat::from_int(k, precision=32),
          BinaryContext::unbounded(bits + 40),
        ).0
      let context = BinaryContext::unbounded(bits + 40)
      values.push(product)
      values.push(product.neg())
      values.push(product.next_up_ctx(context).0)
      values.push(product.next_down_ctx(context).0)
    }
  }
  values
}

///|
/// The enclosure of the series path at a precision that certifies the quadrant
/// and is 256 bits beyond the burst working precision.
fn burst_trig_test_reference(
  value : BinFloat,
  cosine : Bool,
  work : Int32,
) -> (BinFloat, BinFloat)? {
  let top = Int32::max(0, binary_top_bound(value).to_int())
  let reference_work = Int32::max(work, value.precision() + top + 96) + 256
  binary_trigonometric_bounds_series(
    value,
    if cosine {
      BinaryTrigonometricOperation::Cos
    } else {
      BinaryTrigonometricOperation::Sin
    },
    reference_work,
  )
}

///|
test "bit-burst sin and cos contain the series enclosure at higher precision" {
  let mut checked = 0
  for value in burst_trig_test_corpus() {
    for cosine in [false, true] {
      let work = burst_test_work(value.precision())
      match binary_trig_bounds_burst(value, cosine, work) {
        Some(bounds) =>
          match burst_trig_test_reference(value, cosine, work) {
            Some(reference) => {
              assert_true(burst_test_contains(bounds, reference))
              checked += 1
            }
            None => ()
          }
        None => ()
      }
    }
  }
  assert_true(checked > 300)
}

///|
test "bit-burst sin and cos are no wider than the series enclosure" {
  for value in burst_trig_test_corpus() {
    for cosine in [false, true] {
      let work = burst_test_work(value.precision())
      let top = Int32::max(0, binary_top_bound(value).to_int())
      // The series path certifies the quadrant from this precision on.
      let series_work = Int32::max(work, value.precision() + top + 96)
      match binary_trig_bounds_burst(value, cosine, series_work) {
        Some((low, high)) =>
          match
            binary_trigonometric_bounds_series(
              value,
              if cosine {
                BinaryTrigonometricOperation::Cos
              } else {
                BinaryTrigonometricOperation::Sin
              },
              series_work,
            ) {
            Some((series_low, series_high)) =>
              assert_true(
                high.sub(low).compare(series_high.sub(series_low)) <= 0,
              )
            None => ()
          }
        None => ()
      }
    }
  }
}

///|
test "bit-burst sin and cos decline outside their range" {
  let work = 512
  for cosine in [false, true] {
    assert_true(
      binary_trig_bounds_burst(BinFloat::zero(precision=64), cosine, work)
      is None,
    )
    assert_true(
      binary_trig_bounds_burst(
        BinFloat::make_coeff(Coeff::one(), -200, 1),
        cosine,
        work,
      )
      is None,
    )
    assert_true(
      binary_trig_bounds_burst(BinFloat::inf(Sign::Positive), cosine, work)
      is None,
    )
    assert_true(binary_trig_bounds_burst(BinFloat::nan(), cosine, work) is None)
    // 2^5000 is beyond the range of the kernel.
    assert_true(
      binary_trig_bounds_burst(
        BinFloat::make_coeff(Coeff::one(), 5000, 1),
        cosine,
        work,
      )
      is None,
    )
  }
}

///|
test "mutated bit-burst sin and cos are caught by the containment test" {
  let value = burst_test_value(2000, 0, false, 8080UL)
  let work = 2064
  for cosine in [false, true] {
    let reference = burst_trig_test_reference(value, cosine, work).unwrap()
    assert_true(
      burst_test_contains(
        binary_trig_bounds_burst(value, cosine, work).unwrap(),
        reference,
      ),
    )
    let biased = { mid_bias_bits: 64, split_reduce_terms: 0, pi_drop_bits: 0, }
    assert_true(
      burst_test_caught(
        binary_trig_bounds_burst(value, cosine, work, mutation=biased),
        reference,
      ),
    )
    let shortened = {
      mid_bias_bits: 0,
      split_reduce_terms: 40,
      pi_drop_bits: 0,
    }
    assert_true(
      burst_test_caught(
        binary_trig_bounds_burst(value, cosine, work, mutation=shortened),
        reference,
      ),
    )
  }
  // A reduction with too few bits of pi for a large argument.
  let large = burst_test_value(2000, 40, false, 8081UL)
  let large_reference = burst_trig_test_reference(large, false, work).unwrap()
  assert_true(
    burst_test_contains(
      binary_trig_bounds_burst(large, false, work).unwrap(),
      large_reference,
    ),
  )
  let coarse = { mid_bias_bits: 0, split_reduce_terms: 0, pi_drop_bits: 200, }
  assert_true(
    burst_test_caught(
      binary_trig_bounds_burst(large, false, work, mutation=coarse),
      large_reference,
    ),
  )
}

///|
test "sin and cos results equal the rounded series enclosure at high precision" {
  let modes = [
    RoundTiesToEven,
    RoundTowardZero,
    RoundTowardPositive,
    RoundTowardNegative,
  ]
  let mut seed = 9100UL
  let mut compared = 0
  for bits in [200, 300, 513, 640, 1000, 1024, 1536] {
    for top in [-20, -3, -1, 0, 1, 2, 5, 12, 40] {
      for negative in [false, true] {
        seed += 1UL
        let value = burst_test_value(bits, top, negative, seed)
        // The reference enclosure does not depend on the rounding mode: compute
        // it once per value and function (it was recomputed for each mode).
        for cosine in [false, true] {
          let reference_bounds = burst_trig_test_reference(
            value,
            cosine,
            2 * bits + 200,
          )
          match reference_bounds {
            Some((low, high)) =>
              for mode in modes {
                let context = BinaryContext::unbounded(bits, rounding=mode)
                let (expected, unique, expected_flags) = binary_certified_inexact_target_rounding(
                  low, high, context,
                )
                if unique {
                  let (result, flags) = if cosine {
                    value.cos_ctx(context)
                  } else {
                    value.sin_ctx(context)
                  }
                  assert_true(result == expected)
                  assert_true(flags == expected_flags)
                  compared += 1
                }
              }
            None => ()
          }
        }
      }
    }
  }
  assert_true(compared > 400)
}
