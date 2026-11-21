// The endpoints of `Interval::from_midpoint_radius(c, r, precision=p)` are the hull of
// `[c - r, c + r]` in the format of `p` bits (IEEE 1788-2015 12.12.7): the exact `c - r`
// rounded down and the exact `c + r` rounded up, once each, and numbers of the format.
//
// ORACLE of the random tests (level B): the exact sum formed in a context of 600 bits
// (`add_ctx`, `sub_ctx`; exact for these operands, whose exponents lie within 160 places of
// each other, which the test states by checking the flag `inexact`) and then one directed
// rounding by `with_precision`; the primitives shared with the code under test are those
// two, which have the level A oracles of the binary gate (TestFloat and MPFR rows).
// ORACLE of the written-out case (level A): `Fraction` arithmetic in CPython (the script
// is the comment of the case).

///|
fn ne_next(state : Ref[UInt64]) -> UInt64 {
  let mut x = state.val
  x = x ^ (x << 13)
  x = x ^ (x >> 7)
  x = x ^ (x << 17)
  state.val = x
  x
}

///|
fn ne_value(c : UInt64, exponent : Int32, precision : Int32) -> @binary.Binary {
  @binary.Binary::make(@binary.BinCoeff::from_uint64(c), exponent, precision)
}

///|
/// The oracle: the exact `c - r` and `c + r` (600 bits, checked exact), each rounded once
/// to `p` bits in its direction.
fn ne_expected(
  c : @binary.Binary,
  r : @binary.Binary,
  p : Int32,
) -> (@binary.Binary, @binary.Binary) raise {
  let wide = @binary.BinaryContext::new(precision=600)
  let (exact_lo, flags_lo) = c.sub_ctx(r, wide)
  let (exact_hi, flags_hi) = c.add_ctx(r, wide)
  assert_true(!flags_lo.inexact() && !flags_hi.inexact())
  (
    exact_lo.with_precision(p, @binary.BinaryRoundingMode::RoundTowardNegative),
    exact_hi.with_precision(p, @binary.BinaryRoundingMode::RoundTowardPositive),
  )
}

///|
test "the endpoints of Interval::from_midpoint_radius are the hull of the exact center minus and plus the radius, rounded outward" {
  let state = Ref(0x2545f4914f6cdd1dUL)
  let e_min = @binary.binary_implementation_e_min
  for _ in 0..<4000 {
    let bits = 1 + (ne_next(state) % 60UL).to_int()
    let c = ne_value(
      (ne_next(state) % (1UL << bits)) | 1UL,
      e_min - 70 + (ne_next(state) % 90UL).to_int(),
      200,
    )
    let r = ne_value(
      ne_next(state) % 1000UL + 1UL,
      e_min - 70 + (ne_next(state) % 90UL).to_int(),
      200,
    )
    let precisions = [24, 53, 113]
    let p = precisions[(ne_next(state) % 3UL).to_int()]
    let interval = Interval::from_midpoint_radius(c, r, precision=p)
    let (lo, hi) = ne_expected(c, r, p)
    if interval.lower_bound().compare(lo) != 0 ||
      interval.upper_bound().compare(hi) != 0 {
      abort(
        "center \{c} radius \{r} p \{p}: expected [\{lo}, \{hi}], got [\{interval.lower_bound()}, \{interval.upper_bound()}]",
      )
    }
    assert_true(interval.lower_bound().precision() == p)
    assert_true(interval.upper_bound().precision() == p)
  }
}

///|
test "away from the bottom of the range the endpoints are unchanged" {
  let state = Ref(0x9e3779b97f4a7c15UL)
  for _ in 0..<3000 {
    let c = ne_value(
      ne_next(state) % 1000000UL + 1UL,
      (ne_next(state) % 400UL).to_int() - 200,
      53,
    )
    let r = ne_value(
      ne_next(state) % 1000UL + 1UL,
      (ne_next(state) % 400UL).to_int() - 250,
      53,
    )
    let interval = Interval::from_midpoint_radius(c, r, precision=53)
    let (lo, hi) = ne_expected(c, r, 53)
    assert_eq(interval.lower_bound().compare(lo), 0)
    assert_eq(interval.upper_bound().compare(hi), 0)
  }
}

///|
test "the first case of the issue" {
  // center 133022375522373997 * 2^-1073741877 (57 bits, stored at 200), radius
  // 389 * 2^-1073741869, 53 bits. The hull rounded outward to 53 bits (the bound is
  // not in the subnormal band, the numbers near it have 53 bits) is, by `Fraction`
  // arithmetic in CPython (round the exact `c - r` down and `c + r` up to the grid of
  // 53 bits, the quantum below the range floor 2^(e_min - 52)):
  // [4156949235071075, 8313898470154599] * 2^-1073741872, 2^-1073741873.
  // The interval of the first version of this fix (the exact ends of `c' -/+ R`) was
  // [16627796940284301, 16627796940309199] * 2^-1073741874; the ends now are numbers of
  // the format.
  let c = ne_value(133022375522373997UL, -1073741877, 200)
  let r = ne_value(389UL, -1073741869, 200)
  let interval = Interval::from_midpoint_radius(c, r, precision=53)
  inspect(
    interval.lower_bound().to_string(),
    content="4156949235071075p-1073741872",
  )
  inspect(
    interval.upper_bound().to_string(),
    content="8313898470154599p-1073741873",
  )
}
