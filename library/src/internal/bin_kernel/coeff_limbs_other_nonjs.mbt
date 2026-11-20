///|
/// Row primitives on the targets without the C stub (wasm, wasm-gc, llvm): the
/// portable loops. The native counterpart, with the same names and signatures,
/// is `coeff_limbs_native.mbt`.

///|
pub fn bin_limbs_mul_1(
  r : FixedArray[UInt64],
  ro : Int32,
  a : FixedArray[UInt64],
  ao : Int32,
  n : Int32,
  b : UInt64,
) -> UInt64 {
  bin_limbs_mul_1_portable(r, ro, a, ao, n, b)
}

///|
pub fn bin_limbs_addmul_1(
  r : FixedArray[UInt64],
  ro : Int32,
  a : FixedArray[UInt64],
  ao : Int32,
  n : Int32,
  b : UInt64,
) -> UInt64 {
  bin_limbs_addmul_1_portable(r, ro, a, ao, n, b)
}

///|
pub fn bin_limbs_submul_1(
  r : FixedArray[UInt64],
  ro : Int32,
  a : FixedArray[UInt64],
  ao : Int32,
  n : Int32,
  b : UInt64,
) -> UInt64 {
  bin_limbs_submul_1_portable(r, ro, a, ao, n, b)
}

///|
fn bin_limbs_school(
  r : FixedArray[UInt64],
  ro : Int32,
  a : FixedArray[UInt64],
  ao : Int32,
  an : Int32,
  b : FixedArray[UInt64],
  bo : Int32,
  bn : Int32,
) -> Unit {
  bin_coeff_words_school(r, ro, a, ao, an, b, bo, bn)
}

///|
fn bin_limbs_sqr_school(
  r : FixedArray[UInt64],
  ro : Int32,
  s : FixedArray[UInt64],
  so : Int32,
  len : Int32,
) -> Unit {
  bin_coeff_words_sqr_school(r, ro, s, so, len)
}

///|
pub fn bin_limbs_window_combine(
  words : FixedArray[UInt64],
  count : Int32,
  x : FixedArray[UInt64],
  x_len : Int32,
  x_word_shift : Int32,
  x_bit_shift : Int32,
  y : FixedArray[UInt64],
  y_len : Int32,
  y_word_shift : Int32,
  y_bit_shift : Int32,
  subtract : Bool,
  carry_in : UInt64,
) -> UInt64 {
  bin_limbs_window_check(
    words, count, x, x_len, x_word_shift, x_bit_shift, y, y_len, y_word_shift, y_bit_shift,
  )
  bin_limbs_window_combine_portable(
    words, count, x, x_len, x_word_shift, x_bit_shift, y, y_len, y_word_shift, y_bit_shift,
    subtract, carry_in,
  )
}

///|
/// Smallest product, in limbs, that the NTT multiplies, besides the limit on
/// the shorter operand (`bin_coeff_ntt_mul_min_words`): none on the targets
/// without the native row implementations, where the limit on the shorter
/// operand is the whole rule. The native value is in `coeff_thresholds_native.mbt`.
let bin_coeff_ntt_mul_min_product_words : Int32 = 0
