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
fn basics_table_bound(text : String, precision : Int32) -> @binary.Binary {
  if text == "inf" {
    @binary.Binary::inf(precision~)
  } else if text == "-inf" {
    @binary.Binary::inf(negative=true, precision~)
  } else {
    @binary.Binary::from_hex(text, 400).unwrap()
  }
}

///|
/// A bound of the table equals the bound of the interval; the sign of a zero is not compared.
fn basics_table_same(expected : @binary.Binary, got : @binary.Binary) -> Bool {
  if expected.classify() == FpClass::Infinity {
    got.classify() == FpClass::Infinity &&
    expected.is_sign_minus() == got.is_sign_minus()
  } else {
    got.classify() == FpClass::Finite && expected.compare(got) == 0
  }
}

///|
// oracle: A
// source: the hulls of the product, the quotient (denominator without zero) and the integer powers 1 to 5 over boxes made of -inf, -3, -0.1, 0, 0.3, 2.5, inf at 24 and 128 bits, and 600 random fma hulls and 400 random widths at 53 bits (c * 2^e, exponents -200 to 199, away from the bottom of the range), rounded outward, computed with Python fractions (tools/interval_basic_ops_oracle.py, table basic_ops_table_wbtest.mbt: 3,132 rows); this replaces the comparison with the pre-#378 copies of the product, quotient and pown bounds and the old formulas of fma and width, which shared the directed multiplication, division and power of Binary and exact_add_full and store_interval; the sign of a zero bound is checked by the zero sign tests
// shares: Binary::from_hex and String::split read the table; Interval::from_bounds, Binary::inf and Binary::from_hex build the operands
test "interval basics: product, quotient, powers, fma and width are the exact hulls" {
  let mut count = 0
  for line in basic_ops_table().split("\n") {
    let line = line.to_owned()
    if line == "" {
      continue
    }
    let f = line.split(" ").map(fn(s) { s.to_owned() }).collect()
    let precision = point_table_precision(f[1])
    let a = Interval::from_bounds(
      basics_table_bound(f[2], precision),
      basics_table_bound(f[3], precision),
      precision~,
    )
    if f[0] == "width" {
      assert_true(
        basics_table_same(basics_table_bound(f[4], precision), a.width()),
        msg=line,
      )
      count += 1
      continue
    }
    if f[0] == "fma" {
      let b = Interval::from_bounds(
        basics_table_bound(f[4], precision),
        basics_table_bound(f[5], precision),
        precision~,
      )
      let c = Interval::from_bounds(
        basics_table_bound(f[6], precision),
        basics_table_bound(f[7], precision),
        precision~,
      )
      let r = a.fma(b, c)
      assert_true(
        basics_table_same(basics_table_bound(f[8], precision), r.lo_),
        msg=line,
      )
      assert_true(
        basics_table_same(basics_table_bound(f[9], precision), r.hi_),
        msg=line,
      )
      count += 1
      continue
    }
    let (lo, hi) = if f[0] == "pown" {
      let r = pown_positive(a, point_table_precision(f[4]), precision)
      (r.lo_, r.hi_)
    } else {
      let b = Interval::from_bounds(
        basics_table_bound(f[4], precision),
        basics_table_bound(f[5], precision),
        precision~,
      )
      if f[0] == "mul" {
        multiplication_bounds(a, b, precision)
      } else {
        let r = quotient_interval_nonzero_denominator(a, b, precision)
        (r.lo_, r.hi_)
      }
    }
    assert_true(
      basics_table_same(basics_table_bound(f[6], precision), lo),
      msg=line,
    )
    assert_true(
      basics_table_same(basics_table_bound(f[7], precision), hi),
      msg=line,
    )
    count += 1
  }
  assert_eq(count, 3132)
}

///|
// oracle: A
// source: the hulls of sinpi and cospi over 253 intervals of 22 dyadic values (-21/4 to 7), and of atan2 over the boxes of 7 values and of the grid -2, -1, 0, 1, 2 (the whole range [-RU(pi), RU(pi)] across the half-line y = 0, x < 0, and the box of the origin empty), at 5 and 24 bits, from the directed p-bit values of MPFR at the endpoints, the extrema and the corners and axis points of the box (tools/interval_corner_oracle.py, table corner_table_wbtest.mbt); this replaces the comparison with the pre-#378 copies of the four-call selection, which shared the point functions try_sinpi_ctx, try_cospi_ctx and the certified atan2; the sign of a zero bound is checked by the zero sign tests
// shares: Binary::from_hex and String::split read the table; Interval::from_bounds builds the operands
test "corner selection: sinpi, cospi and atan2 are the hulls of the directed point values" {
  let mut count = 0
  for line in corner_table().split("\n") {
    let line = line.to_owned()
    if line == "" {
      continue
    }
    let f = line.split(" ").map(fn(s) { s.to_owned() }).collect()
    let precision = point_table_precision(f[1])
    let bound = fn(i : Int32) { basics_table_bound(f[i], precision) }
    let (result, last) = if f[0] == "atan2" {
      let y = Interval::from_bounds(bound(2), bound(3), precision~)
      let x = Interval::from_bounds(bound(4), bound(5), precision~)
      (y.try_atan2(x).unwrap(), 6)
    } else {
      let a = Interval::from_bounds(bound(2), bound(3), precision~)
      (
        if f[0] == "sinpi" {
          a.try_sinpi().unwrap()
        } else {
          a.try_cospi().unwrap()
        },
        4,
      )
    }
    if f[last] == "empty" {
      assert_true(result.is_empty(), msg=line)
    } else {
      assert_true(basics_table_same(bound(last), result.lo_), msg=line)
      assert_true(basics_table_same(bound(last + 1), result.hi_), msg=line)
    }
    count += 1
  }
  assert_eq(count, 3028)
  let empty = empty_interval(24)
  let one = Interval::from_bounds(
    @binary.Binary::one(precision=24),
    @binary.Binary::one(precision=24),
    precision=24,
  )
  assert_true(empty.try_sinpi().unwrap().is_empty())
  assert_true(empty.try_cospi().unwrap().is_empty())
  assert_true(empty.try_atan2(one).unwrap().is_empty())
  assert_true(one.try_atan2(empty).unwrap().is_empty())
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
// oracle: A
// source: sin, cos and tan of 2^3000 at 24 bits from MPFR 4.2.2 (mpfr_sin, mpfr_cos, mpfr_tan, rounded toward negative and toward positive, argument set exactly): sin in [-0xe7036ep-24, -0xe7036dp-24], cos in [-0x6e4ff68p-28, -0x6e4ff6p-24], tan in [0x2181bd8p-24, 0x2181bdcp-24], each the two floats around the true value, so the enclosure is the exact hull; the argument 2^8100000 is beyond the documented limit of the forward trigonometric functions (an engineering limit), so the three functions return Err
// shares: Binary::make, Binary::from_hex and Interval::from_bounds build the inputs and the expected ends; Binary::compare compares; try_sin, try_cos and try_tan are the code under test
test "try_sin/cos/tan: huge arguments around the cutoff stay sound" {
  let precision = 24
  let power = fn(e : Int32) {
    let x = @binary.Binary::make(@binary.BinCoeff::one(), e, precision)
    Interval::from_bounds(x, x, precision~)
  }
  let hex = fn(text : String) {
    @binary.Binary::from_hex(text, precision).unwrap()
  }
  let near = power(3000)
  let s = near.try_sin().unwrap()
  assert_true(s.lo_.compare(hex("-0xe7036ep-24")) == 0)
  assert_true(s.hi_.compare(hex("-0xe7036dp-24")) == 0)
  let c = near.try_cos().unwrap()
  assert_true(c.lo_.compare(hex("-0x6e4ff68p-28")) == 0)
  assert_true(c.hi_.compare(hex("-0x6e4ff6p-24")) == 0)
  let t = near.try_tan().unwrap()
  assert_true(t.lo_.compare(hex("0x2181bd8p-24")) == 0)
  assert_true(t.hi_.compare(hex("0x2181bdcp-24")) == 0)
  let beyond = power(8_100_000)
  assert_true(beyond.try_sin() is Err(_))
  assert_true(beyond.try_cos() is Err(_))
  assert_true(beyond.try_tan() is Err(_))
}

///|
// `is_common_interval` once called itself after `is_bounded` was folded into
// it, so every caller looped forever (found by the documentation examples,
// which reached it through the decimal elementary functions).
// oracle: A
// source: written out by hand from IEEE 1788-2015 10.6.3 (isCommonInterval) and the definition of a common interval (nonempty and bounded): [-1, 1] and the point [1, 1] are common; Empty, Entire, [1, inf) and (-inf, 1] are not
// shares: Binary::one, Binary::inf, Interval::from_bounds, Interval::exact, Interval::empty and Interval::entire (to build the inputs)
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
