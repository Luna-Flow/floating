///|
/// Deterministic range-boundary cases for the #378 changes (random testing
/// cannot reach these exponents). Expected values come from the test-only
/// copies of the code before #378, never from the new code alone.
test "round core agrees with the old one at the exponent limits and carries" {
  let lowest = binary_implementation_e_min
  let highest = binary_implementation_e_max
  let contexts : Array[BinaryContext] = []
  for
    mode in [
      BinaryRoundingMode::RoundTiesToEven,
      BinaryRoundingMode::RoundTiesToAway,
      BinaryRoundingMode::RoundTowardZero,
      BinaryRoundingMode::RoundTowardPositive,
      BinaryRoundingMode::RoundTowardNegative,
    ] {
    for
      tininess in [
        TininessDetection::BeforeRounding,
        TininessDetection::AfterRounding,
      ] {
      contexts.push(BinaryContext::binary32(rounding=mode, tininess~))
      contexts.push(BinaryContext::binary64(rounding=mode, tininess~))
      contexts.push(
        BinaryContext::new(precision=5, rounding=mode, e_max=10, tininess~),
      )
    }
    for p in [1, 2, 24, 53, 130] {
      contexts.push(BinaryContext::new(precision=p, rounding=mode))
    }
  }
  let mut checked = 0
  for context in contexts {
    let p = context.precision()
    let e_min = context.e_min()
    let e_max = context.e_max()
    // Magnitudes: all ones (carry to a power of two), all ones plus one low
    // bit (halfway and just above), a power of two, and a short odd value.
    let all_ones = Coeff::one().shift_left(p).sub_checked(Coeff::one()).unwrap()
    let magnitudes = [
      all_ones,
      all_ones.shift_left(1).add(Coeff::one()),
      all_ones.shift_left(3).add(Coeff::from_uint64(4UL)),
      Coeff::one().shift_left(p + 2),
      Coeff::from_uint64(3UL),
      Coeff::one(),
    ]
    for magnitude in magnitudes {
      let bits = magnitude.bit_length()
      // Top bit around e_min (subnormal boundary), e_max, and the
      // implementation limits.
      for
        top in [
          lowest - 3,
          lowest,
          lowest + 2,
          e_min - p - 2,
          e_min - p,
          e_min - 1,
          e_min,
          e_min + 1,
          e_max - 1,
          e_max,
          e_max + 1,
          highest - 1,
          highest,
        ] {
        let exponent2 = top - (bits - 1)
        for negative in [false, true] {
          let fresh = binary_round_dyadic(
            negative, magnitude, exponent2, context,
          )
          let old = old_round_dyadic(negative, magnitude, exponent2, context)
          assert_true(
            fresh.0 == old.0,
            msg="value top=\{top} bits=\{bits} p=\{p}",
          )
          assert_true(
            fresh.1 == old.1,
            msg="flags top=\{top} bits=\{bits} p=\{p}",
          )
          checked += 1
        }
      }
    }
  }
  assert_true(checked > 4000)
}

///|
test "hyperbolic bounds agree with the old kernel where exp leaves the range" {
  // exp(x) overflows the implementation range from x about 7.45e8 and
  // underflows from -7.45e8; cosh and sinh are exp(|x|)/2 there.
  for
    d in [
      1.0e-300, 4.0e-9, 0.5, 5.0e8, 7.0e8, 7.4e8, 7.45e8, 7.5e8, 9.0e8, 2.0e9, 1.0e12,
    ] {
    for sign in [1.0, -1.0] {
      let x = BinFloat::from_double(d * sign, precision=53)
      for w in [64, 128] {
        for
          op in [
            BinaryHyperbolicOperation::Sinh,
            BinaryHyperbolicOperation::Cosh,
            BinaryHyperbolicOperation::Tanh,
          ] {
          let fresh = binary_hyperbolic_bounds(x, op, w)
          let old = old_hyperbolic_bounds(x, op, w)
          match (fresh, old) {
            (Some(f), Some(o)) => {
              // Same validity: new encloses the high-precision old enclosure
              // (when that one exists) and is not crossed.
              assert_true(f.0.compare(f.1) <= 0, msg="crossed \{x} \{w}")
              match old_hyperbolic_bounds(x, op, w + 128) {
                Some(r) =>
                  // The old tanh yields a NaN end (inf / inf) where the
                  // enclosure is useless anyway; the new one is [0, inf].
                  if !r.0.is_quiet_nan() && !r.1.is_quiet_nan() {
                    assert_true(f.0.compare(r.0) <= 0, msg="lower \{x} \{w}")
                    assert_true(f.1.compare(r.1) >= 0, msg="upper \{x} \{w}")
                  }
                None => ()
              }
              ignore(o)
            }
            (None, None) => ()
            (Some(_), None) => ()
            (None, Some(_)) =>
              fail(
                "new lost a certification the old kernel had at x=\{x} w=\{w}",
              )
          }
        }
      }
    }
  }
}

///|
test "trigonometric bounds agree with the old path around pi/4 and at extreme exponents" {
  let pi4 = 0.7853981633974483
  let tiny = BinFloat::make_coeff(Coeff::one(), -1073741000, 64)
  let near_values : Array[BinFloat] = [tiny, tiny.neg()]
  // Around pi/4 at working-precision neighbours, both signs.
  for w in [64, 117, 200] {
    let base = BinFloat::from_double(pi4, precision=w)
    for k in -3..<4 {
      let ulp = BinFloat::make_coeff(Coeff::one(), base.exponent2(), w)
      let v = base.add_ctx(
          ulp.mul_ctx(
            BinFloat::from_int(k, precision=w),
            BinaryContext::new(precision=w + 8),
          ).0,
          BinaryContext::new(precision=w),
        ).0
      near_values.push(v)
      near_values.push(v.neg())
    }
  }
  for x in near_values {
    for w in [64, 128, 300] {
      for
        op in [
          BinaryTrigonometricOperation::Sin,
          BinaryTrigonometricOperation::Cos,
          BinaryTrigonometricOperation::Tan,
        ] {
        let fresh = binary_trigonometric_bounds_series(x, op, w)
        let old = old_trigonometric_bounds_series(x, op, w)
        match (fresh, old) {
          (Some(_), Some(_)) =>
            assert_true(
              binary_series_agree(fresh, old, x, w, op),
              msg="trig \{x} w=\{w}",
            )
          (None, None) => ()
          _ => fail("presence differs \{x} w=\{w}")
        }
      }
    }
  }
}

///|
test "sign-aware corners agree with the old ones when products overflow and quotients underflow" {
  let huge = BinFloat::make_coeff(Coeff::from_uint64(3UL), 1073741000, 64)
  let small = BinFloat::make_coeff(Coeff::from_uint64(5UL), -1073741000, 64)
  let values = [
    huge,
    huge.neg(),
    small,
    small.neg(),
    BinFloat::from_int(1, precision=64),
  ]
  for w in [53, 130] {
    let down = BinaryContext::new(precision=w, rounding=RoundTowardNegative)
    let up = BinaryContext::new(precision=w, rounding=RoundTowardPositive)
    for a0 in values {
      for a1 in values {
        for b0 in values {
          for b1 in values {
            if a0.compare(a1) <= 0 && b0.compare(b1) <= 0 {
              let f = binary_product_bounds((a0, a1), (b0, b1), down, up)
              let o = old_product_bounds((a0, a1), (b0, b1), down, up)
              assert_true(f.0 == o.0 && f.1 == o.1, msg="product")
              let fq = binary_quotient_bounds((a0, a1), (b0, b1), down, up)
              let oq = old_quotient_bounds((a0, a1), (b0, b1), down, up)
              match (fq, oq) {
                (Some(x), Some(y)) =>
                  assert_true(x.0 == y.0 && x.1 == y.1, msg="quotient")
                (None, None) => ()
                _ => fail("quotient presence")
              }
            }
          }
        }
      }
    }
  }
}
