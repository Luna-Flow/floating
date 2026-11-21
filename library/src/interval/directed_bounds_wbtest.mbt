// The rewritten endpoint operations (`directed_add`, `directed_sub`,
// `directed_mul`, and their interval users) against the exact route they
// replace, and against `add_ctx`, `sub_ctx` and `mul_ctx` as an independent
// oracle. Two references, both private test code over the exact route:
//   `min_bits = p`: the exact value made at `max(bits, p)` bits and rounded once
//                   to `p` in the direction: the new value must EQUAL it;
//   unmodified:     the exact value made at `bits` bits (the old code): the new
//                   value equals it except when the exact result has fewer bits
//                   than `p` and lies below the normal range or in the overflow
//                   band, where the new value is the correctly rounded one and
//                   lies inside the old one.

///|
/// The exact endpoint sum of the old route of `fma` (removed from the library with
/// the replacement of that route by the directed `fma_ctx`; kept here as the reference
/// of this level E test): an infinite addend is the result, otherwise the exact sum at
/// its own bit length, nothing rounded below the normal range.
fn db_extended_add(
  a : @bin_float.BinFloat,
  b : @bin_float.BinFloat,
  _precision : Int32,
  mode : BinaryRoundingMode,
) -> @bin_float.BinFloat {
  if a.classify() == FpClass::Infinity {
    return a
  }
  if b.classify() == FpClass::Infinity {
    return b
  }
  exact_add(a, b, mode~, min_bits=1, exact_range=true)
}

///|
/// The exact endpoint product of the old route of `fma`, as above.
fn db_extended_mul_exact(
  a : @bin_float.BinFloat,
  b : @bin_float.BinFloat,
  mode : BinaryRoundingMode,
) -> @bin_float.BinFloat {
  exact_mul(a, b, mode~, min_bits=1, exact_range=true)
}

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
fn db_coefficient(state : Ref[UInt64]) -> @bin_float.BinCoeff {
  let lengths = [1, 1, 2, 3, 7, 8, 9, 14, 16, 17, 40]
  let n = lengths[db_below(state, lengths.length())]
  let bytes : Array[Byte] = []
  for _ in 0..<n {
    bytes.push((db_next(state) % 256UL).to_int().to_byte())
  }
  bytes[n - 1] = bytes[n - 1] | b'\x01'
  @bin_float.BinCoeff::from_bytes_be(Bytes::from_array(bytes)[:])
}

///|
let db_precisions : Array[Int32] = [24, 53, 64, 113, 128, 200]

///|
/// A finite value of a random shape: length, sign, precision and exponent (near
/// 1, near the two ends of the stored range, or very far from 1).
fn db_operand(state : Ref[UInt64]) -> @bin_float.BinFloat {
  let precision = db_precisions[db_below(state, db_precisions.length())]
  let e_min = @bin_float.binary_implementation_e_min
  let e_max = @bin_float.binary_implementation_e_max
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
      @bin_float.BinFloat::zero(precision~)
    } else {
      @bin_float.BinFloat::negative_zero(precision~)
    }
  }
  let value = @bin_float.BinFloat::make(
    db_coefficient(state),
    exponent,
    precision,
    negative=db_below(state, 2) == 0,
  )
  if value.classify() == FpClass::Finite {
    value
  } else {
    @bin_float.BinFloat::one(precision~)
  }
}

///|
fn db_bound(
  x : @bin_float.BinFloat,
  precision : Int32,
  mode : BinaryRoundingMode,
) -> @bin_float.BinFloat {
  match mode {
    BinaryRoundingMode::RoundTowardNegative => lower_round_bound(x, precision)
    _ => upper_round_bound(x, precision)
  }
}

///|
/// The new value must equal the reference exactly; it must equal the old value
/// or lie inside it (a lower bound not below, an upper bound not above).
/// Returns 1 when the new value is strictly inside the old one.
fn db_check(
  label : () -> String,
  new : @bin_float.BinFloat,
  reference : @bin_float.BinFloat,
  old : @bin_float.BinFloat,
  mode : BinaryRoundingMode,
) -> Int32 {
  if !new.identical(reference) {
    abort(
      "\{label()}: new \{new} differs from the min_bits reference \{reference}",
    )
  }
  if new.identical(old) {
    return 0
  }
  let order = new.compare(old)
  let inside = match mode {
    BinaryRoundingMode::RoundTowardNegative => order >= 0
    _ => order <= 0
  }
  if !inside {
    abort("\{label()}: new \{new} is not inside the old value \{old}")
  }
  1
}

///|
fn db_modes() -> Array[BinaryRoundingMode] {
  [
    BinaryRoundingMode::RoundTowardNegative,
    BinaryRoundingMode::RoundTowardPositive,
  ]
}

///|
/// The same values through a second engine: `add_ctx`, `sub_ctx` and `mul_ctx` in
/// a context of `precision` bits and the direction (IEEE 754-2019 3.7), with the
/// zero rules of the exact route: a zero operand returns the other one rounded,
/// an exact cancellation is +0. The exact route is the implementation; this is
/// the independent oracle that is not built on `make`.
fn db_context(
  precision : Int32,
  mode : BinaryRoundingMode,
) -> @bin_float.BinaryContext {
  @bin_float.BinaryContext::new(precision~, rounding=mode)
}

///|
fn db_oracle_sum(
  result : (@bin_float.BinFloat, @bin_float.BinaryFlags),
  precision : Int32,
) -> @bin_float.BinFloat {
  let (value, flags) = result
  if value.is_zero() && !flags.inexact() {
    @bin_float.BinFloat::zero(precision~)
  } else {
    value
  }
}

///|
fn db_oracle_add(
  a : @bin_float.BinFloat,
  b : @bin_float.BinFloat,
  precision : Int32,
  mode : BinaryRoundingMode,
) -> @bin_float.BinFloat {
  if a.is_zero() {
    return directed_round(b, precision, mode)
  }
  if b.is_zero() {
    return directed_round(a, precision, mode)
  }
  db_oracle_sum(a.add_ctx(b, db_context(precision, mode)), precision)
}

///|
fn db_oracle_sub(
  a : @bin_float.BinFloat,
  b : @bin_float.BinFloat,
  precision : Int32,
  mode : BinaryRoundingMode,
) -> @bin_float.BinFloat {
  if a.is_zero() {
    return directed_round(b.neg(), precision, mode)
  }
  if b.is_zero() {
    return directed_round(a, precision, mode)
  }
  db_oracle_sum(a.sub_ctx(b, db_context(precision, mode)), precision)
}

///|
/// One sum, one difference and one product of `a` and `b` in `precision` bits,
/// both directions. Returns the number of strictly tighter results.
fn db_endpoint_case(
  a : @bin_float.BinFloat,
  b : @bin_float.BinFloat,
  precision : Int32,
) -> Int32 {
  let mut tighter = 0
  for mode in db_modes() {
    tighter += db_check(
      fn() { "add(\{a}, \{b}, \{precision})" },
      directed_add(a, b, precision, mode),
      db_bound(exact_add(a, b, mode~, min_bits=precision), precision, mode),
      db_bound(exact_add(min_bits=1, a, b, mode~), precision, mode),
      mode,
    )
    tighter += db_check(
      fn() { "sub(\{a}, \{b}, \{precision})" },
      directed_sub(a, b, precision, mode),
      db_bound(exact_sub(a, b, mode~, min_bits=precision), precision, mode),
      db_bound(exact_sub(min_bits=1, a, b, mode~), precision, mode),
      mode,
    )
    if !directed_add(a, b, precision, mode).identical(
        db_oracle_add(a, b, precision, mode),
      ) {
      abort("add(\{a}, \{b}, \{precision}) differs from add_ctx")
    }
    if !directed_sub(a, b, precision, mode).identical(
        db_oracle_sub(a, b, precision, mode),
      ) {
      abort("sub(\{a}, \{b}, \{precision}) differs from sub_ctx")
    }
    if !a.is_zero() &&
      !b.is_zero() &&
      !directed_mul(a, b, precision, mode).identical(
        a.mul_ctx(b, db_context(precision, mode)).0,
      ) {
      abort("mul(\{a}, \{b}, \{precision}) differs from mul_ctx")
    }
    // `extended_mul` returns +0 for a zero operand and the product otherwise
    let new = extended_mul(a, b, precision, mode)
    let reference = if a.is_zero() || b.is_zero() {
      @bin_float.BinFloat::zero(precision~)
    } else {
      db_bound(exact_mul(a, b, mode~, min_bits=precision), precision, mode)
    }
    let old = db_extended_mul_exact(a, b, mode)
    let old = if old.is_zero() { old } else { db_bound(old, precision, mode) }
    tighter += db_check(
      fn() { "mul(\{a}, \{b}, \{precision})" },
      new,
      reference,
      old,
      mode,
    )
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
  tighter
}

///|
test "directed endpoint sums, differences and products equal the exact route" {
  let state = Ref(0x9e3779b97f4a7c15UL)
  let mut tighter = 0
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
          @bin_float.BinFloat::from_int(db_below(state, 7) - 3),
          @bin_float.BinaryContext::new(precision=300),
        ).0
      2 =>
        @bin_float.BinFloat::make(
          db_coefficient(state),
          a.exponent2() - 100000 - db_below(state, 100000),
          53,
        )
      _ => db_operand(state)
    }
    if b.classify() != FpClass::Finite {
      continue
    }
    tighter += db_endpoint_case(a, b, precision)
    cases += 1
  }
  assert_true(cases > 5000)
  println(
    "directed endpoint cases \{cases}, strictly tighter results \{tighter}",
  )
}

///|
/// Exact results of 1 to 3 bits at leading-bit exponents `e_min - 1`, `e_min`,
/// `e_max` and one above (overflow), in 24, 53 and 113 bits.
test "directed bounds at the two ends of the exponent range" {
  let e_min = @bin_float.binary_implementation_e_min
  let e_max = @bin_float.binary_implementation_e_max
  let mut tighter = 0
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
          let half = @bin_float.BinFloat::make(
            @bin_float.BinCoeff::from_uint64(coefficient.to_uint64()),
            top - bits + 1,
            precision,
            negative~,
          )
          // half + half doubles it (leading bit top + 1), half + half/2 ...
          let neighbour = @bin_float.BinFloat::make(
            @bin_float.BinCoeff::from_uint64(coefficient.to_uint64()),
            top - bits,
            precision,
            negative~,
          )
          for other in [half, neighbour, half.neg()] {
            if half.classify() == FpClass::Finite &&
              other.classify() == FpClass::Finite {
              tighter += db_endpoint_case(half, other, precision)
              cases += 1
            }
          }
          // products of two powers of two that land at `top`
          let a = @bin_float.BinFloat::make(
            @bin_float.BinCoeff::from_uint64(coefficient.to_uint64()),
            (top - bits + 1) / 2,
            precision,
            negative~,
          )
          let b = @bin_float.BinFloat::make(
            @bin_float.BinCoeff::one(),
            top - bits + 1 - (top - bits + 1) / 2,
            precision,
          )
          if a.classify() == FpClass::Finite && b.classify() == FpClass::Finite {
            tighter += db_endpoint_case(a, b, precision)
            cases += 1
          }
        }
      }
    }
  }
  assert_true(cases > 500)
  assert_true(tighter > 0)
  println("range-edge cases \{cases}, strictly tighter results \{tighter}")
}

///|
/// The two corner cases named by value: an exact result of fewer bits than the
/// working precision.
test "gradual underflow of a short exact result keeps the correctly rounded bound" {
  let e_min = @bin_float.binary_implementation_e_min
  // 2^(e_min - 3) + 2^(e_min - 3) = 2^(e_min - 2): one bit, below the normal
  // range of every precision, representable exactly at 53 bits
  let part = @bin_float.BinFloat::make(
    @bin_float.BinCoeff::one(),
    e_min - 3,
    53,
  )
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
  let old_down = lower_round_bound(
    exact_add(
      min_bits=1,
      part,
      part,
      mode=BinaryRoundingMode::RoundTowardNegative,
    ),
    53,
  )
  let old_up = upper_round_bound(
    exact_add(
      min_bits=1,
      part,
      part,
      mode=BinaryRoundingMode::RoundTowardPositive,
    ),
    53,
  )
  assert_eq(sum_down.ilogb(), Some(e_min - 2))
  assert_eq(sum_up.ilogb(), Some(e_min - 2))
  // today's bounds were made at one bit: the lower one rounds to zero and the
  // upper one to 2^(e_min - 1), twice the exact value 2^(e_min - 2); the new
  // bounds are the exact value in both directions
  inspect(old_down.is_zero(), content="true")
  assert_eq(old_up.ilogb(), Some(e_min - 1))
  assert_true(old_down.compare(sum_down) < 0)
  assert_true(sum_up.compare(old_up) < 0)
}

///|
test "overflow of a short exact result keeps the correctly rounded bound" {
  let e_max = @bin_float.binary_implementation_e_max
  // 2^e_max + 2^e_max = 2^(e_max + 1): one bit, above the largest finite value
  let part = @bin_float.BinFloat::make(@bin_float.BinCoeff::one(), e_max, 53)
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
  let old_down = lower_round_bound(
    exact_add(
      min_bits=1,
      part,
      part,
      mode=BinaryRoundingMode::RoundTowardNegative,
    ),
    53,
  )
  // the upper bound of a positive overflow is infinity in both
  inspect(sum_up.classify() == FpClass::Infinity, content="true")
  inspect(
    upper_round_bound(
      exact_add(
        min_bits=1,
        part,
        part,
        mode=BinaryRoundingMode::RoundTowardPositive,
      ),
      53,
    ).classify() ==
    FpClass::Infinity,
    content="true",
  )
  // the lower bound is the largest finite value of 53 bits (all ones); the old
  // one was made at one bit, where the largest finite value is 3 * 2^(e_max - 1)
  assert_eq(sum_down.ilogb(), Some(e_max))
  assert_eq(sum_down.coefficient().bit_length(), 53)
  assert_eq(old_down.coefficient().bit_length(), 2)
  assert_true(old_down.compare(sum_down) <= 0)
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
/// The old interval operations, copied over the exact route.
fn db_old_add(a : Interval, b : Interval) -> Interval {
  let precision = Int32::max(a.precision_, b.precision_)
  if a.is_common_interval() && b.is_common_interval() {
    return store_interval(
      exact_add(
        min_bits=1,
        a.lo_,
        b.lo_,
        mode=BinaryRoundingMode::RoundTowardNegative,
      ),
      exact_add(
        min_bits=1,
        a.hi_,
        b.hi_,
        mode=BinaryRoundingMode::RoundTowardPositive,
      ),
      precision,
    )
  }
  store_interval(
    db_extended_add(a.lo_, b.lo_, 1, BinaryRoundingMode::RoundTowardNegative),
    db_extended_add(a.hi_, b.hi_, 1, BinaryRoundingMode::RoundTowardPositive),
    precision,
  )
}

///|
fn db_old_sub(a : Interval, b : Interval) -> Interval {
  let precision = Int32::max(a.precision_, b.precision_)
  if a.is_common_interval() && b.is_common_interval() {
    return store_interval(
      exact_sub(
        min_bits=1,
        a.lo_,
        b.hi_,
        mode=BinaryRoundingMode::RoundTowardNegative,
      ),
      exact_sub(
        min_bits=1,
        a.hi_,
        b.lo_,
        mode=BinaryRoundingMode::RoundTowardPositive,
      ),
      precision,
    )
  }
  store_interval(
    db_extended_add(
      a.lo_,
      b.hi_.neg(),
      1,
      BinaryRoundingMode::RoundTowardNegative,
    ),
    db_extended_add(
      a.hi_,
      b.lo_.neg(),
      1,
      BinaryRoundingMode::RoundTowardPositive,
    ),
    precision,
  )
}

///|
fn db_old_width(x : Interval) -> @bin_float.BinFloat {
  upper_round_bound(
    exact_sub(
      min_bits=1,
      x.hi_,
      x.lo_,
      mode=BinaryRoundingMode::RoundTowardPositive,
    ),
    x.precision_,
  )
}

///|
fn db_old_radius(x : Interval) -> @bin_float.BinFloat {
  let m = x.midpoint()
  let below = upper_round_bound(
    exact_sub(
      min_bits=1,
      m,
      x.lo_,
      mode=BinaryRoundingMode::RoundTowardPositive,
    ),
    x.precision_,
  )
  let above = upper_round_bound(
    exact_sub(
      min_bits=1,
      x.hi_,
      m,
      mode=BinaryRoundingMode::RoundTowardPositive,
    ),
    x.precision_,
  )
  bin_max(below, above)
}

///|
/// The new interval has the old one's precision; each endpoint is the old one or
/// inside it (and an endpoint that is zero is the same zero).
fn db_interval_check(
  label : () -> String,
  new : Interval,
  old : Interval,
) -> Int32 {
  if new.precision_ != old.precision_ || new.empty_ != old.empty_ {
    abort("\{label()}: precision or emptiness differs")
  }
  let mut tighter = 0
  if !new.lo_.identical(old.lo_) {
    if new.lo_.compare(old.lo_) < 0 {
      abort(
        "\{label()}: lower bound \{new.lo_} is below the old one \{old.lo_}",
      )
    }
    tighter += 1
  }
  if !new.hi_.identical(old.hi_) {
    if new.hi_.compare(old.hi_) > 0 {
      abort(
        "\{label()}: upper bound \{new.hi_} is above the old one \{old.hi_}",
      )
    }
    tighter += 1
  }
  tighter
}

///|
test "interval add, sub, radius and width equal the old exact route or lie inside it" {
  let state = Ref(0x2545f4914f6cdd1dUL)
  let mut tighter = 0
  let mut cases = 0
  for _ in 0..<2500 {
    let a = db_interval(state)
    let b = db_interval(state)
    tighter += db_interval_check(
      fn() { "add \{a} \{b}" },
      a.add(b),
      db_old_add(a, b),
    )
    tighter += db_interval_check(
      fn() { "sub \{a} \{b}" },
      a.sub(b),
      db_old_sub(a, b),
    )
    // (width and radius add exact integers as long as the exponent gap of the
    // endpoints: only gaps below 4,000 bits are compared here)
    let gap = Int32::abs(a.hi_.exponent2() - a.lo_.exponent2())
    if a.is_common_interval() && gap < 4000 {
      // upper bounds of a width and a radius: equal to the old ones or below
      assert_true(a.width().compare(db_old_width(a)) <= 0)
      assert_true(a.radius().compare(db_old_radius(a)) <= 0)
      if !a.width().identical(db_old_width(a)) {
        tighter += 1
      }
      if !a.radius().identical(db_old_radius(a)) {
        tighter += 1
      }
    }
    cases += 1
  }
  assert_true(cases == 2500)
  println("interval cases \{cases}, strictly tighter endpoints \{tighter}")
}
