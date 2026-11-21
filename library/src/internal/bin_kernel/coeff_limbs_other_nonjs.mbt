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

///|
/// The product of two limb ranges, `r[ro ..< ro + an + bn] = a[ao ..< ao + an] *
/// b[bo ..< bo + bn]`: all `an + bn` result limbs are written, the top one being
/// the carry limb. Both lengths are at least 1 and `r` does not overlap `a` or
/// `b` (nothing is checked on this target). The rows run over the
/// limbs of `a` (each is one multiplier of the whole of `b`), so pass the shorter
/// operand or the multiplier as `a`: a row costs a call and a carry limb, and the
/// longer rows of `b` amortise both. On the native tiers with the C or assembly
/// rows it is one call into the schoolbook row loop (about 160 instructions
/// fewer than `mul_1` and `addmul_1` through their wrappers at 10 by 9 limbs); on
/// the portable tier and the other targets it is that loop of portable rows, so
/// no target pays more. The result is the same on every tier.
pub fn bin_limbs_product(
  r : FixedArray[UInt64],
  ro : Int32,
  a : FixedArray[UInt64],
  ao : Int32,
  an : Int32,
  b : FixedArray[UInt64],
  bo : Int32,
  bn : Int32,
) -> Unit {
  if an < 1 || bn < 1 {
    abort("bin_kernel limb product needs both lengths at least 1")
  }
  bin_limbs_product_portable(r, ro, a, ao, an, b, bo, bn)
}
