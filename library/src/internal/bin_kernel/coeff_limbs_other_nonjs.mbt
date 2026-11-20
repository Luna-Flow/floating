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
