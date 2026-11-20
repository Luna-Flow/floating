///|
// Integer square root with remainder by Zimmermann's Karatsuba square root,
// `SqrtRem` (P. Zimmermann, "Karatsuba Square Root", INRIA RR-3805, 1999, and
// Brent and Zimmermann, "Modern Computer Arithmetic", Algorithm 1.12), on limbs
// of base 10^9 in `FixedArray[UInt64]` (every limb below the base).
//
// With `n` limbs, `l = floor((n - 1) / 4)` limbs per block, `X = 10^(9 l)`,
// the radicand is `N = H X^2 + a1 X + a0` (`a1`, `a0` below `X`, `H` the top
// `n - 2 l` limbs). The root `s'` and remainder `r'` of `H` come from the
// recursion; `(q, u) = divrem(r' X + a1, 2 s')`, `s = s' X + q` and
// `r = u X + a0 - q^2`; if `r < 0` then `r = r + 2 s - 1` and `s = s - 1`.
//
// The report proves the correctness for `H = a3 X + a2` with `a3 >= X / 4` (its
// condition `a3 >= b/4`; one correction step is then enough). Here
// `l <= (n - 1) / 4` gives `n - 3 l >= l + 1` limbs to `a3`, so `a3 >= X`: the
// condition holds for every radicand whose top limb is not zero, without
// scaling it. (The binary kernel scales its radicand by an even power of 2 to
// an even limb count because its blocks and leaf are laid out on halves of
// the limb count; here the split is at any limb count.)
//
// Division by `2 s'`: `s'` is divided into `floor(D / 2)` (`floor(D / (2 s')) =
// floor(floor(D / 2) / s')`, and the remainder of `D` by `2 s'` is `2 r +
// (D mod 2)` for the remainder `r` of `floor(D / 2)` by `s'`), so `2 s'` is
// never formed and cannot carry out of the limb count of `s'`. The divisor
// `s'` is normalized for Knuth's algorithm D (multiplied with the dividend by
// `base / (top + 1)`, the remainder divided back). The quotient is at most
// `X` (the proof: `q <= floor((2 s' X + a1) / (2 s')) <= X`); a quotient of
// exactly `X` is capped to `X - 1` and `2 s'` is added to `u`, since the root
// cannot exceed `s' X + X - 1` (`H < (s' + 1)^2`).
//
// Base case: up to four limbs (`l = 0`) a root of at most 18 digits, from a
// double estimate corrected with exact limb arithmetic.

///|
let dec_sqrt_base : UInt64 = 1000000000UL

///|
/// Statistics of one root, filled only when a test passes a record down the
/// recursion (the production path passes none and writes nothing): the depth
/// of every leaf, the quotients capped at `X - 1` and the correction steps.
#warnings("-struct_never_constructed-unused_field")
priv struct DecSqrtStats {
  leaf_depths : Array[Int32]
  mut caps : Int32
  mut corrections : Int32
}

///|
/// `limbs[offset ..< offset + count]` compared with `other[0 ..< other_count]`,
/// as numbers (limbs beyond a count are zero).
fn dec_sqrt_compare(
  left : FixedArray[UInt64],
  left_count : Int32,
  right : FixedArray[UInt64],
  right_count : Int32,
) -> Int32 {
  let count = if left_count > right_count { left_count } else { right_count }
  let mut index = count - 1
  while index >= 0 {
    let a = if index < left_count { left.unsafe_get(index) } else { 0UL }
    let b = if index < right_count { right.unsafe_get(index) } else { 0UL }
    if a != b {
      return if a < b { -1 } else { 1 }
    }
    index -= 1
  }
  0
}

///|
/// `target[offset ..< offset + count] += addend[0 ..< addend_count]`, the carry
/// propagated up to `count` limbs (which must hold the sum).
fn dec_sqrt_add_into(
  target : FixedArray[UInt64],
  offset : Int32,
  count : Int32,
  addend : FixedArray[UInt64],
  addend_count : Int32,
) -> Unit {
  let mut carry = 0UL
  for index in 0..<count {
    let other = if index < addend_count {
      addend.unsafe_get(index)
    } else {
      0UL
    }
    if index >= addend_count && carry == 0UL {
      break
    }
    let sum = target.unsafe_get(offset + index) + other + carry
    if sum >= dec_sqrt_base {
      target.unsafe_set(offset + index, sum - dec_sqrt_base)
      carry = 1UL
    } else {
      target.unsafe_set(offset + index, sum)
      carry = 0UL
    }
  }
}

///|
/// `target[0 ..< count] -= subtrahend[0 ..< subtrahend_count]`, which must not
/// exceed it.
fn dec_sqrt_sub_from(
  target : FixedArray[UInt64],
  count : Int32,
  subtrahend : FixedArray[UInt64],
  subtrahend_count : Int32,
) -> Unit {
  let mut borrow = 0UL
  for index in 0..<count {
    let other = if index < subtrahend_count {
      subtrahend.unsafe_get(index)
    } else {
      0UL
    }
    if index >= subtrahend_count && borrow == 0UL {
      break
    }
    let value = target.unsafe_get(index)
    let take = other + borrow
    if value < take {
      target.unsafe_set(index, value + dec_sqrt_base - take)
      borrow = 1UL
    } else {
      target.unsafe_set(index, value - take)
      borrow = 0UL
    }
  }
}

///|
/// `target[0 ..< count] -= 1`, which must not be zero.
fn dec_sqrt_decrement(target : FixedArray[UInt64], count : Int32) -> Unit {
  for index in 0..<count {
    let value = target.unsafe_get(index)
    if value == 0UL {
      target.unsafe_set(index, dec_sqrt_base - 1UL)
    } else {
      target.unsafe_set(index, value - 1UL)
      break
    }
  }
}

///|
/// The square of `value[0 ..< count]` into `square[0 ..< 2 count]` (zeroed by
/// the caller): schoolbook up to the size where the kernel's squaring wins.
fn dec_sqrt_square(
  value : FixedArray[UInt64],
  count : Int32,
  square : FixedArray[UInt64],
) -> Unit {
  if count > dec_sqrt_square_threshold {
    let units : Array[UInt32] = Array::make(count, 0U)
    for index in 0..<count {
      units[index] = value.unsafe_get(index).to_uint()
    }
    let squared = dec_coeff_square_repr(
      dec_coeff_from_unit_accumulator(units, count),
    )
    let length = dec_coeff_unit_len(squared)
    for index in 0..<length {
      square.unsafe_set(index, dec_coeff_limb_at(squared, index).to_uint64())
    }
    return
  }
  for i in 0..<count {
    let multiplier = value.unsafe_get(i)
    if multiplier == 0UL {
      continue
    }
    let mut carry = 0UL
    for j in 0..<count {
      let current = square.unsafe_get(i + j) +
        multiplier * value.unsafe_get(j) +
        carry
      carry = current / dec_sqrt_base
      square.unsafe_set(i + j, current - carry * dec_sqrt_base)
    }
    square.unsafe_set(i + count, carry)
  }
}

///|
/// The limb count below which the schoolbook square is used.
let dec_sqrt_square_threshold : Int32 = 16

///|
/// `N - s^2` of the four-limb radicand `n3 n2 n1 n0` and `s = high * 10^9 +
/// low`: the magnitude in `work[0 ..< 4]`, and whether the difference is
/// negative.
fn dec_sqrt_leaf_residual(
  n0 : UInt64,
  n1 : UInt64,
  n2 : UInt64,
  n3 : UInt64,
  high : UInt64,
  low : UInt64,
  work : FixedArray[UInt64],
) -> Bool {
  let base = dec_sqrt_base
  let low_square = low * low
  let c0 = low_square % base
  let t1 = 2UL * high * low + low_square / base
  let c1 = t1 % base
  let t2 = high * high + t1 / base
  let c2 = t2 % base
  let c3 = t2 / base
  // compare N with s^2 from the top
  let negative = if n3 != c3 {
    n3 < c3
  } else if n2 != c2 {
    n2 < c2
  } else if n1 != c1 {
    n1 < c1
  } else {
    n0 < c0
  }
  // the larger minus the smaller
  let mut a0 = n0
  let mut a1 = n1
  let mut a2 = n2
  let mut a3 = n3
  let mut b0 = c0
  let mut b1 = c1
  let mut b2 = c2
  let mut b3 = c3
  if negative {
    a0 = c0
    a1 = c1
    a2 = c2
    a3 = c3
    b0 = n0
    b1 = n1
    b2 = n2
    b3 = n3
  }
  let mut borrow = 0UL
  let mut take = b0
  if a0 < take {
    work.unsafe_set(0, a0 + base - take)
    borrow = 1UL
  } else {
    work.unsafe_set(0, a0 - take)
  }
  take = b1 + borrow
  borrow = 0UL
  if a1 < take {
    work.unsafe_set(1, a1 + base - take)
    borrow = 1UL
  } else {
    work.unsafe_set(1, a1 - take)
  }
  take = b2 + borrow
  borrow = 0UL
  if a2 < take {
    work.unsafe_set(2, a2 + base - take)
    borrow = 1UL
  } else {
    work.unsafe_set(2, a2 - take)
  }
  take = b3 + borrow
  work.unsafe_set(3, if a3 < take { 0UL } else { a3 - take })
  negative
}

///|
/// Root (`root[0 ..< 2]`) and remainder (`rem[0 ..< 3]`) of the radicand of at
/// most four limbs `source[start ..< start + n]`.
fn dec_sqrt_leaf(
  source : FixedArray[UInt64],
  start : Int32,
  n : Int32,
  root : FixedArray[UInt64],
  rem : FixedArray[UInt64],
) -> Unit {
  let n0 = source.unsafe_get(start)
  let n1 = if n > 1 { source.unsafe_get(start + 1) } else { 0UL }
  let n2 = if n > 2 { source.unsafe_get(start + 2) } else { 0UL }
  let n3 = if n > 3 { source.unsafe_get(start + 3) } else { 0UL }
  let base = dec_sqrt_base
  if n <= 2 {
    let value = n0 + n1 * base
    let (s, r) = dec_coeff_isqrt_word(value)
    root.unsafe_set(0, s)
    rem.unsafe_set(0, r % base)
    rem.unsafe_set(1, r / base)
    return
  }
  let high_part = n2 + n3 * base
  let low_part = n0 + n1 * base
  let estimate = high_part.to_double() * 1.0e18 + low_part.to_double()
  let mut s = estimate.sqrt().to_uint64()
  let work : FixedArray[UInt64] = FixedArray::make(4, 0UL)
  // one Newton correction from the exact residual, then single steps
  let mut negative = dec_sqrt_leaf_residual(
    n0,
    n1,
    n2,
    n3,
    s / base,
    s % base,
    work,
  )
  let magnitude = work.unsafe_get(3).to_double() * 1.0e27 +
    work.unsafe_get(2).to_double() * 1.0e18 +
    work.unsafe_get(1).to_double() * 1.0e9 +
    work.unsafe_get(0).to_double()
  let step = (magnitude / (2.0 * s.to_double())).to_uint64()
  if step > 0UL {
    s = if negative { s - step } else { s + step }
    negative = dec_sqrt_leaf_residual(n0, n1, n2, n3, s / base, s % base, work)
  }
  while negative {
    s -= 1UL
    negative = dec_sqrt_leaf_residual(n0, n1, n2, n3, s / base, s % base, work)
  }
  // `rem` above `2 s`: the residual is the sum of `r_high * 10^18 + r_low`
  while true {
    let r_high = work.unsafe_get(2) + work.unsafe_get(3) * base
    let r_low = work.unsafe_get(0) + work.unsafe_get(1) * base
    let double = 2UL * s
    let above = if r_high > 2UL {
      true
    } else if r_high == 2UL {
      r_low > double - 2000000000000000000UL || double < 2000000000000000000UL
    } else if r_high == 1UL {
      double < 1000000000000000000UL || r_low > double - 1000000000000000000UL
    } else {
      r_low > double
    }
    if !above {
      break
    }
    s += 1UL
    negative = dec_sqrt_leaf_residual(n0, n1, n2, n3, s / base, s % base, work)
    if negative {
      abort("dec_sqrt_leaf: the estimate exceeded the root after a step up")
    }
  }
  root.unsafe_set(0, s % base)
  root.unsafe_set(1, s / base)
  rem.unsafe_set(0, work.unsafe_get(0))
  rem.unsafe_set(1, work.unsafe_get(1))
  rem.unsafe_set(2, work.unsafe_get(2))
}

///|
/// Root (`ceil(n / 2)` limbs) and remainder (one limb more) of the `n`-limb
/// radicand `source[start ..< start + n]` (top limb not zero) into `root` and
/// `rem`.
fn dec_sqrt_rec(
  source : FixedArray[UInt64],
  start : Int32,
  n : Int32,
  root : FixedArray[UInt64],
  rem : FixedArray[UInt64],
  depth~ : Int32 = 0,
  stats? : DecSqrtStats,
) -> Unit {
  if n <= 4 {
    if stats is Some(record) {
      record.leaf_depths.push(depth)
    }
    dec_sqrt_leaf(source, start, n, root, rem)
    return
  }
  let base = dec_sqrt_base
  let block = (n - 1) / 4
  let high_len = n - 2 * block
  let high_roots = (high_len + 1) / 2
  let root_len = high_roots + block
  let high_root : FixedArray[UInt64] = FixedArray::make(high_roots, 0UL)
  let high_rem : FixedArray[UInt64] = FixedArray::make(high_roots + 1, 0UL)
  dec_sqrt_rec(
    source,
    start + 2 * block,
    high_len,
    high_root,
    high_rem,
    depth=depth + 1,
    stats?,
  )
  // D = high_rem * X + a1, halved: the dividend of the division by `s'`
  let dividend_len = high_roots + block
  let dividend : FixedArray[UInt64] = FixedArray::make(dividend_len + 1, 0UL)
  let whole : FixedArray[UInt64] = FixedArray::make(dividend_len + 1, 0UL)
  for index in 0..<block {
    whole.unsafe_set(index, source.unsafe_get(start + block + index))
  }
  for index in 0..<(high_roots + 1) {
    whole.unsafe_set(block + index, high_rem.unsafe_get(index))
  }
  let mut parity = 0UL
  let mut index = dividend_len
  while index >= 0 {
    let current = parity * base + whole.unsafe_get(index)
    dividend.unsafe_set(index, current / 2UL)
    parity = current % 2UL
    index -= 1
  }
  let low_bit = parity
  // normalize the divisor `s'` (at least two limbs) and the dividend
  let top = high_root.unsafe_get(high_roots - 1)
  let unit = base / (top + 1UL)
  let divisor : FixedArray[UInt64] = FixedArray::make(high_roots, 0UL)
  let mut carry = 0UL
  if unit == 1UL {
    for position in 0..<high_roots {
      divisor.unsafe_set(position, high_root.unsafe_get(position))
    }
  } else {
    for position in 0..<high_roots {
      let current = high_root.unsafe_get(position) * unit + carry
      carry = current / base
      divisor.unsafe_set(position, current - carry * base)
    }
    carry = 0UL
    for position in 0..<dividend_len {
      let current = dividend.unsafe_get(position) * unit + carry
      carry = current / base
      dividend.unsafe_set(position, current - carry * base)
    }
    dividend.unsafe_set(dividend_len, carry)
  }
  let quotient : Array[UInt32] = Array::make(block + 1, 0U)
  dec_coeff_knuth_core(dividend, dividend_len, divisor, high_roots, quotient)
  // the remainder of floor(D / 2) by s', denormalized
  if unit != 1UL {
    let mut remainder = 0UL
    let mut position = high_roots - 1
    while position >= 0 {
      let current = remainder * base + dividend.unsafe_get(position)
      dividend.unsafe_set(position, current / unit)
      remainder = current % unit
      position -= 1
    }
  }
  let capped = quotient[block] != 0U
  if capped && stats is Some(record) {
    record.caps += 1
  }
  // the root: s' X + q, with q capped at X - 1
  for position in 0..<block {
    root.unsafe_set(
      position,
      if capped {
        base - 1UL
      } else {
        quotient[position].to_uint64()
      },
    )
  }
  for position in 0..<high_roots {
    root.unsafe_set(block + position, high_root.unsafe_get(position))
  }
  // partial = u X + a0, u = 2 r + (D mod 2) (plus 2 s' when capped)
  let partial_len = root_len + 1
  let partial : FixedArray[UInt64] = FixedArray::make(partial_len, 0UL)
  for position in 0..<block {
    partial.unsafe_set(position, source.unsafe_get(start + position))
  }
  carry = low_bit
  for position in 0..<high_roots {
    let current = dividend.unsafe_get(position) * 2UL + carry
    carry = current / base
    partial.unsafe_set(block + position, current - carry * base)
  }
  partial.unsafe_set(block + high_roots, carry)
  if capped {
    dec_sqrt_add_into(partial, block, high_roots + 1, high_root, high_roots)
    dec_sqrt_add_into(partial, block, high_roots + 1, high_root, high_roots)
  }
  let square : FixedArray[UInt64] = FixedArray::make(2 * block, 0UL)
  dec_sqrt_square(root, block, square)
  // `root` holds the root candidate; only its low `block` limbs are `q`
  if dec_sqrt_compare(partial, partial_len, square, 2 * block) >= 0 {
    for position in 0..<partial_len {
      rem.unsafe_set(position, partial.unsafe_get(position))
    }
    dec_sqrt_sub_from(rem, partial_len, square, 2 * block)
  } else {
    // r = partial + 2 s - 1 - q^2 and s = s - 1
    if stats is Some(record) {
      record.corrections += 1
    }
    dec_sqrt_add_into(partial, 0, partial_len, root, root_len)
    dec_sqrt_add_into(partial, 0, partial_len, root, root_len)
    dec_sqrt_decrement(partial, partial_len)
    dec_sqrt_sub_from(partial, partial_len, square, 2 * block)
    for position in 0..<partial_len {
      rem.unsafe_set(position, partial.unsafe_get(position))
    }
    dec_sqrt_decrement(root, root_len)
  }
}

///|
/// How the remainder `rem = n - s^2` of a floor root `s` compares with the
/// root: what the rounding of the root to the nearest needs, since
/// `n > (s + 1/2)^2` iff `rem > s` (`(s + 1/2)^2 = s^2 + s + 1/4` and `rem` is
/// an integer), and a tie cannot occur.
#derive(Eq, Debug)
pub(all) enum DecSqrtRemainder {
  /// `rem = 0`: the root is exact
  Zero
  /// `0 < rem <= s`: the root is below the midpoint of its neighbours
  UpToRoot
  /// `rem > s`: the root is above the midpoint
  AboveRoot
}

///|
/// The limbs of `n` in a `FixedArray`, its root and remainder by `dec_sqrt_rec`:
/// `(root, remainder, root_len)`; `n` has at least three limbs.
fn dec_sqrt_run(
  n : DecCoeff,
  stats? : DecSqrtStats,
) -> (FixedArray[UInt64], FixedArray[UInt64], Int32) {
  let length = dec_coeff_unit_len(n)
  let source : FixedArray[UInt64] = FixedArray::make(length, 0UL)
  for index in 0..<length {
    source.unsafe_set(index, dec_coeff_limb_at(n, index).to_uint64())
  }
  let root_len = (length + 1) / 2
  let root : FixedArray[UInt64] = FixedArray::make(root_len, 0UL)
  let rem : FixedArray[UInt64] = FixedArray::make(root_len + 1, 0UL)
  dec_sqrt_rec(source, 0, length, root, rem, stats?)
  (root, rem, root_len)
}

///|
fn dec_sqrt_to_coeff(limbs : FixedArray[UInt64], count : Int32) -> DecCoeff {
  let mut length = count
  while length > 0 && limbs.unsafe_get(length - 1) == 0UL {
    length -= 1
  }
  if length == 0 {
    return dec_coeff_zero()
  }
  let units : Array[UInt32] = Array::make(length, 0U)
  for index in 0..<length {
    units[index] = limbs.unsafe_get(index).to_uint()
  }
  dec_coeff_from_unit_accumulator(units, length)
}

///|
/// The floor square root `s` of `n` and how the remainder `n - s^2` compares
/// with `s`, without forming the remainder as a coefficient.
pub fn dec_coeff_sqrt_rounding(n : DecCoeff) -> (DecCoeff, DecSqrtRemainder) {
  if dec_coeff_unit_len(n) <= 2 {
    let (root, remainder) = dec_coeff_integer_sqrt_rem_repr(n)
    return (
      root,
      if remainder.is_zero() {
        Zero
      } else if dec_coeff_compare_repr(remainder, root) > 0 {
        AboveRoot
      } else {
        UpToRoot
      },
    )
  }
  let (root, rem, root_len) = dec_sqrt_run(n)
  let mut zero = true
  for index in 0..<(root_len + 1) {
    if rem.unsafe_get(index) != 0UL {
      zero = false
      break
    }
  }
  let state = if zero {
    Zero
  } else if dec_sqrt_compare(rem, root_len + 1, root, root_len) > 0 {
    AboveRoot
  } else {
    UpToRoot
  }
  (dec_sqrt_to_coeff(root, root_len), state)
}

///|
/// The Karatsuba root with its remainder as coefficients.
fn dec_coeff_sqrt_rem_karatsuba(
  n : DecCoeff,
  stats? : DecSqrtStats,
) -> (DecCoeff, DecCoeff) {
  let (root, rem, root_len) = dec_sqrt_run(n, stats?)
  (dec_sqrt_to_coeff(root, root_len), dec_sqrt_to_coeff(rem, root_len + 1))
}
