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
