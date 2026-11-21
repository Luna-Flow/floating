// Binary::from_hex_ctx with an exponent field of any length (issue #597): the exponent
// saturates as in the decimal reader, and the result is the overflow or underflow result of
// the context with its flags in every rounding direction. The expected result is written out
// by a rounding-direction table (below), not read from the decimal reader, which had the same
// wrap defect (issue #624).

///|
let hex_exponent_modes : Array[BinaryRoundingMode] = [
  BinaryRoundingMode::RoundTiesToEven,
  BinaryRoundingMode::RoundTiesToAway,
  BinaryRoundingMode::RoundTowardPositive,
  BinaryRoundingMode::RoundTowardNegative,
  BinaryRoundingMode::RoundTowardZero,
]

///|
/// The result of a text whose exponent field is far beyond every range (the value of the
/// significand is 1, 1.5 or 1/16 times 2^field with |field| >= 10^12): overflow for a positive
/// exponent, underflow for a negative one, by the rounding direction of 7.4 and 7.5:
/// overflow gives the infinity except toward zero and away from the sign's direction (then the
/// largest finite number), underflow gives zero except in the direction of the sign (then the
/// smallest subnormal). Flags are I-O and IU-.
fn hex_exponent_check_far(
  text : String,
  negative_value : Bool,
  negative_exponent : Bool,
  mode_index : Int32,
  precision : Int32,
  label : String,
) -> Unit raise {
  let mode = hex_exponent_modes[mode_index]
  let context = BinaryContext::new(precision~, rounding=mode)
  let (value, flags) = Binary::from_hex_ctx(text, context).unwrap()
  let label = "\{label} \{text} mode#\{mode_index} p=\{precision}"
  if negative_exponent {
    assert_eq(e2s_flags(flags), "IU-", msg=label)
    let away = match mode {
      RoundTowardPositive => !negative_value
      RoundTowardNegative => negative_value
      _ => false
    }
    assert_eq(value.is_zero(), !away, msg=label)
  } else {
    assert_eq(e2s_flags(flags), "I-O", msg=label)
    let toward = match mode {
      RoundTowardZero => true
      RoundTowardPositive => negative_value
      RoundTowardNegative => !negative_value
      _ => false
    }
    assert_eq(value.is_infinite(), !toward, msg=label)
  }
  assert_eq(value.negative(), negative_value, msg=label)
}

///|
// oracle: A
// source: rounding-direction table of 7.4 and 7.5 written in hex_exponent_check_far (overflow: infinity or largest finite by direction; underflow: zero or smallest subnormal), not read from another reader
// shares: Binary::is_zero, is_infinite, negative (classification only)
test "from_hex_ctx: an exponent beyond 10^12 overflows or underflows in every direction" {
  let exponents = [
    "1000000000000", // 10^12, the old limit
     "1000000000001", // 10^12 + 1, the smallest that failed
     "2147483647", // 2^31 - 1
     "2147483648", // 2^31
     "9223372036854775807", // 2^63 - 1
     "123456789012345678901234567890", // a 30-digit exponent
  ]
  for exponent in exponents {
    for sign in ["", "-"] {
      // above the range, and below the smallest stored value; a significand with a fraction
      // and one below the point, in every direction and at three precisions
      let texts = [
        ("0x1p", false),
        ("0x1p-", true),
        ("0x1.8p", false),
        ("0x.1p-", true),
      ]
      for entry in texts {
        let (prefix, negative_exponent) = entry
        for mode_index in 0..<hex_exponent_modes.length() {
          for precision in [24, 53, 113] {
            hex_exponent_check_far(
              sign + prefix + exponent,
              sign == "-",
              negative_exponent,
              mode_index,
              precision,
              "far",
            )
          }
        }
      }
    }
  }
}

///|
// oracle: A
// source: signed zero without flags written out (5.12.3); the decimal reader is a second check only, the written expectation decides
// shares: Binary::from_string_ctx for the second check only
test "from_hex_ctx: a zero significand is the zero of the sign for any exponent field" {
  for
    exponent in [
      "0", "1000000000001", "9223372036854775807", "123456789012345678901234567890",
    ] {
    for sign in ["", "-"] {
      for exp_sign in ["", "-"] {
        for mode_index in 0..<hex_exponent_modes.length() {
          let mode = hex_exponent_modes[mode_index]
          let context = BinaryContext::new(precision=53, rounding=mode)
          let (value, flags) = Binary::from_hex_ctx(
            sign + "0x0p" + exp_sign + exponent,
            context,
          ).unwrap()
          assert_true(value.is_zero() && value.is_sign_minus() == (sign == "-"))
          assert_eq(flags, BinaryFlags::new())
          let (decimal, _) = Binary::from_string_ctx(
            sign + "0e" + exp_sign + exponent,
            context,
          ).unwrap()
          assert_true(
            decimal.is_zero() &&
            decimal.is_sign_minus() == value.is_sign_minus(),
          )
        }
      }
    }
  }
}

///|
// oracle: A
// source: classes (infinity, largest finite, tiny, zero) and flags written out from 7.4 and 7.5 for 0x1p+-1000000000001
// shares: FpClass (classification only)
test "from_hex_ctx: the result of a huge exponent in each rounding direction, with the flags" {
  // 0x1p1000000000001: above the range
  let up = BinaryContext::new(
    precision=53,
    rounding=BinaryRoundingMode::RoundTowardPositive,
  )
  let (inf, f1) = Binary::from_hex_ctx("0x1p1000000000001", up).unwrap()
  assert_true(inf.classify() == FpClass::Infinity && !inf.is_sign_minus())
  assert_true(f1.overflow() && f1.inexact())
  let zero_dir = BinaryContext::new(
    precision=53,
    rounding=BinaryRoundingMode::RoundTowardZero,
  )
  let (largest, f2) = Binary::from_hex_ctx("0x1p1000000000001", zero_dir).unwrap()
  assert_true(largest.classify() == FpClass::Finite && !largest.is_sign_minus())
  assert_true(f2.overflow() && f2.inexact())
  // the negative literal toward negative infinity: -inf; toward positive: the largest negative
  let down = BinaryContext::new(
    precision=53,
    rounding=BinaryRoundingMode::RoundTowardNegative,
  )
  let (neg_inf_value, f3) = Binary::from_hex_ctx("-0x1p1000000000001", down).unwrap()
  assert_true(
    neg_inf_value.classify() == FpClass::Infinity &&
    neg_inf_value.is_sign_minus(),
  )
  assert_true(f3.overflow())
  // 0x1p-1000000000001: below the smallest stored value
  let (tiny, f4) = Binary::from_hex_ctx("0x1p-1000000000001", up).unwrap()
  assert_true(!tiny.is_zero() && !tiny.is_sign_minus())
  assert_true(f4.underflow() && f4.inexact())
  let (flushed, f5) = Binary::from_hex_ctx("0x1p-1000000000001", zero_dir).unwrap()
  assert_true(flushed.is_zero())
  assert_true(f5.underflow() && f5.inexact())
}

///|
/// The texts that still fail, with the reason: only the grammar of 5.12.3 (a missing `0x`, a
/// missing digit, a missing exponent field or digit, two points, a character that is not a
/// hexadecimal or decimal digit); the length of a significand or of an exponent field is not a
/// reason. `from_hex` also fails on an exponent beyond the 32-bit range, because it stores
/// the exact value.
// oracle: A
// source: error reasons written out from the grammar of 5.12.3; the two long-significand values computed by hand (1 - 2^-8000 and 2^8000 - 1 at 53 bits, inexact), checked with Python fractions
// shares: Binary Display (printing only)
test "from_hex_ctx: what is still an error, and why" {
  let context = BinaryContext::new(precision=53)
  let cases = [
    ("1p0", "binary hex literal needs 0x"),
    ("0x", "binary hex literal needs a hex digit"),
    ("0x.p0", "binary hex literal needs a hex digit"),
    ("0x1", "binary hex literal needs p exponent"),
    ("0x1.8", "binary hex literal needs p exponent"),
    ("0x1p", "invalid binary exponent"),
    ("0x1p-", "invalid binary exponent"),
    ("0x1pA", "invalid binary exponent"),
    ("0x1p1.5", "invalid binary exponent"),
    ("0x1p1000000000000000000000000000000x", "invalid binary exponent"),
    ("0x1.8.0p1", "binary hex literal has two points"),
    ("0x1g0p0", "invalid binary hex digit"),
  ]
  for entry in cases {
    let (text, reason) = entry
    match Binary::from_hex_ctx(text, context) {
      Ok(_) => fail("\{text} should fail")
      Err(error) =>
        assert_true(
          error.message.contains(reason),
          msg=text + ": " + error.message,
        )
    }
  }
  // a long significand and a long fraction are valid
  let digits = String::make(2000, 'f')
  // 0xf...f (2000 digits) * 2^-8000 = 1 - 2^-8000 and 0x.f...f * 2^8000 = 2^8000 - 1: both round
  // to a power of two at 53 bits (exact arithmetic: the quantum is far above the distance), inexact
  let (below, below_flags) = Binary::from_hex_ctx(
    "0x" + digits + "p-8000",
    context,
  ).unwrap()
  assert_eq("\{below}", "1p0")
  assert_eq(e2s_flags(below_flags), "I--")
  let (above, above_flags) = Binary::from_hex_ctx(
    "0x." + digits + "p8000",
    context,
  ).unwrap()
  assert_eq("\{above}", "1p8000")
  assert_eq(e2s_flags(above_flags), "I--")
  // from_hex stores the exact value: an exponent beyond the 32-bit range is an error there
  assert_true(
    match Binary::from_hex("0x1p9223372036854775807", 53) {
      Err(error) => error.message.contains("binary exponent out of range")
      Ok(_) => false
    },
  )
  assert_true(Binary::from_hex("0x0p9223372036854775807", 53) is Ok(_))
}

///|
/// Exponent fields around `Int64::MAX / 10` (9.22e17), `2^60` (1.15e18), `Int64::MAX` and
/// `2^64`: the saturation must not wrap. The expected result is written out, not read from
/// another reader (the decimal reader had the same wrap, issue #624).
// oracle: A
// source: rounding-direction table of 7.4 and 7.5 written in the test, not read from another reader (issue 624)
// shares: Binary::is_zero, is_infinite, negative (classification only)
test "from_hex_ctx: exponent fields of 19 to 21 digits saturate, they do not wrap" {
  let digits = [
    "922337203685477580", "922337203685477581", "1000000000000000000", "1100000000000000000",
    "1152921504606846975", "1152921504606846976", "1152921504606846977", "9223372036854775807",
    "9223372036854775808", "11000000000000000000", "11529215046068469750", "18446744073709551616",
    "93000000000000000000", "999999999999999999999",
  ]
  for d in digits {
    for negative_exponent in [false, true] {
      for negative_value in [false, true] {
        let text = (if negative_value { "-" } else { "" }) +
          "0x1p" +
          (if negative_exponent { "-" } else { "" }) +
          d
        for mode_index in 0..<hex_exponent_modes.length() {
          let mode = hex_exponent_modes[mode_index]
          let context = BinaryContext::new(precision=53, rounding=mode)
          let (value, flags) = Binary::from_hex_ctx(text, context).unwrap()
          let label = "\{text} mode \{mode_index}"
          if negative_exponent {
            // underflow: zero, or the smallest subnormal when the direction is away from zero
            assert_eq(e2s_flags(flags), "IU-", msg=label)
            let away = match mode {
              RoundTowardPositive => !negative_value
              RoundTowardNegative => negative_value
              _ => false
            }
            if away {
              assert_eq(value.is_zero(), false, msg=label)
              assert_eq(value.negative(), negative_value, msg=label)
            } else {
              assert_eq(value.is_zero(), true, msg=label)
              assert_eq(value.negative(), negative_value, msg=label)
            }
          } else {
            // overflow: infinity, or the largest finite value when the direction is toward zero
            assert_eq(e2s_flags(flags), "I-O", msg=label)
            let toward = match mode {
              RoundTowardZero => true
              RoundTowardPositive => negative_value
              RoundTowardNegative => !negative_value
              _ => false
            }
            if toward {
              assert_eq(value.is_infinite(), false, msg=label)
            } else {
              assert_eq(value.is_infinite(), true, msg=label)
            }
            assert_eq(value.negative(), negative_value, msg=label)
          }
        }
      }
    }
  }
  // a zero significand is zero for every field
  for d in digits {
    let (value, flags) = Binary::from_hex_ctx(
      "0x0p" + d,
      BinaryContext::binary64(),
    ).unwrap()
    assert_eq(value.is_zero(), true, msg=d)
    assert_eq(flags, BinaryFlags::new(), msg=d)
  }
}
