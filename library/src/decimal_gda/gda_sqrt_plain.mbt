///|
// The plain case of the square root of a positive operand that is certainly not
// a square: one integer root decides the rounding, where the general route
// (`decimal_sqrt_general`) takes a root of the operand to see whether it is a
// square (`exact_finite_sqrt`) and then a second root of the scaled operand
// (`decimal_sqrt_fixed_result`) whose midpoint comparison builds three
// products of the length of the radicand.
//
// Exactness. Write the operand `c * 10^q` with `c = c0 * 10^z`, `c0` not
// divisible by 10. The root is a decimal iff `q + z` is even and `c0` is a
// square: if `q + z` were odd, `10 * c0` would have to be a square, so the root
// would be divisible by 10, `100` would divide `10 * c0` and `10` would divide
// `c0`. The plain path takes an operand with `z < 8` and
// - an odd `q + z`: not a square; or
// - an even `q + z` and a `c0` that fails a residue test: a square is a square
//   modulo 64, 63, 65 and 11, each test is one remainder by a word;
//   an operand that passes all four (about 1 in 120 non-squares, and every
//   square) is declined and the general route decides, as before. A square
//   would cost the plain path a root of twice the length for nothing, which
//   is why it is not tried here.
// So `rem = 0` cannot happen below; if it did the path declines.
//
// The rounding. Let `p` be the precision, `a` the adjusted exponent of the
// operand and `E = floor(a / 2) - p + 1` the exponent of a root of `p` digits.
// With the radicand `R = c * 10^s`, `s = q - 2 E`, `R` has `2p - 1` or `2p`
// digits and `r = floor(sqrt(R))` has exactly `p` digits; `rem = R - r^2` is
// not zero. The result has `p` digits at the exponent `E`: `r`, or `r + 1` when
// the exact root is above `r + 1/2`; `R > (r + 1/2)^2` is `rem > r`, because
// `(r + 1/2)^2 = r^2 + r + 1/4` and `rem` is an integer, so a tie cannot
// occur. The sign of `rem - r` stands for the sign of `R - (r + 1/2)^2` in the
// decision of the rounding mode; `Inexact` and `Rounded` are raised (GDA 1.70,
// square-root: the inexact result "is rounded using the round-half-even
// algorithm and the coefficient will have exactly precision digits (unless the
// result is subnormal)"). A carry into `10^p` divides by ten and raises the
// exponent by one.
//
// Declined (`None`: the general route runs, and is the reference of the
// differential tests, one named test for each):
// 1. tiny operands (a root of adjusted exponent of at most `Etiny - 2`) are
//    decided before this function by `decimal_sqrt_tiny_result`
//    (test "sqrt plain declines a tiny operand and agrees");
// 2. a root whose adjusted exponent is below `e_min` (a subnormal result, or
//    one clamped at `Etiny`) or not below `e_max` (a root that could overflow
//    or sit at the top of the range)
//    (test "sqrt plain declines a subnormal and an out-of-range root and agrees");
// 3. `s < 0`, an operand with more digits than the radicand of a root of `p`
//    digits, which the general route divides
//    (test "sqrt plain declines long coefficients and agrees");
// 4. a coefficient ending in 8 zeros or more, and an operand that may be a
//    square (the residue tests above)
//    (test "sqrt plain declines the operands that may be squares");
// 5. a context without a precision (`precision = 0`).
// The clamp of a format never folds a plain result: `root_adjusted < e_max`
// bounds the exponent, after a carry too, by `e_max - p + 1`.

///|
/// The squares modulo `modulus`, as a table.
fn gda_sqrt_residues(modulus : Int32) -> FixedArray[Bool] {
  let table : FixedArray[Bool] = FixedArray::make(modulus, false)
  for value in 0..<modulus {
    table[value * value % modulus] = true
  }
  table
}

///|
let gda_sqrt_residues_64 : FixedArray[Bool] = gda_sqrt_residues(64)

///|
let gda_sqrt_residues_63 : FixedArray[Bool] = gda_sqrt_residues(63)

///|
let gda_sqrt_residues_65 : FixedArray[Bool] = gda_sqrt_residues(65)

///|
let gda_sqrt_residues_11 : FixedArray[Bool] = gda_sqrt_residues(11)

///|
/// Whether the operand `c * 10^q` (`c` nonzero) is certainly not a square of a
/// decimal: see the exactness argument above. `false` means "may be a square".
/// With `c = c0 * 10^z` (`z` below 8, read from the last 8 digits), the residue
/// of `c0` modulo `m` is `(c mod (m 10^z)) / 10^z`, one remainder by a word.
fn gda_sqrt_certainly_not_square(
  coefficient : DecCoeff,
  exponent : Int32,
) -> Bool {
  let low = dec_coeff_mod_unit(coefficient, 100_000_000)
  if low == 0 {
    return false
  }
  let mut power = 1
  let mut zeros = 0
  let mut rest = low
  while rest % 10 == 0 {
    rest = rest / 10
    power = power * 10
    zeros += 1
  }
  // the exponent of the operand with its trailing zeros made part of it
  if ((exponent + zeros) & 1) != 0 {
    return true
  }
  !gda_sqrt_residues_64[dec_coeff_mod_unit(coefficient, 64 * power) / power] ||
  !gda_sqrt_residues_63[dec_coeff_mod_unit(coefficient, 63 * power) / power] ||
  !gda_sqrt_residues_65[dec_coeff_mod_unit(coefficient, 65 * power) / power] ||
  !gda_sqrt_residues_11[dec_coeff_mod_unit(coefficient, 11 * power) / power]
}

///|
fn decimal_sqrt_plain(
  operand : Decimal,
  ctx : DecimalContext,
  precision : Int32,
) -> (Decimal, DecimalFlags)? {
  guard ctx.precision >= 1 &&
    operand.class == FpClass::Finite &&
    !operand.negative &&
    !operand.coefficient.is_zero() else {
    return None
  }
  let root_adjusted = adjusted_exponent(operand) >> 1
  guard root_adjusted >= ctx.e_min && root_adjusted < ctx.e_max else {
    return None
  }
  let root_exponent = root_adjusted - precision + 1
  let scale = operand.exponent10.to_int64() - 2L * root_exponent.to_int64()
  guard scale >= 0L else { return None }
  guard gda_sqrt_certainly_not_square(operand.coefficient, operand.exponent10) else {
    return None
  }
  let radicand = dec_coeff_shift_power10_repr(
    operand.coefficient,
    scale.to_int(),
  )
  let (root, state) = dec_coeff_sqrt_rounding(radicand)
  guard state != DecSqrtRemainder::Zero else { return None }
  let round_up = decimal_sqrt_should_increment(
    root,
    if state == DecSqrtRemainder::AboveRoot {
      1
    } else {
      -1
    },
    true,
    ctx.decimal_rounding,
  )
  let mut coefficient = if round_up {
    dec_coeff_magnitude_add_unit(root, 1)
  } else {
    root
  }
  let mut exponent = root_exponent
  if coefficient.digits10() > precision {
    exponent += 1
    coefficient = match exact_divide_by_power_of_ten_repr(coefficient, 1) {
      Some(value) => value
      None => abort("decimal_sqrt_plain expected an exact divide by 10")
    }
  }
  Some(
    (
      finite_with_exponent_repr(false, coefficient, exponent, precision),
      gda_flags_engine_rounded_inexact,
    ),
  )
}

///|
/// The engine flag set of an inexact plain root, built once (an immutable
/// record compared by value, like `decimal_flags_none_value`).
let gda_flags_engine_rounded_inexact : DecimalFlags = {
  ..decimal_flags_none_value,
  rounded: true,
  inexact: true,
}
