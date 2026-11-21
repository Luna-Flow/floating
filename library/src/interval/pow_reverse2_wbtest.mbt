///|
fn q_num(x : Double) -> @binary.Binary {
  @binary.Binary::from_double(x)
}

///|
fn q_dyadic_is(cls : QuotClass, value : Double) -> Bool {
  match cls {
    QDyadic(v) => v.compare(q_num(value)) == 0
    _ => false
  }
}

///|
fn q_rational_is(
  cls : QuotClass,
  negative : Bool,
  num : UInt64,
  den : UInt64,
) -> Bool {
  match cls {
    QRational(n, a, b) =>
      n == negative &&
      coeff_compare(a, @binary.BinCoeff::from_uint64(num)) == 0 &&
      coeff_compare(b, @binary.BinCoeff::from_uint64(den)) == 0
    _ => false
  }
}

///|
fn q_pow3(exponent : Int32) -> @binary.Binary {
  let power = coeff_pow_small(@binary.BinCoeff::from_uint64(3UL), exponent)
  @binary.Binary::make(power, 0, power.bit_length())
}

///|
test "pow_rev2 classes: ln(c) / ln(a) by the multiplicative Euclidean algorithm" {
  // both odd parts 1: j / i
  assert_true(q_dyadic_is(quot_end_class(q_num(16.0), q_num(4.0)), 2.0))
  assert_true(q_dyadic_is(quot_end_class(q_num(0.5), q_num(2.0)), -1.0))
  assert_true(q_dyadic_is(quot_end_class(q_num(0.5), q_num(0.25)), 0.5))
  assert_true(
    q_rational_is(quot_end_class(q_num(0.5), q_num(8.0)), true, 1UL, 3UL),
  )
  assert_true(
    q_rational_is(quot_end_class(q_num(4.0), q_num(8.0)), false, 2UL, 3UL),
  )
  // c = 1 is 0
  assert_true(q_dyadic_is(quot_end_class(q_num(1.0), q_num(3.0)), 0.0))
  // both odd parts above 1: 9 = 3^2, 3: r = 2 (and with the powers of two 9/16 = (3/4)^2)
  assert_true(q_dyadic_is(quot_end_class(q_num(9.0), q_num(3.0)), 2.0))
  assert_true(q_dyadic_is(quot_end_class(q_num(0.5625), q_num(0.75)), 2.0))
  // 27 / 9 = 3^3 / 3^2: r = 3/2 (a float), 9 / 27: r = 2/3 (not a float)
  assert_true(q_dyadic_is(quot_end_class(q_num(27.0), q_num(9.0)), 1.5))
  assert_true(
    q_rational_is(quot_end_class(q_num(9.0), q_num(27.0)), false, 2UL, 3UL),
  )
  // the powers of 2 do not match the odd parts: 3 / 4 against 9: independent of the odd part
  assert_true(quot_end_class(q_num(9.0), q_num(1.5)) is QIrrational)
  // exactly one odd part is 1: irrational (c != 1)
  assert_true(quot_end_class(q_num(3.0), q_num(2.0)) is QIrrational)
  assert_true(quot_end_class(q_num(2.0), q_num(3.0)) is QIrrational)
  // different odd parts: 3 against 5, 3 against 15 (15 / 3 = 5 is not a power of 3)
  assert_true(quot_end_class(q_num(3.0), q_num(5.0)) is QIrrational)
  assert_true(quot_end_class(q_num(15.0), q_num(3.0)) is QIrrational)
  assert_true(q_dyadic_is(quot_end_class(q_num(5.0), q_num(25.0)), 0.5))
}

///|
test "pow_rev2 classes: a high power of a small base is decided exactly, a huge one is Unknown" {
  // 3 against 3^40000 (63,400 bits): 40000 Euclid steps, exact
  let cls = quot_end_class(q_pow3(40000), q_num(3.0))
  assert_true(q_dyadic_is(cls, 40000.0))
  assert_true(
    q_rational_is(
      quot_end_class(q_num(3.0), q_pow3(40000)),
      false,
      1UL,
      40000UL,
    ),
  )
  // 3^50000 has more bits than the budget: Unknown
  assert_true(quot_end_class(q_pow3(50000), q_num(3.0)) is QUnknown)
}

///|
test "pow_rev2 rational ends: comparison and directed rounding" {
  // r = -1/3 (c = 1/2, a = 8)
  let cls = quot_end_class(q_num(0.5), q_num(8.0))
  let third = q_num(1.0 / 3.0)
  let neg_third = q_num(-1.0 / 3.0)
  assert_true(
    quot_end_compare(q_num(0.5), q_num(8.0), cls, neg_third, 53, 12) is Below,
  )
  assert_true(
    quot_end_compare(q_num(0.5), q_num(8.0), cls, third, 53, 12) is Below,
  )
  assert_true(
    quot_end_compare(q_num(0.5), q_num(8.0), cls, q_num(-0.5), 53, 12) is Above,
  )
  assert_true(
    quot_end_compare(q_num(0.5), q_num(8.0), cls, q_num(0.0), 53, 12) is Below,
  )
  let down = quot_end_rounded(q_num(0.5), q_num(8.0), cls, false, 53, 12)
  let up = quot_end_rounded(q_num(0.5), q_num(8.0), cls, true, 53, 12)
  // RD < -1/3 < RU, adjacent floats
  let ctx = @binary.BinaryContext::new(precision=53)
  assert_true(down.compare(up) < 0)
  assert_true(down.next_up_ctx(ctx).0.compare(up) == 0)
  assert_true(
    quot_end_compare(q_num(0.5), q_num(8.0), cls, down, 53, 12) is Above,
  )
  assert_true(
    quot_end_compare(q_num(0.5), q_num(8.0), cls, up, 53, 12) is Below,
  )
  // r = +2/3 (c = 4, a = 8)
  let cls2 = quot_end_class(q_num(4.0), q_num(8.0))
  let d2 = quot_end_rounded(q_num(4.0), q_num(8.0), cls2, false, 53, 12)
  let u2 = quot_end_rounded(q_num(4.0), q_num(8.0), cls2, true, 53, 12)
  assert_true(d2.next_up_ctx(ctx).0.compare(u2) == 0)
  assert_true(
    quot_end_compare(q_num(4.0), q_num(8.0), cls2, d2, 53, 12) is Above,
  )
  assert_true(
    quot_end_compare(q_num(4.0), q_num(8.0), cls2, u2, 53, 12) is Below,
  )
}

///|
test "pow_rev2: the examples of the corpus and open ends against a prior touching 0" {
  let p = 53
  let x = pw_ival
  // the corpus: a in [1/4, 1/2], c in [1/2, 1]: beta in [0, 1]
  assert_true(pw_same(x(0.25, 0.5, p).pow_rev2(x(0.5, 1.0, p)), 0.0, 1.0))
  // c in [2, 4]: beta in [-2, -1/2]
  assert_true(pw_same(x(0.25, 0.5, p).pow_rev2(x(2.0, 4.0, p)), -2.0, -0.5))
  // c in [2, +inf): beta <= -1/2 only (the corpus statement is wider)
  assert_true(
    pw_same(x(0.25, 0.5, p).pow_rev2(x(2.0, pw_inf, p)), -pw_inf, -0.5),
  )
  // 1 in a: beta in (-inf, -1/2] for c in [2, inf) and a in [1/4, 1]; 1 not in c ...
  assert_true(
    pw_same(x(0.25, 1.0, p).pow_rev2(x(2.0, pw_inf, p)), -pw_inf, -0.5),
  )
  // a = [2, inf), c = [2, 4]: beta in (0, 2]: 0 is not attained
  let a = x(2.0, pw_inf, p)
  let c = x(2.0, 4.0, p)
  assert_true(pw_same(a.pow_rev2(c), 0.0, 2.0))
  assert_true(a.pow_rev2(c, x=x(-3.0, 0.0, p)).is_empty())
  assert_true(a.pow_rev2(c, x=x(0.0, 0.0, p)).is_empty())
  assert_true(pw_same(a.pow_rev2(c, x=x(0.0, 5.0, p)), 0.0, 2.0))
  // c = [1, 4]: beta in [0, 2], 0 attained (1 in c)
  let c1 = x(1.0, 4.0, p)
  assert_true(pw_same(a.pow_rev2(c1, x=x(-3.0, 0.0, p)), 0.0, 0.0))
  // the base 0: a = [0, 0], c = [0, 0]: beta in (0, +inf)
  assert_true(pw_same(x(0.0, 0.0, p).pow_rev2(x(0.0, 0.0, p)), 0.0, pw_inf))
  assert_true(
    x(0.0, 0.0, p).pow_rev2(x(0.0, 0.0, p), x=x(-4.0, 0.0, p)).is_empty(),
  )
  assert_true(
    pw_same(
      x(0.0, 0.0, p).pow_rev2(x(0.0, 0.0, p), x=x(-4.0, 3.0, p)),
      0.0,
      3.0,
    ),
  )
  // 1 in a and 1 in c: every exponent
  assert_true(pw_same(x(0.5, 2.0, p).pow_rev2(x(0.5, 2.0, p)), -pw_inf, pw_inf))
  // the point base 1 gives every exponent only if 1 is in c, else nothing
  assert_true(x(1.0, 1.0, p).pow_rev2(x(2.0, 4.0, p)).is_empty())
  assert_true(pw_same(x(1.0, 1.0, p).pow_rev2(x(0.5, 2.0, p)), -pw_inf, pw_inf))
}

///|
/// An end next to 1: `ln` of a float one unit from 1 is tiny and the quotient is huge; the
/// first working precision follows the magnitude of the quotient.
test "pow_rev2: a base one unit from 1 gives a huge quotient, enclosed and tight" {
  let p = 53
  let ctx = @binary.BinaryContext::new(precision=p)
  let one = @binary.Binary::one(precision=p)
  for a in [one.next_up_ctx(ctx).0, one.next_down_ctx(ctx).0] {
    for cv in [2.0, 0.5, 10.0] {
      let c = q_num(cv)
      let r = pw_box(a, a, p).pow_rev2(pw_box(c, c, p))
      // the reference: the quotient of the logarithms at 200 bits
      let e = Interval::exact(c, precision=200).ln() /
        Interval::exact(a, precision=200).ln()
      assert_true(!r.is_empty())
      assert_true(r.lo_.compare(e.lo_) <= 0)
      assert_true(r.hi_.compare(e.hi_) >= 0)
      // tight: the two ends are adjacent floats
      assert_true(r.lo_.next_up_ctx(ctx).0.compare(r.hi_) == 0)
    }
  }
}

///|
test "pow_rev2: extreme bases, results and prior ends return at once" {
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
  let two = q_num(2.0)
  let three = q_num(3.0)
  // a = 2^1e9, c = 2: beta = 1 / 10^9 (rational, not a float): two adjacent floats around
  // the double 1e-9; c = 3: ln 3 / (1e9 ln 2), about 1.6e-9
  let ctx = @binary.BinaryContext::new(precision=p)
  let a_huge = pw_box(huge, huge, p)
  let r = a_huge.pow_rev2(pw_box(two, two, p))
  assert_true(r.lo_.next_up_ctx(ctx).0.compare(r.hi_) == 0)
  assert_true(
    r.lo_.compare(q_num(1.0e-9)) <= 0 && r.hi_.compare(q_num(1.0e-9)) >= 0,
  )
  let r2 = a_huge.pow_rev2(pw_box(three, three, p))
  assert_true(!r2.is_empty())
  assert_true(r2.lo_.compare(r2.hi_) < 0)
  // a = 2^-1e9, c = 2: beta = -1 / 10^9
  let a_tiny = pw_box(tiny, tiny, p)
  let r3 = a_tiny.pow_rev2(pw_box(two, two, p))
  assert_true(r3.lo_.next_up_ctx(ctx).0.compare(r3.hi_) == 0)
  assert_true(
    r3.lo_.compare(q_num(-1.0e-9)) <= 0 && r3.hi_.compare(q_num(-1.0e-9)) >= 0,
  )
  // c = 2^1e9 with a = 2: beta = 1e9 (exact)
  let r4 = pw_box(two, two, p).pow_rev2(pw_box(huge, huge, p))
  assert_true(
    r4.lo_.compare(q_num(1.0e9)) == 0 && r4.hi_.compare(q_num(1.0e9)) == 0,
  )
  // prior ends of 2^1e9 and 2^-1e9
  let a2 = pw_ival(2.0, 2.0, p)
  let c4 = pw_ival(4.0, 4.0, p)
  assert_true(pw_same(a2.pow_rev2(c4, x=pw_box(tiny, huge, p)), 2.0, 2.0))
  assert_true(a2.pow_rev2(c4, x=pw_box(huge, huge, p)).is_empty())
  assert_true(a2.pow_rev2(c4, x=pw_box(tiny, tiny, p)).is_empty())
  assert_true(a2.pow_rev2(c4, x=pw_box(huge.neg(), tiny.neg(), p)).is_empty())
}

///|
test "pow_rev2: a 63,400-bit odd part: 3^40000 against 3, and 3^50000 beyond the budget" {
  let p = 53
  let three = pw_ival(3.0, 3.0, p)
  let big = q_pow3(40000)
  let c = Interval::from_bounds(big, big, precision=big.precision())
  let r = three.pow_rev2(c)
  assert_true(
    r.lo_.compare(q_num(40000.0)) == 0 && r.hi_.compare(q_num(40000.0)) == 0,
  )
}

///|
test "pow_rev2: the result keeps the precision of the operands and a decorated form is trv" {
  let p = 24
  let a = pw_ival(0.25, 0.5, p)
  let c = pw_ival(0.5, 1.0, p)
  let r = a.pow_rev2(c)
  assert_true(r.precision() == p)
  let da = DecoratedInterval::new(a, decoration=Com)
  let dc = DecoratedInterval::new(c, decoration=Com)
  let dr = da.pow_rev2(dc)
  assert_true(dr.decoration() == Trv)
  assert_true(da.pow_rev2(DecoratedInterval::nai(precision=p)).is_nai())
}

///|
/// The ends at the edge of the stored range: the largest finite float (the top binade),
/// the smallest positive stored value (the subnormal range), as base and as result. The
/// quotient `ln(c) / ln(a)` is moderate in each case, and the result contains the
/// reference quotient at 200 bits.
test "pow_rev2: bases and results at the edge of the stored range, at 53 and 113 bits" {
  for p in [53, 113] {
    let ctx = @binary.BinaryContext::new(precision=p)
    let largest = pw_largest(p)
    let smallest = pw_smallest(p)
    let top = @binary.Binary::make(
      @binary.BinCoeff::from_uint64(1UL),
      @binary.binary_value_e_max,
      p,
    )
    let two = pw_num(2.0, p)
    let point = fn(x : @binary.Binary) { pw_box(x, x, p) }
    let reference = fn(c : @binary.Binary, a : @binary.Binary) {
      Interval::exact(c, precision=200).ln() /
      Interval::exact(a, precision=200).ln()
    }
    // (1) a = largest finite float, c = 2^e_max: beta = about 1 - 2^-30, irrational
    let r1 = point(largest).pow_rev2(point(top))
    let e1 = reference(top, largest)
    assert_true(r1.lo_.compare(e1.lo_) <= 0 && r1.hi_.compare(e1.hi_) >= 0)
    assert_true(r1.lo_.next_up_ctx(ctx).0.compare(r1.hi_) == 0)
    // (2) a = smallest stored value (2^(e_min - p + 1)), c = 2: beta = -1 / (p - 1 - e_min),
    // a rational that is not a float
    let r2 = point(smallest).pow_rev2(point(two))
    let e2 = reference(two, smallest)
    assert_true(r2.lo_.compare(e2.lo_) <= 0 && r2.hi_.compare(e2.hi_) >= 0)
    assert_true(r2.lo_.next_up_ctx(ctx).0.compare(r2.hi_) == 0)
    // (3) a = 2, c = largest finite float: beta = log2(c), a hair under 2^30
    let r3 = point(two).pow_rev2(point(largest))
    let e3 = reference(largest, two)
    assert_true(r3.lo_.compare(e3.lo_) <= 0 && r3.hi_.compare(e3.hi_) >= 0)
    assert_true(r3.lo_.next_up_ctx(ctx).0.compare(r3.hi_) == 0)
    // (4) a = 2, c = smallest stored value: beta = e_min - p + 1, exact
    let r4 = point(two).pow_rev2(point(smallest))
    let exact_beta = q_num((@binary.binary_value_e_min - p + 1).to_double())
    assert_true(
      r4.lo_.compare(exact_beta) == 0 && r4.hi_.compare(exact_beta) == 0,
    )
    // priors that cut: [lo, hi] keeps the result, a prior one end past it is Empty
    assert_true(
      point(largest).pow_rev2(point(top), x=pw_box(r1.lo_, r1.hi_, p)) == r1,
    )
    assert_true(
      point(largest)
      .pow_rev2(point(top), x=pw_box(r1.hi_, pos_inf(p), p))
      .is_empty(),
    )
    assert_true(
      point(two)
      .pow_rev2(point(smallest), x=pw_box(exact_beta.neg(), pos_inf(p), p))
      .is_empty(),
    )
    println(
      "EDGE2 p=\{p} top=[\{r1.lo_.to_string()}, \{r1.hi_.to_string()}] sub=[\{r2.lo_.to_string()}, \{r2.hi_.to_string()}] big=[\{r3.lo_.to_string()}, \{r3.hi_.to_string()}] smallest=[\{r4.lo_.to_string()}, \{r4.hi_.to_string()}]",
    )
  }
}
