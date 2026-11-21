///|
/// Row primitives on the native backend: the C functions of `luna_limbs.c`
/// behind wrappers that check every range once per call and fall back to the
/// portable loops (`coeff_limbs_portable_nonjs.mbt`, `coeff_words_nonjs.mbt`)
/// when the environment variable `LUNA_FLOATING_PORTABLE` is set (a test and
/// benchmark knob: results are the same either way). The other targets have the
/// same names in `coeff_limbs_other_nonjs.mbt`.

///|
extern "C" fn luna_limbs_mode() -> Int32 = "luna_limbs_mode"

///|
/// 1 when the assembly tier is compiled in (arm64 Apple), 0 when the `_asm` entries are the C rows.
pub extern "C" fn luna_limbs_tier() -> Int32 = "luna_limbs_tier"

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
/// 1 when the build is Apple arm64 with clang or gcc, where the assembly tier must be active.
pub extern "C" fn luna_limbs_expects_asm() -> Int32 = "luna_limbs_expects_asm"

///|
/// 1 when `LUNA_FLOATING_PORTABLE` or `LUNA_FLOATING_LIMBS` is set.
pub extern "C" fn luna_limbs_override_set() -> Int32 = "luna_limbs_override_set"

///|
/// 0 portable MoonBit loops, 1 C rows, 2 assembly rows (see `luna_limbs.c`).
let bin_limbs_mode : Int32 = luna_limbs_mode()

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
extern "C" fn luna_mul_1_asm(
  r : FixedArray[UInt64],
  ro : Int32,
  a : FixedArray[UInt64],
  ao : Int32,
  n : Int32,
  b : UInt64,
) -> UInt64 = "luna_mul_1_asm"

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
extern "C" fn luna_addmul_1_asm(
  r : FixedArray[UInt64],
  ro : Int32,
  a : FixedArray[UInt64],
  ao : Int32,
  n : Int32,
  b : UInt64,
) -> UInt64 = "luna_addmul_1_asm"

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
#borrow(r, a)
extern "C" fn luna_submul_1_asm(
  r : FixedArray[UInt64],
  ro : Int32,
  a : FixedArray[UInt64],
  ao : Int32,
  n : Int32,
  b : UInt64,
) -> UInt64 = "luna_submul_1_asm"

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
#borrow(r, a, b)
extern "C" fn luna_school_asm(
  r : FixedArray[UInt64],
  ro : Int32,
  a : FixedArray[UInt64],
  ao : Int32,
  an : Int32,
  b : FixedArray[UInt64],
  bo : Int32,
  bn : Int32,
) -> Unit = "luna_school_asm"

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
#borrow(r, s)
extern "C" fn luna_sqr_school_asm(
  r : FixedArray[UInt64],
  ro : Int32,
  s : FixedArray[UInt64],
  so : Int32,
  len : Int32,
) -> Unit = "luna_sqr_school_asm"

///|
/// Aborts unless `array[offset ..< offset + len]` lies inside the array.
fn bin_limbs_check_range(
  array : FixedArray[UInt64],
  offset : Int32,
  len : Int32,
) -> Unit {
  if offset < 0 || len < 0 || offset > array.length() - len {
    abort("binary_kernel limb row out of range")
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
    abort("binary_kernel limb row ranges overlap")
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
  if bin_limbs_mode != 0 {
    bin_limbs_check_range(r, ro, n)
    bin_limbs_check_range(a, ao, n)
    if bin_limbs_mode == 2 {
      luna_mul_1_asm(r, ro, a, ao, n, b)
    } else {
      luna_mul_1(r, ro, a, ao, n, b)
    }
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
  if bin_limbs_mode != 0 {
    bin_limbs_check_range(r, ro, n)
    bin_limbs_check_range(a, ao, n)
    if bin_limbs_mode == 2 {
      luna_addmul_1_asm(r, ro, a, ao, n, b)
    } else {
      luna_addmul_1(r, ro, a, ao, n, b)
    }
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
  if bin_limbs_mode != 0 {
    bin_limbs_check_range(r, ro, n)
    bin_limbs_check_range(a, ao, n)
    if bin_limbs_mode == 2 {
      luna_submul_1_asm(r, ro, a, ao, n, b)
    } else {
      luna_submul_1(r, ro, a, ao, n, b)
    }
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
  if bin_limbs_mode != 0 && an > 0 && bn > 0 {
    bin_limbs_check_range(r, ro, an + bn)
    bin_limbs_check_range(a, ao, an)
    bin_limbs_check_range(b, bo, bn)
    bin_limbs_check_disjoint(r, ro, an + bn, a, ao, an)
    bin_limbs_check_disjoint(r, ro, an + bn, b, bo, bn)
    if bin_limbs_mode == 2 {
      luna_school_asm(r, ro, a, ao, an, b, bo, bn)
    } else {
      luna_school(r, ro, a, ao, an, b, bo, bn)
    }
  } else {
    bin_coeff_words_school(r, ro, a, ao, an, b, bo, bn)
  }
}

///|
/// The product of two limb ranges, `r[ro ..< ro + an + bn] = a[ao ..< ao + an] *
/// b[bo ..< bo + bn]`: all `an + bn` result limbs are written, the top one being
/// the carry limb. Both lengths are at least 1 and `r` does not overlap `a` or
/// `b` (aborts otherwise, as does a range outside an array, where the C or
/// assembly rows run; the portable path checks nothing). The rows run over the
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
    abort("binary_kernel limb product needs both lengths at least 1")
  }
  if bin_limbs_mode != 0 {
    bin_limbs_check_range(r, ro, an + bn)
    bin_limbs_check_range(a, ao, an)
    bin_limbs_check_range(b, bo, bn)
    bin_limbs_check_disjoint(r, ro, an + bn, a, ao, an)
    bin_limbs_check_disjoint(r, ro, an + bn, b, bo, bn)
    if bin_limbs_mode == 2 {
      luna_school_asm(r, ro, a, ao, an, b, bo, bn)
    } else {
      luna_school(r, ro, a, ao, an, b, bo, bn)
    }
  } else {
    bin_limbs_product_portable(r, ro, a, ao, an, b, bo, bn)
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
  if bin_limbs_mode != 0 && len > 0 {
    bin_limbs_check_range(r, ro, 2 * len)
    bin_limbs_check_range(s, so, len)
    bin_limbs_check_disjoint(r, ro, 2 * len, s, so, len)
    if bin_limbs_mode == 2 {
      luna_sqr_school_asm(r, ro, s, so, len)
    } else {
      luna_sqr_school(r, ro, s, so, len)
    }
  } else {
    bin_coeff_words_sqr_school(r, ro, s, so, len)
  }
}

///|
#borrow(words, x, y)
extern "C" fn luna_window_combine(
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
  subtract : Int32,
  carry_in : UInt64,
) -> UInt64 = "luna_window_combine"

///|
/// Shortest window, in limbs, that goes to the C body: the call into C, its
/// range checks and the generic limbs at the two ends cost about 200
/// instructions, which the portable body (no call, one edge limb at each end)
/// does not pay, so below this length the portable body is faster. Measured
/// (instructions per call, one operand shifted by one bit, 9 to 40 limbs of
/// both operands, the two bodies in one executable): portable / C 323 / 337 at
/// 12 limbs, 387 / 374 at 16, 451 / 411 at 20, 643 / 522 at 32; both operands
/// shifted: 394 / 391 at 12, 478 / 441 at 16.
let bin_limbs_window_c_min_count : Int32 = 14

///|
/// The window row of the wide sum of two coefficients, one pass over `count`
/// limbs. Contract:
///
/// - Operands: `x` (`x_len` limbs) and `y` (`y_len` limbs), read only, each
///   viewed through a window: limb `index` of the window of `w` with word
///   shift `ws` and bit shift `bs` is `(w[index - ws] << bs) | (w[index - ws -
///   1] >> (64 - bs))` (just `w[index - ws]` when `bs = 0`), a source index
///   outside `0 ..< len` reading as zero. `0 <= x_bit_shift, y_bit_shift <=
///   63`; the word shifts are within `-bin_limbs_window_max ..= bin_limbs_window_max`
///   (2^28; the callers give magnitudes of at most 2^24: `y_word_shift` is
///   negative when the operand is cut at the window bottom, and the callers'
///   `x_word_shift` is not), and `count`, `x_len` and `y_len` are at most
///   `bin_limbs_window_max` as well, so that no index sum wraps in either body.
///   `y_len = 0` means no second operand: it reads as zero everywhere.
///   Every combination of shifts is allowed; `x` and `y` may be the same
///   array.
/// - Result: `words[0 ..< count]` (`count >= 1`, `words` at least that long)
///   receives `x_window + (y_window ^ mask) + carry` limb by limb, where
///   `mask` is zero for an addition and all ones for a subtraction, and the
///   carry in is `carry_in` for an addition and `1 - carry_in` for a
///   subtraction (so that `x - y - carry_in`, `carry_in` a borrow, is
///   `x + !y + (1 - carry_in)`). `words` must not be `x` or `y`.
/// - Return: the carry out of the top limb for an addition, and `1 - carry
///   out` (the borrow out) for a subtraction.
/// - Past the shorter operand: limbs beyond an operand read as zero (for a
///   subtraction a missing `y` reads as all ones after the mask), so the pass
///   always runs over all `count` limbs.
/// - It computes exactly the previous loop of `binary_coeff_fast_add_parts`
///   (`bin_window_combine`), which is the reference of the tests.
///
/// Tiers: native with the C rows or the assembly tier calls the C body for
/// windows of at least `bin_limbs_window_c_min_count` limbs (there is no
/// assembly body for this row yet: the assembly tier runs the C one); shorter
/// windows, the portable configuration and the other targets run
/// `bin_limbs_window_combine_portable`.
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
  if bin_limbs_mode != 0 && count >= bin_limbs_window_c_min_count {
    luna_window_combine(
      words,
      count,
      x,
      x_len,
      x_word_shift,
      x_bit_shift,
      y,
      y_len,
      y_word_shift,
      y_bit_shift,
      if subtract {
        1
      } else {
        0
      },
      carry_in,
    )
  } else {
    bin_limbs_window_combine_portable(
      words, count, x, x_len, x_word_shift, x_bit_shift, y, y_len, y_word_shift,
      y_bit_shift, subtract, carry_in,
    )
  }
}
