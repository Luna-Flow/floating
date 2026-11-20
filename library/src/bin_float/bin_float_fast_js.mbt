///|
/// JavaScript keeps its coefficients in a host `bigint`; the one-word fast
/// paths of the other targets do not apply there.

///|
fn binary_fast_add_signed(
  _left : BinFloat,
  _right : BinFloat,
  _flip : Bool,
) -> BinFloat? {
  None
}

///|
fn binary_fast_mul(_left : BinFloat, _right : BinFloat) -> BinFloat? {
  None
}

///|
fn binary_fast_div(_left : BinFloat, _right : BinFloat) -> BinFloat? {
  None
}

///|
fn binary_fast_sqrt(_value : BinFloat) -> BinFloat? {
  None
}

///|
fn binary_coeff_fast_add_signed(
  _left : BinFloat,
  _right : BinFloat,
  _flip : Bool,
) -> BinFloat? {
  None
}

///|
fn binary_coeff_fast_mul(_left : BinFloat, _right : BinFloat) -> BinFloat? {
  None
}

///|
fn binary_coeff_fast_div(_left : BinFloat, _right : BinFloat) -> BinFloat? {
  None
}

///|
/// `(root, remainder)` of `magnitude * 2^scale` (`scale >= 0`): the shifted
/// radicand through the host-bigint kernel, as the split did before the
/// scaled kernel existed.
fn binary_sqrt_rem_scaled(magnitude : Coeff, scale : Int32) -> (Coeff, Coeff) {
  bin_coeff_sqrt_rem_kernel(magnitude.shift_left(scale))
}

///|
fn binary_coeff_fast_sqrt(_value : BinFloat) -> BinFloat? {
  None
}

///|
fn binary_pair_add_signed(
  _left : BinFloat,
  _right : BinFloat,
  _flip : Bool,
) -> BinFloat? {
  None
}

///|
fn binary_pair_div(_left : BinFloat, _right : BinFloat) -> BinFloat? {
  None
}

///|
fn binary_pair_mul(_left : BinFloat, _right : BinFloat) -> BinFloat? {
  None
}
