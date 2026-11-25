// `Interval::fma` at the bottom of the exponent range (issue #607): the products
// and the sums are exact and the result is rounded once, outward, at the end
// (IEEE 1788-2015 12.10.2: the accuracy of the basic operations shall be
// tightest). The product was made at its own bit length, which rounds it outward
// to the quantum of a few bits before the sum.

///|
fn fm_next(state : Ref[UInt64]) -> UInt64 {
  let mut x = state.val
  x = x ^ (x << 13)
  x = x ^ (x >> 7)
  x = x ^ (x << 17)
  state.val = x
  x
}

///|
fn fm_value(c : UInt64, exponent : Int32, negative : Bool) -> @binary.Binary {
  @binary.Binary::make(
    @binary.BinCoeff::from_uint64(c),
    exponent,
    200,
    negative~,
  )
}

///|
fn fm_point(v : @binary.Binary, precision : Int32) -> Interval {
  Interval::from_bounds(v, v, precision~)
}

///|
test "the fma of the issue is the exact point" {
  let e_min = @binary.binary_value_e_min
  let t = fm_value(1UL, e_min - 3, false)
  let one = fm_value(1UL, 0, false)
  let z = fm_point(t, 53).fma(fm_point(one, 53), fm_point(t, 53))
  // t * 1 + t = 2t = 2^(e_min - 2)
  inspect(z.lower_bound().to_string(), content="1p-1073741824")
  inspect(z.upper_bound().to_string(), content="1p-1073741824")
}

///|
/// The oracle: the hull of `x * y + z` over the corners, exact in 600 bits,
/// rounded outward once.
fn fm_expected(
  x : Interval,
  y : Interval,
  z : Interval,
) -> (@binary.Binary, @binary.Binary) {
  let wide = @binary.BinaryContext::new(precision=600)
  let corners = [
    x.lower_bound().mul_ctx(y.lower_bound(), wide).0,
    x.lower_bound().mul_ctx(y.upper_bound(), wide).0,
    x.upper_bound().mul_ctx(y.lower_bound(), wide).0,
    x.upper_bound().mul_ctx(y.upper_bound(), wide).0,
  ]
  let mut low = corners[0]
  let mut high = corners[0]
  for c in corners {
    if c.compare(low) < 0 {
      low = c
    }
    if c.compare(high) > 0 {
      high = c
    }
  }
  let p = Int32::max(x.precision(), Int32::max(y.precision(), z.precision()))
  (
    low.add_ctx(z.lower_bound(), wide).0.with_precision(
      p,
      @binary.BinaryRoundingMode::RoundTowardNegative,
    ),
    high.add_ctx(z.upper_bound(), wide).0.with_precision(
      p,
      @binary.BinaryRoundingMode::RoundTowardPositive,
    ),
  )
}

///|
test "fma near the bottom of the range is the tightest interval" {
  let state = Ref(0x9e3779b97f4a7c15UL)
  let e_min = @binary.binary_value_e_min
  let precisions = [53, 113, 128]
  for _ in 0..<2500 {
    let p = precisions[(fm_next(state) % 3UL).to_int()]
    let bits = 1 + (fm_next(state) % 40UL).to_int()
    let x_lo = fm_value(
      (fm_next(state) % (1UL << bits)) | 1UL,
      e_min - 60 + (fm_next(state) % 60UL).to_int(),
      fm_next(state) % 2UL == 0UL,
    )
    let x_hi = fm_value(
      (fm_next(state) % (1UL << bits)) | 1UL,
      e_min - 60 + (fm_next(state) % 60UL).to_int(),
      fm_next(state) % 2UL == 0UL,
    )
    // a multiplier near 1 so that the products stay near the bottom of the range
    let y_lo = fm_value(
      fm_next(state) % 64UL + 1UL,
      -6 + (fm_next(state) % 4UL).to_int(),
      fm_next(state) % 2UL == 0UL,
    )
    let y_hi = fm_value(
      fm_next(state) % 64UL + 1UL,
      -6 + (fm_next(state) % 4UL).to_int(),
      fm_next(state) % 2UL == 0UL,
    )
    let z_lo = fm_value(
      (fm_next(state) % (1UL << bits)) | 1UL,
      e_min - 60 + (fm_next(state) % 60UL).to_int(),
      fm_next(state) % 2UL == 0UL,
    )
    let z_hi = fm_value(
      (fm_next(state) % (1UL << bits)) | 1UL,
      e_min - 60 + (fm_next(state) % 60UL).to_int(),
      fm_next(state) % 2UL == 0UL,
    )
    let order = fn(a : @binary.Binary, b : @binary.Binary) {
      if a.compare(b) <= 0 {
        (a, b)
      } else {
        (b, a)
      }
    }
    let (xl, xh) = order(x_lo, x_hi)
    let (yl, yh) = order(y_lo, y_hi)
    let (zl, zh) = order(z_lo, z_hi)
    let x = Interval::from_bounds(xl, xh, precision=p)
    let y = Interval::from_bounds(yl, yh, precision=p)
    let z = Interval::from_bounds(zl, zh, precision=p)
    let (lo, hi) = fm_expected(x, y, z)
    let result = x.fma(y, z)
    if result.lower_bound().compare(lo) != 0 ||
      result.upper_bound().compare(hi) != 0 {
      abort(
        "fma(\{x}, \{y}, \{z}) p=\{p}: expected [\{lo}, \{hi}], got [\{result.lower_bound()}, \{result.upper_bound()}]",
      )
    }
  }
}
