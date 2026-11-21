///|
// Differential tests of the conversions between binary and decimal values that
// no longer pass through a host big integer, against the previous
// implementations, kept here as reference code: the decimal limbs of a
// big-endian byte string, and `decimal_exact_dyadic_endpoint`.

///|
fn endpoint_next(state : Ref[UInt64]) -> UInt64 {
  let mut x = state.val
  x = x ^ (x << 13)
  x = x ^ (x >> 7)
  x = x ^ (x << 17)
  state.val = x
  x
}

///|
fn endpoint_random_bytes(state : Ref[UInt64], length : Int32) -> Bytes {
  let bytes = FixedArray::make(length, b'\x00')
  let style = endpoint_next(state) % 6UL
  for index in 0..<length {
    let value = match style {
      0UL => 255
      1UL => if index == 0 { 1 } else { 0 }
      2UL => if endpoint_next(state) % 4UL == 0UL { 255 } else { 0 }
      _ => (endpoint_next(state) % 256UL).to_int()
    }
    bytes[index] = value.to_byte()
  }
  Bytes::from_array(bytes)
}

///|
fn endpoint_same_coeff(a : DecCoeff, b : DecCoeff) -> Bool {
  match (a, b) {
    (Small(x), Small(y)) => x == y
    (Limbs(x, dx), Limbs(y, dy)) => dx == dy && x == y
    _ => false
  }
}

///|
test "decimal limbs of big-endian bytes equal the big integer conversion" {
  let state = Ref(0x9E3779B97F4A7C15UL)
  let mut checked = 0
  for length in 0..<260 {
    for _ in 0..<6 {
      let bytes = endpoint_random_bytes(state, length)
      let expected = if length == 0 {
        dec_coeff_zero()
      } else {
        dec_coeff_from_bigint_repr(BigInt::from_octets(bytes))
      }
      assert_true(
        endpoint_same_coeff(decimal_coeff_from_be_bytes(bytes), expected),
      )
      checked += 1
    }
  }
  // long strings: 1 to 5,000 bytes (40,000 bits)
  // 8,918 bytes is the first length whose bit count times 30103 exceeds
  // Int32 (the old capacity computation wrapped there); 9,000 and 20,000 are
  // above it
  for
    length in [
      300, 511, 512, 513, 1000, 2047, 4999, 5000, 8917, 8918, 9000, 20000,
    ] {
    let bytes = endpoint_random_bytes(state, length)
    assert_true(
      endpoint_same_coeff(
        decimal_coeff_from_be_bytes(bytes),
        dec_coeff_from_bigint_repr(BigInt::from_octets(bytes)),
      ),
    )
  }
  assert_true(checked > 1000)
  // leading zero bytes, and powers of two with their neighbours
  for shift in 0..<400 {
    let power = BigInt::from_int(1) << shift
    for delta in [-1, 0, 1] {
      let value = power + BigInt::from_int(delta)
      if value > BigInt::from_int(0) {
        let bytes = value.to_octets()
        assert_true(
          endpoint_same_coeff(
            decimal_coeff_from_be_bytes(bytes),
            dec_coeff_from_bigint_repr(value),
          ),
        )
      }
    }
  }
}

///|
/// The previous `decimal_exact_dyadic_endpoint`: the binary coefficient through
/// `BigInt`, `<< e2` or `* 5^k`, and the conversion of the product.
fn decimal_exact_dyadic_endpoint_reference(
  value : @bin_float.BinFloat,
  ctx : DecimalContext,
) -> Decimal? {
  if value.classify() == FpClass::Infinity {
    return Some(
      finite_with_exponent(
        value.is_negative(),
        BigInt::from_int(1),
        ctx.e_max + 2,
        1,
      ),
    )
  }
  guard value.classify() == FpClass::Finite else { return None }
  match decimal_out_of_range_endpoint(value, ctx) {
    Some(representative) => return Some(representative)
    None => ()
  }
  if value.is_zero() {
    return Some(
      if value.is_negative_zero() {
        Decimal::negative_zero_raw(precision=1)
      } else {
        Decimal::zero_raw(precision=1)
      },
    )
  }
  let coefficient = BigInt::from_octets(value.coefficient().to_bytes_be())
  let (magnitude, exponent10) = if value.exponent2() >= 0 {
    (coefficient << value.exponent2(), 0)
  } else {
    let shift = -value.exponent2()
    (coefficient * pow5(shift), -shift)
  }
  Some(
    finite_with_exponent(
      value.is_negative(),
      magnitude,
      exponent10,
      digits10(magnitude),
    ),
  )
}

///|
fn endpoint_check(
  value : @bin_float.BinFloat,
  ctx : DecimalContext,
) -> Unit raise {
  let actual = decimal_exact_dyadic_endpoint(value, ctx)
  let expected = decimal_exact_dyadic_endpoint_reference(value, ctx)
  let same = match (actual, expected) {
    (None, None) => true
    (Some(a), Some(b)) => add_plain_same_decimal(a, b)
    _ => false
  }
  if !same {
    fail("dyadic endpoint differs for \{value.to_string()}")
  }
}

///|
test "exact dyadic endpoints equal the big integer route" {
  let state = Ref(0xD1B54A32D192ED03UL)
  let wide = DecimalContext::new(
    precision=34,
    e_min=-999999999,
    e_max=999999999,
  )
  let narrow = DecimalContext::new(precision=7, e_min=-99, e_max=99)
  let mut taken = 0
  for iteration in 0..<400 {
    let bytes_len = 1 +
      (endpoint_next(state) % 24UL).to_int() +
      (if iteration % 40 == 0 { 400 } else { 0 })
    let coefficient = @bin_float.BinCoeff::from_bytes_be(
      endpoint_random_bytes(state, bytes_len)[:],
    )
    if coefficient.is_zero() {
      continue
    }
    let precision = coefficient.bit_length()
    let negative = endpoint_next(state) % 2UL == 0UL
    for
      exponent2 in [
        0,
        1,
        7,
        63,
        64,
        -1,
        -9,
        -63,
        -64,
        -200,
        200,
        -(endpoint_next(state) % 1500UL).to_int(),
        (endpoint_next(state) % 1500UL).to_int(),
      ] {
      let value = @bin_float.BinFloat::make(
        coefficient,
        exponent2,
        precision,
        negative~,
      )
      endpoint_check(value, wide)
      endpoint_check(value, narrow)
      taken += 1
    }
  }
  assert_true(taken > 3000)
  // zero, infinity, and the out-of-range representatives
  endpoint_check(@bin_float.BinFloat::zero(precision=53), wide)
  endpoint_check(@bin_float.BinFloat::inf(precision=53), wide)
  endpoint_check(@bin_float.BinFloat::inf(negative=true, precision=53), narrow)
}
