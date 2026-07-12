///|
let audit_ctx : @lf_arith.ArithmeticContext = @lf_arith.ArithmeticContext::new(
  12,
  rounding=@lf_arith.RoundingMode::TowardPositive,
)

///|
test "def predicates classify finite nan and enclosing zero consistently" {
  let finite = @bin_float.BinFloat::from_int(3, precision=8)
  let nan = @bin_float.BinFloat::nan(precision=8)
  let inf = @decimal.Decimal::inf(@def.Sign::Positive, precision=8)
  let straddle = @ball_float.BallFloat::new(
    @bin_float.BinFloat::zero(precision=8),
    binary_test_make(1N, -2, 8),
    precision=8,
  )
  assert_true(@def.is_finite(finite))
  assert_true(@def.is_nan(nan))
  assert_true(@def.is_infinite(inf))
  assert_true(@def.is_zero(straddle))
  assert_false(@def.is_zero(nan))
}

///|
test "internal rounding helpers honor tie and directed modes" {
  assert_eq(
    @internal.round_positive_div(
      5N,
      2N,
      false,
      @lf_arith.RoundingMode::ToNearestEven,
    ).to_string(),
    "2",
  )
  assert_eq(
    @internal.round_positive_div(
      7N,
      2N,
      false,
      @lf_arith.RoundingMode::ToNearestEven,
    ).to_string(),
    "4",
  )
  assert_eq(
    @internal.round_positive_div(
      3N,
      2N,
      false,
      @lf_arith.RoundingMode::TowardZero,
    ).to_string(),
    "1",
  )
  assert_eq(
    @internal.round_positive_div(
      3N,
      2N,
      true,
      @lf_arith.RoundingMode::TowardNegative,
    ).to_string(),
    "2",
  )
  assert_eq(
    @internal.round_shift(7N, 1, false, @lf_arith.RoundingMode::AwayFromZero).to_string(),
    "4",
  )
  assert_eq(@internal.compare_abs(-3N, 2N), 1)
  assert_eq(@internal.pow10(0).to_string(), "1")
  assert_eq(@internal.pow10(1).to_string(), "10")
  assert_eq(@internal.pow10(18).to_string(), "1000000000000000000")
  assert_eq(@internal.pow10(19).to_string(), "10000000000000000000")
  assert_eq(@internal.pow5(0).to_string(), "1")
  assert_eq(@internal.pow5(1).to_string(), "5")
  assert_eq(@internal.pow5(18).to_string(), "3814697265625")
  assert_eq(@internal.pow5(19).to_string(), "19073486328125")
}

///|
test "internal decimal parser accepts scientific notation and rejects malformed strings" {
  match @internal.split_decimal_string("12.340e-1") {
    Some((negative, digits, exponent10)) => {
      assert_false(negative)
      assert_eq(digits, "12340")
      assert_eq(exponent10, -4)
    }
    None => fail("expected scientific decimal parse to succeed")
  }
  match @internal.split_decimal_string("-0.05E+3") {
    Some((negative, digits, exponent10)) => {
      assert_true(negative)
      assert_eq(digits, "005")
      assert_eq(exponent10, 1)
    }
    None => fail("expected signed scientific decimal parse to succeed")
  }
  assert_true(@internal.split_decimal_string("1e") is None)
  assert_true(@internal.split_decimal_string("..1") is None)
}

///|
test "context and parse error types are exposed" {
  let ctx = @lf_arith.ArithmeticContext::new(
    7,
    rounding=@lf_arith.RoundingMode::TowardPositive,
  )
  assert_eq(ctx.precision, 7)
  assert_true(ctx.rounding == @lf_arith.RoundingMode::TowardPositive)
  let result = @decimal.Decimal::parse("bad", precision=10)
  match result {
    Ok(_) => fail("expected parse error")
    Err(err) => assert_true(err.is_parse_error())
  }
  assert_true(@decimal.Decimal::from_string("bad", precision=10) is None)
  assert_true(
    @decimal.Decimal::from_interchange_hex(
      "#77FFFF3FCFF3FCFG",
      @decimal.DecimalInterchangeFormat::Decimal64,
    )
    is None,
  )
  match
    @decimal.Decimal::from_interchange_hex(
      "#A2300000000003D0",
      @decimal.DecimalInterchangeFormat::Decimal64,
    ) {
    Some(value) =>
      assert_eq(
        value
        .compare_total(
          @decimal.Decimal::from_string("-7.50", precision=64).unwrap(),
        )
        .to_string(),
        "0",
      )
    None => fail("expected valid interchange decode to succeed")
  }
  assert_true(
    @decimal.DecimalInterchange::from_hex(
      "#77FFFF3FCFF3FCFG",
      @decimal.DecimalInterchangeFormat::Decimal64,
    )
    is None,
  )
  match
    @decimal.DecimalInterchange::from_hex(
      " \t#a2300000000003d0\n",
      @decimal.DecimalInterchangeFormat::Decimal64,
    ) {
    Some(interchange) => {
      assert_eq(interchange.to_hex(), "#A2300000000003D0")
      assert_true(
        interchange.format() == @decimal.DecimalInterchangeFormat::Decimal64,
      )
    }
    None => fail("expected valid interchange wrapper decode to succeed")
  }
}

///|
test "decimal interchange facade preserves format and fixed-width hex output" {
  let value32 = @decimal.Decimal::from_string("1E-95", precision=32).unwrap()
  let value64 = @decimal.Decimal::from_string("-7.50", precision=64).unwrap()
  let value128 = @decimal.Decimal::from_string("1E-6143", precision=128).unwrap()

  let (encoded32, encoded32_flags) = value32.to_interchange_hex(
    @decimal.DecimalInterchangeFormat::Decimal32,
  )
  let (encoded64, encoded64_flags) = value64.to_interchange_hex(
    @decimal.DecimalInterchangeFormat::Decimal64,
  )
  let (encoded128, encoded128_flags) = value128.to_interchange_hex(
    @decimal.DecimalInterchangeFormat::Decimal128,
  )

  let (raw32, flags32) = @decimal.DecimalInterchange::from_decimal(
    value32,
    @decimal.DecimalInterchangeFormat::Decimal32,
  )
  let (raw64, flags64) = @decimal.DecimalInterchange::from_decimal(
    value64,
    @decimal.DecimalInterchangeFormat::Decimal64,
  )
  let (raw128, flags128) = @decimal.DecimalInterchange::from_decimal(
    value128,
    @decimal.DecimalInterchangeFormat::Decimal128,
  )

  assert_true(raw32.format() == @decimal.DecimalInterchangeFormat::Decimal32)
  assert_true(raw64.format() == @decimal.DecimalInterchangeFormat::Decimal64)
  assert_true(raw128.format() == @decimal.DecimalInterchangeFormat::Decimal128)

  assert_eq(raw32.to_hex(), encoded32)
  assert_eq(raw64.to_hex(), encoded64)
  assert_eq(raw128.to_hex(), encoded128)

  assert_true(flags32 == encoded32_flags)
  assert_true(flags64 == encoded64_flags)
  assert_true(flags128 == encoded128_flags)
}

///|
test "decimal interchange facade from_decimal preserves finite bits flags and format" {
  let value32 = @decimal.Decimal::from_string("1.23E+96", precision=64).unwrap()
  let value64 = @decimal.Decimal::from_string("1.23E+384", precision=64).unwrap()
  let value128 = @decimal.Decimal::from_string("1.23E+6144", precision=64).unwrap()

  let (encoded32, encoded32_flags) = value32.to_interchange_hex(
    @decimal.DecimalInterchangeFormat::Decimal32,
  )
  let (wrapped32, wrapped32_flags) = @decimal.DecimalInterchange::from_decimal(
    value32,
    @decimal.DecimalInterchangeFormat::Decimal32,
  )
  let (encoded64, encoded64_flags) = value64.to_interchange_hex(
    @decimal.DecimalInterchangeFormat::Decimal64,
  )
  let (wrapped64, wrapped64_flags) = @decimal.DecimalInterchange::from_decimal(
    value64,
    @decimal.DecimalInterchangeFormat::Decimal64,
  )
  let (encoded128, encoded128_flags) = value128.to_interchange_hex(
    @decimal.DecimalInterchangeFormat::Decimal128,
  )
  let (wrapped128, wrapped128_flags) = @decimal.DecimalInterchange::from_decimal(
    value128,
    @decimal.DecimalInterchangeFormat::Decimal128,
  )

  assert_eq(wrapped32.to_hex(), encoded32)
  assert_true(
    wrapped32.format() == @decimal.DecimalInterchangeFormat::Decimal32,
  )
  assert_true(wrapped32_flags == encoded32_flags)
  assert_true(wrapped32_flags.clamped)

  assert_eq(wrapped64.to_hex(), encoded64)
  assert_true(
    wrapped64.format() == @decimal.DecimalInterchangeFormat::Decimal64,
  )
  assert_true(wrapped64_flags == encoded64_flags)
  assert_true(wrapped64_flags.clamped)

  assert_eq(wrapped128.to_hex(), encoded128)
  assert_true(
    wrapped128.format() == @decimal.DecimalInterchangeFormat::Decimal128,
  )
  assert_true(wrapped128_flags == encoded128_flags)
  assert_true(wrapped128_flags.clamped)
}

///|
test "decimal interchange scalar encode preserves finite flags across formats" {
  let value32 = @decimal.Decimal::from_string("1.23E+96", precision=64).unwrap()
  let value64 = @decimal.Decimal::from_string("1.23E+384", precision=64).unwrap()
  let value128 = @decimal.Decimal::from_string("1.23E+6144", precision=64).unwrap()

  let (encoded32, flags32) = value32.to_interchange_hex(
    @decimal.DecimalInterchangeFormat::Decimal32,
  )
  let (encoded64, flags64) = value64.to_interchange_hex(
    @decimal.DecimalInterchangeFormat::Decimal64,
  )
  let (encoded128, flags128) = value128.to_interchange_hex(
    @decimal.DecimalInterchangeFormat::Decimal128,
  )

  assert_eq(encoded32, "#47F4C000")
  assert_eq(encoded64, "#47FD300000000000")
  assert_eq(encoded128, "#47FFD300000000000000000000000000")
  assert_true(flags32.clamped)
  assert_true(flags64.clamped)
  assert_true(flags128.clamped)
}

///|
test "decimal interchange facade from_decimal preserves special bits flags and format" {
  let inf = @decimal.Decimal::inf(@def.Sign::Negative, precision=32)
  let qnan = @decimal.Decimal::quiet_nan(
    payload=12345N,
    negative=true,
    precision=32,
  )
  let snan = @decimal.Decimal::signaling_nan(
    payload=54321N,
    negative=true,
    precision=32,
  )

  let (inf32_expected_bits, inf32_expected_flags) = inf.to_interchange_hex(
    @decimal.DecimalInterchangeFormat::Decimal32,
  )
  let (inf32, inf32_flags) = @decimal.DecimalInterchange::from_decimal(
    inf,
    @decimal.DecimalInterchangeFormat::Decimal32,
  )
  let (qnan64_expected_bits, qnan64_expected_flags) = qnan.to_interchange_hex(
    @decimal.DecimalInterchangeFormat::Decimal64,
  )
  let (qnan64, qnan64_flags) = @decimal.DecimalInterchange::from_decimal(
    qnan,
    @decimal.DecimalInterchangeFormat::Decimal64,
  )
  let (snan128_expected_bits, snan128_expected_flags) = snan.to_interchange_hex(
    @decimal.DecimalInterchangeFormat::Decimal128,
  )
  let (snan128, snan128_flags) = @decimal.DecimalInterchange::from_decimal(
    snan,
    @decimal.DecimalInterchangeFormat::Decimal128,
  )

  assert_eq(inf32.to_hex(), inf32_expected_bits)
  assert_true(inf32.format() == @decimal.DecimalInterchangeFormat::Decimal32)
  assert_true(inf32_flags == inf32_expected_flags)
  assert_false(inf32_flags.has_error())

  assert_eq(qnan64.to_hex(), qnan64_expected_bits)
  assert_true(qnan64.format() == @decimal.DecimalInterchangeFormat::Decimal64)
  assert_true(qnan64_flags == qnan64_expected_flags)
  assert_false(qnan64_flags.has_error())

  assert_eq(snan128.to_hex(), snan128_expected_bits)
  assert_true(snan128.format() == @decimal.DecimalInterchangeFormat::Decimal128)
  assert_true(snan128_flags == snan128_expected_flags)
  assert_false(snan128_flags.has_error())
}

///|
test "decimal interchange facade decodes specials through to_decimal" {
  let pos_inf = @decimal.DecimalInterchange::from_hex(
    "#7800000000000000",
    @decimal.DecimalInterchangeFormat::Decimal64,
  ).unwrap()
  let neg_qnan = @decimal.DecimalInterchange::from_hex(
    "#FC0049C5",
    @decimal.DecimalInterchangeFormat::Decimal32,
  ).unwrap()
  let neg_snan = @decimal.DecimalInterchange::from_hex(
    "#FE0000000000000000000000000049C5",
    @decimal.DecimalInterchangeFormat::Decimal128,
  ).unwrap()

  let inf = pos_inf.to_decimal()
  let qnan = neg_qnan.to_decimal()
  let snan = neg_snan.to_decimal()

  assert_true(inf.classify() == @lf_arith.FpClass::Infinity)
  assert_false(inf.is_negative())
  assert_true(qnan.is_qnan())
  assert_true(qnan.is_negative())
  assert_eq(qnan.nan_payload(), 12345N)
  assert_true(snan.is_snan())
  assert_true(snan.is_negative())
  assert_eq(snan.nan_payload(), 12345N)
}

///|
test "decimal interchange facade exposes decimal32 non-canonical qnan witness" {
  let raw = @decimal.DecimalInterchange::from_hex(
    "#7C00016E",
    @decimal.DecimalInterchangeFormat::Decimal32,
  ).unwrap()
  let canonical = @decimal.DecimalInterchange::from_hex(
    "#7C00006E",
    @decimal.DecimalInterchangeFormat::Decimal32,
  ).unwrap()

  assert_false(raw.is_canonical())
  assert_true(canonical.is_canonical())
  assert_eq(raw.canonical().to_hex(), "#7C00006E")
  assert_true(raw.to_decimal().is_qnan())
}

///|
test "decimal interchange facade keeps wrapper canonical predicate distinct from scalar decimal" {
  let raw = @decimal.DecimalInterchange::from_hex(
    "#77FFFF3FCFF3FCFF",
    @decimal.DecimalInterchangeFormat::Decimal64,
  ).unwrap()
  let scalar = raw.to_decimal()
  let expected = @decimal.Decimal::from_string(
    "9.999999999999999E+384",
    precision=64,
  ).unwrap()

  assert_false(raw.is_canonical())
  assert_true(scalar.is_canonical())
  assert_eq(scalar.compare_total(expected).to_string(), "0")
}

///|
test "decimal interchange facade sign transforms preserve observable special meaning" {
  let neg_qnan32 = @decimal.DecimalInterchange::from_hex(
    "#FC0049C5",
    @decimal.DecimalInterchangeFormat::Decimal32,
  ).unwrap()
  let pos_inf32 = @decimal.DecimalInterchange::from_hex(
    "#78000000",
    @decimal.DecimalInterchangeFormat::Decimal32,
  ).unwrap()

  let qnan32_positive = neg_qnan32.copy_abs().to_decimal()
  let inf32_negative = pos_inf32.copy_negate().to_decimal()

  assert_true(qnan32_positive.is_qnan())
  assert_false(qnan32_positive.is_negative())
  assert_eq(qnan32_positive.nan_payload(), 12345N)
  assert_true(inf32_negative.is_infinite())
  assert_true(inf32_negative.is_negative())
}

///|
test "decimal interchange facade sign transforms preserve special raw bits" {
  let neg_qnan32 = @decimal.DecimalInterchange::from_hex(
    "#FC0049C5",
    @decimal.DecimalInterchangeFormat::Decimal32,
  ).unwrap()
  let pos_inf32 = @decimal.DecimalInterchange::from_hex(
    "#78000000",
    @decimal.DecimalInterchangeFormat::Decimal32,
  ).unwrap()
  let neg_snan128 = @decimal.DecimalInterchange::from_hex(
    "#FE0000000000000000000000000049C5",
    @decimal.DecimalInterchangeFormat::Decimal128,
  ).unwrap()
  let pos_inf128 = @decimal.DecimalInterchange::from_hex(
    "#78000000000000000000000000000000",
    @decimal.DecimalInterchangeFormat::Decimal128,
  ).unwrap()

  assert_eq(neg_qnan32.copy_abs().to_hex(), "#7C0049C5")
  assert_eq(pos_inf32.copy_negate().to_hex(), "#F8000000")
  assert_eq(
    neg_snan128.copy_sign(pos_inf128).to_hex(),
    "#7E0000000000000000000000000049C5",
  )
}

///|
test "decimal interchange facade sign transforms preserve finite raw bits and meaning" {
  let finite64 = @decimal.DecimalInterchange::from_hex(
    "#77FFFF3FCFF3FCFF",
    @decimal.DecimalInterchangeFormat::Decimal64,
  ).unwrap()
  let neg_finite64 = @decimal.DecimalInterchange::from_hex(
    "#F7FFFF3FCFF3FCFF",
    @decimal.DecimalInterchangeFormat::Decimal64,
  ).unwrap()

  let abs64 = neg_finite64.copy_abs()
  let negated64 = finite64.copy_negate()
  let signed64 = finite64.copy_sign(neg_finite64)
  let expected_positive64 = @decimal.Decimal::from_string(
    "9.999999999999999E+384",
    precision=64,
  ).unwrap()
  let expected_negative64 = @decimal.Decimal::from_string(
    "-9.999999999999999E+384",
    precision=64,
  ).unwrap()

  assert_eq(abs64.to_hex(), "#77FFFF3FCFF3FCFF")
  assert_eq(negated64.to_hex(), "#F7FFFF3FCFF3FCFF")
  assert_eq(signed64.to_hex(), "#F7FFFF3FCFF3FCFF")
  assert_true(abs64.format() == @decimal.DecimalInterchangeFormat::Decimal64)
  assert_true(
    negated64.format() == @decimal.DecimalInterchangeFormat::Decimal64,
  )
  assert_true(signed64.format() == @decimal.DecimalInterchangeFormat::Decimal64)
  assert_eq(
    abs64.to_decimal().compare_total(expected_positive64).to_string(),
    "0",
  )
  assert_eq(
    negated64.to_decimal().compare_total(expected_negative64).to_string(),
    "0",
  )
  assert_eq(
    signed64.to_decimal().compare_total(expected_negative64).to_string(),
    "0",
  )
}

///|
test "decimal interchange facade sign transforms preserve canonical decimal32 finite raw bits and meaning" {
  let finite32 = @decimal.DecimalInterchange::from_hex(
    "#77F3FCFF",
    @decimal.DecimalInterchangeFormat::Decimal32,
  ).unwrap()
  let neg_finite32 = @decimal.DecimalInterchange::from_hex(
    "#F7F3FCFF",
    @decimal.DecimalInterchangeFormat::Decimal32,
  ).unwrap()

  let abs32 = neg_finite32.copy_abs()
  let negated32 = finite32.copy_negate()
  let signed32 = finite32.copy_sign(neg_finite32)
  let expected_positive32 = @decimal.Decimal::from_string(
    "9.999999E+96",
    precision=64,
  ).unwrap()
  let expected_negative32 = @decimal.Decimal::from_string(
    "-9.999999E+96",
    precision=64,
  ).unwrap()

  assert_eq(abs32.to_hex(), "#77F3FCFF")
  assert_eq(negated32.to_hex(), "#F7F3FCFF")
  assert_eq(signed32.to_hex(), "#F7F3FCFF")
  assert_true(abs32.format() == @decimal.DecimalInterchangeFormat::Decimal32)
  assert_true(
    negated32.format() == @decimal.DecimalInterchangeFormat::Decimal32,
  )
  assert_true(signed32.format() == @decimal.DecimalInterchangeFormat::Decimal32)
  assert_eq(
    abs32.to_decimal().compare_total(expected_positive32).to_string(),
    "0",
  )
  assert_eq(
    negated32.to_decimal().compare_total(expected_negative32).to_string(),
    "0",
  )
  assert_eq(
    signed32.to_decimal().compare_total(expected_negative32).to_string(),
    "0",
  )
}

///|
test "decimal interchange facade copy preserves special raw bits and format" {
  let raw32 = @decimal.DecimalInterchange::from_hex(
    "#7C00016E",
    @decimal.DecimalInterchangeFormat::Decimal32,
  ).unwrap()
  let raw128 = @decimal.DecimalInterchange::from_hex(
    "#7E000000000000000000000000003039",
    @decimal.DecimalInterchangeFormat::Decimal128,
  ).unwrap()

  let copied32 = raw32.copy()
  let copied128 = raw128.copy()

  assert_eq(copied32.to_hex(), "#7C00016E")
  assert_true(copied32.format() == @decimal.DecimalInterchangeFormat::Decimal32)
  assert_true(copied32.to_decimal().is_qnan())
  assert_eq(copied128.to_hex(), "#7E000000000000000000000000003039")
  assert_true(
    copied128.format() == @decimal.DecimalInterchangeFormat::Decimal128,
  )
  assert_true(copied128.to_decimal().is_snan())
}

///|
test "decimal interchange facade copy preserves finite raw bits and format" {
  let raw32 = @decimal.DecimalInterchange::from_hex(
    "#77F3FFFF",
    @decimal.DecimalInterchangeFormat::Decimal32,
  ).unwrap()
  let raw64 = @decimal.DecimalInterchange::from_hex(
    "#77FFFF3FCFF3FCFF",
    @decimal.DecimalInterchangeFormat::Decimal64,
  ).unwrap()
  let raw128 = @decimal.DecimalInterchange::from_hex(
    "#77FFFFF3FCFF3FCFF3FCFF3FCFF3FCFF",
    @decimal.DecimalInterchangeFormat::Decimal128,
  ).unwrap()

  let copied32 = raw32.copy()
  let copied64 = raw64.copy()
  let copied128 = raw128.copy()

  assert_eq(copied32.to_hex(), "#77F3FFFF")
  assert_eq(copied64.to_hex(), "#77FFFF3FCFF3FCFF")
  assert_eq(copied128.to_hex(), "#77FFFFF3FCFF3FCFF3FCFF3FCFF3FCFF")
  assert_true(copied32.format() == @decimal.DecimalInterchangeFormat::Decimal32)
  assert_true(copied64.format() == @decimal.DecimalInterchangeFormat::Decimal64)
  assert_true(
    copied128.format() == @decimal.DecimalInterchangeFormat::Decimal128,
  )
}

///|
test "decimal interchange facade canonical predicate covers decimal64 special raw bits" {
  let raw_qnan64 = @decimal.DecimalInterchange::from_hex(
    "#7C03FF3FCFF3FCFF",
    @decimal.DecimalInterchangeFormat::Decimal64,
  ).unwrap()
  let canonical_qnan64 = @decimal.DecimalInterchange::from_hex(
    "#7C00FF3FCFF3FCFF",
    @decimal.DecimalInterchangeFormat::Decimal64,
  ).unwrap()

  assert_false(raw_qnan64.is_canonical())
  assert_true(canonical_qnan64.is_canonical())
  assert_eq(raw_qnan64.canonical().to_hex(), "#7C00FF3FCFF3FCFF")
}

///|
test "decimal interchange facade canonical predicate covers decimal32 special raw bits" {
  let raw_qnan32 = @decimal.DecimalInterchange::from_hex(
    "#7C00016E",
    @decimal.DecimalInterchangeFormat::Decimal32,
  ).unwrap()
  let canonical_qnan32 = @decimal.DecimalInterchange::from_hex(
    "#7C00006E",
    @decimal.DecimalInterchangeFormat::Decimal32,
  ).unwrap()
  assert_false(raw_qnan32.is_canonical())
  assert_true(canonical_qnan32.is_canonical())
  assert_eq(raw_qnan32.canonical().to_hex(), "#7C00006E")
}

///|
test "decimal interchange facade canonical predicate covers decimal128 special raw bits" {
  let raw_snan128 = @decimal.DecimalInterchange::from_hex(
    "#FE020000000000000000000000003039",
    @decimal.DecimalInterchangeFormat::Decimal128,
  ).unwrap()
  let canonical_snan128 = @decimal.DecimalInterchange::from_hex(
    "#FE000000000000000000000000003039",
    @decimal.DecimalInterchangeFormat::Decimal128,
  ).unwrap()

  assert_false(raw_snan128.is_canonical())
  assert_true(canonical_snan128.is_canonical())
  assert_eq(
    raw_snan128.canonical().to_hex(),
    "#FE000000000000000000000000003039",
  )
}

///|
test "decimal interchange facade canonical predicate covers finite raw bits across formats" {
  let raw32 = @decimal.DecimalInterchange::from_hex(
    "#77F3FFFF",
    @decimal.DecimalInterchangeFormat::Decimal32,
  ).unwrap()
  let canonical32 = @decimal.DecimalInterchange::from_hex(
    "#77F3FCFF",
    @decimal.DecimalInterchangeFormat::Decimal32,
  ).unwrap()
  let raw64 = @decimal.DecimalInterchange::from_hex(
    "#77FFFF3FCFF3FCFF",
    @decimal.DecimalInterchangeFormat::Decimal64,
  ).unwrap()
  let canonical64 = @decimal.DecimalInterchange::from_hex(
    "#77FCFF3FCFF3FCFF",
    @decimal.DecimalInterchangeFormat::Decimal64,
  ).unwrap()
  let raw128 = @decimal.DecimalInterchange::from_hex(
    "#77FFFFF3FCFF3FCFF3FCFF3FCFF3FCFF",
    @decimal.DecimalInterchangeFormat::Decimal128,
  ).unwrap()
  let canonical128 = @decimal.DecimalInterchange::from_hex(
    "#77FFCFF3FCFF3FCFF3FCFF3FCFF3FCFF",
    @decimal.DecimalInterchangeFormat::Decimal128,
  ).unwrap()

  assert_false(raw32.is_canonical())
  assert_true(canonical32.is_canonical())
  assert_eq(raw32.canonical().to_hex(), "#77F3FCFF")
  assert_false(raw64.is_canonical())
  assert_true(canonical64.is_canonical())
  assert_eq(raw64.canonical().to_hex(), "#77FCFF3FCFF3FCFF")
  assert_false(raw128.is_canonical())
  assert_true(canonical128.is_canonical())
  assert_eq(raw128.canonical().to_hex(), "#77FFCFF3FCFF3FCFF3FCFF3FCFF3FCFF")
}

///|
test "bin_float checked compare rejects nan" {
  let result = @bin_float.BinFloat::nan(precision=8).compare_checked(
    @bin_float.BinFloat::zero(precision=8),
  )
  match result {
    Ok(_) => fail("expected unordered compare")
    Err(err) => assert_true(err.is_unordered_comparison())
  }
}

///|
test "bin_float low precision rounding and ulp stay explicit" {
  let x = binary_test_make(13N, -3, 8)
  let rounded = x.with_precision(2, @lf_arith.RoundingMode::ToNearestEven)
  assert_eq(rounded.to_string(), "3p-1")
  assert_eq(rounded.ulp().to_string(), "1p-1")
  assert_eq(@bin_float.BinFloat::zero(precision=4).ulp().to_string(), "1p-3")
}

///|
test "checked trait helpers are usable through arithmetic boundary" {
  let parsed : Result[@decimal.Decimal, @lf_arith.ArithmeticError] = @lf_arith.ParseChecked::parse_checked(
    "12.5", audit_ctx,
  )
  match parsed {
    Ok(value) => assert_eq(value.to_string(), "12.5")
    Err(_) => fail("expected checked parse to succeed")
  }
  match
    @lf_arith.DivChecked::div_checked(
      @decimal.Decimal::from_int(7, precision=6),
      @decimal.Decimal::from_int(2, precision=6),
      audit_ctx,
    ) {
    Ok(value) => assert_true(value.to_string().has_prefix("3.5"))
    Err(_) => fail("expected checked decimal division to succeed")
  }
}

///|
test "semantic scalar interpretation unifies binary and decimal rationals" {
  let expected = @semantic.SemanticScalar::Rational(
    @semantic.ExactRational::new(3N, 2N),
  )
  let binary = @semantic.SemanticScalar::from_bin_float(
    binary_test_make(3N, -1, 16),
  )
  let decimal = @semantic.SemanticScalar::from_decimal(
    @decimal.Decimal::from_string("1.50", precision=16).unwrap(),
  )
  assert_true(binary == expected)
  assert_true(decimal == expected)
}

///|
test "semantic result interpretation totalizes checked failures" {
  let checked = @bin_float.BinFloat::from_int(1, precision=16).div_checked(
    @bin_float.BinFloat::zero(precision=16),
  )
  let semantic = @semantic.semantic_scalar_result(checked, value => {
    @semantic.SemanticScalar::from_bin_float(value)
  })
  assert_true(
    semantic ==
    @semantic.SemanticResult::Error(@semantic.SemanticError::DivisionByZero),
  )
}

///|
test "semantic interval interpretation preserves ball bounds" {
  let ball = @ball_float.BallFloat::from_bounds(
    binary_test_make(1N, -1, 16),
    binary_test_make(3N, -1, 16),
    precision=16,
  )
  let interval = @semantic.SemanticInterval::from_ball_float(ball)
  assert_true(
    interval.lower ==
    @semantic.SemanticScalar::Rational(@semantic.ExactRational::new(1N, 2N)),
  )
  assert_true(
    interval.upper ==
    @semantic.SemanticScalar::Rational(@semantic.ExactRational::new(3N, 2N)),
  )
}

///|
test "decimal32 finite sign transforms stay aligned with direct interchange decode" {
  let pos32 = @decimal.DecimalInterchange::from_hex(
    "#77FFFF3F",
    @decimal.DecimalInterchangeFormat::Decimal32,
  ).unwrap()
  let neg32 = @decimal.DecimalInterchange::from_hex(
    "#F7FFFF3F",
    @decimal.DecimalInterchangeFormat::Decimal32,
  ).unwrap()

  let direct_pos = pos32.to_decimal()
  let direct_neg = neg32.to_decimal()
  let abs_from_neg = neg32.copy_abs()
  let negated_from_pos = pos32.copy_negate()
  let signed_from_pos = pos32.copy_sign(neg32)

  assert_eq(abs_from_neg.to_hex(), "#77FFFF3F")
  assert_eq(negated_from_pos.to_hex(), "#F7FFFF3F")
  assert_eq(signed_from_pos.to_hex(), "#F7FFFF3F")
  assert_true(
    abs_from_neg.format() == @decimal.DecimalInterchangeFormat::Decimal32,
  )
  assert_true(
    negated_from_pos.format() == @decimal.DecimalInterchangeFormat::Decimal32,
  )
  assert_true(
    signed_from_pos.format() == @decimal.DecimalInterchangeFormat::Decimal32,
  )
  assert_eq(
    abs_from_neg.to_decimal().compare_total(direct_pos).to_string(),
    "0",
  )
  assert_eq(
    negated_from_pos.to_decimal().compare_total(direct_neg).to_string(),
    "0",
  )
  assert_eq(
    signed_from_pos.to_decimal().compare_total(direct_neg).to_string(),
    "0",
  )
}
