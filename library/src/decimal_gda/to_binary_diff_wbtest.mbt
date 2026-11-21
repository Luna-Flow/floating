///|
// Oracle (level E, equivalence with the previous implementation, which has
// a level A oracle on these input classes through the decTest and libmpdec
// rows of the certified exp/ln/log10; level B for the checks of the helper
// against BigInt arithmetic) for the differential tests; the written-out
// tests at the end are level A.
//
// `Decimal::to_binary_raw` against its previous implementation, which went
// through host big integers (and two divisions by 10^k for a negative exponent); the
// previous code is kept here as the reference.

///|
fn to_binary_reference(
  x : Decimal,
  precision : Int32,
  mode : @binary.BinaryRoundingMode,
) -> @binary.Binary {
  if x.exponent10 >= 0 {
    let magnitude = coeff_bigint(x.coefficient) * pow5(x.exponent10)
    return @binary.Binary::make(
      @binary.BinCoeff::from_bytes_be(magnitude.to_octets()),
      x.exponent10,
      precision,
      negative=x.negative,
      mode~,
    )
  }
  let scale = -x.exponent10
  let binary_shift = precision + scale * 4 + 2
  let numerator = abs_bigint(coeff_bigint(x.coefficient)) << binary_shift
  let denominator = pow10(scale)
  let truncated = numerator / denominator
  let q = if (numerator % denominator).is_zero() {
    truncated
  } else {
    truncated | bigint_one()
  }
  @binary.Binary::make(
    @binary.BinCoeff::from_bytes_be(q.to_octets()),
    -binary_shift,
    precision,
    negative=x.sign() == Sign::Negative,
    mode~,
  )
}

///|
fn to_binary_same(a : @binary.Binary, b : @binary.Binary) -> Bool {
  a.compare(b) == 0 &&
  a.precision() == b.precision() &&
  a.is_negative() == b.is_negative() &&
  a.exponent2() == b.exponent2() &&
  a.coefficient().to_bytes_be() == b.coefficient().to_bytes_be()
}

///|
let to_binary_modes : Array[@binary.BinaryRoundingMode] = [
  RoundTiesToEven,
  RoundTiesToAway,
  RoundTowardZero,
  RoundTowardPositive,
  RoundTowardNegative,
]

///|
fn to_binary_check(
  coefficient : DecCoeff,
  exponent10 : Int32,
  negative : Bool,
  precision : Int32,
  mode : @binary.BinaryRoundingMode,
) -> Unit raise {
  let x = finite_with_exponent_repr(
    negative,
    coefficient,
    exponent10,
    coefficient.digits10(),
  )
  // the reference of the arithmetic only: inside the plain range
  assert_true(
    to_binary_same(
      x.to_binary_raw(precision~, mode~),
      to_binary_reference(x, precision, mode),
    ),
  )
}

///|
test "to_binary_raw equals the big integer reference" {
  let state = Ref(0x3C6EF372FE94F82BUL)
  let precisions = [1, 2, 11, 24, 53, 64, 113, 200, 1000]
  let mut taken = 0
  for iteration in 0..<1500 {
    let bytes_len = match iteration % 10 {
      0 => 1 + (endpoint_next(state) % 5000UL).to_int()
      1 => 1 + (endpoint_next(state) % 300UL).to_int()
      _ => 1 + (endpoint_next(state) % 24UL).to_int()
    }
    let n = BigInt::from_octets(endpoint_random_bytes(state, bytes_len))
    if n == BigInt::from_int(0) {
      continue
    }
    let coefficient = dec_coeff_from_bigint_repr(n)
    let span = if bytes_len > 300 { 400 } else { 3000 }
    for
      exponent10 in [
        0,
        1,
        -1,
        (endpoint_next(state) % span.to_uint64()).to_int(),
        -(endpoint_next(state) % span.to_uint64()).to_int(),
        -(endpoint_next(state) % 40UL).to_int(),
      ] {
      let precision = precisions[(endpoint_next(state) % 9UL).to_int()]
      let mode = to_binary_modes[(endpoint_next(state) % 5UL).to_int()]
      to_binary_check(
        coefficient,
        exponent10,
        endpoint_next(state) % 2UL == 0UL,
        precision,
        mode,
      )
      taken += 1
    }
  }
  assert_true(taken > 7000)
}

///|
test "to_binary_raw of exact quotients and powers, in every mode" {
  // c * 10^-k is a dyadic rational (exact quotient, the sticky bit decides)
  // when 5^k divides c: c = 5^j * 2^i, and powers of ten, with neighbours
  let five = BigInt::from_int(5)
  let two = BigInt::from_int(2)
  let ten = BigInt::from_int(10)
  for j in 0..<80 {
    for i in [0, 1, 3, 17, 64] {
      let base = five.pow(BigInt::from_int(j)) * two.pow(BigInt::from_int(i))
      for delta in [-1, 0, 1] {
        let n = base + BigInt::from_int(delta)
        if n <= BigInt::from_int(0) {
          continue
        }
        for exponent10 in [-j, -j - 1, -j + 1, -(j * 2), 0, 3] {
          for precision in [1, 24, 53, 113] {
            for mode in to_binary_modes {
              to_binary_check(
                dec_coeff_from_bigint_repr(n),
                exponent10,
                (i + j) % 2 == 0,
                precision,
                mode,
              )
            }
          }
        }
      }
    }
  }
  for j in 0..<130 {
    for delta in [-1, 0, 1] {
      let n = ten.pow(BigInt::from_int(j)) + BigInt::from_int(delta)
      if n <= BigInt::from_int(0) {
        continue
      }
      for exponent10 in [-j, -j - 1, -j + 1, -(j / 2), 0, 5] {
        for mode in to_binary_modes {
          to_binary_check(
            dec_coeff_from_bigint_repr(n),
            exponent10,
            false,
            53,
            mode,
          )
          to_binary_check(
            dec_coeff_from_bigint_repr(n),
            exponent10,
            true,
            11,
            mode,
          )
        }
      }
    }
  }
}

///|
test "5^k divides a coefficient exactly when the big integer remainder is zero" {
  let five = BigInt::from_int(5)
  for j in [0, 1, 2, 12, 13, 25, 26, 27, 40, 80] {
    let unit = five.pow(BigInt::from_int(j))
    for m in [1, 2, 3, 5, 7, 25, 123456789] {
      for delta in [-1, 0, 1] {
        let n = unit * BigInt::from_int(m) + BigInt::from_int(delta)
        if n <= BigInt::from_int(0) {
          continue
        }
        for k in [0, 1, j - 1, j, j + 1, j + 2, 90] {
          if k < 0 {
            continue
          }
          let expected = (n % five.pow(BigInt::from_int(k))).is_zero()
          // 2 is "not decided": it only occurs beyond the step limit and is
          // then settled by the product in the caller
          let got = decimal_coeff_pow5_divisibility(
            dec_coeff_from_bigint_repr(n),
            k,
          )
          if got != 2 {
            assert_eq(got == 1, expected)
          }
        }
      }
    }
  }
}

///|
test "to_binary_raw of short coefficients with a small scale, where the sticky bit decides" {
  // The quotient keeps `precision + 2 + bits(c) + 0.68 * scale` bits, so a
  // short coefficient with a small scale leaves only a few bits below the
  // target position: the truncated quotient can then end in exactly the tie
  // pattern while the division was inexact, and only the round-to-odd bit
  // (sticky) tells that value from a tie.
  let mut taken = 0
  for c in 1..<300 {
    for scale in 1..<13 {
      for precision in [1, 2, 3, 5, 8, 11, 24, 53] {
        for mode in to_binary_modes {
          to_binary_check(
            DecCoeff::Small(c.to_uint64()),
            -scale,
            c % 2 == 0,
            precision,
            mode,
          )
          taken += 1
        }
      }
    }
  }
  assert_true(taken > 100000)
}

///|
test "to_binary_raw of tiny coefficients at every precision to 140 bits" {
  // quotients of more than one machine word, for which the sticky bit is set
  // on the byte string (the word route is the test above); the position of the
  // tie moves with the precision, so every precision is tried
  let mut taken = 0
  for c in 1..<40 {
    for scale in 1..<9 {
      for precision in 1..<141 {
        for mode in to_binary_modes {
          to_binary_check(
            DecCoeff::Small(c.to_uint64()),
            -scale,
            false,
            precision,
            mode,
          )
          taken += 1
        }
      }
    }
  }
  assert_true(taken > 100000)
}

///|
test "to_binary_raw just above and below a binary midpoint, in every mode" {
  // 1 + 2^-p is the midpoint of two p-bit numbers near 1: the decimal
  // (2^p + 1) * 5^p * 10^t / 10^(p + t), moved by a few units in the last
  // place of a longer expansion. Just above it only the sticky bit (the round
  // to odd of the truncated quotient) tells the value from the tie.
  let two = BigInt::from_int(2)
  let five = BigInt::from_int(5)
  let ten = BigInt::from_int(10)
  for p in [1, 2, 3, 11, 24, 53, 64, 113] {
    let midpoint = (two.pow(BigInt::from_int(p)) + BigInt::from_int(1)) *
      five.pow(BigInt::from_int(p))
    for t in [1, 3, 9, 18, 20, 40] {
      for d in [-2, -1, 0, 1, 2] {
        let n = midpoint * ten.pow(BigInt::from_int(t)) + BigInt::from_int(d)
        for mode in to_binary_modes {
          to_binary_check(
            dec_coeff_from_bigint_repr(n),
            -(p + t),
            false,
            p,
            mode,
          )
          to_binary_check(
            dec_coeff_from_bigint_repr(n),
            -(p + t),
            true,
            p,
            mode,
          )
        }
      }
    }
  }
}

///|
// Oracle (level A): expected values written out by hand, independent of the
// code under test and of the previous implementation: the IEEE 754 binary32
// and binary64 constants of 0.1, 0.2 and 0.3 (the well-known bit patterns
// 0x3DCCCCCD, 0x3FB999999999999A, 0x3FC999999999999A, 0x3FD3333333333333 with
// their odd coefficients), dyadic values 5^k * 10^-k = 2^-k at the limb
// boundaries of the decimal representation (5^9, 5^13, 5^18, 5^26 and 5^27
// are 1953125, 1220703125, 3814697265625, 1490116119384765625 and
// 7450580596923828125), and a two-bit precision, where the nearest values to
// 0.3125 = 5/16 are 0.25 and 0.375 and the neighbours of 2^-13 are 3 * 2^-15
// and 3 * 2^-14.

///|
fn written_expect(
  text : String,
  precision : Int32,
  mode : @binary.BinaryRoundingMode,
  coefficient : UInt64,
  exponent2 : Int32,
  negative~ : Bool = false,
  digits~ : Int32 = 34,
) -> Unit raise {
  let x = Decimal::from_string(text, precision=digits)
    .unwrap()
    .to_binary_raw(precision~, mode~)
  assert_eq(x.coefficient().to_uint64(), Some(coefficient))
  assert_eq(x.exponent2(), exponent2)
  assert_eq(x.is_negative(), negative)
}

///|
test "to_binary_raw: written-out values (level A)" {
  let rne = @binary.BinaryRoundingMode::RoundTiesToEven
  // the IEEE 754 constants
  written_expect("0.1", 53, rne, 3602879701896397UL, -55)
  written_expect("0.2", 53, rne, 3602879701896397UL, -54)
  written_expect("0.3", 53, rne, 5404319552844595UL, -54)
  written_expect("0.1", 24, rne, 13421773UL, -27)
  // exactly representable values
  written_expect("0.5", 53, rne, 1UL, -1)
  written_expect("0.375", 53, rne, 3UL, -3)
  written_expect("2.5", 53, rne, 5UL, -1)
  written_expect("10", 53, rne, 5UL, 1)
  written_expect("1E+3", 53, rne, 125UL, 3)
  written_expect("-0.375", 53, rne, 3UL, -3, negative=true)
  // 5^k * 10^-k = 2^-k: the exact quotient across the 10^9 limb boundaries
  written_expect("1953125E-9", 53, rne, 1UL, -9)
  written_expect("1220703125E-13", 53, rne, 1UL, -13)
  written_expect("3814697265625E-18", 53, rne, 1UL, -18)
  written_expect("1490116119384765625E-26", 53, rne, 1UL, -26)
  written_expect("7450580596923828125E-27", 53, rne, 1UL, -27)
  // the same exact quotients at two bits stay exact in every mode
  for mode in to_binary_modes {
    written_expect("1220703125E-13", 2, mode, 1UL, -13)
    written_expect("7450580596923828125E-27", 2, mode, 1UL, -27)
  }
}

///|
test "to_binary_raw: ties and their neighbours at two bits (level A)" {
  // 0.3125 is the exact midpoint of 0.25 = 1 * 2^-2 and 0.375 = 3 * 2^-3
  written_expect("0.3125", 2, RoundTiesToEven, 1UL, -2)
  written_expect("0.3125", 2, RoundTiesToAway, 3UL, -3)
  written_expect("0.3125", 2, RoundTowardPositive, 3UL, -3)
  written_expect("0.3125", 2, RoundTowardNegative, 1UL, -2)
  written_expect("0.3125", 2, RoundTowardZero, 1UL, -2)
  written_expect("-0.3125", 2, RoundTowardPositive, 1UL, -2, negative=true)
  // one unit above the midpoint (23 significant digits): only the round to
  // odd of the truncated quotient tells it from the tie
  written_expect("0.31250000000000000000001", 2, RoundTiesToEven, 3UL, -3)
  written_expect("0.31250000000000000000001", 2, RoundTiesToAway, 3UL, -3)
  written_expect("0.31250000000000000000001", 2, RoundTowardNegative, 1UL, -2)
  // one unit below it
  written_expect("0.31249999999999999999999", 2, RoundTiesToEven, 1UL, -2)
  written_expect("0.31249999999999999999999", 2, RoundTiesToAway, 1UL, -2)
  written_expect("0.31249999999999999999999", 2, RoundTowardPositive, 3UL, -3)
  // 2^-13 + 10^-13 * 1 and - 1 (limb-boundary quotients with one unit more or
  // less): the grid next to 2^-13 holds 3 * 2^-15 below and 3 * 2^-14 above
  written_expect("1220703126E-13", 2, RoundTowardPositive, 3UL, -14)
  written_expect("1220703126E-13", 2, RoundTowardNegative, 1UL, -13)
  written_expect("1220703126E-13", 2, RoundTiesToEven, 1UL, -13)
  written_expect("1220703124E-13", 2, RoundTowardNegative, 3UL, -15)
  written_expect("1220703124E-13", 2, RoundTowardPositive, 1UL, -13)
  written_expect("1220703124E-13", 2, RoundTiesToEven, 1UL, -13)
}

///|
// Oracle (level A, written out): the value 10^d * 10^-d is exactly 1 and
// 5^d * 10^-d is exactly 2^-d, at every size (the shapes of a value with a long
// run of trailing zeros under a matching negative exponent, and of a dyadic
// rational written in decimal, whose divisibility test is the long one).
test "to_binary_raw of 10^d * 10^-d and 5^d * 10^-d is exact (level A)" {
  for d in [1, 8, 9, 10, 18, 19, 27, 40, 100, 1000, 2500] {
    let ten = "1" + "0".repeat(d)
    let five = BigInt::from_int(5).pow(BigInt::from_int(d)).to_string()
    for mode in to_binary_modes {
      for precision in [1, 24, 53] {
        written_expect(
          ten + "E-" + d.to_string(),
          precision,
          mode,
          1UL,
          0,
          digits=d + 2,
        )
        written_expect(
          five + "E-" + d.to_string(),
          precision,
          mode,
          1UL,
          -d,
          digits=d + 2,
        )
      }
    }
  }
}
