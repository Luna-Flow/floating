///|
fn basics_corpus(precision : Int32) -> Array[BallFloat] {
  let inf = @bin_float.BinFloat::inf(Sign::Positive, precision~)
  let ninf = @bin_float.BinFloat::inf(Sign::Negative, precision~)
  let values : Array[@bin_float.BinFloat] = [ninf]
  for d in [-7.25, -3.0, -1.0, -0.1, -0.0, 0.0, 0.3, 1.0, 2.5, 3.0] {
    values.push(@bin_float.BinFloat::from_double(d, precision~))
  }
  values.push(inf)
  let out : Array[BallFloat] = [empty_interval(precision)]
  for i in 0..<values.length() {
    for j in i..<values.length() {
      match BallFloat::try_from_bounds(values[i], values[j], precision~) {
        Ok(v) => out.push(v)
        Err(_) => ()
      }
    }
  }
  out
}

///|
test "interval basics: multiplication matches the 4/8-product original" {
  for precision in [24, 128] {
    let corpus = basics_corpus(precision)
    for a in corpus {
      for b in corpus {
        if a.is_empty() || b.is_empty() {
          continue
        }
        let p = Int32::max(a.precision_, b.precision_)
        let (lo, hi) = multiplication_bounds(a, b, p)
        let (olo, ohi) = old_multiplication_bounds(a, b, p)
        assert_eq(lo.to_string(), olo.to_string())
        assert_eq(hi.to_string(), ohi.to_string())
        assert_eq(lo.is_negative(), olo.is_negative())
        assert_eq(hi.is_negative(), ohi.is_negative())
      }
    }
  }
}

///|
test "interval basics: division matches the 4-division original" {
  for precision in [24, 128] {
    let corpus = basics_corpus(precision)
    for a in corpus {
      for b in corpus {
        if a.is_empty() || b.is_empty() || b.contains_zero() {
          continue
        }
        let p = Int32::max(a.precision_, b.precision_)
        let r = quotient_interval_nonzero_denominator(a, b, p)
        let o = old_quotient_interval_nonzero_denominator(a, b, p)
        assert_eq(r, o)
        assert_eq(r.lo_.is_negative(), o.lo_.is_negative())
        assert_eq(r.hi_.is_negative(), o.hi_.is_negative())
      }
    }
  }
}

///|
test "interval basics: sqrt matches the 4-root original" {
  for precision in [24, 128] {
    for a in basics_corpus(precision) {
      assert_eq(a.sqrt_interval(), a.old_sqrt_interval())
    }
  }
}

///|
test "interval basics: pown matches the original powers" {
  for precision in [24, 128] {
    for a in basics_corpus(precision) {
      if a.is_empty() {
        continue
      }
      for n in [1, 2, 3, 4, 5] {
        assert_eq(
          pown_positive(a, n, precision),
          old_pown_positive(a, n, precision),
        )
      }
    }
  }
}

///|
fn trig_corpus(precision : Int32) -> Array[BallFloat] {
  let values : Array[@bin_float.BinFloat] = []
  for
    d in [
      -5.3, -3.0, -2.5, -1.5, -1.0, -0.75, -0.5, -0.1, -0.0, 0.0, 0.2, 0.5, 0.6,
      1.0, 1.25, 1.5, 1.75, 2.0, 2.4, 3.0, 3.5, 4.5, 7.0,
    ] {
    values.push(@bin_float.BinFloat::from_double(d, precision~))
  }
  let out : Array[BallFloat] = [empty_interval(precision)]
  for i in 0..<values.length() {
    for j in i..<values.length() {
      match BallFloat::try_from_bounds(values[i], values[j], precision~) {
        Ok(v) => out.push(v)
        Err(_) => ()
      }
    }
  }
  out
}

///|
fn same_try(
  a : Result[BallFloat, @def.ArithmeticError],
  b : Result[BallFloat, @def.ArithmeticError],
) -> Unit raise {
  // Endpoints are compared as numbers: interval endpoints identify -0 and +0
  // (see `canonical_interval_endpoint`); a zero endpoint can come from either
  // end of a monotone range and keep the sign of its source.
  match (a, b) {
    (Ok(x), Ok(y)) => {
      assert_eq(x.lo_.compare(y.lo_), 0)
      assert_eq(x.hi_.compare(y.hi_), 0)
      if !x.lo_.is_zero() {
        assert_eq(x.lo_.to_string(), y.lo_.to_string())
      }
      if !x.hi_.is_zero() {
        assert_eq(x.hi_.to_string(), y.hi_.to_string())
      }
      assert_eq(x.precision_, y.precision_)
      assert_eq(x.is_empty(), y.is_empty())
    }
    (Err(_), Err(_)) => ()
    _ => fail("result kinds differ")
  }
}

///|
test "corner selection: sinpi and cospi match the four-call original" {
  for precision in [24, 80] {
    for a in trig_corpus(precision) {
      same_try(a.try_sinpi_interval(), a.old_try_sinpi_interval())
      same_try(a.try_cospi_interval(), a.old_try_cospi_interval())
    }
  }
}

///|
test "corner selection: atan2 matches the corner-and-axis hull" {
  for precision in [24, 80] {
    let corpus = trig_corpus(precision).filter(fn(v) { v.precision_ >= 0 })
    // a coarser sub-sample keeps the quadratic loop cheap
    let mut i = 0
    for a in corpus {
      i += 1
      if i % 3 != 0 {
        continue
      }
      let mut j = 0
      for b in corpus {
        j += 1
        if j % 3 != 1 {
          continue
        }
        same_try(a.try_atan2_interval(b), a.old_try_atan2_interval(b))
      }
    }
  }
}

///|
test "try_sin/cos/tan: native kernels give the rational-series hull" {
  for precision in [24, 80] {
    let corpus = trig_corpus(precision)
    let mut i = 0
    for a in corpus {
      i += 1
      if precision == 80 && i % 4 != 0 {
        continue
      }
      same_try(a.try_sin_interval(), a.old_try_sin_interval())
      same_try(a.try_cos_interval(), a.old_try_cos_interval())
      same_try(a.try_tan_interval(), a.old_try_tan_interval())
    }
  }
}

///|
test "try_sin/cos/tan: near critical points, large and tiny arguments" {
  let values = [
    1.5707963267948966, 1.5707963267948968, 1.5707963267948963, 3.141592653589793,
    3.1415926535897936, 4.71238898038469, 6.283185307179586, 100.0, 12345.678, 100000.0,
    1.0e-30, -1.0e-30, -1.5707963267948966, -3.141592653589793,
  ]
  for precision in [24, 53, 80] {
    let points = values.map(fn(d) {
      @bin_float.BinFloat::from_double(d, precision~)
    })
    for i in 0..<points.length() {
      for j in i..<points.length() {
        if j - i > 2 && j != points.length() - 1 {
          continue
        }
        match BallFloat::try_from_bounds(points[i], points[j], precision~) {
          Ok(v) => {
            same_try(v.try_sin_interval(), v.old_try_sin_interval())
            same_try(v.try_cos_interval(), v.old_try_cos_interval())
            same_try(v.try_tan_interval(), v.old_try_tan_interval())
          }
          Err(_) => ()
        }
      }
    }
  }
}
