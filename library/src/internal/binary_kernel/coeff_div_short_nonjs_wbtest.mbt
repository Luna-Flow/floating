///|
/// Round-to-nearest-even of the real `numerator / divisor` to `precision` bits,
/// as (kept bits, bit length of the integer quotient); the reference of the
/// short division, computed with BigInt.
fn short_div_reference_round(
  numerator : BigInt,
  divisor : BigInt,
  precision : Int32,
) -> (BigInt, Int32) {
  let quotient = numerator / divisor
  let remainder = numerator % divisor
  let bits = quotient.bit_length()
  let shift = bits - precision
  let kept = quotient >> shift
  let low = quotient - (kept << shift)
  let half = 1N << (shift - 1)
  let up = if low > half {
    true
  } else if low == half {
    // a tie only when the division is exact; else above half
    if remainder != 0N {
      true
    } else {
      kept % 2N == 1N
    }
  } else {
    false
  }
  (if up { kept + 1N } else { kept }, bits)
}

///|
/// The same rounding of the returned approximate quotient: it is only ever
/// returned when no grid point is within its bound, so the low bits decide.
fn short_div_round_approximate(
  approximate : BigInt,
  precision : Int32,
) -> BigInt raise {
  let shift = approximate.bit_length() - precision
  let kept = approximate >> shift
  let low = approximate - (kept << shift)
  let half = 1N << (shift - 1)
  assert_true(low != half)
  if low > half {
    kept + 1N
  } else {
    kept
  }
}

///|
/// Checks `bin_coeff_div_short_quotient` on one input: either it declines, or
/// its value rounds, to `precision` bits, as the exact quotient does.
fn short_div_check(
  dividend_big : BigInt,
  scale : Int32,
  divisor_big : BigInt,
  precision : Int32,
) -> Bool raise {
  let dividend = bin_coeff_test_from_bigint(dividend_big)
  let divisor = bin_coeff_test_from_bigint(divisor_big)
  if !bin_coeff_div_short_ok(dividend, scale, divisor) {
    return false
  }
  let approximate = bin_coeff_div_short_quotient(
    dividend, scale, divisor, precision,
  )
  if approximate.is_zero() {
    return false
  }
  let numerator = dividend_big << scale
  let (expected, bits) = short_div_reference_round(
    numerator, divisor_big, precision,
  )
  let approximate_big = @string.parse_bigint(approximate.to_string())
  // the bit length of the exact quotient is that of the approximation
  assert_eq(approximate_big.bit_length(), bits)
  assert_true(
    short_div_round_approximate(approximate_big, precision) == expected,
  )
  // directed modes: the truncation to `precision` bits and the inexact flag
  // agree (toward zero keeps the truncation, away from zero adds one unit)
  let shift = bits - precision
  let exact_quotient = numerator / divisor_big
  assert_true(exact_quotient >> shift == approximate_big >> shift)
  let exact_low = exact_quotient - (exact_quotient >> shift << shift)
  assert_true(exact_low != 0N || numerator % divisor_big != 0N)
  true
}

///|
test "short quotient rounds like the exact quotient on random operands" {
  let mut returned = 0
  let mut total = 0
  for
    limbs in [
      2, 3, 4, 5, 8, 9, 16, 17, 31, 32, 33, 64, 65, 96, 128, 191, 192, 255, 256,
    ] {
    for variant in 0..<3 {
      let divisor_bits = limbs * 64 - variant * 23
      for seed in 1..<30 {
        let divisor_big = bin_coeff_sqrt_test_value(
            divisor_bits,
            (seed + limbs * 1000).to_uint64(),
          ) |
          1N
        for precision_offset in [0, 1, -1, -63, -70] {
          let precision = limbs * 64 + precision_offset
          if precision < 2 {
            continue
          }
          let dividend_bits = precision - seed % 3
          let dividend_big = bin_coeff_sqrt_test_value(
              dividend_bits,
              (seed * 31 + variant).to_uint64(),
            ) |
            1N
          let scale = Int32::max(
            0,
            precision +
            2 +
            32 +
            divisor_big.bit_length() -
            dividend_big.bit_length(),
          )
          total += 1
          if short_div_check(dividend_big, scale, divisor_big, precision) {
            returned += 1
          }
        }
      }
    }
  }
  // the fallback is rare on random operands
  assert_true(returned * 100 > total * 95)
}

///|
/// Operands next to a rounding boundary. For dividend and divisor of at most
/// `precision` bits the quotient is either exactly on the grid of halfway and
/// representable points or at least `2^(quotient_bits - precision)` away from
/// it (the numerator `A * 2^scale - T * B` of the distance is a nonzero
/// integer), which is far more than the bound of the short quotient. So the
/// adversarial inputs are the exact quotients (`A = T * B`, on the grid and
/// halfway when `T` has `precision` or `precision + 1` bits) and their
/// neighbours (`A = T * B +- delta`), for divisors that are hard for the digit
/// estimates (all ones, `2^k + 1`, a top limb just above half).
test "short quotient on exact quotients and their neighbours" {
  let mut exact_returned = 0
  let mut neighbours_returned = 0
  let mut neighbours_total = 0
  for limbs in [2, 3, 4, 8, 9, 17, 32, 33, 64, 128] {
    let hard = [
      (1N << (limbs * 64)) - 1N,
      (1N << (limbs * 64 - 1)) + 1N,
      (1N << (limbs * 64 - 1)) + (1N << 64) + 1N,
      bin_coeff_sqrt_test_value(limbs * 64, 5UL) | 1N,
      bin_coeff_sqrt_test_value(limbs * 64 - 17, 6UL) | 1N,
    ]
    for divisor_big in hard {
      let divisor_bits = divisor_big.bit_length()
      for precision in [limbs * 64, limbs * 64 + 1, limbs * 64 + 17] {
        for extra in [0, 1, 2, 5] {
          // T has `precision - divisor_bits - extra` or fewer bits: A = T * B
          // has at most `precision` bits
          let t_bits = precision - divisor_bits + extra
          if t_bits < 1 {
            continue
          }
          for seed in 1..<6 {
            let t = bin_coeff_sqrt_test_value(t_bits, seed.to_uint64()) | 1N
            let product = t * divisor_big
            for scale in [34, 40, 64, 70, 131, 200] {
              // exact quotient: must decline
              if short_div_check(product, scale, divisor_big, precision) {
                exact_returned += 1
              }
              for delta in [-3N, -1N, 1N, 2N] {
                let neighbour = product + delta
                if neighbour > 0N {
                  neighbours_total += 1
                  if short_div_check(neighbour, scale, divisor_big, precision) {
                    neighbours_returned += 1
                  }
                }
              }
            }
          }
        }
      }
    }
  }
  assert_eq(exact_returned, 0)
  // the neighbours are returned wherever the guard bits allow it
  assert_true(neighbours_returned > 0)
  assert_true(neighbours_total > 1000)
}
