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
// oracle: A
// source: written out by hand from the unique factorisation of the operands: ln(c) / ln(a) is 2 for (16, 4), -1 for (1/2, 2), 1/2 for (1/2, 1/4), -1/3 for (1/2, 8), 2/3 for (4, 8), 0 for c = 1, 2 for (9, 3) and (9/16, 3/4), 3/2 for (27, 9), 2/3 for (9, 27), 1/2 for (5, 25); irrational when exactly one odd part is 1 or the odd parts are different primes' powers ((9, 3/2), (3, 2), (2, 3), (3, 5), (15, 3))
// shares: q_num, q_pow3 (Binary::from_double, coeff_pow_small and Binary::make), pw_ival and Interval::from_bounds build the inputs; the class and the interval comparisons compare; quot_end_class and pow_rev2 are the code under test
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
// oracle: A
// source: written out by hand: ln(3^40000) / ln(3) = 40000 and its inverse is 1/40000 (the 63,400-bit operand is decided by 40,000 exact steps); 3^50000 has more bits than the documented budget, so the class is Unknown (an engineering limit, as documented)
// shares: q_num, q_pow3 (Binary::from_double, coeff_pow_small and Binary::make), pw_ival and Interval::from_bounds build the inputs; the class and the interval comparisons compare; quot_end_class and pow_rev2 are the code under test
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
// oracle: A
// source: worked by hand: ln(1/2) / ln(8) = -1/3 and ln 4 / ln 8 = 2/3 are not floats. The comparison reports where the exact value lies relative to the float: Below when the value is smaller (-1/3 is below the double 1/3, below 0 and below the nearest double -0x1.5555555555555p-2, above -1/2); at 53 bits RD(-1/3) = -0x1.5555555555556p-2 and RU(-1/3) = -0x1.5555555555555p-2, RD(2/3) = 0x1.5555555555555p-1 and RU(2/3) = 0x1.5555555555556p-1, so the value is Above the float RD and Below the float RU
// shares: q_num (Binary::from_double) builds the inputs; quot_end_class, quot_end_compare and quot_end_rounded are the code under test
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
  assert_true(down.compare(q_num(-0x1.5555555555556p-2)) == 0)
  assert_true(up.compare(q_num(-0x1.5555555555555p-2)) == 0)
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
  assert_true(d2.compare(q_num(0x1.5555555555555p-1)) == 0)
  assert_true(u2.compare(q_num(0x1.5555555555556p-1)) == 0)
  assert_true(
    quot_end_compare(q_num(4.0), q_num(8.0), cls2, d2, 53, 12) is Above,
  )
  assert_true(
    quot_end_compare(q_num(4.0), q_num(8.0), cls2, u2, 53, 12) is Below,
  )
}

///|
// oracle: A
// source: written out by hand from the definition of pow_rev2 (IEEE 1788-2015 Table 10.1) with literal double bounds including infinities: a in [1/4, 1/2], c in [1/2, 1] gives [0, 1]; c in [2, 4] gives [-2, -1/2]; c in [2, +inf) gives (-inf, -1/2]; a = [2, +inf), c = [2, 4] gives (0, 2] (0 is not attained, so the priors [-3, 0] and [0, 0] give Empty and [0, 5] gives [0, 2]; with c = [1, 4], 0 is attained); the base 0 with c = 0 gives (0, +inf); 1 in a and in c gives every exponent; the point base 1 gives every exponent only if 1 is in c
// shares: q_num, q_pow3 (Binary::from_double, coeff_pow_small and Binary::make), pw_ival and Interval::from_bounds build the inputs; the class and the interval comparisons compare; quot_end_class and pow_rev2 are the code under test
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
// oracle: A
// source: the ends of ln(c) / ln(a) for a = 1 + 2^-52 and 1 - 2^-53 and c = 2, 1/2, 10 are the rows p2-up-* and p2-down-* of reverse_table_wbtest.mbt (Python decimal at 400 digits, tools/interval_reverse_oracle.py); the two ends are the floats next to the quotient (RD and RU)
// shares: Binary::from_hex (the table), pw_box and Interval::from_bounds build the inputs; the comparisons compare; pow_rev2 is the code under test
test "pow_rev2: a base one unit from 1 gives a huge quotient, enclosed and tight" {
  for a in ["up", "down"] {
    for c in ["2", "half", "10"] {
      let row = reverse_row("p2-\{a}-\{c}-53")
      let r = row.run()
      assert_true(!r.is_empty())
      // the two ends are the adjacent floats around ln(c) / ln(a)
      assert_true(r.lo_.compare(row.lo) == 0 && r.hi_.compare(row.hi) == 0)
    }
  }
}

///|
// oracle: A
// source: worked by hand: a = 2^1e9, c = 2 gives 1 / 10^9 (not a float), c = 3 gives log2(3) / 10^9, a = 2^-1e9, c = 2 gives -1 / 10^9; their ends are the rows p2-huge-base-2-53, p2-huge-base-3-53 and p2-tiny-base-2-53 of reverse_table_wbtest.mbt (Python decimal); a = 2, c = 2^1e9 gives exactly 10^9; a = 2, c = 2^(2^25 + 1) at 24 bits gives the 26-bit integer 2^25 + 1, between the floats 2^25 and 2^25 + 4; the priors that start or end at 2^1e9 or 2^-1e9 keep the point 2 or give Empty
// shares: Binary::from_hex (the table), q_num, pw_box, pw_ival and Interval::from_bounds build the inputs; the comparisons compare; pow_rev2 is the code under test
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
  // a = 2^1e9, c = 2: beta = 1 / 10^9 (rational, not a float): two adjacent floats around
  // the double 1e-9; c = 3: ln 3 / (1e9 ln 2), about 1.6e-9
  let row = reverse_row("p2-huge-base-2-53")
  let r = row.run()
  assert_true(r.lo_.compare(row.lo) == 0 && r.hi_.compare(row.hi) == 0)
  let row2 = reverse_row("p2-huge-base-3-53")
  let r2 = row2.run()
  assert_true(r2.lo_.compare(row2.lo) == 0 && r2.hi_.compare(row2.hi) == 0)
  // a = 2^-1e9, c = 2: beta = -1 / 10^9
  let row3 = reverse_row("p2-tiny-base-2-53")
  let r3 = row3.run()
  assert_true(r3.lo_.compare(row3.lo) == 0 && r3.hi_.compare(row3.hi) == 0)
  // c = 2^1e9 with a = 2: beta = 1e9 (exact)
  let r4 = pw_box(two, two, p).pow_rev2(pw_box(huge, huge, p))
  assert_true(
    r4.lo_.compare(q_num(1.0e9)) == 0 && r4.hi_.compare(q_num(1.0e9)) == 0,
  )
  // a dyadic quotient that needs more bits than the precision: a = 2, c = 2^(2^25 + 1) at 24 bits
  // gives beta = 2^25 + 1, a 26-bit integer; in the binade of 2^25 the floats are 4 apart, so
  // the ends are [2^25, 2^25 + 4]
  let c24 = @binary.Binary::make(@binary.BinCoeff::one(), 33554433, 24)
  let two24 = @binary.Binary::make(@binary.BinCoeff::one(), 1, 24)
  let rq = pw_box(two24, two24, 24).pow_rev2(pw_box(c24, c24, 24))
  assert_true(rq.lo_.compare(@binary.Binary::from_double(33554432.0)) == 0)
  assert_true(rq.hi_.compare(@binary.Binary::from_double(33554436.0)) == 0)
  // prior ends of 2^1e9 and 2^-1e9
  let a2 = pw_ival(2.0, 2.0, p)
  let c4 = pw_ival(4.0, 4.0, p)
  assert_true(pw_same(a2.pow_rev2(c4, x=pw_box(tiny, huge, p)), 2.0, 2.0))
  assert_true(a2.pow_rev2(c4, x=pw_box(huge, huge, p)).is_empty())
  assert_true(a2.pow_rev2(c4, x=pw_box(tiny, tiny, p)).is_empty())
  assert_true(a2.pow_rev2(c4, x=pw_box(huge.neg(), tiny.neg(), p)).is_empty())
}

///|
// oracle: A
// source: written out by hand: the exponent beta with 3^beta = 3^40000 is 40000, so pow_rev2 of the base [3, 3] and the result [3^40000, 3^40000] is [40000, 40000]
// shares: q_num, q_pow3 (Binary::from_double, coeff_pow_small and Binary::make), pw_ival and Interval::from_bounds build the inputs; the class and the interval comparisons compare; quot_end_class and pow_rev2 are the code under test
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
// oracle: A
// source: written out from IEEE 1788-2015 clause 11 (a reverse operation is trivially decorated, trv) and the definition of the precision: the result of 24-bit operands has precision 24, the decorated result of com inputs is trv, and a NaI operand gives NaI; the interval value is not checked here
// shares: q_num, q_pow3 (Binary::from_double, coeff_pow_small and Binary::make), pw_ival and Interval::from_bounds build the inputs; the class and the interval comparisons compare; quot_end_class and pow_rev2 are the code under test
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
// oracle: A
// source: the ends of ln(c) / ln(a) at the edges of the stored range are the rows p2-top-p, p2-sub-p and p2-big-p of reverse_table_wbtest.mbt (Python decimal at 400 digits): the largest finite float against c = 2^e_max, the smallest stored value against c = 2, and a = 2 against the largest finite float; a = 2, c = the smallest stored value gives exactly e_min - p + 1; the priors that cut are worked from the ends: a prior [lo, hi] keeps the result, [hi, +inf] misses the value (it lies strictly between lo and hi) and a prior starting above the exact beta is Empty
// shares: Binary::from_hex (the table), q_num, pw_largest, pw_smallest, pw_box and Binary::make build the inputs; the comparisons compare; pow_rev2 is the code under test
test "pow_rev2: bases and results at the edge of the stored range, at 53 and 113 bits" {
  for p in [53, 113] {
    let largest = pw_largest(p)
    let smallest = pw_smallest(p)
    let top = @binary.Binary::make(
      @binary.BinCoeff::from_uint64(1UL),
      @binary.binary_value_e_max,
      p,
    )
    let two = pw_num(2.0, p)
    let point = fn(x : @binary.Binary) { pw_box(x, x, p) }
    // (1) a = largest finite float, c = 2^e_max: beta = about 1 - 2^-30, irrational
    let r1 = point(largest).pow_rev2(point(top))
    let row1 = reverse_row("p2-top-\{p}")
    assert_true(r1.lo_.compare(row1.lo) == 0 && r1.hi_.compare(row1.hi) == 0)
    // (2) a = smallest stored value (2^(e_min - p + 1)), c = 2: beta = -1 / (p - 1 - e_min),
    // a rational that is not a float
    let r2 = point(smallest).pow_rev2(point(two))
    let row2 = reverse_row("p2-sub-\{p}")
    assert_true(r2.lo_.compare(row2.lo) == 0 && r2.hi_.compare(row2.hi) == 0)
    // (3) a = 2, c = largest finite float: beta = log2(c), a hair under 2^30
    let r3 = point(two).pow_rev2(point(largest))
    let row3 = reverse_row("p2-big-\{p}")
    assert_true(r3.lo_.compare(row3.lo) == 0 && r3.hi_.compare(row3.hi) == 0)
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
  }
}
