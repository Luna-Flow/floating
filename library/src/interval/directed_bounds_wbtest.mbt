// The endpoint operations (`directed_add`, `directed_sub`, `directed_mul`, `extended_mul_both`
// and their interval users: `add`, `sub`, `radius`, `width`) against an exact reference.
//
// ORACLE (level B): the exact sum or product of the two operands formed by integer arithmetic
// (`exact_sum_rounded`, `exact_product_rounded`: aligned `BinCoeff` sums and products, no rounding,
// no surrogate for a far addend) and then rounded once to the precision in the direction by
// `Binary::make`. The shared primitives are
// `BinCoeff` arithmetic and `Binary::make`, which have level A oracles in
// the binary gate (TestFloat, MPFR rows); the code under test is `add_ctx`, `sub_ctx` and `mul_ctx`
// reached through `directed_*`. The new value must EQUAL the reference (a zero of either sign
// counts as the same value).
// Before the change the code under test was a route that made the exact value itself; its results
// were compared with this reference in this file for the 6,000 random endpoint cases, the 672
// range-edge cases and the 2,500 interval cases below, with no difference except the sign of a
// zero from an exact cancellation (a directed `add_ctx` toward negative gives -0).

///|
fn db_next(state : Ref[UInt64]) -> UInt64 {
  let mut x = state.val
  x = x ^ (x << 13)
  x = x ^ (x >> 7)
  x = x ^ (x << 17)
  state.val = x
  x
}

///|
fn db_below(state : Ref[UInt64], n : Int32) -> Int32 {
  (db_next(state) % n.to_uint64()).to_int()
}

///|
fn db_coefficient(state : Ref[UInt64]) -> @binary.BinCoeff {
  let lengths = [1, 1, 2, 3, 7, 8, 9, 14, 16, 17, 40]
  let n = lengths[db_below(state, lengths.length())]
  let bytes : Array[Byte] = []
  for _ in 0..<n {
    bytes.push((db_next(state) % 256UL).to_int().to_byte())
  }
  bytes[n - 1] = bytes[n - 1] | b'\x01'
  @binary.BinCoeff::from_bytes_be(Bytes::from_array(bytes)[:])
}

///|
let db_precisions : Array[Int32] = [24, 53, 64, 113, 128, 200]

///|
/// A finite value of a random shape: length, sign, precision and exponent (near
/// 1, near the two ends of the stored range, or very far from 1).
fn db_operand(state : Ref[UInt64]) -> @binary.Binary {
  let precision = db_precisions[db_below(state, db_precisions.length())]
  let e_min = @binary.binary_value_e_min
  let e_max = @binary.binary_value_e_max
  let exponent = match db_below(state, 6) {
    0 => db_below(state, 600) - 300
    1 => e_min - 60 + db_below(state, 120)
    2 => e_max - 200 + db_below(state, 150)
    3 => db_below(state, 2000000) - 1000000
    4 =>
      if db_below(state, 2) == 0 {
        e_min + db_below(state, 100)
      } else {
        e_max - 400 - db_below(state, 100)
      }
    _ => db_below(state, 100) - 50
  }
  if db_below(state, 25) == 0 {
    return if db_below(state, 2) == 0 {
      @binary.Binary::zero(precision~)
    } else {
      @binary.Binary::negative_zero(precision~)
    }
  }
  let value = @binary.Binary::make(
    db_coefficient(state),
    exponent,
    precision,
    negative=db_below(state, 2) == 0,
  )
  if value.classify() == FpClass::Finite {
    value
  } else {
    @binary.Binary::one(precision~)
  }
}

///|
fn db_same(a : @binary.Binary, b : @binary.Binary) -> Bool {
  // the sign of a zero is not part of the value (an exact cancellation is -0 toward negative)
  a.identical(b) ||
  (a.is_zero() && b.is_zero() && a.precision() == b.precision())
}

///|
/// The new value must equal the reference exactly.
fn db_check(
  label : () -> String,
  new : @binary.Binary,
  reference : @binary.Binary,
) -> Unit {
  if !db_same(new, reference) {
    abort("\{label()}: new \{new} differs from the reference \{reference}")
  }
}

///|
fn db_modes() -> Array[BinaryRoundingMode] {
  [
    BinaryRoundingMode::RoundTowardNegative,
    BinaryRoundingMode::RoundTowardPositive,
  ]
}

///|
/// Whether the reference can align the two values: a zero or an infinity, or an exponent gap of
/// less than 1,000,000 places.
fn db_near(a : @binary.Binary, b : @binary.Binary) -> Bool {
  a.is_zero() ||
  b.is_zero() ||
  a.classify() != FpClass::Finite ||
  b.classify() != FpClass::Finite ||
  Int64::abs(a.exponent2().to_int64() - b.exponent2().to_int64()) < 1000000L
}

///|
/// One sum, one difference and one product of `a` and `b` in `precision` bits, both directions,
/// against the exact reference rounded once.
fn db_endpoint_case(
  a : @binary.Binary,
  b : @binary.Binary,
  precision : Int32,
) -> Unit {
  // the reference aligns the two operands over their exponent gap: gaps of more than 1,000,000
  // places are left to the far-addend tests and to the differential stage against MPFR
  let near = db_near(a, b)
  for mode in db_modes() {
    if near {
      db_check(
        fn() { "add(\{a}, \{b}, \{precision})" },
        directed_add(a, b, precision, mode),
        exact_sum_rounded(a, b, precision, mode),
      )
      db_check(
        fn() { "sub(\{a}, \{b}, \{precision})" },
        directed_sub(a, b, precision, mode),
        exact_sum_rounded(a, b.neg(), precision, mode),
      )
    }
    // `extended_mul` returns +0 for a zero operand and the product otherwise
    let new = extended_mul(a, b, precision, mode)
    let reference = if a.is_zero() || b.is_zero() {
      @binary.Binary::zero(precision~)
    } else {
      exact_product_rounded(a, b, precision, mode)
    }
    db_check(fn() { "mul(\{a}, \{b}, \{precision})" }, new, reference)
  }
  // the two directed products of one coefficient product
  let (down, up) = extended_mul_both(a, b, precision)
  if !down.identical(
      extended_mul(a, b, precision, BinaryRoundingMode::RoundTowardNegative),
    ) ||
    !up.identical(
      extended_mul(a, b, precision, BinaryRoundingMode::RoundTowardPositive),
    ) {
    abort(
      "extended_mul_both(\{a}, \{b}, \{precision}) differs from two products",
    )
  }
}

///|
test "directed endpoint sums, differences and products equal the exact reference rounded once" {
  let state = Ref(0x9e3779b97f4a7c15UL)
  let mut cases = 0
  for _ in 0..<6000 {
    let a = db_operand(state)
    let precision = db_precisions[db_below(state, db_precisions.length())]
    // the second operand: random, the negation of the first (cancellation),
    // the first scaled by a few bits, or a far-away tiny value
    let b = match db_below(state, 5) {
      0 => a.neg()
      1 =>
        a.scaleb_ctx(
          @binary.Binary::from_int(db_below(state, 7) - 3),
          @binary.BinaryContext::new(precision=300),
        ).0
      2 =>
        @binary.Binary::make(
          db_coefficient(state),
          a.exponent2() - 100000 - db_below(state, 100000),
          53,
        )
      _ => db_operand(state)
    }
    if b.classify() != FpClass::Finite {
      continue
    }
    db_endpoint_case(a, b, precision)
    cases += 1
  }
  assert_true(cases > 5000)
}

///|
/// Exact results of 1 to 3 bits at leading-bit exponents `e_min - 1`, `e_min`,
/// `e_max` and one above (overflow), in 24, 53 and 113 bits.
test "directed bounds at the two ends of the exponent range" {
  let e_min = @binary.binary_value_e_min
  let e_max = @binary.binary_value_e_max
  let mut cases = 0
  for
    top in [e_min - 3, e_min - 2, e_min - 1, e_min, e_min + 1, e_max - 1, e_max] {
    for coefficient in [1, 3, 5, 7] {
      let bits = if coefficient == 1 {
        1
      } else if coefficient < 4 {
        2
      } else {
        3
      }
      for precision in [24, 53, 113] {
        for negative in [false, true] {
          // `coefficient * 2^(top - bits + 1)` has its leading bit at `top`
          let half = @binary.Binary::make(
            @binary.BinCoeff::from_uint64(coefficient.to_uint64()),
            top - bits + 1,
            precision,
            negative~,
          )
          // half + half doubles it (leading bit top + 1), half + half/2 ...
          let neighbour = @binary.Binary::make(
            @binary.BinCoeff::from_uint64(coefficient.to_uint64()),
            top - bits,
            precision,
            negative~,
          )
          for other in [half, neighbour, half.neg()] {
            if half.classify() == FpClass::Finite &&
              other.classify() == FpClass::Finite {
              db_endpoint_case(half, other, precision)
              cases += 1
            }
          }
          // products of two powers of two that land at `top`
          let a = @binary.Binary::make(
            @binary.BinCoeff::from_uint64(coefficient.to_uint64()),
            (top - bits + 1) / 2,
            precision,
            negative~,
          )
          let b = @binary.Binary::make(
            @binary.BinCoeff::one(),
            top - bits + 1 - (top - bits + 1) / 2,
            precision,
          )
          if a.classify() == FpClass::Finite && b.classify() == FpClass::Finite {
            db_endpoint_case(a, b, precision)
            cases += 1
          }
        }
      }
    }
  }
  assert_true(cases > 500)
}

///|
// The two corner cases named by value (level A, worked out by hand): an exact result of fewer
// bits than the working precision.
// oracle: A
// source: worked by hand: 2^(e_min - 3) + 2^(e_min - 3) = 2^(e_min - 2) is exact (one bit) in every directed rounding mode at 53 bits, so each mode returns it (IEEE 754-2019 4.3.2)
// shares: Binary::make builds the operands and the expected value; directed_add is the code under test
test "gradual underflow of a short exact result keeps the correctly rounded bound" {
  let e_min = @binary.binary_value_e_min
  // 2^(e_min - 3) + 2^(e_min - 3) = 2^(e_min - 2): one bit, below the normal
  // range of every precision, representable exactly at 53 bits: both directions give it
  let part = @binary.Binary::make(@binary.BinCoeff::one(), e_min - 3, 53)
  let expected = @binary.Binary::make(@binary.BinCoeff::one(), e_min - 2, 53)
  for mode in db_modes() {
    let sum = directed_add(part, part, 53, mode)
    assert_eq(sum.ilogb(), Some(e_min - 2))
    assert_eq(sum.compare(expected), 0)
  }
}

///|
// oracle: A
// source: worked by hand from IEEE 754-2019 4.3.2 and 7.4: 2^e_max + 2^e_max = 2^(e_max + 1) exceeds the largest finite number (2^53 - 1) * 2^(e_max - 52) of 53 bits, so rounding toward positive gives +infinity and rounding toward negative gives that largest finite number
// shares: Binary::make builds the operands and the expected value; directed_add is the code under test
test "overflow of a short exact result keeps the correctly rounded bound" {
  let e_max = @binary.binary_value_e_max
  // 2^e_max + 2^e_max = 2^(e_max + 1): one bit, above the largest finite value
  let part = @binary.Binary::make(@binary.BinCoeff::one(), e_max, 53)
  let sum_down = directed_add(
    part,
    part,
    53,
    BinaryRoundingMode::RoundTowardNegative,
  )
  let sum_up = directed_add(
    part,
    part,
    53,
    BinaryRoundingMode::RoundTowardPositive,
  )
  // the upper bound of a positive overflow is infinity
  inspect(sum_up.classify() == FpClass::Infinity, content="true")
  // the lower bound is the largest finite value of 53 bits, (2^53 - 1) * 2^(e_max - 52)
  let largest = @binary.Binary::make(
    @binary.BinCoeff::from_uint64((1UL << 53) - 1UL),
    e_max - 52,
    53,
  )
  assert_eq(sum_down.ilogb(), Some(e_max))
  assert_eq(sum_down.coefficient().bit_length(), 53)
  assert_eq(sum_down.compare(largest), 0)
}

///|
fn db_interval(state : Ref[UInt64]) -> Interval {
  let x = db_operand(state)
  let y = db_operand(state)
  let (lo, hi) = if x.compare(y) <= 0 { (x, y) } else { (y, x) }
  let precision = db_precisions[db_below(state, db_precisions.length())]
  match db_below(state, 12) {
    0 => Interval::from_bounds(pos_inf(precision).neg(), hi, precision~)
    1 => Interval::from_bounds(lo, pos_inf(precision), precision~)
    2 => Interval::from_bounds(lo, lo, precision~)
    _ => Interval::from_bounds(lo, hi, precision~)
  }
}

///|
/// The endpoint sum of the reference: an infinite addend is the result, otherwise the exact sum
/// rounded once.
fn db_ref_sum(
  a : @binary.Binary,
  b : @binary.Binary,
  precision : Int32,
  mode : BinaryRoundingMode,
) -> @binary.Binary {
  if a.classify() == FpClass::Infinity {
    return a
  }
  if b.classify() == FpClass::Infinity {
    return b
  }
  exact_sum_rounded(a, b, precision, mode)
}

///|
/// The interval sum of the reference: the exact endpoint sums rounded outward once.
fn db_ref_add(a : Interval, b : Interval) -> Interval {
  let p = Int32::max(a.precision_, b.precision_)
  store_interval(
    db_ref_sum(a.lo_, b.lo_, p, BinaryRoundingMode::RoundTowardNegative),
    db_ref_sum(a.hi_, b.hi_, p, BinaryRoundingMode::RoundTowardPositive),
    p,
  )
}

///|
fn db_ref_sub(a : Interval, b : Interval) -> Interval {
  let p = Int32::max(a.precision_, b.precision_)
  store_interval(
    db_ref_sum(a.lo_, b.hi_.neg(), p, BinaryRoundingMode::RoundTowardNegative),
    db_ref_sum(a.hi_, b.lo_.neg(), p, BinaryRoundingMode::RoundTowardPositive),
    p,
  )
}

///|
fn db_ref_width(x : Interval) -> @binary.Binary {
  exact_sum_rounded(
    x.hi_,
    x.lo_.neg(),
    x.precision_,
    BinaryRoundingMode::RoundTowardPositive,
  )
}

///|
fn db_ref_radius(x : Interval) -> @binary.Binary {
  let m = x.midpoint()
  let up = BinaryRoundingMode::RoundTowardPositive
  bin_max(
    exact_sum_rounded(m, x.lo_.neg(), x.precision_, up),
    exact_sum_rounded(x.hi_, m.neg(), x.precision_, up),
  )
}

///|
/// The new interval has the reference's precision and equal endpoints (a zero of either sign is
/// the same value).
fn db_interval_check(
  label : () -> String,
  new : Interval,
  reference : Interval,
) -> Unit {
  if new.precision_ != reference.precision_ || new.empty_ != reference.empty_ {
    abort("\{label()}: precision or emptiness differs")
  }
  if !db_same(new.lo_, reference.lo_) || !db_same(new.hi_, reference.hi_) {
    abort("x")
  }
}

///|
test "interval add, sub, radius and width equal the exact reference rounded outward" {
  let state = Ref(0x2545f4914f6cdd1dUL)
  let mut cases = 0
  let mut compared = 0
  for _ in 0..<2500 {
    let a = db_interval(state)
    let b = db_interval(state)
    if !a.is_empty() && !b.is_empty() {
      if db_near(a.lo_, b.lo_) && db_near(a.hi_, b.hi_) {
        db_interval_check(fn() { "add \{a} \{b}" }, a.add(b), db_ref_add(a, b))
        compared += 1
      }
      if db_near(a.lo_, b.hi_) && db_near(a.hi_, b.lo_) {
        db_interval_check(fn() { "sub \{a} \{b}" }, a.sub(b), db_ref_sub(a, b))
        compared += 1
      }
    }
    // (the reference of width and radius adds exact integers as long as the exponent gap
    // of the endpoints: only gaps below 4,000 bits are compared here)
    let gap = Int32::abs(a.hi_.exponent2() - a.lo_.exponent2())
    if a.is_common_interval() && gap < 4000 {
      assert_true(db_same(a.width(), db_ref_width(a)))
      assert_true(db_same(a.radius(), db_ref_radius(a)))
    }
    cases += 1
  }
  assert_true(cases == 2500)
  assert_true(compared > 1000)
}
