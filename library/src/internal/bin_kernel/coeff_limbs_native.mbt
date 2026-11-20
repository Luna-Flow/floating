///|
/// Row primitives on the native backend: the C functions of `luna_limbs.c`
/// behind wrappers that check every range once per call and fall back to the
/// portable loops (`coeff_limbs_portable_nonjs.mbt`, `coeff_words_nonjs.mbt`)
/// when the environment variable `LUNA_FLOATING_PORTABLE` is set (a test and
/// benchmark knob: results are the same either way). The other targets have the
/// same names in `coeff_limbs_other_nonjs.mbt`.

///|
extern "C" fn luna_limbs_enabled() -> Int32 = "luna_limbs_enabled"

///|
/// 1 when the stub was compiled with `unsigned __int128`, 0 for the 32-bit
/// fallback of the limb product.
pub extern "C" fn luna_limbs_has_int128() -> Int32 = "luna_limbs_has_int128"

///|
/// 1 clang, 2 gcc, 3 MSVC, 4 tcc, 0 other: the compiler of the stub.
pub extern "C" fn luna_limbs_cc_id() -> Int32 = "luna_limbs_cc_id"

///|
/// 1 x86-64, 2 arm64, 0 other: the architecture of the stub.
pub extern "C" fn luna_limbs_arch_id() -> Int32 = "luna_limbs_arch_id"

///|
/// Bit 0: BMI2, bit 1: ADX (x86-64 only, 0 elsewhere). Only logged, no code uses them.
pub extern "C" fn luna_limbs_cpu_features() -> Int32 = "luna_limbs_cpu_features"

///|
let bin_limbs_native : Bool = luna_limbs_enabled() != 0

///|
#borrow(r, a)
extern "C" fn luna_mul_1(
  r : FixedArray[UInt64],
  ro : Int32,
  a : FixedArray[UInt64],
  ao : Int32,
  n : Int32,
  b : UInt64,
) -> UInt64 = "luna_mul_1"

///|
#borrow(r, a)
extern "C" fn luna_addmul_1(
  r : FixedArray[UInt64],
  ro : Int32,
  a : FixedArray[UInt64],
  ao : Int32,
  n : Int32,
  b : UInt64,
) -> UInt64 = "luna_addmul_1"

///|
#borrow(r, a)
extern "C" fn luna_submul_1(
  r : FixedArray[UInt64],
  ro : Int32,
  a : FixedArray[UInt64],
  ao : Int32,
  n : Int32,
  b : UInt64,
) -> UInt64 = "luna_submul_1"

///|
#borrow(r, a, b)
extern "C" fn luna_school(
  r : FixedArray[UInt64],
  ro : Int32,
  a : FixedArray[UInt64],
  ao : Int32,
  an : Int32,
  b : FixedArray[UInt64],
  bo : Int32,
  bn : Int32,
) -> Unit = "luna_school"

///|
#borrow(r, s)
extern "C" fn luna_sqr_school(
  r : FixedArray[UInt64],
  ro : Int32,
  s : FixedArray[UInt64],
  so : Int32,
  len : Int32,
) -> Unit = "luna_sqr_school"

///|
/// Aborts unless `array[offset ..< offset + len]` lies inside the array.
fn bin_limbs_check_range(
  array : FixedArray[UInt64],
  offset : Int32,
  len : Int32,
) -> Unit {
  if offset < 0 || len < 0 || offset > array.length() - len {
    abort("bin_kernel limb row out of range")
  }
}

///|
/// Aborts when two ranges of the same array overlap.
fn bin_limbs_check_disjoint(
  first : FixedArray[UInt64],
  first_offset : Int32,
  first_len : Int32,
  second : FixedArray[UInt64],
  second_offset : Int32,
  second_len : Int32,
) -> Unit {
  if physical_equal(first, second) &&
    first_offset < second_offset + second_len &&
    second_offset < first_offset + first_len {
    abort("bin_kernel limb row ranges overlap")
  }
}

///|
pub fn bin_limbs_mul_1(
  r : FixedArray[UInt64],
  ro : Int32,
  a : FixedArray[UInt64],
  ao : Int32,
  n : Int32,
  b : UInt64,
) -> UInt64 {
  if bin_limbs_native {
    bin_limbs_check_range(r, ro, n)
    bin_limbs_check_range(a, ao, n)
    luna_mul_1(r, ro, a, ao, n, b)
  } else {
    bin_limbs_mul_1_portable(r, ro, a, ao, n, b)
  }
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
  if bin_limbs_native {
    bin_limbs_check_range(r, ro, n)
    bin_limbs_check_range(a, ao, n)
    luna_addmul_1(r, ro, a, ao, n, b)
  } else {
    bin_limbs_addmul_1_portable(r, ro, a, ao, n, b)
  }
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
  if bin_limbs_native {
    bin_limbs_check_range(r, ro, n)
    bin_limbs_check_range(a, ao, n)
    luna_submul_1(r, ro, a, ao, n, b)
  } else {
    bin_limbs_submul_1_portable(r, ro, a, ao, n, b)
  }
}

///|
/// `r[ro ..< ro + an + bn] = a[ao ..< ao + an] * b[bo ..< bo + bn]`, both
/// lengths at least 1, `r` not overlapping `a` or `b`.
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
  if bin_limbs_native && an > 0 && bn > 0 {
    bin_limbs_check_range(r, ro, an + bn)
    bin_limbs_check_range(a, ao, an)
    bin_limbs_check_range(b, bo, bn)
    bin_limbs_check_disjoint(r, ro, an + bn, a, ao, an)
    bin_limbs_check_disjoint(r, ro, an + bn, b, bo, bn)
    luna_school(r, ro, a, ao, an, b, bo, bn)
  } else {
    bin_coeff_words_school(r, ro, a, ao, an, b, bo, bn)
  }
}

///|
/// `r[ro ..< ro + 2 len] = s[so ..< so + len]^2`, `r` not overlapping `s`.
fn bin_limbs_sqr_school(
  r : FixedArray[UInt64],
  ro : Int32,
  s : FixedArray[UInt64],
  so : Int32,
  len : Int32,
) -> Unit {
  if bin_limbs_native && len > 0 {
    bin_limbs_check_range(r, ro, 2 * len)
    bin_limbs_check_range(s, so, len)
    bin_limbs_check_disjoint(r, ro, 2 * len, s, so, len)
    luna_sqr_school(r, ro, s, so, len)
  } else {
    bin_coeff_words_sqr_school(r, ro, s, so, len)
  }
}
