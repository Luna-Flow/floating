// `Interval::fma` is the directed `fma_ctx` of the corners that the signs select
// (the replacement of the exact route, #657). ORACLE level A: every expected bound is
// worked out by hand from the product and the sum of integers (the corners of
// `a * b + c`) or written out as `m * 2^e` at the two ends of the exponent range
// (e_max = 1073741823); the code under test is compared by `compare` only.

///|
fn fc_range(lo : Int32, hi : Int32) -> Interval {
  Interval::from_bounds(
    @binary.Binary::from_int(lo, precision=53),
    @binary.Binary::from_int(hi, precision=53),
    precision=53,
  )
}

///|
fn fc_is(x : Interval, lo : Int32, hi : Int32) -> Bool {
  !x.is_empty() &&
  x.lower_bound().compare(@binary.Binary::from_int(lo, precision=53)) == 0 &&
  x.upper_bound().compare(@binary.Binary::from_int(hi, precision=53)) == 0
}

///|
test "fma: the nine sign cases of the factors, corners worked out by hand" {
  let c = fc_range(1, 2)
  // a >= 0, b >= 0: [a1 b1, a2 b2] = [2 * 4, 3 * 5] = [8, 15], plus [1, 2]
  assert_true(fc_is(fc_range(2, 3).fma(fc_range(4, 5), c), 9, 17))
  // a >= 0, b <= 0: [a2 b1, a1 b2] = [3 * -5, 2 * -4] = [-15, -8]
  assert_true(fc_is(fc_range(2, 3).fma(fc_range(-5, -4), c), -14, -6))
  // a >= 0, b straddles: [a2 b1, a2 b2] = [3 * -4, 3 * 5] = [-12, 15]
  assert_true(fc_is(fc_range(2, 3).fma(fc_range(-4, 5), c), -11, 17))
  // a <= 0, b >= 0: [a1 b2, a2 b1] = [-3 * 5, -2 * 4] = [-15, -8]
  assert_true(fc_is(fc_range(-3, -2).fma(fc_range(4, 5), c), -14, -6))
  // a <= 0, b <= 0: [a2 b2, a1 b1] = [-2 * -4, -3 * -5] = [8, 15]
  assert_true(fc_is(fc_range(-3, -2).fma(fc_range(-5, -4), c), 9, 17))
  // a <= 0, b straddles: [a1 b2, a1 b1] = [-3 * 5, -3 * -4] = [-15, 12]
  assert_true(fc_is(fc_range(-3, -2).fma(fc_range(-4, 5), c), -14, 14))
  // a straddles, b >= 0: [a1 b2, a2 b2] = [-2 * 5, 3 * 5] = [-10, 15]
  assert_true(fc_is(fc_range(-2, 3).fma(fc_range(4, 5), c), -9, 17))
  // a straddles, b <= 0: [a2 b1, a1 b1] = [3 * -5, -2 * -5] = [-15, 10]
  assert_true(fc_is(fc_range(-2, 3).fma(fc_range(-5, -4), c), -14, 12))
  // both straddle: min(a1 b2, a2 b1) = min(-10, -12) = -12, max(a1 b1, a2 b2) =
  // max(8, 15) = 15, the two candidates of each bound
  assert_true(fc_is(fc_range(-2, 3).fma(fc_range(-4, 5), c), -11, 17))
  // both straddle, the other candidate: a = [-3, 2], b = [-4, 5]: min(-15, -8) = -15,
  // max(12, 10) = 12
  assert_true(fc_is(fc_range(-3, 2).fma(fc_range(-4, 5), c), -14, 14))
}

///|
test "fma: zeros of either sign, 0 times infinity, infinite addends, unbounded and empty operands" {
  let zero_pair = Interval::from_bounds(
    @binary.Binary::negative_zero(precision=53),
    @binary.Binary::zero(precision=53),
    precision=53,
  )
  let entire = Interval::entire(precision=53)
  // [-0, +0] * [1, 2] + [5, 6] = [5, 6]
  assert_true(fc_is(zero_pair.fma(fc_range(1, 2), fc_range(5, 6)), 5, 6))
  // [0, 0] * entire + [1, 2] = [1, 2]: 0 times infinity is 0
  assert_true(fc_is(fc_range(0, 0).fma(entire, fc_range(1, 2)), 1, 2))
  // [0, 5] * [0, +inf) + [1, 1]: the products fill [0, +inf)
  let non_negative = Interval::from_bounds(
    @binary.Binary::zero(precision=53),
    @binary.Binary::inf(precision=53),
    precision=53,
  )
  let r = fc_range(0, 5).fma(non_negative, fc_range(1, 1))
  assert_true(
    r.lower_bound().compare(@binary.Binary::from_int(1, precision=53)) == 0,
  )
  assert_true(r.upper_bound().classify() == FpClass::Infinity)
  // [-inf, -1] * [-3, -2] + [0, 0] = [2, +inf)
  let negative = Interval::from_bounds(
    @binary.Binary::inf(negative=true, precision=53),
    @binary.Binary::from_int(-1, precision=53),
    precision=53,
  )
  let r = negative.fma(fc_range(-3, -2), fc_range(0, 0))
  assert_true(
    r.lower_bound().compare(@binary.Binary::from_int(2, precision=53)) == 0,
  )
  assert_true(r.upper_bound().classify() == FpClass::Infinity)
  // an infinite addend: [1, 2] * [1, 2] + [-inf, 3] = [-inf, 7]; + [3, +inf) = [4, +inf)
  let below = Interval::from_bounds(
    @binary.Binary::inf(negative=true, precision=53),
    @binary.Binary::from_int(3, precision=53),
    precision=53,
  )
  let r = fc_range(1, 2).fma(fc_range(1, 2), below)
  assert_true(r.lower_bound().classify() == FpClass::Infinity)
  assert_true(
    r.upper_bound().compare(@binary.Binary::from_int(7, precision=53)) == 0,
  )
  let r = fc_range(1, 2).fma(fc_range(1, 2), non_negative.add(fc_range(3, 3)))
  assert_true(
    r.lower_bound().compare(@binary.Binary::from_int(4, precision=53)) == 0,
  )
  assert_true(r.upper_bound().classify() == FpClass::Infinity)
  // entire addend and unbounded factors
  assert_true(fc_range(1, 2).fma(fc_range(1, 2), entire).is_entire())
  assert_true(entire.fma(fc_range(1, 2), fc_range(1, 1)).is_entire())
  // an empty operand in each place
  let empty = Interval::empty(precision=53)
  assert_true(empty.fma(fc_range(1, 2), fc_range(1, 2)).is_empty())
  assert_true(fc_range(1, 2).fma(empty, fc_range(1, 2)).is_empty())
  assert_true(fc_range(1, 2).fma(fc_range(1, 2), empty).is_empty())
}

///|
fn fc_hex(text : String, exponent : Int32, precision : Int32) -> @binary.Binary {
  match @binary.BinCoeff::parse(text, radix=16) {
    Ok(coefficient) => @binary.Binary::make(coefficient, exponent, precision)
    Err(error) => abort(error)
  }
}

///|
test "fma: a product beyond the range brought back by the addend (#657)" {
  let e_max = 1073741823
  for precision in [53, 128, 512] {
    // a = 2^e_max, b = 3: the product 3 * 2^e_max is beyond the largest finite
    // number; c = -3 * 2^(e_max - 1); the exact sum is 3 * 2^(e_max - 1), a number of
    // 2 bits inside the range: the point [3 * 2^(e_max - 1), 3 * 2^(e_max - 1)]
    let a = Interval::from_bounds(
      @binary.Binary::make(@binary.BinCoeff::one(), e_max, precision),
      @binary.Binary::make(@binary.BinCoeff::one(), e_max, precision),
      precision~,
    )
    let b = Interval::from_int(3, precision~)
    let c_value = @binary.Binary::make(
      @binary.BinCoeff::from_uint64(3UL),
      e_max - 1,
      precision,
    )
    let c = Interval::from_bounds(c_value.neg(), c_value.neg(), precision~)
    let r = a.fma(b, c)
    assert_true(r.lower_bound().compare(c_value) == 0)
    assert_true(r.upper_bound().compare(c_value) == 0)
    // the mirror image: a = -2^e_max, c = +3 * 2^(e_max - 1): the point -(...)
    let a_negative = Interval::from_bounds(
      a.lower_bound().neg(),
      a.upper_bound().neg(),
      precision~,
    )
    let c_positive = Interval::from_bounds(c_value, c_value, precision~)
    let r = a_negative.fma(b, c_positive)
    assert_true(r.lower_bound().compare(c_value.neg()) == 0)
    assert_true(r.upper_bound().compare(c_value.neg()) == 0)
    // an interval: the same with b = [3, 3] and c = [-3 * 2^(e_max - 1) - 2^(e_max - 3),
    // -3 * 2^(e_max - 1)]: the sum is [3 * 2^(e_max - 1) - ..., 3 * 2^(e_max - 1)]
    let extra = @binary.Binary::make(
      @binary.BinCoeff::one(),
      e_max - 3,
      precision,
    )
    let c_wide = Interval::from_bounds(
      c_value
      .neg()
      .sub_ctx(extra, @binary.BinaryContext::new(precision=precision + 8)).0,
      c_value.neg(),
      precision~,
    )
    let r = a.fma(b, c_wide)
    assert_true(r.upper_bound().compare(c_value) == 0)
    assert_true(r.lower_bound().compare(c_value) < 0)
  }
}

///|
test "fma: the product finite and the sum beyond the range, the largest finite number of the precision as the bound" {
  // 2 * (2^p - 1) * 2^(e_max + 1 - p) is the largest finite number M plus M: [M, +inf)
  let e_max = 1073741823
  for precision in [53, 128] {
    // the 53 bits of ones are '1' and thirteen 'F'; the 128 bits thirty-two 'F'
    let text = if precision % 4 == 0 {
      "F".repeat(precision / 4)
    } else {
      "1FFFFFFFFFFFFF"
    }
    let m = fc_hex(text, e_max + 1 - precision, precision)
    let x = Interval::from_bounds(m, m, precision~)
    let one = Interval::from_int(1, precision~)
    let r = x.fma(one, x)
    assert_true(r.lower_bound().compare(m) == 0)
    assert_true(r.upper_bound().classify() == FpClass::Infinity)
  }
}

///|
fn fc_next(state : Ref[UInt64]) -> UInt64 {
  let mut x = state.val
  x = x ^ (x << 13)
  x = x ^ (x >> 7)
  x = x ^ (x << 17)
  state.val = x
  x
}

///|
fn fc_value(state : Ref[UInt64], precision : Int32) -> @binary.Binary {
  let magnitude = fc_next(state) % 4096UL
  let exponent = (fc_next(state) % 81UL).to_int() - 40
  if fc_next(state) % 11UL == 0UL {
    return @binary.Binary::zero(precision~)
  }
  @binary.Binary::make(
    @binary.BinCoeff::from_uint64(magnitude + 1UL),
    exponent,
    precision,
    negative=fc_next(state) % 2UL == 0UL,
  )
}

///|
fn fc_interval(state : Ref[UInt64], precision : Int32) -> Interval {
  let x = fc_value(state, precision)
  let y = fc_value(state, precision)
  if x.compare(y) <= 0 {
    Interval::from_bounds(x, y, precision~)
  } else {
    Interval::from_bounds(y, x, precision~)
  }
}

///|
/// ORACLE (level B): all four corners tried, in no particular sign class (so the
/// corner selection of `fma` is not shared): the exact `x * y + z` in a context of 600
/// bits (exact for these operands), rounded once to `precision` bits in the direction
/// with `with_precision`, the minimum for the lower bound and the maximum for the
/// upper one. Shared primitives: `make`, `mul_ctx`, `add_ctx`, `with_precision`.
fn fc_sweep(divisor : Int32) -> Unit raise {
  let state = Ref(0x9e3779b97f4a7c15UL)
  let wide = @binary.BinaryContext::new(precision=600)
  for _ in 0..<(6000 / divisor) {
    let precision = [24, 53, 113][(fc_next(state) % 3UL).to_int()]
    let a = fc_interval(state, precision)
    let b = fc_interval(state, precision)
    let c = fc_interval(state, precision)
    let r = a.fma(b, c)
    let mut lo : @binary.Binary? = None
    let mut hi : @binary.Binary? = None
    for x in [a.lower_bound(), a.upper_bound()] {
      for y in [b.lower_bound(), b.upper_bound()] {
        let product = x.mul_ctx(y, wide).0
        let low = product.add_ctx(c.lower_bound(), wide).0.with_precision(
          precision,
          BinaryRoundingMode::RoundTowardNegative,
        )
        let high = product.add_ctx(c.upper_bound(), wide).0.with_precision(
          precision,
          BinaryRoundingMode::RoundTowardPositive,
        )
        match lo {
          Some(v) => if low.compare(v) < 0 { lo = Some(low) }
          None => lo = Some(low)
        }
        match hi {
          Some(v) => if high.compare(v) > 0 { hi = Some(high) }
          None => hi = Some(high)
        }
      }
    }
    if r.lower_bound().compare(lo.unwrap()) != 0 ||
      r.upper_bound().compare(hi.unwrap()) != 0 {
      fail(
        "fma(\{a.lower_bound()}..\{a.upper_bound()}, \{b.lower_bound()}..\{b.upper_bound()}, \{c.lower_bound()}..\{c.upper_bound()}) p=\{precision}: [\{r.lower_bound()}, \{r.upper_bound()}], expected [\{lo.unwrap()}, \{hi.unwrap()}]",
      )
    }
  }
}

///|
test "fma against the four corners tried in full (6,000 cases, about 1 s)" {
  fc_sweep(1)
}
