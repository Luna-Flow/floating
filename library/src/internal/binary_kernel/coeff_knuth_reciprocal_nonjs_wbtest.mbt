///|
/// The digit estimate of Knuth's algorithm D before the reciprocal: the
/// quotient of the top two limbs by the top limb and the correction against
/// the next limb of the divisor; the reference of `bin_knuth_digit_3by2`
/// (`high < divisor_top`).
fn knuth_digit_reference(
  high : UInt64,
  next : UInt64,
  after : UInt64,
  divisor_top : UInt64,
  divisor_next : UInt64,
) -> UInt64 {
  let mut trial = binary_fast_div_wide(high, next, divisor_top)
  let mut trial_remainder = next - trial * divisor_top
  let mut remainder_overflow = false
  while !remainder_overflow {
    let product_high = bin_coeff_mul_high(trial, divisor_next)
    let product_low = trial * divisor_next
    if product_high > trial_remainder ||
      (product_high == trial_remainder && product_low > after) {
      trial -= 1UL
      trial_remainder += divisor_top
      remainder_overflow = trial_remainder < divisor_top
    } else {
      break
    }
  }
  trial
}

///|
fn knuth_two_words(high : UInt64, low : UInt64) -> BigInt {
  (BigInt::from_uint64(high) << 64) + BigInt::from_uint64(low)
}

///|
fn knuth_check_reciprocal(d1 : UInt64, d0 : UInt64) -> Unit raise {
  let v = bin_knuth_reciprocal_3by2(d1, d0)
  let divisor = knuth_two_words(d1, d0)
  let base_cubed = 1N << 192
  // v = floor((B^3 - 1) / D) - B
  assert_eq(BigInt::from_uint64(v) + (1N << 64), (base_cubed - 1N) / divisor)
}

///|
fn knuth_check_digit(
  u2 : UInt64,
  u1 : UInt64,
  u0 : UInt64,
  d1 : UInt64,
  d0 : UInt64,
  v : UInt64,
) -> Unit raise {
  let digit = bin_knuth_digit_3by2(u2, u1, u0, d1, d0, v)
  // against the old estimate
  assert_eq(digit, knuth_digit_reference(u2, u1, u0, d1, d0))
  // and against the exact quotient of the three limbs by the two
  let dividend = (knuth_two_words(u2, u1) << 64) + BigInt::from_uint64(u0)
  assert_eq(BigInt::from_uint64(digit), dividend / knuth_two_words(d1, d0))
}

///|
/// Words that put every comparison of the algorithm at its edge: zero, one,
/// the sign bit and its neighbours, all ones and its neighbours.
fn knuth_edge_words() -> Array[UInt64] {
  [
    0UL, 1UL, 2UL, 0x7FFF_FFFF_FFFF_FFFFUL, 0x8000_0000_0000_0000UL, 0x8000_0000_0000_0001UL,
    0xFFFF_FFFF_0000_0000UL, 0x0000_0000_FFFF_FFFFUL, 0xFFFF_FFFF_FFFF_FFFDUL, 0xFFFF_FFFF_FFFF_FFFEUL,
    0xFFFF_FFFF_FFFF_FFFFUL,
  ]
}

///|
test "the 3 by 2 reciprocal of Algorithm 6 is floor((B^3 - 1) / D) - B at the edges and at random" {
  let words = knuth_edge_words()
  for d1 in words {
    if d1 >= 0x8000_0000_0000_0000UL {
      for d0 in words {
        knuth_check_reciprocal(d1, d0)
      }
    }
  }
  let random = { words_state: 0x3C6E_F372_FE94_F82BUL, }
  for _ in 0..<20000 {
    let d1 = random.next() | 0x8000_0000_0000_0000UL
    knuth_check_reciprocal(d1, random.next())
    // d0 near the carry thresholds of lines 3 and 12
    knuth_check_reciprocal(d1, 0UL - d1)
    knuth_check_reciprocal(d1, d1)
    knuth_check_reciprocal(d1, d1 + 1UL)
    knuth_check_reciprocal(d1, 0xFFFF_FFFF_FFFF_FFFFUL - random.next() % 4UL)
  }
}

///|
test "the 3 by 2 digit of Algorithm 5 equals the old estimate and the exact quotient at the edges and at random" {
  let words = knuth_edge_words()
  for d1 in words {
    if d1 >= 0x8000_0000_0000_0000UL {
      for d0 in words {
        let v = bin_knuth_reciprocal_3by2(d1, d0)
        // the top limb below the divisor's: edges of u2, plus d1 - 1, d1 - 2
        let top = [0UL, 1UL, d1 - 1UL, d1 - 2UL, d1 / 2UL]
        for u2 in top {
          if u2 < d1 {
            for u1 in words {
              for u0 in words {
                knuth_check_digit(u2, u1, u0, d1, d0, v)
              }
            }
          }
        }
      }
    }
  }
  let random = { words_state: 0x9E37_79B9_7F4A_7C15UL, }
  for _ in 0..<20000 {
    let d1 = random.next() | 0x8000_0000_0000_0000UL
    let d0 = random.next()
    let v = bin_knuth_reciprocal_3by2(d1, d0)
    let u2 = random.next() % d1
    knuth_check_digit(u2, random.next(), random.next(), d1, d0, v)
    // remainders at both ends: the dividend a multiple of the divisor, and
    // one below
    let q = random.next()
    let product = BigInt::from_uint64(q) * knuth_two_words(d1, d0)
    let low_word = BigInt::from_uint64(0xFFFF_FFFF_FFFF_FFFFUL)
    let u0 = (product & low_word).to_uint64()
    let u1 = ((product >> 64) & low_word).to_uint64()
    let u2_exact = (product >> 128).to_uint64()
    if u2_exact < d1 {
      knuth_check_digit(u2_exact, u1, u0, d1, d0, v)
      if product > 0N {
        let below = product - 1N
        knuth_check_digit(
          (below >> 128).to_uint64(),
          ((below >> 64) & low_word).to_uint64(),
          (below & low_word).to_uint64(),
          d1,
          d0,
          v,
        )
      }
    }
  }
}

///|
/// The reciprocal of Algorithm 6 on 8-bit words (`B = 256`), transliterated
/// with `Int` arithmetic reduced modulo 256: exhaustive over all 32,768
/// divisors, and it counts how often each branch of the equality cases runs
/// (the 64-bit loops cannot reach those by random inputs). Returns `v` and
/// sets `hits[0]` for the carry of line 4 with `p == d1`, `hits[1]` for the
/// carry of line 12 with `p == d1`, `hits[2]` with `p == d1` and `t0 == d0`.
fn knuth_model_reciprocal8(
  d1 : Int32,
  d0 : Int32,
  hits : Array[Int32],
) -> Int32 {
  let mut v = 65535 / d1 - 256
  let mut p = (d1 * v + d0) % 256
  if p < d0 {
    // line 4: the carry out
    if p == d1 {
      hits[0] += 1
    }
    v -= 1
    if p >= d1 {
      v -= 1
      p -= d1
    }
    p = (p - d1 + 256) % 256
  }
  let t = v * d0
  let t_low = t % 256
  let t_high = t / 256
  p = (p + t_high) % 256
  if p < t_high {
    if p == d1 {
      hits[1] += 1
    }
    if p == d1 && t_low == d0 {
      hits[2] += 1
    }
    v -= 1
    if p > d1 || (p == d1 && t_low >= d0) {
      v -= 1
    }
  }
  v
}

///|
test "Algorithm 6 on 8-bit words is exact for every divisor, and reaches its equality cases" {
  let hits = [0, 0, 0]
  for d1 in 128..<256 {
    for d0 in 0..<256 {
      let v = knuth_model_reciprocal8(d1, d0, hits)
      let divisor = d1 * 256 + d0
      // v = floor((B^3 - 1) / D) - B
      assert_eq(v + 256, 16777215 / divisor)
    }
  }
  inspect(hits[0] > 0, content="true")
  inspect(hits[1] > 0, content="true")
  // the tie `t0 == d0` together with `p == d1` in line 14 is not reached on
  // 8-bit words (the paper's `>=` is kept; the case is exhaustively absent)
  inspect(hits[2], content="0")
}

///|
test "the 3 by 2 reciprocal handles the carry with p equal to d1 on 64-bit words" {
  // `k = B^2 - (B + v1) d1` for the single-word reciprocal `v1` of `d1`; with
  // `d0 = d1 + k` the carry of line 4 leaves `p = d1`
  let random = { words_state: 0xA5A5_5A5A_1234_5678UL, }
  let mut checked = 0
  for _ in 0..<20000 {
    let d1 = random.next() | 0x8000_0000_0000_0000UL
    let v1 = binary_fast_div_wide(
      0xFFFF_FFFF_FFFF_FFFFUL - d1,
      0xFFFF_FFFF_FFFF_FFFFUL,
      d1,
    )
    let k = 0UL - d1 * v1
    if k < 0xFFFF_FFFF_FFFF_FFFFUL - d1 {
      knuth_check_reciprocal(d1, d1 + k)
      checked += 1
    }
  }
  assert_true(checked > 0)
}
