///|
/// Row primitives on 64-bit limbs, portable form (issue 438, section 8).
///
/// These are the reference of `luna_limbs.c`: on native the wrappers of
/// `coeff_limbs_native.mbt` call the C functions of the same name, on every
/// other target the wrappers of `coeff_limbs_other_nonjs.mbt` call these. All
/// rows take arrays and offsets in limbs and return a carry limb; none checks
/// lengths. The schoolbook product and square are `bin_coeff_words_school` and
/// `bin_coeff_words_sqr_school` (`coeff_words_nonjs.mbt`), the same contract.

///|
/// `r[ro ..< ro + n] = a[ao ..< ao + n] * b`; returns the carry limb (the limb
/// that belongs at `r[ro + n]`, which is not written).
fn bin_limbs_mul_1_portable(
  r : FixedArray[UInt64],
  ro : Int32,
  a : FixedArray[UInt64],
  ao : Int32,
  n : Int32,
  b : UInt64,
) -> UInt64 {
  let b_low = b & bin_coeff_limb_mask
  let b_high = b >> 32
  let mut carry = 0UL
  for index in 0..<n {
    let word = a.unsafe_get(ao + index)
    let low = word * b
    let word_low = word & bin_coeff_limb_mask
    let word_high = word >> 32
    let cross = b_high * word_low + ((b_low * word_low) >> 32)
    let high = b_high * word_high +
      (cross >> 32) +
      ((b_low * word_high + (cross & bin_coeff_limb_mask)) >> 32)
    let total = low + carry
    r.unsafe_set(ro + index, total)
    carry = high + (if total < low { 1UL } else { 0UL })
  }
  carry
}

///|
/// `r[ro ..< ro + n] += a[ao ..< ao + n] * b`; returns the carry limb. The
/// ranges may be the same range of one array (`r` and `a` equal): each limb of
/// both is read before the limb of `r` is written.
fn bin_limbs_addmul_1_portable(
  r : FixedArray[UInt64],
  ro : Int32,
  a : FixedArray[UInt64],
  ao : Int32,
  n : Int32,
  b : UInt64,
) -> UInt64 {
  let b_low = b & bin_coeff_limb_mask
  let b_high = b >> 32
  let mut carry = 0UL
  for index in 0..<n {
    let word = a.unsafe_get(ao + index)
    let low = word * b
    let word_low = word & bin_coeff_limb_mask
    let word_high = word >> 32
    let cross = b_high * word_low + ((b_low * word_low) >> 32)
    let high = b_high * word_high +
      (cross >> 32) +
      ((b_low * word_high + (cross & bin_coeff_limb_mask)) >> 32)
    let partial = low + carry
    let carry_one = if partial < low { 1UL } else { 0UL }
    let total = partial + r.unsafe_get(ro + index)
    let carry_two = if total < partial { 1UL } else { 0UL }
    r.unsafe_set(ro + index, total)
    carry = high + carry_one + carry_two
  }
  carry
}

///|
/// `r[ro ..< ro + n] -= a[ao ..< ao + n] * b`; returns the carry limb plus the
/// borrow out of the row, folded into one limb (it never exceeds 2^64 - 1): the
/// caller subtracts it from the limb above the row, and the row has borrowed
/// out exactly when that subtraction does. Same aliasing as
/// `bin_limbs_addmul_1_portable`.
fn bin_limbs_submul_1_portable(
  r : FixedArray[UInt64],
  ro : Int32,
  a : FixedArray[UInt64],
  ao : Int32,
  n : Int32,
  b : UInt64,
) -> UInt64 {
  let b_low = b & bin_coeff_limb_mask
  let b_high = b >> 32
  let mut carry = 0UL
  for index in 0..<n {
    let word = a.unsafe_get(ao + index)
    let low = word * b
    let word_low = word & bin_coeff_limb_mask
    let word_high = word >> 32
    let cross = b_high * word_low + ((b_low * word_low) >> 32)
    let high = b_high * word_high +
      (cross >> 32) +
      ((b_low * word_high + (cross & bin_coeff_limb_mask)) >> 32)
    let low_total = low + carry
    let carry_one = if low_total < low { 1UL } else { 0UL }
    let current = r.unsafe_get(ro + index)
    let borrow = if current < low_total { 1UL } else { 0UL }
    r.unsafe_set(ro + index, current - low_total)
    carry = high + carry_one + borrow
  }
  carry
}

///|
/// The largest magnitude of the word shifts, and the largest length (`count`,
/// `x_len`, `y_len`), that `bin_limbs_window_combine` accepts: 2^28 limbs. The
/// callers (`binary_coeff_fast_add_parts`) give lengths of at most 2^14 limbs
/// (coefficients of at most 2^20 bits) and word shifts of at most 2^24 in
/// magnitude (exponents within +-2^28); within the bound every index sum of the
/// portable body (32-bit) and of the C body (64-bit) is exact.
let bin_limbs_window_max : Int32 = 268435456

///|
/// Aborts unless the arguments of `bin_limbs_window_combine` meet its
/// contract: `0 <= count <= words.length()`, `0 <= x_len <= x.length()`,
/// `0 <= y_len <= y.length()`, bit shifts in `0 ..= 63`, word shifts of
/// magnitude at most `bin_limbs_window_max`, lengths at most the same, and
/// `words` neither `x` nor `y`.
fn bin_limbs_window_check(
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
) -> Unit {
  let limit = bin_limbs_window_max.reinterpret_as_uint()
  if count < 0 ||
    count > words.length() ||
    x_len < 0 ||
    x_len > x.length() ||
    y_len < 0 ||
    y_len > y.length() ||
    count.reinterpret_as_uint() > limit ||
    x_len.reinterpret_as_uint() > limit ||
    y_len.reinterpret_as_uint() > limit ||
    (x_word_shift + bin_limbs_window_max).reinterpret_as_uint() > 2U * limit ||
    (y_word_shift + bin_limbs_window_max).reinterpret_as_uint() > 2U * limit ||
    x_bit_shift < 0 ||
    x_bit_shift > 63 ||
    y_bit_shift < 0 ||
    y_bit_shift > 63 ||
    physical_equal(words, x) ||
    physical_equal(words, y) {
    abort("binary_kernel window row contract violated")
  }
}

///|
/// Word `index` of the window of one operand of `bin_limbs_window_combine`:
/// `words` (`len` limbs) placed so that its bit 0 is bit `64 * word_shift +
/// bit_shift` of the window; limbs outside the operand read as zero.
fn bin_limbs_window_word(
  words : FixedArray[UInt64],
  len : Int32,
  word_shift : Int32,
  bit_shift : Int32,
  index : Int32,
) -> UInt64 {
  let source = index - word_shift
  let low = if source >= 0 && source < len {
    words.unsafe_get(source)
  } else {
    0UL
  }
  if bit_shift == 0 {
    return low
  }
  let below = if source >= 1 && source <= len {
    words.unsafe_get(source - 1)
  } else {
    0UL
  }
  (low << bit_shift) | (below >> (64 - bit_shift))
}

///|
/// The portable body of `bin_limbs_window_combine` (the contract is there).
/// The limbs where every source limb of both operands exists are read without
/// a bounds test, each source limb once (the previous one is kept in a
/// register), and an operand without a bit shift is read directly instead of
/// through the two shifts (the operand that starts at the window bottom has
/// none, so one of the two usually has none: four loops by which operand is
/// shifted, plus the case without a second operand). The carry is written as
/// the comparison idiom `sum = a + b + carry; carry = (partial < a) | (sum <
/// partial)`, which the compiler turns into an add-with-carry chain when the
/// loop body is as small as in the unshifted loop (a bit expression of the
/// three words, measured, defeats that and costs more per limb). The few
/// limbs at either end go through `bin_limbs_window_word`.
fn bin_limbs_window_combine_portable(
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
  let mask = if subtract { 0xFFFFFFFFFFFFFFFFUL } else { 0UL }
  let mut carry = if subtract { 1UL - carry_in } else { carry_in }
  let use_y = y_len > 0
  let mut low = x_word_shift + 1
  let mut high = x_word_shift + x_len
  if use_y {
    low = Int32::max(low, y_word_shift + 1)
    high = Int32::min(high, y_word_shift + y_len)
  }
  low = Int32::max(0, Int32::min(low, count))
  high = Int32::min(count, Int32::max(high, low))
  for index in 0..<low {
    let a = bin_limbs_window_word(x, x_len, x_word_shift, x_bit_shift, index)
    let b = bin_limbs_window_word(y, y_len, y_word_shift, y_bit_shift, index) ^
      mask
    let partial = a + b
    let sum = partial + carry
    let first = if partial < a { 1UL } else { 0UL }
    let second = if sum < partial { 1UL } else { 0UL }
    carry = first | second
    words.unsafe_set(index, sum)
  }
  if low < high {
    if use_y {
      if x_bit_shift == 0 && y_bit_shift == 0 {
        for index in low..<high {
          let a = x.unsafe_get(index - x_word_shift)
          let b = y.unsafe_get(index - y_word_shift) ^ mask
          let partial = a + b
          let sum = partial + carry
          let first = if partial < a { 1UL } else { 0UL }
          let second = if sum < partial { 1UL } else { 0UL }
          carry = first | second
          words.unsafe_set(index, sum)
        }
      } else if x_bit_shift == 0 {
        let y_down = 63 - y_bit_shift
        let mut y_previous = y.unsafe_get(low - y_word_shift - 1)
        for index in low..<high {
          let y_current = y.unsafe_get(index - y_word_shift)
          let a = x.unsafe_get(index - x_word_shift)
          let b = ((y_current << y_bit_shift) | (y_previous >> 1 >> y_down)) ^
            mask
          y_previous = y_current
          let partial = a + b
          let sum = partial + carry
          let first = if partial < a { 1UL } else { 0UL }
          let second = if sum < partial { 1UL } else { 0UL }
          carry = first | second
          words.unsafe_set(index, sum)
        }
      } else if y_bit_shift == 0 {
        let x_down = 63 - x_bit_shift
        let mut x_previous = x.unsafe_get(low - x_word_shift - 1)
        for index in low..<high {
          let x_current = x.unsafe_get(index - x_word_shift)
          let a = (x_current << x_bit_shift) | (x_previous >> 1 >> x_down)
          let b = y.unsafe_get(index - y_word_shift) ^ mask
          x_previous = x_current
          let partial = a + b
          let sum = partial + carry
          let first = if partial < a { 1UL } else { 0UL }
          let second = if sum < partial { 1UL } else { 0UL }
          carry = first | second
          words.unsafe_set(index, sum)
        }
      } else {
        let x_down = 63 - x_bit_shift
        let y_down = 63 - y_bit_shift
        let mut x_previous = x.unsafe_get(low - x_word_shift - 1)
        let mut y_previous = y.unsafe_get(low - y_word_shift - 1)
        for index in low..<high {
          let x_current = x.unsafe_get(index - x_word_shift)
          let y_current = y.unsafe_get(index - y_word_shift)
          let a = (x_current << x_bit_shift) | (x_previous >> 1 >> x_down)
          let b = ((y_current << y_bit_shift) | (y_previous >> 1 >> y_down)) ^
            mask
          x_previous = x_current
          y_previous = y_current
          let partial = a + b
          let sum = partial + carry
          let first = if partial < a { 1UL } else { 0UL }
          let second = if sum < partial { 1UL } else { 0UL }
          carry = first | second
          words.unsafe_set(index, sum)
        }
      }
    } else {
      let x_down = 63 - x_bit_shift
      let mut x_previous = x.unsafe_get(low - x_word_shift - 1)
      for index in low..<high {
        let x_current = x.unsafe_get(index - x_word_shift)
        let a = (x_current << x_bit_shift) | (x_previous >> 1 >> x_down)
        x_previous = x_current
        let partial = a + mask
        let sum = partial + carry
        let first = if partial < a { 1UL } else { 0UL }
        let second = if sum < partial { 1UL } else { 0UL }
        carry = first | second
        words.unsafe_set(index, sum)
      }
    }
  }
  for index in high..<count {
    let a = bin_limbs_window_word(x, x_len, x_word_shift, x_bit_shift, index)
    let b = bin_limbs_window_word(y, y_len, y_word_shift, y_bit_shift, index) ^
      mask
    let partial = a + b
    let sum = partial + carry
    let first = if partial < a { 1UL } else { 0UL }
    let second = if sum < partial { 1UL } else { 0UL }
    carry = first | second
    words.unsafe_set(index, sum)
  }
  if subtract {
    1UL - carry
  } else {
    carry
  }
}

///|
/// `r[ro ..< ro + an + bn] = a[ao ..< ao + an] * b[bo ..< bo + bn]` as one `mul_1`
/// and `an - 1` `addmul_1` rows: row `j` multiplies `b` by the limb `a[ao + j]`
/// and its carry limb is the result limb `ro + j + bn`. The reference form of
/// `bin_limbs_product`; `r` does not overlap `a` or `b`, both lengths are at
/// least 1, and nothing is checked.
fn bin_limbs_product_portable(
  r : FixedArray[UInt64],
  ro : Int32,
  a : FixedArray[UInt64],
  ao : Int32,
  an : Int32,
  b : FixedArray[UInt64],
  bo : Int32,
  bn : Int32,
) -> Unit {
  r.unsafe_set(
    ro + bn,
    bin_limbs_mul_1_portable(r, ro, b, bo, bn, a.unsafe_get(ao)),
  )
  for j in 1..<an {
    r.unsafe_set(
      ro + j + bn,
      bin_limbs_addmul_1_portable(r, ro + j, b, bo, bn, a.unsafe_get(ao + j)),
    )
  }
}
