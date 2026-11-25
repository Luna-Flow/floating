///|
/// Canonical text of a result, for comparing a result of the library with a
/// result of the reference (MPFR, libmpdec) as text.
///
/// The comparison must not pass through a reader of the library under test: a
/// reader that misreads a result would misread the reference in the same way
/// and the two would agree. These functions read the reference text and the
/// text the library prints with one small parser of their own (no library
/// reader, no library comparison), and what is compared is the canonical text:
///
/// - binary: `nan`, `inf`, `-inf`, `0`, `-0` (the sign of zero is compared), or
///   `[-]0b<bits>p<exponent>` with no leading zero and a last bit of 1 (the
///   value is a unique pair of an odd integer and an exponent);
/// - decimal: `NaN`, `Infinity`, `-Infinity`, or `[-]<coefficient>E<exponent>`
///   with the coefficient digits as written (trailing zeros kept: the cohort is
///   compared) without leading zeros, the sign of zero kept.
///
/// A NaN is compared as a NaN: the sign and the payload of a NaN carry no
/// result in the cases of the baseline.
fn hex_digit_value(c : Char) -> Int32? {
  let n = c.to_int()
  if n >= 48 && n <= 57 {
    Some(n - 48)
  } else if n >= 97 && n <= 102 {
    Some(n - 87)
  } else if n >= 65 && n <= 70 {
    Some(n - 55)
  } else {
    None
  }
}

///|
fn is_decimal_digit(c : Char) -> Bool {
  c.to_int() >= 48 && c.to_int() <= 57
}

///|
fn text_chars(text : String) -> Array[Char] {
  let chars : Array[Char] = []
  for c in text {
    chars.push(c)
  }
  chars
}

///|
/// The signed exponent that starts at `start` (`+5`, `-12`, `7`), or `None` for
/// no digit, a stray character or a magnitude above 2^40 (no format of the
/// baseline comes near it).
fn parse_exponent(chars : Array[Char], start : Int32) -> Int64? {
  let mut i = start
  let mut negative = false
  if i < chars.length() && (chars[i] == '+' || chars[i] == '-') {
    negative = chars[i] == '-'
    i += 1
  }
  if i >= chars.length() {
    return None
  }
  let mut value = 0L
  while i < chars.length() {
    if !is_decimal_digit(chars[i]) {
      return None
    }
    value = value * 10L + (chars[i].to_int() - 48).to_int64()
    if value > 1099511627776L {
      return None
    }
    i += 1
  }
  Some(if negative { -value } else { value })
}

///|
fn canonical_binary(text : String) -> String? {
  let chars = text_chars(text)
  let mut i = 0
  let mut sign = ""
  if i < chars.length() && (chars[i] == '-' || chars[i] == '+') {
    if chars[i] == '-' {
      sign = "-"
    }
    i += 1
  }
  let rest = String::from_array(chars[i:].to_owned())
  if rest == "nan" || rest == "NaN" || rest == "@NaN@" {
    return Some("nan")
  }
  if rest == "inf" || rest == "Inf" || rest == "@Inf@" {
    return Some(sign + "inf")
  }
  if i + 1 >= chars.length() || chars[i] != '0' || chars[i + 1] != 'x' {
    return None
  }
  i += 2
  let bits : Array[Char] = []
  let mut fraction_digits = 0
  let mut seen_point = false
  let mut digits = 0
  while i < chars.length() && chars[i] != 'p' && chars[i] != 'P' {
    if chars[i] == '.' {
      if seen_point {
        return None
      }
      seen_point = true
    } else {
      match hex_digit_value(chars[i]) {
        Some(v) => {
          bits.push(if (v & 8) != 0 { '1' } else { '0' })
          bits.push(if (v & 4) != 0 { '1' } else { '0' })
          bits.push(if (v & 2) != 0 { '1' } else { '0' })
          bits.push(if (v & 1) != 0 { '1' } else { '0' })
          digits += 1
          if seen_point {
            fraction_digits += 1
          }
        }
        None => return None
      }
    }
    i += 1
  }
  if digits == 0 {
    return None
  }
  let mut exponent = 0L
  if i < chars.length() {
    // the `p` of the binary exponent
    match parse_exponent(chars, i + 1) {
      Some(e) => exponent = e
      None => return None
    }
  }
  let mut first = 0
  while first < bits.length() && bits[first] == '0' {
    first += 1
  }
  if first == bits.length() {
    return Some(sign + "0")
  }
  let mut last = bits.length()
  while bits[last - 1] == '0' {
    last -= 1
  }
  let trailing_zero_bits = bits.length() - last
  exponent = exponent -
    (4 * fraction_digits).to_int64() +
    trailing_zero_bits.to_int64()
  Some(
    sign +
    "0b" +
    String::from_array(bits[first:last].to_owned()) +
    "p" +
    exponent.to_string(),
  )
}

///|
fn canonical_decimal(text : String) -> String? {
  let chars = text_chars(text)
  let mut i = 0
  let mut sign = ""
  if i < chars.length() && (chars[i] == '-' || chars[i] == '+') {
    if chars[i] == '-' {
      sign = "-"
    }
    i += 1
  }
  let rest = String::from_array(chars[i:].to_owned())
  if rest == "NaN" || rest == "nan" {
    return Some("NaN")
  }
  if rest == "Infinity" || rest == "Inf" || rest == "inf" {
    return Some(sign + "Infinity")
  }
  let digits : Array[Char] = []
  let mut fraction_digits = 0
  let mut seen_point = false
  while i < chars.length() && chars[i] != 'E' && chars[i] != 'e' {
    if chars[i] == '.' {
      if seen_point {
        return None
      }
      seen_point = true
    } else if is_decimal_digit(chars[i]) {
      digits.push(chars[i])
      if seen_point {
        fraction_digits += 1
      }
    } else {
      return None
    }
    i += 1
  }
  if digits.length() == 0 {
    return None
  }
  let mut exponent = 0L
  if i < chars.length() {
    match parse_exponent(chars, i + 1) {
      Some(e) => exponent = e
      None => return None
    }
  }
  let mut first = 0
  while first < digits.length() - 1 && digits[first] == '0' {
    first += 1
  }
  Some(
    sign +
    String::from_array(digits[first:].to_owned()) +
    "E" +
    (exponent - fraction_digits.to_int64()).to_string(),
  )
}

///|
// Oracle: level A (expected texts written out, for MPFR `%Ra` output and for
// the text the library prints).
// oracle: A
// source: expected texts written out, for the MPFR %Ra output and for the text of to_hex: 3/2 as 0b11p-1, -3/8 as
//   -0b11p-3, the sign of zero, specials, the exponent beyond Int32; the odd part
//   0b101111110010000111100100010000000000001110101100111p946 of 0x1.7e43c8800759cp+996 is 0x17e43c8800759c
//   shifted right by 2 bits with exponent 944+2, recomputed with Python integers in this review (51 bits, last
//   bit 1); the parser under test reads no library function
// shares: nothing
test "canonical binary text: the formats of MPFR and of to_hex agree on one value" {
  // 3/2: MPFR prints 0x1.8p+0, the library 0x3p-1
  assert_eq(canonical_binary("0x1.8p+0"), Some("0b11p-1"))
  assert_eq(canonical_binary("0x3p-1"), Some("0b11p-1"))
  assert_eq(canonical_binary("0x6p-2"), Some("0b11p-1"))
  assert_eq(canonical_binary("0x18p-4"), Some("0b11p-1"))
  // -3/8: MPFR prints -0x6p-4
  assert_eq(canonical_binary("-0x6p-4"), Some("-0b11p-3"))
  assert_eq(canonical_binary("-0x3p-3"), Some("-0b11p-3"))
  // the sign of zero is part of the text
  assert_eq(canonical_binary("0x0p+0"), Some("0"))
  assert_eq(canonical_binary("-0x0p+0"), Some("-0"))
  assert_eq(canonical_binary("-0x0p0"), Some("-0"))
  assert_eq(canonical_binary("0x0.000p+5"), Some("0"))
  // specials
  assert_eq(canonical_binary("nan"), Some("nan"))
  assert_eq(canonical_binary("-nan"), Some("nan"))
  assert_eq(canonical_binary("inf"), Some("inf"))
  assert_eq(canonical_binary("-inf"), Some("-inf"))
  // a power of two, and an exponent beyond Int32
  assert_eq(canonical_binary("0x1p+0"), Some("0b1p0"))
  assert_eq(canonical_binary("0x1p-1073741823"), Some("0b1p-1073741823"))
  assert_eq(canonical_binary("0x10p+1073741820"), Some("0b1p1073741824"))
  // 0x1.7e43c8800759cp+996 is the integer 0x17e43c8800759c times 2^944; its
  // last two bits are zero: odd part 0b1011...0111 (51 bits), exponent 946
  // (computed with Python integers, not with this code)
  assert_eq(
    canonical_binary("0x1.7e43c8800759cp+996"),
    Some("0b101111110010000111100100010000000000001110101100111p946"),
  )
  // a hex digit above 9 in either case
  assert_eq(canonical_binary("0xAb.Cp-2"), canonical_binary("0xab.cp-2"))
  // not a number
  assert_eq(canonical_binary(""), None)
  assert_eq(canonical_binary("0x"), None)
  assert_eq(canonical_binary("0x1.8.0p+0"), None)
  assert_eq(canonical_binary("0x1gp+0"), None)
  assert_eq(canonical_binary("0x1p"), None)
  assert_eq(canonical_binary("0x1p+x"), None)
  assert_eq(canonical_binary("1.5"), None)
}

///|
// Oracle: level A (expected texts written out, for libmpdec `mpd_to_sci`
// output and for the text of the library).
// oracle: A
// source: expected texts written out, for the libmpdec to-scientific text and the text of the library: the coefficient
//   digits are kept with trailing zeros (cohort) and the sign of zero is kept; the parser under test reads no
//   library function
// shares: nothing
test "canonical decimal text: one value, the cohort and the sign of zero are kept" {
  assert_eq(canonical_decimal("1.234E+5"), Some("1234E2"))
  assert_eq(canonical_decimal("123400"), Some("123400E0"))
  // trailing zeros are a different member of the cohort
  assert_eq(canonical_decimal("1.20"), Some("120E-2"))
  assert_eq(canonical_decimal("1.2"), Some("12E-1"))
  assert_eq(canonical_decimal("0.00"), Some("0E-2"))
  assert_eq(canonical_decimal("-0E-3"), Some("-0E-3"))
  assert_eq(canonical_decimal("0E-3"), Some("0E-3"))
  assert_eq(canonical_decimal("000123E1"), Some("123E1"))
  assert_eq(canonical_decimal("1E+999999"), Some("1E999999"))
  assert_eq(canonical_decimal("NaN"), Some("NaN"))
  assert_eq(canonical_decimal("-NaN"), Some("NaN"))
  assert_eq(canonical_decimal("Infinity"), Some("Infinity"))
  assert_eq(canonical_decimal("-Infinity"), Some("-Infinity"))
  assert_eq(canonical_decimal(""), None)
  assert_eq(canonical_decimal("1.2.3"), None)
  assert_eq(canonical_decimal("1x"), None)
  assert_eq(canonical_decimal("1E"), None)
  assert_eq(canonical_decimal("E5"), None)
}
