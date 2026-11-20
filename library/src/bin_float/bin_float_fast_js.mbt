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
fn binary_sqrt_ctx_words_ok(
  _value : BinFloat,
  _context : BinaryContext,
) -> Bool {
  false
}

///|
fn binary_sqrt_ctx_words(
  _value : BinFloat,
  _context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  abort("binary_sqrt_ctx_words is not available on js")
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

///|
/// No word comparison on this target: 2 sends the caller to the general path.
fn binary_compare_pair(_left : BinFloat, _right : BinFloat) -> Int32 {
  2
}

///|
fn binary_compare_pair_magnitude(_left : BinFloat, _right : BinFloat) -> Int32 {
  2
}

///|
/// The two-word paths do not exist on this target; the limit is only read by the
/// dispatch of the plain operations.
let binary_pair_precision_limit : Int32 = 128

///|
/// No word route on this target: the general route of the contextual operations.
fn binary_ctx_add_words(
  _left : BinFloat,
  _right : BinFloat,
  _flip : Bool,
  _context : BinaryContext,
) -> (BinFloat, BinaryFlags)? {
  None
}

///|
fn binary_ctx_mul_words(
  _left : BinFloat,
  _right : BinFloat,
  _context : BinaryContext,
) -> (BinFloat, BinaryFlags)? {
  None
}

///|
fn binary_ctx_div_words(
  _left : BinFloat,
  _right : BinFloat,
  _context : BinaryContext,
) -> (BinFloat, BinaryFlags)? {
  None
}
