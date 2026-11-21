///|
// The stored range of a finite `Decimal` (#438, decided with the one of
// `decimal_gda`): largest adjusted exponent `decimal_value_e_max`
// (2147483646), smallest exponent `decimal_value_e_tiny` (-2147483645). The
// exact constructors refuse a value outside it, a zero included, checked
// after the rounding to the precision (a carry included); nothing is
// replaced silently.

///|
fn stored_range_storable(x : Decimal) -> Bool {
  if !x.is_finite() {
    return true
  }
  let digits = if x.is_zero() { 1 } else { x.coefficient.digits10() }
  x.exponent10.to_int64() >= decimal_value_e_tiny.to_int64() &&
  x.exponent10.to_int64() + (digits - 1).to_int64() <=
  decimal_value_e_max.to_int64()
}

///|
test "the limits are the largest adjusted exponent and the smallest exponent" {
  assert_eq(decimal_value_e_max, 2147483646)
  assert_eq(decimal_value_e_tiny, -2147483645)
}

///|
test "make accepts the limits and refuses one beyond" {
  // largest adjusted exponent: 1 digit at 2147483646, 5 digits at 2147483642
  assert_eq(Decimal::make(1N, 2147483646, 34).exponent10, 2147483646)
  assert_eq(Decimal::make(12345N, 2147483642, 34).exponent10, 2147483642)
  assert_true(Decimal::try_make(1N, 2147483647, 34) is Err(_))
  assert_true(Decimal::try_make(12345N, 2147483643, 34) is Err(_))
  // smallest exponent
  assert_eq(Decimal::make(1N, -2147483645, 34).exponent10, -2147483645)
  assert_true(Decimal::try_make(1N, -2147483646, 34) is Err(_))
  // zeros are treated like every finite value
  assert_eq(Decimal::make(0N, 2147483646, 34).to_string(), "0E+2147483646")
  assert_eq(Decimal::make(0N, -2147483645, 34).to_string(), "0E-2147483645")
  assert_true(Decimal::try_make(0N, 2147483647, 34) is Err(_))
  assert_true(Decimal::try_make(0N, -2147483646, 34) is Err(_))
  assert_true(Decimal::try_make(0N, -2147483648, 34) is Err(_))
}

///|
test "the range is checked after the rounding to the precision, a carry included" {
  // 99999 at precision 3 rounds to 100E+2: the carry raises the exponent by
  // one, and the adjusted exponent 2147483646 of the input becomes 2147483647
  assert_true(Decimal::try_make(99999N, 2147483642, 3) is Err(_))
  assert_eq(
    Decimal::make(99949N, 2147483642, 3).to_string(),
    "9.99E+2147483646",
  )
  // a long coefficient below the smallest exponent is rounded into the range
  let rounded = Decimal::make(1249N, -2147483646, 3)
  assert_eq(rounded.exponent10, -2147483645)
  assert_true(Decimal::try_make(1249N, -2147483647, 3) is Err(_))
}

///|
fn stored_range_message(
  coefficient : BigInt,
  exponent : Int32,
  precision : Int32,
) -> String {
  match Decimal::try_make(coefficient, exponent, precision) {
    Err(error) => error.message
    Ok(_) => abort("expected the domain error")
  }
}

///|
test "the error names the exponent the caller gave, both limits and the rounded exponent" {
  // below the smallest exponent: no rounding, the exponent given is named
  let below = stored_range_message(1N, -2147483646, 34)
  assert_eq(
    below, "Decimal::try_make: the value with exponent -2147483646 (adjusted exponent -2147483646) is outside the range of a Decimal (smallest exponent -2147483645, largest adjusted exponent 2147483646)",
  )
  // adjusted exponent above the largest without rounding: exponent and adjusted
  let above = stored_range_message(12345N, 2147483643, 34)
  assert_eq(
    above, "Decimal::try_make: the value with exponent 2147483643 (adjusted exponent 2147483647) is outside the range of a Decimal (smallest exponent -2147483645, largest adjusted exponent 2147483646)",
  )
  // above it only by the carry: the input is inside (adjusted 2147483646), the
  // rounding to 3 digits gives exponent 2147483645 and adjusted exponent 2147483647
  let carry = stored_range_message(99999N, 2147483642, 3)
  assert_eq(
    carry, "Decimal::try_make: the value with exponent 2147483642 (adjusted exponent 2147483646) is outside the range of a Decimal (smallest exponent -2147483645, largest adjusted exponent 2147483646); after the rounding to the precision its exponent is 2147483645 (adjusted exponent 2147483647)",
  )
  // a zero is named by its exponent
  assert_eq(
    stored_range_message(0N, 2147483647, 34),
    "Decimal::try_make: the value with exponent 2147483647 (adjusted exponent 2147483647) is outside the range of a Decimal (smallest exponent -2147483645, largest adjusted exponent 2147483646)",
  )
  // the precision error names the precision
  match Decimal::try_make(1N, 0, 0) {
    Err(error) =>
      assert_eq(
        error.message,
        "Decimal::try_make: precision 0 must be within 1..=999999999",
      )
    Ok(_) => fail("expected the domain error")
  }
}

///|
test "from_string accepts the limits and refuse one beyond" {
  assert_true(Decimal::from_string("1E2147483646") is Ok(_))
  assert_true(Decimal::from_string("12345E2147483642") is Ok(_))
  assert_true(Decimal::from_string("-0E2147483646") is Ok(_))
  assert_true(Decimal::from_string("1E-2147483645") is Ok(_))
  assert_true(Decimal::from_string("0E-2147483645") is Ok(_))
  assert_true(Decimal::from_string("1E2147483647") is Err(_))
  assert_true(Decimal::from_string("12345E2147483643") is Err(_))
  assert_true(Decimal::from_string("0E2147483647") is Err(_))
  assert_true(Decimal::from_string("1E-2147483646") is Err(_))
  assert_true(Decimal::from_string("0E-2147483646") is Err(_))
  // a text outside the limits is read with a context when a rounded value is wanted
  let (value, flags) = Decimal::from_string_ctx(
    "1E2147483647",
    DecimalContext::new(precision=34, e_max=999_999_999),
  )
  assert_true(value.is_infinite())
  assert_true(flags.overflow())
}

///|
test "rounding without a context at the top of the range overflows by the mode" {
  let top = Decimal::make(9999N, 2147483643, 4)
  assert_eq(top.exponent10, 2147483643)
  assert_true(
    top
    .with_precision(2, DecimalRoundingMode::RoundTowardPositive)
    .is_infinite(),
  )
  assert_eq(
    top.with_precision(2, DecimalRoundingMode::RoundTowardZero).to_string(),
    "9.9E+2147483646",
  )
  assert_true(
    top.with_precision(2, DecimalRoundingMode::RoundTiesToEven).is_infinite(),
  )
}

///|
test "every context-free function that returns a Decimal gives a non-finite or a storable value" {
  // inputs at and near both ends of the stored range, digits 1, 2, 34, 100
  let exponents : Array[Int32] = [
    2147483646, 2147483645, 2147483613, 2147483547, 2147483000, 1000000000, 999999,
    0, -999998, -1000000000, -2147483000, -2147483644, -2147483645,
  ]
  let coefficients : Array[String] = [
    "1",
    "9",
    "12",
    "99",
    "1234567890123456789012345678901234",
    "9999999999999999999999999999999999",
    String::make(100, '9'),
  ]
  let values : Array[Decimal] = []
  for coefficient in coefficients {
    let digits = coefficient.length()
    for exponent in exponents {
      for negative in [false, true] {
        let text = (if negative { "-" } else { "" }) +
          coefficient +
          "E" +
          exponent.to_string()
        match Decimal::from_string(text, precision=Int32::max(digits, 34)) {
          Ok(value) => {
            assert_true(stored_range_storable(value), msg="from_string " + text)
            values.push(value)
          }
          Err(_) => {
            // refused exactly when the adjusted exponent is beyond the limit
            let adjusted = exponent.to_int64() + (digits - 1).to_int64()
            assert_true(adjusted > decimal_value_e_max.to_int64(), msg=text)
          }
        }
        match
          Decimal::try_make(
            (if negative { -1N } else { 1N }) * bigint_from_text(coefficient),
            exponent,
            Int32::max(digits, 34),
          ) {
          Ok(value) =>
            assert_true(stored_range_storable(value), msg="make " + text)
          Err(_) => ()
        }
      }
    }
  }
  for
    z in [
      Decimal::zero(),
      Decimal::negative_zero(),
      Decimal::make(0N, 2147483646, 34),
      Decimal::make(0N, -2147483645, 34),
    ] {
    values.push(z)
  }
  assert_true(values.length() > 150)
  let one = Decimal::one()
  let modes = [
    DecimalRoundingMode::RoundTiesToEven,
    DecimalRoundingMode::RoundTiesToAway,
    DecimalRoundingMode::RoundTowardZero,
    DecimalRoundingMode::RoundTowardPositive,
    DecimalRoundingMode::RoundTowardNegative,
  ]
  for x in values {
    // functions of one value: abs, copy, neg, normalized, sqrt, set_payload,
    // set_payload_signaling, with_precision
    for
      result in [
        x.abs(),
        x.copy(),
        x.neg(),
        x.normalized(),
        x.sqrt(),
        x.set_payload(0N),
        x.set_payload_signaling(0N),
        x.set_payload(7N),
      ] {
      assert_true(stored_range_storable(result), msg="unary " + x.to_string())
    }
    for p in [1, 2, 5, 34] {
      for mode in modes {
        assert_true(
          stored_range_storable(x.with_precision(p, mode)),
          msg="with_precision " + x.to_string(),
        )
      }
    }
    // the plain arithmetic: overflow or underflow of the working context
    for
      y in [
        one,
        x,
        x.neg(),
        Decimal::zero(),
        Decimal::make(7N, -2147483645, 34),
      ] {
      for
        result in [
          x + y,
          x - y,
          x * y,
          x / y,
          x.min(y),
          x.max(y),
          x.copy_sign(y),
          x.clamp(min=y.min(y.neg()), max=y.max(y.neg())),
        ] {
        assert_true(
          stored_range_storable(result),
          msg=x.to_string() + " op " + y.to_string(),
        )
      }
    }
  }
  // constructors from integers, floats and binary floats
  for n in [0, 1, -1, 2147483647, -2147483647 - 1] {
    assert_true(stored_range_storable(Decimal::from_int(n)))
    assert_true(
      stored_range_storable(Decimal::from_bigint(BigInt::from_int(n))),
    )
  }
  for
    f in [1.7976931348623157e308, 5.0e-324, -2.2250738585072014e-308, 0.0, 1.0] {
    assert_true(stored_range_storable(Decimal::from_double(f)))
    assert_true(stored_range_storable(Decimal::from_double(f, precision=1)))
  }
  assert_true(stored_range_storable(Decimal::from_float(3.4028235e38)))
  for k in [1073741000, -1073741000, 0, 100000, -100000] {
    let x = @binary.Binary::make(@binary.BinCoeff::one(), k, 2)
    for p in [1, 34, 100] {
      assert_true(stored_range_storable(Decimal::from_binary(x, precision=p)))
    }
  }
  assert_true(stored_range_storable(Decimal::inf()))
  assert_true(stored_range_storable(Decimal::nan()))
  assert_true(stored_range_storable(Decimal::quiet_nan(payload=5N)))
  assert_true(stored_range_storable(Decimal::signaling_nan(payload=5N)))
  // the interchange formats hold exponents far inside the range by construction
  for
    format in [
      DecimalInterchangeFormat::Decimal32,
      DecimalInterchangeFormat::Decimal64,
      DecimalInterchangeFormat::Decimal128,
    ] {
    match
      Decimal::from_interchange_hex(
        match format {
          Decimal32 => "78000000"
          Decimal64 => "7800000000000000"
          Decimal128 => "78000000000000000000000000000000"
        },
        format,
      ) {
      Ok(value) => assert_true(stored_range_storable(value))
      Err(_) => ()
    }
  }
}
