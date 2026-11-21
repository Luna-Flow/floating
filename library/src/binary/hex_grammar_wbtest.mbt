// IEEE 754-2019 §5.12.3 hexSequence and §5.12.1 infinities and NaNs, production by
// production: every row of `accepted` must parse to the exact value built independently with
// `Binary::make`, every row of `rejected` must be an error.

///|
fn hex_expect(
  coefficient : UInt64,
  exponent : Int32,
  precision : Int32,
  negative : Bool,
) -> Binary {
  if coefficient == 0UL {
    if negative {
      Binary::negative_zero(precision~)
    } else {
      Binary::zero(precision~)
    }
  } else {
    Binary::make(
      BinCoeff::from_uint64(coefficient),
      exponent,
      precision,
      negative~,
    )
  }
}

///|
fn assert_same_value(
  source : String,
  actual : Binary,
  expected : Binary,
) -> Unit raise {
  assert_eq(actual.to_hex(), expected.to_hex(), msg=source)
  assert_eq(
    actual.is_sign_minus(),
    expected.is_sign_minus(),
    msg=source + " sign",
  )
  assert_eq(actual.precision(), expected.precision(), msg=source + " precision")
}

///|
test "§5.12.3 accepted hexSequence forms" {
  // (source, coefficient, exponent, negative): the value is coefficient * 2^exponent
  let accepted : Array[(String, UInt64, Int32, Bool)] = [
    // hexIndicator "0" [Xx]; hexSignificand {hexDigit}+
    ("0x1p0", 1, 0, false),
    ("0X1p0", 1, 0, false),
    // sign
    ("+0x1p0", 1, 0, false),
    ("-0x1p0", 1, 0, true),
    // hexSignificand {hexDigit}* "." {hexDigit}+
    ("0x1.8p1", 3, 0, false),
    ("0x.8p1", 1, 0, false),
    ("0x0.1p4", 1, 0, false),
    // hexSignificand {hexDigit}+ "."
    ("0x1.p0", 1, 0, false),
    ("0xA.p0", 10, 0, false),
    // hexDigit in either case, most significant first
    ("0xaBcDeFp0", 0xabcdef, 0, false),
    ("0xA.bCp8", 0xabc, 0, false),
    ("0x000.0010p12", 1, 0, false),
    // hexExpIndicator [Pp]; decExponent {sign}? {digit}+
    ("0x1P3", 1, 3, false),
    ("0x1p+3", 1, 3, false),
    ("0x1p-3", 1, -3, false),
    ("0x1p007", 1, 7, false),
    ("0x1p-1074", 1, -1074, false),
    ("0x1p1073741823", 1, 1073741823, false),
    // signed zeros keep their sign
    ("0x0p0", 0, 0, false),
    ("-0x0.0p5", 0, 0, true),
    ("+0x.0p-9", 0, 0, false),
    // surrounding whitespace is trimmed (a language-level choice, outside the grammar)
    ("  0x1p0\t", 1, 0, false),
  ]
  for row in accepted {
    let (source, coefficient, exponent, negative) = row
    let actual = Binary::from_hex(source, 53).unwrap()
    assert_same_value(
      source,
      actual,
      hex_expect(coefficient, exponent, 53, negative),
    )
    // The same grammar through from_hex_ctx: the value is exact (at most 53
    // bits), so no flag is raised.
    let (through, flags) = Binary::from_hex_ctx(
      source,
      BinaryContext::new(precision=53),
    ).unwrap()
    assert_same_value(
      source,
      through,
      hex_expect(coefficient, exponent, 53, negative),
    )
    assert_eq(flags, BinaryFlags::new(), msg=source)
  }
}

///|
test "§5.12.3 conversion is rounded once to the precision, ties to even" {
  // 0x1.fffffffffffff8 has 54 significant bits and lies halfway: ties to even rounds up to 2
  let tie = Binary::from_hex("0x1.fffffffffffff8p0", 53).unwrap()
  assert_same_value("tie up", tie, hex_expect(1, 1, 53, false))
  // 0x1.00000000000008 is halfway between 1 and its successor: ties to even keeps 1
  let even = Binary::from_hex("0x1.00000000000008p0", 53).unwrap()
  assert_same_value("tie down", even, hex_expect(1, 0, 53, false))
  // above half rounds up, at precision 24
  let up = Binary::from_hex("0x1.0000018p0", 24).unwrap()
  assert_same_value("above half", up, hex_expect(0x800001, -23, 24, false))
  let negative = Binary::from_hex("-0x1.fffffffffffff8p0", 53).unwrap()
  assert_same_value("negative tie", negative, hex_expect(1, 1, 53, true))
}

///|
test "§5.12.1 infinities and NaNs in any case with an optional sign" {
  for source in ["inf", "INF", "+Inf", "infinity", "+INFINITY", "InFiNiTy"] {
    let x = Binary::from_hex(source, 53).unwrap()
    assert_true(
      x.classify() == FpClass::Infinity && !x.is_sign_minus(),
      msg=source,
    )
  }
  for source in ["-inf", "-Infinity"] {
    let x = Binary::from_hex(source, 53).unwrap()
    assert_true(
      x.classify() == FpClass::Infinity && x.is_sign_minus(),
      msg=source,
    )
  }
  for source in ["nan", "NaN", "+NAN", "-nan"] {
    let x = Binary::from_hex(source, 53).unwrap()
    assert_true(x.is_quiet_nan(), msg=source)
  }
  for source in ["snan", "sNaN", "+SNAN", "-snan"] {
    let x = Binary::from_hex(source, 53).unwrap()
    assert_true(x.is_signaling_nan(), msg=source)
  }
  // from_hex_ctx gives the same special values without a flag, as
  // from_string_ctx does (5.12.1: the conversion is exact).
  let context = BinaryContext::binary64()
  for source in ["inf", "-Infinity", "nan", "-nan", "snan", "-SNAN"] {
    let (x, flags) = Binary::from_hex_ctx(source, context).unwrap()
    let (y, _) = Binary::from_string_ctx(source, context).unwrap()
    assert_eq(x.classify() == y.classify(), true, msg=source)
    assert_eq(x.is_sign_minus(), y.is_sign_minus(), msg=source)
    assert_eq(x.is_signaling_nan(), y.is_signaling_nan(), msg=source)
    assert_eq(flags, BinaryFlags::new(), msg=source)
  }
}

///|
test "§5.12.3 rejected forms" {
  let rejected = [
    "", "+", "-", // nothing to read
     "1p0", "x1p0", "0p0", "1.8p3", // hexIndicator is required
     "0x", "0xp0", "0x.p0", "0X.P1", // hexSignificand needs a hex digit
     "0x1", "0x1.8", "0x1e3", // decExponent is required (`e` is a hex digit)
     "0x1p", "0x1p+", "0x1p-", // decExponent needs a digit
     "0x1.8.0p1", "0x..1p0", // one period at most
     "0x1g0p0", "0x1 p0", "0x_1p0", // only hex digits in the significand
     "0x1p0x10", "0x1p1_0", "0x1pA", "0x1p1.5", "0x1p++1", "0x1p+-1", // decimal exponent digits only
     "++0x1p0", "+-0x1p0", "-+0x1p0", // one sign at most
     "0x1p999999999999999", "0x1p2147483648", "0x1p-2147483649", // exponent outside the 32-bit range (from_hex only)
     "infinit", "infinityy", "nanq", "snan0", "qnan", "in f", // §5.12.1 words only
  ]
  for source in rejected {
    assert_true(Binary::from_hex(source, 53) is Err(_), msg=source)
    // An exponent beyond the 32-bit range is a parse error for from_hex only (it stores
    // the exact value): from_hex_ctx overflows or underflows, whatever the length of the
    // exponent field (tested in hex_exponent_wbtest.mbt).
    if source != "0x1p2147483648" &&
      source != "0x1p-2147483649" &&
      source != "0x1p999999999999999" {
      assert_true(
        Binary::from_hex_ctx(source, BinaryContext::new(precision=53)) is Err(_),
        msg=source,
      )
    }
  }
}

///|
test "§5.12.3 round trip: from_hex(to_hex(x)) recovers x" {
  let precisions = [1, 8, 11, 24, 53, 64, 113, 237]
  let mut state = 0x9e3779b97f4a7c15UL
  for i in 0..<4000 {
    state = state * 6364136223846793005UL + 1442695040888963407UL
    let coefficient = state >> (state & 63UL).to_int()
    state = state * 6364136223846793005UL + 1442695040888963407UL
    let exponent = (state >> 40).to_int() % 4000 - 2000
    let precision = precisions[i % precisions.length()]
    let x = hex_expect(coefficient, exponent, precision, i % 3 == 0)
    let text = x.to_hex()
    let back = Binary::from_hex(text, precision).unwrap()
    assert_same_value(text, back, x)
  }
  for x in [Binary::inf(), Binary::inf(negative=true), Binary::negative_zero()] {
    let back = Binary::from_hex(x.to_hex(), 53).unwrap()
    assert_eq(back.to_hex(), x.to_hex())
    assert_eq(back.is_sign_minus(), x.is_sign_minus())
  }
  assert_true(
    Binary::from_hex(Binary::quiet_nan().to_hex(), 53).unwrap().is_quiet_nan(),
  )
}
