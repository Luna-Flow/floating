///|
/// JavaScript keeps its coefficients in a host `bigint`; the one-word fast
/// paths of the other targets do not apply there.
fn binary_fast_add(_left : BinFloat, _right : BinFloat) -> BinFloat? {
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
