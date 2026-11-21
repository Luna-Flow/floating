///|
/// Largest `|degree|` that `rootn` (and `rsqrt`, `pow` with a unit-fraction
/// exponent) may round with one integer root.
let binary_rootn_integer_max_degree : Int32 = 32

///|
/// Up to this degree the integer root is used at every precision. Instructions
/// retired, certified loop divided by integer root, measured from 53 to 32768
/// bits: degree 2 about 50 to 300, 3 about 15 to 33, 5 about 7 to 21, 10 about
/// 2.5 to 14, 12 about 2.4 to 49.
let binary_rootn_integer_any_precision_degree : Int32 = 12

///|
/// Above that degree (13 to 32) the integer root is used up to this context
/// precision: its Newton steps raise a number of `n (p + 2)` bits to the power
/// `n - 1`, while the loop gets the fast `exp` and `ln` kernels from about
/// 1500 bits on. Measured ratios (loop / integer): degree 16 is 30 at 512 bits
/// and 20 at 1024 bits, then 1.6 at 2048 and 1.1 at 4096; degree 20 is 12 at
/// 1024 and 1.1 at 2048; degrees 24 and 32 are 9.9 and 6.7 at 1024 bits and
/// 0.8 and 0.45 (slower) at 2048.
let binary_rootn_integer_wide_degree_max_precision : Int32 = 1024

///|
/// Whether `rootn` of degree `magnitude_degree` at `precision` takes the
/// integer root (otherwise the certified loop).
fn binary_rootn_integer_enabled(
  magnitude_degree : Int64,
  precision : Int32,
) -> Bool {
  magnitude_degree <= binary_rootn_integer_any_precision_degree.to_int64() ||
  (
    magnitude_degree <= binary_rootn_integer_max_degree.to_int64() &&
    precision <= binary_rootn_integer_wide_degree_max_precision
  )
}

///|
fn binary_floor_div_int32(value : Int32, divisor : Int32) -> Int32 {
  let quotient = value / divisor
  if value % divisor != 0 && value < 0 {
    quotient - 1
  } else {
    quotient
  }
}

///|
/// `floor(y^(1/n))` and whether `y` is exactly its `n`-th power.
fn binary_rootn_integer_root(y : Coeff, n : Int32) -> (Coeff, Bool) {
  if n == 2 {
    let (root, remainder) = bin_coeff_sqrt_rem_kernel(y)
    return (root, remainder.is_zero())
  }
  let root = binary_floor_nth_root(y, n)
  (root, root.pow_nat(n.reinterpret_as_uint()).compare(y) == 0)
}

///|
/// `floor(x^(s / n) / 2^grid)` for `x = coefficient * 2^exponent2` (positive,
/// finite), `s = +1` or, with `reciprocal`, `-1`; and whether the value is
/// exactly that integer.
///
/// `floor(v^(1/n)) = floor(floor(v)^(1/n))` for real `v >= 0` (an integer `r`
/// satisfies `r^n <= v` exactly when `r^n <= floor(v)`), so the real value is
/// replaced by the integer `y = floor(x 2^(-n grid))` (positive degree) or
/// `floor(2^(-n grid) / x)` (reciprocal), whose root is the answer; the value is
/// exact only when `y` was exact (no dropped bits, no remainder) and `y` is a
/// perfect `n`-th power.
fn binary_rootn_integer_split(
  coefficient : Coeff,
  exponent2 : Int32,
  n : Int32,
  reciprocal : Bool,
  grid : Int64,
) -> (Coeff, Bool) {
  let exponent = exponent2.to_int64()
  if !reciprocal {
    let shift = exponent - n.to_int64() * grid
    let (y, y_exact) = if shift >= 0L {
      (coefficient.shift_left(shift.to_int()), true)
    } else if -shift >= coefficient.bit_length().to_int64() {
      (Coeff::zero(), false)
    } else {
      let dropped = (-shift).to_int()
      let y = coefficient.shift_right(dropped)
      (y, y.shift_left(dropped).compare(coefficient) == 0)
    }
    let (root, perfect) = binary_rootn_integer_root(y, n)
    return (root, y_exact && perfect)
  }
  let power = -n.to_int64() * grid - exponent
  if power < 0L {
    // 2^power / x < 1: the root is 0, the value is positive.
    return (Coeff::zero(), false)
  }
  let (y, remainder) = Coeff::one()
    .shift_left(power.to_int())
    .div_rem_checked(coefficient)
    .unwrap()
  let (root, perfect) = binary_rootn_integer_root(y, n)
  (root, remainder.is_zero() && perfect)
}

///|
/// The correctly rounded `x^(1/n)` (`n = degree > 0`) or `x^(-1/n)` (`degree < 0`)
/// of a finite nonzero `x` (negative only for an odd degree), `2 <= |degree| <=
/// binary_rootn_integer_max_degree`, in one step: the root is taken to `p + 1`
/// bits on the grid of half a unit in the last place (`r2 = floor(root /
/// 2^(target - 1))`), `r2 >> 1` is the retained part, the low bit of `r2` the
/// round bit, and the root is above `r2` exactly when it is not exact, so
/// the sticky bit is `not exact`. The nearest-even and directed decisions are
/// then those of `binary_round_pack` on the exact value: a boundary of the
/// rounding is an integer multiple of half an ulp, so a value strictly between
/// `r2` and `r2 + 1` (in half ulps) lies on the same side of every boundary as
/// `r2` with the sticky bit set.
///
/// The top bit of the root is `floor(top(x) / n)` (positive degree: `x` is in
/// `[2^t, 2^(t+1))`, so its root is in `[2^(t/n), 2^((t+1)/n))` and
/// `t + 1 <= n (floor(t/n) + 1)`); for a reciprocal root it is
/// `-floor(t/n) - 1`, or `-ceil(t/n)` when `x` is a power of two (the
/// coefficient is 1), by the same inequality on `1/x`.
fn binary_rootn_integer(
  value : Binary,
  degree : Int32,
  context : BinaryContext,
) -> (Binary, BinaryFlags) {
  let negative = value.is_negative()
  let reciprocal = degree < 0
  let n = if reciprocal { -degree } else { degree }
  let coefficient = value.coefficient_()
  let exponent2 = value.exponent2_()
  let top = binary_exact_top(coefficient, exponent2)
  let floor_top = binary_floor_div_int32(top, n)
  let exact_top = if !reciprocal {
    floor_top
  } else if coefficient.compare(Coeff::one()) == 0 {
    -(-binary_floor_div_int32(-top, n))
  } else {
    -floor_top - 1
  }
  if exact_top > context.range_e_max() {
    return binary_overflow_result(negative, context)
  }
  let target_exponent = binary_target_exponent(exact_top, context)
  let (r2, exact) = binary_rootn_integer_split(
    coefficient,
    exponent2,
    n,
    reciprocal,
    target_exponent.to_int64() - 1L,
  )
  let retained = r2.shift_right(1)
  let round_bit = r2.test_bit(0)
  let sticky = !exact
  let unbounded_target = binary_sub_sat(exact_top, context.precision - 1)
  let (unbounded_retained, unbounded_guard, unbounded_sticky) = if unbounded_target ==
    target_exponent {
    (retained, round_bit, sticky)
  } else {
    let (u2, u_exact) = binary_rootn_integer_split(
      coefficient,
      exponent2,
      n,
      reciprocal,
      unbounded_target.to_int64() - 1L,
    )
    (u2.shift_right(1), u2.test_bit(0), !u_exact)
  }
  let unbounded_rounded = binary_apply_round_bits(
    unbounded_retained,
    unbounded_guard,
    unbounded_sticky,
    negative,
    context.rounding,
  )
  binary_round_pack(
    negative,
    retained,
    round_bit,
    sticky,
    target_exponent,
    exact_top,
    binary_exact_top(unbounded_rounded, unbounded_target),
    context,
  )
}
