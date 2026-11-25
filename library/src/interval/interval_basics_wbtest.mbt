///|
fn basics_corpus(precision : Int32) -> Array[Interval] {
  let inf = @binary.Binary::inf(precision~)
  let ninf = @binary.Binary::inf(negative=true, precision~)
  let values : Array[@binary.Binary] = [ninf]
  for d in [-7.25, -3.0, -1.0, -0.1, -0.0, 0.0, 0.3, 1.0, 2.5, 3.0] {
    values.push(@binary.Binary::from_double(d, precision~))
  }
  values.push(inf)
  let out : Array[Interval] = [empty_interval(precision)]
  for i in 0..<values.length() {
    for j in i..<values.length() {
      match Interval::try_from_bounds(values[i], values[j], precision~) {
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
        assert_eq(lo.is_sign_minus(), olo.is_sign_minus())
        assert_eq(hi.is_sign_minus(), ohi.is_sign_minus())
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
        assert_eq(r.lo_.is_sign_minus(), o.lo_.is_sign_minus())
        assert_eq(r.hi_.is_sign_minus(), o.hi_.is_sign_minus())
      }
    }
  }
}

///|
fn sqrt_expected_end(
  coefficient : String,
  exponent : Int32,
  precision : Int32,
) -> @binary.Binary {
  @binary.Binary::make(
    @binary.BinCoeff::parse(coefficient).unwrap(),
    exponent,
    precision,
  )
}

///|
fn sqrt_point_interval(lo : Double, hi : Double, precision : Int32) -> Interval {
  Interval::from_bounds(
    @binary.Binary::from_double(lo, precision~),
    @binary.Binary::from_double(hi, precision~),
    precision~,
  )
}

///|
fn sqrt_check(
  a : Interval,
  lo : @binary.Binary,
  hi : @binary.Binary,
) -> Unit raise {
  let r = a.sqrt()
  assert_false(r.is_empty())
  assert_eq(r.lo_.compare(lo), 0)
  assert_eq(r.hi_.compare(hi), 0)
}

///|
// oracle: A
// source: endpoint values written out: exact roots (1, 2, 3, 4, 1/2, 3/2) and the directed bounds of the
//   irrational roots of 2, 3 and 5/2 at 24 and 128 bits as p-bit integers computed outside this repository
//   by Python 3 math.isqrt on exact integers (floor, and floor + 1 for an irrational root); this library
//   produced none of them
// shares: nothing
test "interval basics: sqrt endpoints are the directed square roots" {
  for precision in [24, 128] {
    // exact squares, both ends
    sqrt_check(
      sqrt_point_interval(1.0, 1.0, precision),
      @binary.Binary::from_int(1, precision~),
      @binary.Binary::from_int(1, precision~),
    )
    sqrt_check(
      sqrt_point_interval(4.0, 9.0, precision),
      @binary.Binary::from_int(2, precision~),
      @binary.Binary::from_int(3, precision~),
    )
    sqrt_check(
      sqrt_point_interval(0.25, 2.25, precision),
      @binary.Binary::from_double(0.5, precision~),
      @binary.Binary::from_double(1.5, precision~),
    )
    // a lower end at or below zero gives zero; a negative interval is empty
    sqrt_check(
      sqrt_point_interval(0.0, 16.0, precision),
      @binary.Binary::zero(precision~),
      @binary.Binary::from_int(4, precision~),
    )
    sqrt_check(
      sqrt_point_interval(-1.0, 4.0, precision),
      @binary.Binary::zero(precision~),
      @binary.Binary::from_int(2, precision~),
    )
    assert_true(sqrt_point_interval(-3.0, -1.0, precision).sqrt().is_empty())
    assert_true(Interval::empty(precision~).sqrt().is_empty())
  }
  // the irrational roots, directed outward
  let p24 = 24
  sqrt_check(
    sqrt_point_interval(2.0, 3.0, p24),
    sqrt_expected_end("11863283", -23, p24),
    sqrt_expected_end("14529496", -23, p24),
  )
  sqrt_check(
    sqrt_point_interval(2.5, 2.5, p24),
    sqrt_expected_end("13263553", -23, p24),
    sqrt_expected_end("13263554", -23, p24),
  )
  let p128 = 128
  sqrt_check(
    sqrt_point_interval(2.0, 3.0, p128),
    sqrt_expected_end("240615969168004511545033772477625056927", -127, p128),
    sqrt_expected_end("294693174213430241384087455685767077317", -127, p128),
  )
  sqrt_check(
    sqrt_point_interval(2.5, 2.5, p128),
    sqrt_expected_end("269016831765825801719526439316123156306", -127, p128),
    sqrt_expected_end("269016831765825801719526439316123156307", -127, p128),
  )
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
fn trig_corpus(precision : Int32) -> Array[Interval] {
  let values : Array[@binary.Binary] = []
  for
    d in [
      -5.3, -3.0, -2.5, -1.5, -1.0, -0.75, -0.5, -0.1, -0.0, 0.0, 0.2, 0.5, 0.6,
      1.0, 1.25, 1.5, 1.75, 2.0, 2.4, 3.0, 3.5, 4.5, 7.0,
    ] {
    values.push(@binary.Binary::from_double(d, precision~))
  }
  let out : Array[Interval] = [empty_interval(precision)]
  for i in 0..<values.length() {
    for j in i..<values.length() {
      match Interval::try_from_bounds(values[i], values[j], precision~) {
        Ok(v) => out.push(v)
        Err(_) => ()
      }
    }
  }
  out
}

///|
fn same_try(
  a : Result[Interval, @def.ArithmeticError],
  b : Result[Interval, @def.ArithmeticError],
) -> Unit raise {
  // Bit for bit, including the sign of a zero endpoint.
  match (a, b) {
    (Ok(x), Ok(y)) => {
      assert_eq(x, y)
      assert_eq(x.lo_.to_string(), y.lo_.to_string())
      assert_eq(x.hi_.to_string(), y.hi_.to_string())
      assert_eq(x.lo_.is_sign_minus(), y.lo_.is_sign_minus())
      assert_eq(x.hi_.is_sign_minus(), y.hi_.is_sign_minus())
    }
    (Err(_), Err(_)) => ()
    _ => fail("result kinds differ")
  }
}

///|
test "corner selection: sinpi and cospi match the four-call original" {
  for precision in [24, 80] {
    for a in trig_corpus(precision) {
      same_try(a.try_sinpi(), a.old_try_sinpi_interval())
      same_try(a.try_cospi(), a.old_try_cospi_interval())
    }
  }
}

///|
test "corner selection: atan2 matches the corner-and-axis hull" {
  for precision in [24] {
    let corpus = trig_corpus(precision).filter(fn(v) { v.precision_ >= 0 })
    // a coarser sub-sample keeps the quadratic loop cheap
    let mut i = 0
    for a in corpus {
      i += 1
      if i % 13 != 0 {
        continue
      }
      let mut j = 0
      for b in corpus {
        j += 1
        if j % 11 != 1 {
          continue
        }
        same_try(a.try_atan2(b), a.old_try_atan2_interval(b))
      }
    }
  }
}

///|
// oracle: B
// source: the expected gcd of each pair of small integers comes from the Euclidean algorithm written in the test on Int (a different algorithm from the shift and big-integer gcd of the code); the two large cases are written out: gcd(3 * 2^200, 2^150) = 2^150 (3 is odd, so the power of two is the whole common factor), in both orders
// shares: BinCoeff::from_uint64, coeff_shift_left, coeff_one and BinCoeff compare (constructing and comparing exact integers)
// primitives: BinCoeff::from_uint64 and compare, exact on the integers used
test "coeff_gcd: power-of-two shortcut equals the general gcd" {
  let nums = [1, 2, 3, 4, 6, 8, 12, 40, 96, 1024, 1536, 65536, 1000003]
  for a in nums {
    for b in nums {
      let x = @binary.BinCoeff::from_uint64(a.to_uint64())
      let y = @binary.BinCoeff::from_uint64(b.to_uint64())
      let expected = @binary.BinCoeff::from_uint64(euclid_gcd(a, b).to_uint64())
      assert_eq(coeff_gcd(x, y).compare(expected), 0)
    }
  }
  let big = coeff_shift_left(@binary.BinCoeff::from_uint64(3UL), 200)
  let pow = coeff_shift_left(coeff_one(), 150)
  assert_eq(coeff_gcd(big, pow).compare(pow), 0)
  assert_eq(coeff_gcd(pow, big).compare(pow), 0)
}

///|
fn euclid_gcd(a : Int32, b : Int32) -> Int32 {
  let mut x = a
  let mut y = b
  while y != 0 {
    let t = x % y
    x = y
    y = t
  }
  x
}

///|
test "corner selection: atan2 on every box of a sign-complete grid" {
  let precision = 24
  let grid = [-2.0, -1.0, 0.0, 1.0, 2.0].map(fn(d) {
    @binary.Binary::from_double(d, precision~)
  })
  let boxes : Array[Interval] = []
  for i in 0..<grid.length() {
    for j in i..<grid.length() {
      boxes.push(Interval::from_bounds(grid[i], grid[j], precision~))
    }
  }
  for a in boxes {
    for b in boxes {
      same_try(a.try_atan2(b), a.old_try_atan2_interval(b))
    }
  }
}

///|
test "try_sin/cos/tan: huge arguments around the cutoff stay sound" {
  let precision = 24
  let power = fn(e : Int32) {
    let x = @binary.Binary::make(@binary.BinCoeff::one(), e, precision)
    Interval::from_bounds(x, x, precision~)
  }
  let unit = unit_interval(precision)
  let near = power(3000)
  assert_true(near.try_sin().unwrap().subset(unit))
  assert_true(near.try_cos().unwrap().subset(unit))
  assert_true(near.try_tan() is Ok(_))
  let beyond = power(8_100_000)
  assert_true(beyond.try_sin() is Err(_))
  assert_true(beyond.try_cos() is Err(_))
  assert_true(beyond.try_tan() is Err(_))
}

///|
/// `is_common_interval` once called itself after `is_bounded` was folded into
/// it, so every caller looped forever (found by the documentation examples,
/// which reached it through the decimal elementary functions).
// oracle: A
// source: written out by hand from IEEE 1788-2015 10.6.3 (isCommonInterval) and the definition of a common interval (nonempty and bounded): [-1, 1] and the point [1, 1] are common; Empty, Entire, [1, inf) and (-inf, 1] are not
// shares: nothing

///|
test "is_common_interval terminates and classifies the shapes" {
  let one = @binary.Binary::one(precision=53)
  let inf = @binary.Binary::inf(precision=53)
  assert_true(
    Interval::from_bounds(one.neg(), one, precision=53).is_common_interval(),
  )
  assert_true(Interval::exact(one, precision=53).is_common_interval())
  assert_false(Interval::empty(precision=53).is_common_interval())
  assert_false(Interval::entire(precision=53).is_common_interval())
  assert_false(
    Interval::from_bounds(one, inf, precision=53).is_common_interval(),
  )
  assert_false(
    Interval::from_bounds(inf.neg(), one, precision=53).is_common_interval(),
  )
}
