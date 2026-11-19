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
