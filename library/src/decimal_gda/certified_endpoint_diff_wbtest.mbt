///|
// The conversions between binary and decimal values that no longer pass through a host
// big integer: the decimal limbs of a big-endian byte string, and
// `decimal_exact_dyadic_endpoint`. The oracles are the rows of
// `certified_endpoint_rows_wbtest.mbt` (CPython, tools/generate_decimal_gda_endpoint_rows.py)
// and core `BigInt` text conversion; the previous implementations are gone.

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
fn endpoint_coeff_text(coeff : DecCoeff) -> String {
  finite_with_exponent_repr(false, coeff, 0, coeff.digits10()).to_string()
}

///|
fn endpoint_pattern_bytes(pattern : String, length : Int32) -> Bytes {
  let bytes = FixedArray::make(length, b'\x00')
  for index in 0..<length {
    bytes[index] = if pattern == "ones" {
      b'\xff'
    } else if index == 0 {
      b'\x01'
    } else {
      b'\x00'
    }
  }
  Bytes::from_array(bytes)
}

///|
// oracle: B, A
// source: the digits of the integer are given by core `BigInt::to_string` (a decimal conversion of another implementation, MoonBit core) for random byte strings, leading zero bytes, and powers of two with their neighbours; and, at the edges, by the rows `limb_edge_rows` (digit count, first and last 20 digits of CPython integers) for lengths 1 to 20000 bytes including 8917 and 8918, where the capacity computation of the old code wrapped
// shares: `finite_with_exponent_repr` and `Decimal::to_string` print the result (the printers of the result; the expected text is the CPython text); `dec_coeff_zero` for the empty string
// primitives: Decimal::to_string, finite_with_exponent_repr
test "decimal limbs of big-endian bytes equal the big integer conversion" {
  let state = Ref(0x9E3779B97F4A7C15UL)
  let mut checked = 0
  for length in 0..<260 {
    for _ in 0..<6 {
      let bytes = endpoint_random_bytes(state, length)
      let expected = if length == 0 {
        "0"
      } else {
        BigInt::from_octets(bytes).to_string()
      }
      assert_eq(
        endpoint_coeff_text(decimal_coeff_from_be_bytes(bytes)),
        expected,
      )
      checked += 1
    }
  }
  for length in [300, 511, 512, 513, 1000, 2047, 4999, 5000, 8917, 8918, 9000] {
    let bytes = endpoint_random_bytes(state, length)
    assert_eq(
      endpoint_coeff_text(decimal_coeff_from_be_bytes(bytes)),
      BigInt::from_octets(bytes).to_string(),
    )
  }
  assert_true(checked > 1000)
  // powers of two with their neighbours
  for shift in 0..<400 {
    let power = BigInt::from_int(1) << shift
    for delta in [-1, 0, 1] {
      let value = power + BigInt::from_int(delta)
      if value > BigInt::from_int(0) {
        assert_eq(
          endpoint_coeff_text(decimal_coeff_from_be_bytes(value.to_octets())),
          value.to_string(),
        )
      }
    }
  }
  // the edge rows
  for row in limb_edge_rows {
    let (pattern, length, count, head, tail) = row
    let text = endpoint_coeff_text(
      decimal_coeff_from_be_bytes(endpoint_pattern_bytes(pattern, length)),
    )
    assert_eq((pattern, length, text.length()), (pattern, length, count))
    assert_eq((pattern, length, text[:20].to_owned()), (pattern, length, head))
    assert_eq(
      (pattern, length, text[text.length() - 20:].to_owned()),
      (pattern, length, tail),
    )
  }
}

///|
// oracle: A
// source: the rows `dyadic_endpoint_rows` (CPython integers and `decimal`: the exact decimal text of coefficient * 2^exponent2 with its sign, and the exact classification against 10^(emax+2) and 10^(etiny-2)); an endpoint far outside the range may be replaced by 1E+(emax+2) or 1E+(etiny-2) of the same sign, as the documentation of decimal_out_of_range_endpoint says; zero and the infinities are written out
// shares: Decimal::to_string (prints the result)
test "exact dyadic endpoints equal the big integer route" {
  let wide = DecimalContext::new(
    precision=34,
    e_min=-999999999,
    e_max=999999999,
  )
  let narrow = DecimalContext::new(precision=7, e_min=-99, e_max=99)
  let mut bad = 0
  for row in dyadic_endpoint_rows {
    let (negative, hex, exponent2, context, text, over, under) = row
    let coefficient = @binary.BinCoeff::from_bytes_be(
      from_binary_hex_bytes(hex)[:],
    )
    let value = @binary.Binary::make(
      coefficient,
      exponent2,
      coefficient.bit_length(),
      negative~,
    )
    let actual = decimal_exact_dyadic_endpoint(
      value,
      if context == 0 {
        wide
      } else {
        narrow
      },
    )
    let sign = if negative { "-" } else { "" }
    // wide: emax + 2 = 1000000001, etiny - 2 = -1000000034; narrow: 101, -107
    let over_text = sign +
      (if context == 0 { "1E+1000000001" } else { "1E+101" })
    let under_text = sign +
      (if context == 0 { "1E-1000000034" } else { "1E-107" })
    let got = match actual {
      Some(d) => d.to_string()
      None => "none"
    }
    let expected_text = text
    let ok = got == expected_text ||
      (over && got == over_text) ||
      (under && got == under_text)
    if !ok {
      bad += 1
      if bad <= 10 {
        println(
          "row \{hex} e2=\{exponent2} ctx=\{context}: got \{got}, expected \{expected_text}",
        )
      }
    }
  }
  assert_eq(bad, 0)
  // zero and the infinities
  let zero = decimal_exact_dyadic_endpoint(
    @binary.Binary::zero(precision=53),
    wide,
  )
  assert_eq(zero.unwrap().to_string(), "0")
  let inf = decimal_exact_dyadic_endpoint(
    @binary.Binary::inf(precision=53),
    wide,
  )
  assert_eq(inf.unwrap().to_string(), "1E+1000000001")
  let ninf = decimal_exact_dyadic_endpoint(
    @binary.Binary::inf(negative=true, precision=53),
    narrow,
  )
  assert_eq(ninf.unwrap().to_string(), "-1E+101")
  assert_true(
    decimal_exact_dyadic_endpoint(@binary.Binary::nan(precision=53), wide)
    is None,
  )
}
