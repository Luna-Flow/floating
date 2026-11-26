///|
fn pw_num(x : Double, precision : Int32) -> @binary.Binary {
  @binary.Binary::from_double(x, precision~).with_precision(
    precision,
    @binary.BinaryRoundingMode::RoundTiesToEven,
  )
}

///|
fn pw_box(
  lo : @binary.Binary,
  hi : @binary.Binary,
  precision : Int32,
) -> Interval {
  Interval::from_bounds(lo, hi, precision~)
}

///|
fn pw_ival(lo : Double, hi : Double, precision : Int32) -> Interval {
  pw_box(pw_num(lo, precision), pw_num(hi, precision), precision)
}

///|
let pw_inf : Double = 1.0 / 0.0

///|
fn pw_same(a : Interval, lo : Double, hi : Double) -> Bool {
  !a.is_empty() &&
  a.lo_.compare(@binary.Binary::from_double(lo)) == 0 &&
  a.hi_.compare(@binary.Binary::from_double(hi)) == 0
}

///|
fn pw_class_is_dyadic(cls : PowClass, value : Double) -> Bool {
  match cls {
    Dyadic(v) => v.compare(@binary.Binary::from_double(value)) == 0
    _ => false
  }
}

///|
// oracle: A
// source: roots worked by hand and written as literals: 0.25^(1/-2) = 2, 8^(1/3) = 2, 8^2 = 64, 2^-1 = 1/2, 81^(1/4) = 3, 16^(1/-4) = 1/2, 2.25^(1/2) = 3/2, 9^(1/-2) = 1/3 (rational, denominator 3); 2^(1/2), 10^(1/3) and 2^(1/3) are irrational by unique factorisation; (2^1000 + 1)^2 has the root 2^1000 + 1; a coefficient of pow_int_budget + 11 bits gives Unknown (the documented budget, an engineering limit)
// shares: pw_ival, pw_num (Binary::from_double and Interval::from_bounds) and the BinCoeff helpers build the inputs; the comparisons compare; pow_rev1 and the class functions are the code under test
test "classes of c^(1/beta): dyadic, rational and not dyadic, irrational, over the budget" {
  let p = 53
  let n = fn(x : Double) { pw_num(x, p) }
  // 0.25^(1/-2) = 2, 8^(1/3) = 2, 8^2 = 64 (beta = 1/2), 2^(1/-1) = 1/2, c = 1
  assert_true(pw_class_is_dyadic(pow_end_class(n(0.25), n(-2.0), p), 2.0))
  assert_true(pw_class_is_dyadic(pow_end_class(n(8.0), n(3.0), p), 2.0))
  assert_true(pw_class_is_dyadic(pow_end_class(n(8.0), n(0.5), p), 64.0))
  assert_true(pw_class_is_dyadic(pow_end_class(n(2.0), n(-1.0), p), 0.5))
  assert_true(pw_class_is_dyadic(pow_end_class(n(1.0), n(-7.5), p), 1.0))
  // 81^(1/4) = 3, 16^(1/-4) = 1/2, 4^(1/2) = 2, (9/4)^(1/2) = 3/2
  assert_true(pw_class_is_dyadic(pow_end_class(n(81.0), n(4.0), p), 3.0))
  assert_true(pw_class_is_dyadic(pow_end_class(n(16.0), n(-4.0), p), 0.5))
  assert_true(pw_class_is_dyadic(pow_end_class(n(4.0), n(2.0), p), 2.0))
  assert_true(pw_class_is_dyadic(pow_end_class(n(2.25), n(2.0), p), 1.5))
  // 9^(1/-2) = 1/3: rational and not a float
  match pow_end_class(n(9.0), n(-2.0), p) {
    Rational(den, exp2) => {
      assert_true(den.to_uint64() == Some(3UL))
      assert_eq(exp2, 0)
    }
    _ => fail("9^(1/-2) must be the rational 1/3")
  }
  // irrational: 2^(1/2), 10^(1/3), 2^(1/3), a beta of 70 bits
  assert_true(pow_end_class(n(2.0), n(2.0), p) is Irrational)
  assert_true(pow_end_class(n(10.0), n(3.0), p) is Irrational)
  assert_true(pow_end_class(n(2.0), n(3.0), p) is Irrational)
  let big_beta = @binary.Binary::make(@binary.BinCoeff::from_uint64(3UL), 70, p)
  assert_true(pow_end_class(n(5.0), big_beta, p) is Irrational)
  // an odd part that is huge: over the budget of the integer test
  let wide = @binary.Binary::make(
    coeff_add(coeff_shift_left(coeff_one(), pow_int_budget + 10), coeff_one()),
    0,
    pow_int_budget + 20,
  )
  assert_true(pow_end_class(wide, n(2.0), p) is Unknown)
  // a 2000-bit perfect square: the root is exact
  let root = coeff_add(coeff_shift_left(coeff_one(), 1000), coeff_one())
  let square = @binary.Binary::make(coeff_mul(root, root), 0, 2100)
  match pow_end_class(square, n(2.0), p) {
    Dyadic(v) => assert_true(v.coefficient().compare(root) == 0)
    _ => fail("the square root of a 2000-bit square is exact")
  }
}

///|
// oracle: A
// source: written out by hand: 1/3 at 8 bits lies between 1.0101010b * 2^-2 = 0.33203125 and 1.0101011b * 2^-2 = 0.333984375; 1/3 is above 1/4 and below 1/2, above the double nearest to it (which lies below 1/3) and below the next double; 1024/3 lies between 341 and 342; 1/3 is above -1
// shares: pw_ival, pw_num (Binary::from_double and Interval::from_bounds) and the BinCoeff helpers build the inputs; the comparisons compare; pow_rev1 and the class functions are the code under test
// oracle: A
// source: worked by hand: 1/3 = 0.010101...b is not a float; at 53 bits RD(1/3) = 0x1.5555555555555p-2 and the next float up 0x1.5555555555556p-2 is above it; at 8 bits RD = 1.0101010b * 2^-2 = 0.33203125 and RU = 1.0101011b * 2^-2 = 0.333984375; 1/3 * 2^10 lies between 341 and 342
// shares: pw_num, Binary::from_double and the BinCoeff constructor build the inputs; the integer comparisons compare; pow_rational_compare and pow_rational_round are the code under test
test "rational class: comparison and directed rounding of 2^E / D" {
  let three = @binary.BinCoeff::from_uint64(3UL)
  let third = pw_num(0x1.5555555555555p-2, 53)
  assert_eq(pow_rational_compare(three, 0, pw_num(0.25, 53)), 1)
  assert_eq(pow_rational_compare(three, 0, pw_num(0.5, 53)), -1)
  // 1/3 against the two floats around it: strict
  assert_eq(pow_rational_compare(three, 0, third), 1)
  assert_eq(
    pow_rational_compare(three, 0, pw_num(0x1.5555555555556p-2, 53)),
    -1,
  )
  let down = pow_rational_round(three, 0, false, 8)
  let up = pow_rational_round(three, 0, true, 8)
  assert_true(down.compare(@binary.Binary::from_double(0.33203125)) == 0)
  assert_true(up.compare(@binary.Binary::from_double(0.333984375)) == 0)
  // 1/3 * 2^10 and a negative or zero float
  assert_eq(pow_rational_compare(three, 10, pw_num(341.0, 53)), 1)
  assert_eq(pow_rational_compare(three, 10, pw_num(342.0, 53)), -1)
  assert_eq(pow_rational_compare(three, 0, pw_num(-1.0, 53)), 1)
}

///|
// oracle: A
// source: worked by hand from Table 10.1: x^2 = 4 gives 2, x^-2 = 1/4 gives 2, 9^(1/2) = 3, 9^(1/-2) = 1/3 (not a float: RD(1/3) = 0x1.5555555555555p-2, RU = 0x1.5555555555556p-2), 0^beta = 0 for beta > 0, x^0 = 1 for every x > 0 (0^0 is undefined), 1^beta = 1, empty operands and a negative c give Empty; for beta in [-4, -2] and c in [1/4, 1/2] the set is [2^(1/4), 2] (0.5^(1/-4) and 0.25^(1/-2)), where 2^(1/4) = 1.189207115002721... has RD 0x1.306FE0A31B715p0 at 53 bits (Python decimal at 80 digits)
// shares: pw_ival, pw_num (Binary::from_double and Interval::from_bounds) build the inputs; the comparisons compare; pow_rev1 is the code under test
test "pow_rev1: the examples that fix the definition, with exact and rounded ends" {
  let p = 53
  // x^2 in [4, 4] with x > 0: x = 2
  assert_true(
    pw_same(pw_ival(2.0, 2.0, p).pow_rev1(pw_ival(4.0, 4.0, p)), 2.0, 2.0),
  )
  // x^(-2) in [0.25, 0.25]: x = 2
  assert_true(
    pw_same(pw_ival(-2.0, -2.0, p).pow_rev1(pw_ival(0.25, 0.25, p)), 2.0, 2.0),
  )
  // beta in [-4, -2], c = [0.25, 0.5]: [0.5^(-1/4)..] = [2^(1/4), 2], the lower end rounded down
  let r = pw_ival(-4.0, -2.0, p).pow_rev1(pw_ival(0.25, 0.5, p))
  assert_true(pw_same(r, 0x1.306FE0A31B715p0, 2.0))
  // 0^beta = 0 for beta > 0
  assert_true(
    pw_same(pw_ival(1.0, 2.0, p).pow_rev1(pw_ival(0.0, 0.0, p)), 0.0, 0.0),
  )
  assert_true(pw_ival(-2.0, 0.0, p).pow_rev1(pw_ival(0.0, 0.0, p)).is_empty())
  // x^0 = 1 for x > 0 (0^0 is undefined)
  assert_true(
    pw_ival(0.0, 0.0, p).pow_rev1(pw_ival(1.0, 1.0, p)) ==
    pw_ival(0.0, pw_inf, p),
  )
  assert_true(pw_ival(0.0, 0.0, p).pow_rev1(pw_ival(2.0, 3.0, p)).is_empty())
  // 1^beta = 1
  assert_true(
    pw_same(
      pw_ival(-5.0, 5.0, p).pow_rev1(
        pw_ival(1.0, 1.0, p),
        x=pw_ival(1.0, 1.0, p),
      ),
      1.0,
      1.0,
    ),
  )
  // empty operands, c below 0
  assert_true(Interval::empty().pow_rev1(pw_ival(1.0, 2.0, p)).is_empty())
  assert_true(pw_ival(1.0, 2.0, p).pow_rev1(Interval::empty()).is_empty())
  assert_true(pw_ival(1.0, 2.0, p).pow_rev1(pw_ival(-3.0, -1.0, p)).is_empty())
  // a rational that is not a float: 9^(1/2) = 3 is dyadic, 9^(1/-2) = 1/3 is not
  let third_set = pw_ival(-2.0, -2.0, p).pow_rev1(pw_ival(9.0, 9.0, p))
  assert_true(third_set.lo_.compare(pw_num(0x1.5555555555555p-2, p)) == 0)
  assert_true(third_set.hi_.compare(pw_num(0x1.5555555555556p-2, p)) == 0)
  assert_true(
    pw_same(pw_ival(2.0, 2.0, p).pow_rev1(pw_ival(9.0, 9.0, p)), 3.0, 3.0),
  )
}

///|
// oracle: A
// source: worked by hand from Table 10.1 for the sets (0, +inf) and (1, +inf) and (0, 1): 0 and 1 are limits that no x attains, so a prior that only touches them gives Empty, a prior that reaches past them keeps its part, and the zero part of c = [0, 2] closes the end at 0; the floats next to 1 are 1 - 2^-p and 1 + 2^(1-p), written with Binary::make
// shares: pw_num, pw_box and Binary::make build the inputs; the comparisons compare; pow_rev1 is the code under test
test "pow_rev1: the open ends at 0 and at 1 against a prior that touches them" {
  for p in [24, 53, 113] {
    let zero = pw_num(0.0, p)
    let one = pw_num(1.0, p)
    let tiny = @binary.Binary::make(
      @binary.BinCoeff::from_uint64(1UL),
      -1000,
      p,
    )
    // 1 - 2^-p and 1 + 2^(1-p), the floats next to 1
    let below_one = @binary.Binary::make(
      coeff_sub(coeff_shift_left(coeff_one(), p), coeff_one()),
      -p,
      p,
    )
    let above_one = @binary.Binary::make(
      coeff_add(coeff_shift_left(coeff_one(), p - 1), coeff_one()),
      1 - p,
      p,
    )
    // (a) 0 in L and 0 in b: S = (0, +inf), 0 is not attained and not in the zero part
    let b = pw_ival(-1.0, 1.0, p)
    let c = pw_ival(0.5, 2.0, p)
    assert_true(b.pow_rev1(c, x=pw_box(zero, zero, p)).is_empty())
    assert_true(b.pow_rev1(c, x=pw_box(pw_num(-1.0, p), zero, p)).is_empty())
    assert_true(pw_same(b.pow_rev1(c, x=pw_box(zero, one, p)), 0.0, 1.0))
    assert_true(!b.pow_rev1(c, x=pw_box(tiny, tiny, p)).is_empty())
    // the zero part closes the end at 0
    let bz = pw_ival(-1.0, 1.0, p)
    let cz = pw_ival(0.0, 2.0, p)
    assert_true(pw_same(bz.pow_rev1(cz, x=pw_box(zero, zero, p)), 0.0, 0.0))
    // (b) 1 is a limit: c = [2, inf), b = [1, inf): S = (1, +inf)
    let b1 = pw_box(one, pos_inf(p), p)
    let c1 = pw_box(pw_num(2.0, p), pos_inf(p), p)
    assert_true(b1.pow_rev1(c1, x=pw_box(one, one, p)).is_empty())
    assert_true(b1.pow_rev1(c1, x=pw_box(zero, one, p)).is_empty())
    assert_true(b1.pow_rev1(c1, x=pw_box(zero, below_one, p)).is_empty())
    let touching = b1.pow_rev1(c1, x=pw_box(one, pw_num(2.0, p), p))
    assert_true(
      pw_same(touching, 1.0, 2.0) ||
      (
        touching.lo_.compare(one) == 0 &&
        touching.hi_.compare(pw_num(2.0, p)) == 0
      ),
    )
    let above = b1.pow_rev1(c1, x=pw_box(above_one, pw_num(2.0, p), p))
    assert_true(above.lo_.compare(above_one) == 0)
    // c = [0.25, 0.5] and b = [1, inf): x^beta in c for large beta: S = (0, 1), 1 is open
    let c_small = pw_ival(0.25, 0.5, p)
    assert_true(
      b1.pow_rev1(c_small, x=pw_box(one, pw_num(3.0, p), p)).is_empty(),
    )
    assert_true(!b1.pow_rev1(c_small, x=pw_box(below_one, one, p)).is_empty())
    assert_true(b1.pow_rev1(c_small, x=pw_box(zero, zero, p)).is_empty())
    // (c) a half-line: b = [-2, 0], c = [2, 4]: beta < 0, x^beta >= 2 gives x <= 2^(1/-2)...
    let bh = pw_ival(-2.0, 0.0, p)
    let ch = pw_ival(2.0, 4.0, p)
    assert_true(
      bh.pow_rev1(ch, x=pw_box(pw_num(1.0, p), pw_num(5.0, p), p)).is_empty(),
    )
    assert_true(!bh.pow_rev1(ch, x=pw_box(zero, one, p)).is_empty())
  }
}

///|
// The band between the exponent range (about |t| = 2^30 ln 2) and 2^40: the end
// `c^(1/beta)` is beyond the range and is clamped at once, without `exp` of a huge
// argument and without refinement.
// oracle: A
// source: worked out by hand: c^(2^e) for e = 31, 35, 40 is beyond the range above (c > 1) or below (c < 1), so the result has the upper end +inf and the lower end 0 or the upper end 2^(e_min - p + 1) (the smallest positive number of the precision), and the priors that start at 2^1e9 give Empty; the cases are the table of the test
// shares: pw_ival, pw_num (Binary::from_double and Interval::from_bounds) and the BinCoeff helpers build the inputs; the comparisons compare; pow_rev1 and the class functions are the code under test
test "pow_rev1: ends beyond the exponent range for beta = 2^-31, 2^-35, 2^-40 return at once" {
  let p = 53
  let ctx = @binary.BinaryContext::new(precision=p)
  let near_huge = @binary.Binary::make(
    @binary.BinCoeff::from_uint64(1UL),
    1000000000,
    p,
  )
  let cs : Array[(Double, Double)] = [
    (2.0, 2.0),
    (0.5, 0.5),
    (2.0, 3.0),
    (0.25, 0.5),
  ]
  for e in [31, 35, 40] {
    for sign in [1, -1] {
      let beta = @binary.Binary::make(@binary.BinCoeff::from_uint64(1UL), -e, p)
      let beta = if sign < 0 { beta.neg() } else { beta }
      let b = pw_box(beta, beta, p)
      for pair in cs {
        let (lo, hi) = pair
        let c = pw_ival(lo, hi, p)
        // c > 1 with beta > 0, or c < 1 with beta < 0: the set is beyond +range
        let up = (lo > 1.0) == (sign > 0)
        for
          prior in [
            Interval::entire(precision=p),
            pw_box(near_huge, pos_inf(p), p),
            pw_box(near_huge.neg().next_up_ctx(ctx).0, near_huge, p),
          ] {
          let r = b.pow_rev1(c, x=prior)
          if prior.hi_.classify() == FpClass::Infinity {
            if up {
              assert_true(!r.is_empty())
              assert_true(r.hi_.classify() == FpClass::Infinity)
            } else if prior.lo_.signum() == Sign::Negative {
              assert_true(!r.is_empty())
              assert_true(r.lo_.is_zero())
            } else {
              // the set lies below the range's lower limit, the prior starts at 2^1e9
              assert_true(r.is_empty())
            }
          } else if up {
            // the set starts above 2^e_max, the prior ends at 2^1e9
            assert_true(r.is_empty())
          } else {
            // the set is [0, the smallest positive stored value]
            assert_true(!r.is_empty())
            assert_true(r.lo_.is_zero())
            assert_true(r.hi_.compare(pw_smallest(p)) <= 0)
            assert_true(r.hi_.compare(pw_smallest(p)) == 0)
          }
        }
      }
    }
  }
}

///|
/// The smallest positive stored value at `p` bits, `2^(e_min - p + 1)`.
fn pw_smallest(p : Int32) -> @binary.Binary {
  @binary.Binary::make(
    @binary.BinCoeff::from_uint64(1UL),
    @binary.binary_value_e_min - p + 1,
    p,
  )
}

///|
/// The largest finite float at `p` bits, `(2^p - 1) 2^(e_max - p + 1)`.
fn pw_largest(p : Int32) -> @binary.Binary {
  @binary.Binary::make(
    coeff_sub(coeff_shift_left(coeff_one(), p), coeff_one()),
    @binary.binary_value_e_max - p + 1,
    p,
  )
}

///|
/// `2^e` as a float at `p` bits, negated for `negative`.
fn pw_pow2(e : Int32, p : Int32, negative~ : Bool = false) -> @binary.Binary {
  let v = @binary.Binary::make(@binary.BinCoeff::from_uint64(1UL), e, p)
  if negative {
    v.neg()
  } else {
    v
  }
}

///|
/// `2 - 2^-40` at `p >= 41` bits.
fn pw_two_less(p : Int32) -> @binary.Binary {
  @binary.Binary::make(
    coeff_sub(coeff_shift_left(coeff_one(), 41), coeff_one()),
    -40,
    p,
  )
}

///|
// oracle: A
// source: the ends of (2 - 2^-40)^(2^30) (top binade) and 1 / (2 - 2^-40)^(2^30) (subnormal) are the rows p1-top-p and p1-sub-p of reverse_table_wbtest.mbt (Python decimal, tools/interval_reverse_oracle.py); the exact edge 2^(2^30) = 2^(e_max + 1) gives [largest finite float, +inf] and 2^(-2^31) gives [0, smallest positive float] by the definition of the clamp; the priors that cut are worked from those ends: the value lies strictly between the two floats, so [hi, +inf] and [0, lo] miss it and [lo, +inf] keeps both
// shares: pw_box, pw_num, pw_pow2, pw_largest, pw_smallest and Binary::from_hex (the table) build the inputs; the comparisons compare; pow_rev1 is the code under test
test "pow_rev1: the edge of the exponent range, at 53 and 113 bits" {
  for p in [53, 113] {
    let top = reverse_row("p1-top-\{p}")
    let sub = reverse_row("p1-sub-\{p}")
    let two = pw_num(2.0, p)
    let c_two = pw_box(two, two, p)
    let c_less = pw_box(pw_two_less(p), pw_two_less(p), p)
    let b_pos = pw_box(pw_pow2(-30, p), pw_pow2(-30, p), p)
    let b_neg = pw_box(
      pw_pow2(-30, p, negative=true),
      pw_pow2(-30, p, negative=true),
      p,
    )
    let b_neg31 = pw_box(
      pw_pow2(-31, p, negative=true),
      pw_pow2(-31, p, negative=true),
      p,
    )
    let entire = Interval::entire(precision=p)
    // (1) top binade: (2 - 2^-40)^(2^30) is about 2^(e_max + 1) (1 - 2^-11), finite
    let r1 = b_pos.pow_rev1(c_less)
    assert_true(!r1.is_empty())
    assert_true(r1.lo_.compare(top.lo) == 0 && r1.hi_.compare(top.hi) == 0)
    // a prior that cuts: the value lies strictly between the two floats, so [hi, +inf]
    // and [0, lo] miss it, and [lo, +inf] keeps both
    assert_true(
      b_pos.pow_rev1(c_less, x=pw_box(r1.hi_, pos_inf(p), p)).is_empty(),
    )
    assert_true(
      b_pos.pow_rev1(c_less, x=pw_box(pw_num(0.0, p), r1.lo_, p)).is_empty(),
    )
    let r1c = b_pos.pow_rev1(c_less, x=pw_box(r1.lo_, pos_inf(p), p))
    assert_true(r1c.lo_.compare(r1.lo_) == 0 && r1c.hi_.compare(r1.hi_) == 0)
    // (2) exactly at the edge: 2^(2^30) = 2^(e_max + 1): [largest finite float, +inf]
    let r2 = b_pos.pow_rev1(c_two, x=entire)
    assert_true(r2.lo_.compare(pw_largest(p)) == 0)
    assert_true(r2.hi_.classify() == FpClass::Infinity)
    // a prior that cuts: below the largest finite float nothing is left, from it the
    // result is the same
    assert_true(
      b_pos
      .pow_rev1(c_two, x=pw_box(pw_num(0.0, p), pw_largest(p), p))
      .is_empty(),
    )
    let r2c = b_pos.pow_rev1(c_two, x=pw_box(pw_largest(p), pos_inf(p), p))
    assert_true(r2c.lo_.compare(pw_largest(p)) == 0)
    assert_true(r2c.hi_.classify() == FpClass::Infinity)
    // (3) subnormal: 1 / (2 - 2^-40)^(2^30) has leading bit e_min - 2: two adjacent
    // stored values, not zero
    let r3 = b_neg.pow_rev1(c_less)
    assert_true(!r3.is_empty())
    assert_true(r3.lo_.compare(sub.lo) == 0 && r3.hi_.compare(sub.hi) == 0)
    // a prior that cuts: [0, lo] misses the value, [lo, hi] keeps both floats
    assert_true(
      b_neg.pow_rev1(c_less, x=pw_box(pw_num(0.0, p), r3.lo_, p)).is_empty(),
    )
    let r3c = b_neg.pow_rev1(c_less, x=pw_box(r3.lo_, r3.hi_, p))
    assert_true(r3c.lo_.compare(r3.lo_) == 0 && r3c.hi_.compare(r3.hi_) == 0)
    // (4) below the stored minimum: 2^(-2^31): [0, the smallest positive stored value]
    let r4 = b_neg31.pow_rev1(c_two)
    assert_true(r4.lo_.is_zero())
    assert_true(r4.hi_.compare(pw_smallest(p)) == 0)
    // a prior that cuts: [smallest, smallest] is past the value
    assert_true(
      b_neg31
      .pow_rev1(c_two, x=pw_box(pw_smallest(p), pw_smallest(p), p))
      .is_empty(),
    )
    let r4c = b_neg31.pow_rev1(
      c_two,
      x=pw_box(pw_num(0.0, p), pw_smallest(p), p),
    )
    assert_true(r4c.lo_.is_zero() && r4c.hi_.compare(pw_smallest(p)) == 0)
  }
}

///|
/// An exact end in the subnormal range stays exact: `(2)^(-2^30)` is the stored value
/// `2^(e_min - 2)` at every precision of 3 or more. It is a point set, so the result is
/// `[v, v]` for every prior that contains it, and all four calls return at once (about
/// 0.2 s each in a separate run, at 53 and 113 bits). A rational end in that range
/// (`2^(e_min)/3`) is not a float: two adjacent stored values around it.
// oracle: A
// source: 2^(e_min - 2) is the stored value 1 * 2^(-2^30) and (2)^(-2^30) = 2^(-2^30) is exact, so the set is the point [v, v] for every prior holding v, Empty for a prior one float above or below (the floats next to v are v + quantum and v - quantum with quantum 2^(e_min - p + 1), written with Binary::make); the rational 2^e_min / 3 has the ends of the row p1-third-p of reverse_table_wbtest.mbt (Python decimal and integers: floor and ceiling of 2^(p-1)/3 units of the quantum)
// shares: pw_box, pw_num, pw_pow2, Binary::make, the constant binary_value_e_min and Binary::from_hex (the table) build the inputs; the comparisons compare; pow_rev1 is the code under test
test "pow_rev1: an exact end in the subnormal range returns at once" {
  for p in [53, 113] {
    let v = pw_pow2(-1073741824, p)
    // v = 2^(p - 3) quanta of 2^(e_min - p + 1): the floats next to it are 2^(p-3) +- 1 quanta
    let v_up = @binary.Binary::make(
      coeff_add(coeff_shift_left(coeff_one(), p - 3), coeff_one()),
      @binary.binary_value_e_min - p + 1,
      p,
    )
    let v_down = @binary.Binary::make(
      coeff_sub(coeff_shift_left(coeff_one(), p - 3), coeff_one()),
      @binary.binary_value_e_min - p + 1,
      p,
    )
    let b = pw_box(
      pw_pow2(-30, p, negative=true),
      pw_pow2(-30, p, negative=true),
      p,
    )
    let c = pw_box(pw_num(2.0, p), pw_num(2.0, p), p)
    let one = pw_num(1.0, p)
    let zero = pw_num(0.0, p)
    for
      prior in [
        Interval::entire(precision=p),
        pw_box(zero, v, p),
        pw_box(v, one, p),
        pw_box(v, v, p),
      ] {
      let r = b.pow_rev1(c, x=prior)
      assert_true(!r.is_empty())
      assert_true(r.lo_.compare(v) == 0 && r.hi_.compare(v) == 0)
    }
    // the point v is below a prior that starts one float above it and above a prior that ends
    // one float below it
    assert_true(b.pow_rev1(c, x=pw_box(v_up, one, p)).is_empty())
    assert_true(b.pow_rev1(c, x=pw_box(zero, v_down, p)).is_empty())
    // the Rational class: 1 / (3 * 2^(-e_min)) = 2^e_min / 3, beta = -1, below the normal range
    let third = reverse_row("p1-third-\{p}")
    let r = third.run()
    assert_true(!r.is_empty())
    assert_true(r.lo_.compare(third.lo) == 0 && r.hi_.compare(third.hi) == 0)
  }
}

///|
// Exact dyadic ends in the subnormal range whose coefficient has more than one bit: a
// stored value at `P` bits is a multiple of the quantum `2^(e_min - P + 1)`, so the datum
// needs `P >= e_min - exponent + 1` (the lowest bit, not the leading bit). Both ends are
// point sets, so the result is `[v, v]` for every prior that contains `v` and Empty for a
// prior one float off. Before the fix (head 1238bec0) none of these calls returned within
// 40 s.
// oracle: A
// source: worked out by hand with e_min = 2 - 2^30: c2 = 3 * 2^-536870914 squared is 9 * 2^-1073741828 = 9 * 2^(e_min - 6), and c3 gives 9 * 2^(e_min - 78) as well; at p = 53 the lower end is 0 and the upper end the smallest positive number (the grid argument), at p = 113 the result is exact; the priors one float off give Empty
// shares: pw_ival, pw_num (Binary::from_double and Interval::from_bounds) and the BinCoeff helpers build the inputs; the comparisons compare; pow_rev1 and the class functions are the code under test
test "pow_rev1: an exact subnormal end with a wide coefficient is exact" {
  for p in [53, 113] {
    let ctx = @binary.BinaryContext::new(precision=p)
    let e_min = @binary.binary_value_e_min
    let one = pw_num(1.0, p)
    let zero = pw_num(0.0, p)
    // case 1: b = 1, c = v = 3 * 2^(e_min - 5), bitlen 2, top = e_min - 4: needs 6 bits
    let v1 = @binary.Binary::make(
      @binary.BinCoeff::from_uint64(3UL),
      e_min - 5,
      p,
    )
    // case 2: b = 1/2, c = 3 * 2^k with k = -536870914: the end is 9 * 2^(e_min - 6),
    // bitlen 4, top = e_min - 3: needs 7 bits
    let c2 = @binary.Binary::make(
      @binary.BinCoeff::from_uint64(3UL),
      -536870914,
      p,
    )
    let v2 = @binary.Binary::make(
      @binary.BinCoeff::from_uint64(9UL),
      e_min - 6,
      p,
    )
    let cases = [
      (pw_box(one, one, p), pw_box(v1, v1, p), v1),
      (pw_box(pw_num(0.5, p), pw_num(0.5, p), p), pw_box(c2, c2, p), v2),
    ]
    for entry in cases {
      let (b, c, v) = entry
      for
        prior in [
          Interval::entire(precision=p),
          pw_box(zero, v, p),
          pw_box(v, one, p),
          pw_box(v, v, p),
        ] {
        let r = b.pow_rev1(c, x=prior)
        println(
          "SUBN p=\{p} prior=\{prior.to_string()} lo=\{r.lo_.to_string()} hi=\{r.hi_.to_string()} v=\{v.to_string()}",
        )
        assert_true(!r.is_empty())
        assert_true(r.lo_.compare(v) == 0 && r.hi_.compare(v) == 0)
      }
      assert_true(
        b.pow_rev1(c, x=pw_box(v.next_up_ctx(ctx).0, one, p)).is_empty(),
      )
      assert_true(
        b.pow_rev1(c, x=pw_box(zero, v.next_down_ctx(ctx).0, p)).is_empty(),
      )
    }
    // an exact end finer than the grid of the result precision: c = 3 * 2^-536870950, b = 1/2:
    // the end is 9 * 2^(e_min - 78), exact at 79 bits; at p = 53 it is below half a quantum
    // (RD = 0, RU = the smallest positive stored value), at p = 113 it is a stored value
    let c3 = @binary.Binary::make(
      @binary.BinCoeff::from_uint64(3UL),
      -536870950,
      p,
    )
    let v3 = @binary.Binary::make(
      @binary.BinCoeff::from_uint64(9UL),
      e_min - 78,
      p,
    )
    let r3 = pw_box(pw_num(0.5, p), pw_num(0.5, p), p).pow_rev1(
      pw_box(c3, c3, p),
    )
    println("SUBN3 p=\{p} lo=\{r3.lo_.to_string()} hi=\{r3.hi_.to_string()}")
    if p == 53 {
      assert_true(r3.lo_.is_zero())
      assert_true(r3.hi_.compare(pw_smallest(p)) == 0)
    } else {
      assert_true(r3.lo_.compare(v3) == 0 && r3.hi_.compare(v3) == 0)
    }
  }
}

///|
// oracle: A
// source: worked by hand: 2^(2^-1e9) = 1 + 2^-1e9 ln 2 lies strictly between 1 and 1 + 2^(1-p), so its ends are [1, 1 + 2^(1-p)]; 2^(-2^-1e9) lies strictly between 1 - 2^-p and 1, so its ends are [1 - 2^-p, 1]; 2^(2^(1e9)) is beyond the range, so [largest finite float, +inf], and 0.5^(2^(1e9)) below it, so [0, smallest positive float]; the priors that start or end at 2^1e9 or 2^-1e9 keep the point 2 or give Empty; (2^1000 + 1)^2 has the exact root 2^1000 + 1; 2^(1/(1 + 2^-500)) at 501 bits is the row p1-near-two-501 of reverse_table_wbtest.mbt (Python decimal; its ends are 2 - 2^-499 and 2 - 2^-500)
// shares: pw_box, pw_num, pw_largest, pw_smallest, the BinCoeff helpers, Binary::make and Binary::from_hex (the table) build the inputs; the comparisons compare; pow_rev1 is the code under test
test "pow_rev1: extreme exponents, operands and prior ends return at once" {
  let p = 53
  let huge = @binary.Binary::make(
    @binary.BinCoeff::from_uint64(1UL),
    1000000000,
    p,
  )
  let tiny = @binary.Binary::make(
    @binary.BinCoeff::from_uint64(1UL),
    -1000000000,
    p,
  )
  let two = pw_num(2.0, p)
  let one = pw_num(1.0, p)
  let c = pw_box(two, two, p)
  // beta = 2^1e9: x = 2^(1/2^1e9) = 1 + 2^-1e9 * ln 2, strictly above 1: [1, 1 + ulp]
  let b_huge = pw_box(huge, huge, p)
  let r = b_huge.pow_rev1(c)
  assert_true(r.lo_.compare(one) == 0)
  // 1 + 2^(1 - p), the float above 1
  assert_true(r.hi_.compare(pw_num(0x1.0000000000001p0, p)) == 0)
  // beta = -2^1e9: x = 2^(-1/2^1e9), strictly below 1: [1 - ulp/2, 1]
  let r2 = pw_box(huge.neg(), huge.neg(), p).pow_rev1(c)
  assert_true(r2.hi_.compare(one) == 0)
  // 1 - 2^-53, the float below 1
  assert_true(r2.lo_.compare(pw_num(0x1.fffffffffffffp-1, p)) == 0)
  // beta = 2^-1e9: x = 2^(2^1e9) is beyond the exponent range: it clamps outward
  let r3 = pw_box(tiny, tiny, p).pow_rev1(c)
  assert_true(!r3.is_empty())
  assert_true(r3.lo_.compare(pw_largest(p)) == 0)
  assert_true(r3.hi_.classify() == FpClass::Infinity)
  let r4 = pw_box(tiny, tiny, p).pow_rev1(
    pw_box(pw_num(0.5, p), pw_num(0.5, p), p),
  )
  assert_true(!r4.is_empty())
  assert_true(r4.lo_.is_zero())
  assert_true(r4.hi_.compare(pw_smallest(p)) == 0)
  // prior ends of 2^1e9 and 2^-1e9
  let b2 = pw_ival(2.0, 2.0, p)
  let c4 = pw_ival(4.0, 4.0, p)
  assert_true(pw_same(b2.pow_rev1(c4, x=pw_box(tiny, huge, p)), 2.0, 2.0))
  assert_true(b2.pow_rev1(c4, x=pw_box(huge, huge, p)).is_empty())
  assert_true(b2.pow_rev1(c4, x=pw_box(tiny, tiny, p)).is_empty())
  // a 2000-bit c and a beta with 500 fractional bits
  let root = coeff_add(coeff_shift_left(coeff_one(), 1000), coeff_one())
  let square = @binary.Binary::make(coeff_mul(root, root), 0, 2100)
  let c_wide = Interval::from_bounds(square, square, precision=2100)
  let r5 = pw_ival(2.0, 2.0, p).pow_rev1(c_wide)
  // the result has the precision of the operands (2100 bits), and the root 2^1000 + 1
  // is exact in the class of dyadic values: [2^1000 + 1, 2^1000 + 1]
  let exact_root = @binary.Binary::make(root, 0, 1001)
  assert_true(r5.lo_.compare(exact_root) == 0)
  assert_true(r5.hi_.compare(exact_root) == 0)
  let near_two = reverse_row("p1-near-two-501")
  let r6 = near_two.run()
  assert_true(r6.lo_.compare(near_two.lo) == 0)
  assert_true(r6.hi_.compare(near_two.hi) == 0)
}

///|
// oracle: A
// source: written out from IEEE 1788-2015 clause 11 and Table 10.1: the decorated pow_rev1 of [2, 2] and [4, 4] is [2, 2] with decoration trv (a reverse operation is trivially decorated), NaI in any operand gives NaI, and the default prior gives the whole set [0, +inf) for the base [-1, 1] and the result [1/2, 2]
// shares: pw_ival, pw_num (Binary::from_double and Interval::from_bounds) and the BinCoeff helpers build the inputs; the comparisons compare; pow_rev1 and the class functions are the code under test
test "decorated and the unbounded forms" {
  let p = 53
  let d = fn(lo : Double, hi : Double, dec : Decoration) {
    DecoratedInterval::new(pw_ival(lo, hi, p), decoration=dec)
  }
  let r = d(2.0, 2.0, Com).pow_rev1(d(4.0, 4.0, Com))
  assert_true(pw_same(r.interval(), 2.0, 2.0))
  assert_eq(r.decoration(), Trv)
  let nai = DecoratedInterval::nai()
  assert_true(nai.pow_rev1(d(4.0, 4.0, Com)).is_nai())
  assert_true(d(2.0, 2.0, Com).pow_rev1(nai).is_nai())
  assert_true(d(2.0, 2.0, Com).pow_rev1(d(4.0, 4.0, Com), x=nai).is_nai())
  // the default prior: the whole set
  let all = pw_ival(-1.0, 1.0, p).pow_rev1(pw_ival(0.5, 2.0, p))
  assert_true(all == pw_ival(0.0, pw_inf, p))
}
