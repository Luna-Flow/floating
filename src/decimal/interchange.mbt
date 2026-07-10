///|
// Decimal interchange encoding helpers and public APIs.

fn decimal_interchange_total_bits(format : DecimalInterchangeFormat) -> Int {
  match format {
    Decimal32 => 32
    Decimal64 => 64
    Decimal128 => 128
  }
}

///|
fn decimal_interchange_hex_digits(format : DecimalInterchangeFormat) -> Int {
  decimal_interchange_total_bits(format) / 4
}

///|
fn decimal_interchange_precision(format : DecimalInterchangeFormat) -> Int {
  match format {
    Decimal32 => 7
    Decimal64 => 16
    Decimal128 => 34
  }
}

///|
fn decimal_interchange_bias(format : DecimalInterchangeFormat) -> Int {
  match format {
    Decimal32 => 101
    Decimal64 => 398
    Decimal128 => 6176
  }
}

///|
fn decimal_interchange_exponent_continuation_bits(
  format : DecimalInterchangeFormat,
) -> Int {
  match format {
    Decimal32 => 6
    Decimal64 => 8
    Decimal128 => 12
  }
}

///|
fn decimal_interchange_coefficient_bits(
  format : DecimalInterchangeFormat,
) -> Int {
  match format {
    Decimal32 => 20
    Decimal64 => 50
    Decimal128 => 110
  }
}

///|
fn decimal_interchange_payload_digits(format : DecimalInterchangeFormat) -> Int {
  decimal_interchange_precision(format) - 1
}

///|
fn decimal_interchange_mask(format : DecimalInterchangeFormat) -> BigInt {
  (bigint_one() << decimal_interchange_total_bits(format)) - bigint_one()
}

///|
fn decimal_interchange_sign_mask(format : DecimalInterchangeFormat) -> BigInt {
  bigint_one() << (decimal_interchange_total_bits(format) - 1)
}

///|
fn uppercase_ascii(src : String) -> String {
  let b = StringBuilder::new()
  for ch in src {
    if ch >= 'a' && ch <= 'f' {
      b.write_char(
        Int::unsafe_to_char(ch.to_int() + ('A'.to_int() - 'a'.to_int())),
      )
    } else {
      b.write_char(ch)
    }
  }
  b.to_string()
}

///|
fn normalize_interchange_hex(src : String, digits : Int) -> BigInt? {
  let trimmed = src.trim()
  let body = if trimmed.length() > 0 && trimmed[0] == '#' {
    trimmed[1:].to_owned()
  } else {
    trimmed.to_owned()
  }
  guard body.length() == digits else { return None }
  guard body.length() > 0 else { return None }
  for ch in body {
    guard ch.is_ascii_hexdigit() else { return None }
  }
  Some(BigInt::from_string(body, radix=16))
}

///|
fn interchange_hex_string(
  bits : BigInt,
  format : DecimalInterchangeFormat,
) -> String {
  let digits = decimal_interchange_hex_digits(format)
  let body = uppercase_ascii(bits.to_string(radix=16))
  let padded = if body.length() < digits {
    zeros(digits - body.length()) + body
  } else {
    body
  }
  "#" + padded
}

///|
pub fn DecimalInterchange::from_hex(
  src : String,
  format : DecimalInterchangeFormat,
) -> DecimalInterchange? {
  let digits = decimal_interchange_hex_digits(format)
  match normalize_interchange_hex(src, digits) {
    Some(bits) =>
      Some({
        format,
        bits: bits % (decimal_interchange_mask(format) + bigint_one()),
      })
    None => None
  }
}

///|
pub fn DecimalInterchange::from_decimal(
  value : Decimal,
  format : DecimalInterchangeFormat,
) -> (DecimalInterchange, DecimalFlags) {
  let (bits, flags) = value.to_interchange_hex(format)
  let interchange = DecimalInterchange::from_hex(bits, format).unwrap()
  (interchange, flags)
}

///|
pub fn DecimalInterchange::format(
  self : DecimalInterchange,
) -> DecimalInterchangeFormat {
  self.format
}

///|
pub fn DecimalInterchange::to_hex(self : DecimalInterchange) -> String {
  interchange_hex_string(self.bits, self.format)
}

///|
pub fn DecimalInterchange::to_decimal(self : DecimalInterchange) -> Decimal {
  Decimal::from_interchange_hex(self.to_hex(), self.format).unwrap()
}

///|
pub fn DecimalInterchange::to_decimal_ctx(
  self : DecimalInterchange,
) -> (Decimal, DecimalFlags) {
  let value = self.to_decimal()
  let flags = if value.is_subnormal(self.format.context()) {
    { ..DecimalFlags::new(), subnormal: true }
  } else {
    DecimalFlags::new()
  }
  (value, flags)
}

///|
pub fn DecimalInterchange::canonical(
  self : DecimalInterchange,
) -> DecimalInterchange {
  let (canonical_bits, _flags) = self
    .to_decimal()
    .to_interchange_hex(self.format)
  DecimalInterchange::from_hex(canonical_bits, self.format).unwrap()
}

///|
pub fn DecimalInterchange::is_canonical(self : DecimalInterchange) -> Bool {
  self.to_hex() == self.canonical().to_hex()
}

///|
pub fn DecimalInterchange::copy(
  self : DecimalInterchange,
) -> DecimalInterchange {
  self
}

///|
pub fn DecimalInterchange::copy_abs(
  self : DecimalInterchange,
) -> DecimalInterchange {
  {
    format: self.format,
    bits: self.bits &
    (
      decimal_interchange_mask(self.format) -
      decimal_interchange_sign_mask(self.format)
    ),
  }
}

///|
pub fn DecimalInterchange::copy_negate(
  self : DecimalInterchange,
) -> DecimalInterchange {
  {
    format: self.format,
    bits: self.bits ^ decimal_interchange_sign_mask(self.format),
  }
}

///|
pub fn DecimalInterchange::copy_sign(
  self : DecimalInterchange,
  other : DecimalInterchange,
) -> DecimalInterchange {
  guard self.format == other.format else {
    abort("DecimalInterchange::copy_sign requires matching formats")
  }
  let sign_mask = decimal_interchange_sign_mask(self.format)
  let magnitude = self.bits &
    (decimal_interchange_mask(self.format) - sign_mask)
  let sign = other.bits & sign_mask
  { format: self.format, bits: magnitude | sign }
}

///|
fn decimal_interchange_extract(bits : BigInt, shift : Int, width : Int) -> Int {
  if width <= 0 {
    0
  } else {
    ((bits >> shift) % (bigint_one() << width)).to_int()
  }
}

///|
fn decimal_interchange_coefficient_digits(
  value : Decimal,
  precision : Int,
) -> String {
  let digits = value.coefficient.to_string()
  if digits.length() >= precision {
    digits
  } else {
    zeros(precision - digits.length()) + digits
  }
}

///|
fn decimal_nan_payload_digits(payload : BigInt, digits : Int) -> String {
  let raw = abs_bigint(payload).to_string()
  let limited = if raw.length() > digits {
    raw[raw.length() - digits:].to_owned()
  } else {
    raw
  }
  if limited.length() >= digits {
    limited
  } else {
    zeros(digits - limited.length()) + limited
  }
}

///|
fn bit_from_bool(value : Bool) -> Int {
  if value {
    1
  } else {
    0
  }
}

///|
fn decimal_digit_triplet_to_dpd(lhs : Int, mid : Int, rhs : Int) -> Int {
  let a = (lhs & 0b1000) != 0
  let b = (lhs & 0b0100) != 0
  let c = (lhs & 0b0010) != 0
  let d = (lhs & 0b0001) != 0
  let e = (mid & 0b1000) != 0
  let f = (mid & 0b0100) != 0
  let g = (mid & 0b0010) != 0
  let h = (mid & 0b0001) != 0
  let i = (rhs & 0b1000) != 0
  let j = (rhs & 0b0100) != 0
  let k = (rhs & 0b0010) != 0
  let m = (rhs & 0b0001) != 0
  let p = bit_from_bool(b || (a && j) || (a && f && i))
  let q = bit_from_bool(c || (a && k) || (a && g && i))
  let r = bit_from_bool(d)
  let s = bit_from_bool((f && (!a || !i)) || (!a && e && j) || (e && i))
  let t = bit_from_bool(g || (!a && e && k) || (a && i))
  let u = bit_from_bool(h)
  let v = bit_from_bool(a || e || i)
  let w = bit_from_bool(a || (e && i) || (!e && j))
  let x = bit_from_bool(e || (a && i) || (!a && k))
  let y = bit_from_bool(m)
  let high = (((((((p << 1) | q) << 1) | r) << 1) | s) << 1) | t
  let upper = ((high << 1) | u) << 4
  upper | (v << 3) | (w << 2) | (x << 1) | y
}

///|
fn decimal_dpd_to_digit_triplet(code : Int) -> (Int, Int, Int) {
  let p = ((code >> 9) & 1) == 1
  let q = ((code >> 8) & 1) == 1
  let r = ((code >> 7) & 1) == 1
  let s = ((code >> 6) & 1) == 1
  let t = ((code >> 5) & 1) == 1
  let u = ((code >> 4) & 1) == 1
  let v = ((code >> 3) & 1) == 1
  let w = ((code >> 2) & 1) == 1
  let x = ((code >> 1) & 1) == 1
  let y = (code & 1) == 1
  let a = bit_from_bool((v && w) && (!s || t || !x))
  let b = bit_from_bool(p && (!v || !w || (s && !t && x)))
  let c = bit_from_bool(q && (!v || !w || (s && !t && x)))
  let d = bit_from_bool(r)
  let e = bit_from_bool(v && ((!w && x) || (!t && x) || (s && x)))
  let f = bit_from_bool((s && (!v || !x)) || (p && !s && t && v && w && x))
  let g = bit_from_bool((t && (!v || !x)) || (q && !s && t && w))
  let h = bit_from_bool(u)
  let i = bit_from_bool(v && ((!w && !x) || (w && x && (s || t))))
  let j = bit_from_bool(
    (!v && w) || (s && v && !w && x) || (p && w && (!x || (!s && !t))),
  )
  let k = bit_from_bool(
    (!v && x) || (t && !w && x) || (q && v && w && (!x || (!s && !t))),
  )
  let m = bit_from_bool(y)
  (
    (a << 3) | (b << 2) | (c << 1) | d,
    (e << 3) | (f << 2) | (g << 1) | h,
    (i << 3) | (j << 2) | (k << 1) | m,
  )
}

///|
fn decimal_interchange_digits_to_coefficient_bits(digits : String) -> BigInt {
  guard digits.length() % 3 == 0 else {
    abort(
      "interchange coefficient continuation requires groups of three digits",
    )
  }
  let mut bits = bigint_zero()
  let groups = digits.length() / 3
  for index in 0..<groups {
    let base = index * 3
    let lhs = digits[base].to_int() - '0'.to_int()
    let mid = digits[base + 1].to_int() - '0'.to_int()
    let rhs = digits[base + 2].to_int() - '0'.to_int()
    let dpd = decimal_digit_triplet_to_dpd(lhs, mid, rhs)
    bits = (bits << 10) + BigInt::from_int(dpd)
  }
  bits
}

///|
fn decimal_interchange_coefficient_bits_to_digits(
  bits : BigInt,
  groups : Int,
) -> String {
  let b = StringBuilder::new()
  for index in 0..<groups {
    let shift = (groups - index - 1) * 10
    let code = decimal_interchange_extract(bits, shift, 10)
    let (lhs, mid, rhs) = decimal_dpd_to_digit_triplet(code)
    b.write_char(Int::unsafe_to_char('0'.to_int() + lhs))
    b.write_char(Int::unsafe_to_char('0'.to_int() + mid))
    b.write_char(Int::unsafe_to_char('0'.to_int() + rhs))
  }
  b.to_string()
}

///|

///|
pub fn Decimal::from_interchange_hex(
  src : String,
  format : DecimalInterchangeFormat,
) -> Decimal? {
  let total_bits = decimal_interchange_total_bits(format)
  let exp_bits = decimal_interchange_exponent_continuation_bits(format)
  let coeff_bits = decimal_interchange_coefficient_bits(format)
  let precision = decimal_interchange_precision(format)
  let bias = decimal_interchange_bias(format)
  let bits = match
    normalize_interchange_hex(src, decimal_interchange_hex_digits(format)) {
    Some(bits) => bits
    None => return None
  }
  let sign = decimal_interchange_extract(bits, total_bits - 1, 1) == 1
  let combination = decimal_interchange_extract(bits, coeff_bits + exp_bits, 5)
  let coefficient_bits = bits % (bigint_one() << coeff_bits)
  if combination == 0b11110 {
    return Some(
      Decimal::inf(
        if sign {
          Sign::Negative
        } else {
          Sign::Positive
        },
        precision~,
      ),
    )
  }
  if combination == 0b11111 {
    let payload_digits = decimal_interchange_coefficient_bits_to_digits(
      coefficient_bits,
      coeff_bits / 10,
    )
    let payload = BigInt::from_string(payload_digits)
    let signaling = decimal_interchange_extract(
        bits,
        coeff_bits + exp_bits - 1,
        1,
      ) ==
      1
    return Some(
      if signaling {
        Decimal::signaling_nan(payload~, negative=sign, precision~)
      } else {
        Decimal::quiet_nan(payload~, negative=sign, precision~)
      },
    )
  }
  let (exp_msb, msd) = if (combination & 0b11000) == 0b11000 {
    ((combination >> 1) & 0b11, 8 + (combination & 1))
  } else {
    ((combination >> 3) & 0b11, combination & 0b111)
  }
  let exponent_continuation = decimal_interchange_extract(
    bits, coeff_bits, exp_bits,
  )
  let exponent = ((exp_msb << exp_bits) | exponent_continuation) - bias
  let continuation_digits = decimal_interchange_coefficient_bits_to_digits(
    coefficient_bits,
    coeff_bits / 10,
  )
  let coefficient_digits = msd.to_string() + continuation_digits
  let coefficient = BigInt::from_string(coefficient_digits)
  Some(finite_with_exponent(sign, coefficient, exponent, precision))
}

///|
pub fn Decimal::to_interchange_hex(
  self : Decimal,
  format : DecimalInterchangeFormat,
) -> (String, DecimalFlags) {
  let ctx = format.context()
  let precision = decimal_interchange_precision(format)
  let total_bits = decimal_interchange_total_bits(format)
  let exp_bits = decimal_interchange_exponent_continuation_bits(format)
  let coeff_bits = decimal_interchange_coefficient_bits(format)
  let bias = decimal_interchange_bias(format)
  let sign_shift = total_bits - 1
  let special_prefix_shift = coeff_bits + exp_bits
  let (applied, flags) = match self.class {
    FpClass::Finite => self.apply_ctx(ctx)
    FpClass::Infinity | FpClass::NaN => (self, DecimalFlags::new())
  }
  let sign_bit = if applied.negative { bigint_one() } else { bigint_zero() }
  let bits = match applied.class {
    FpClass::Infinity =>
      (sign_bit << sign_shift) +
      (BigInt::from_int(0b11110) << special_prefix_shift)
    FpClass::NaN => {
      let payload_digits = decimal_nan_payload_digits(
        applied.nan_payload(),
        decimal_interchange_payload_digits(format),
      )
      let payload_bits = decimal_interchange_digits_to_coefficient_bits(
        payload_digits,
      )
      let signal_head = if applied.signaling_nan { 1 } else { 0 }
      let exponent_head = BigInt::from_int(signal_head) << (exp_bits - 1)
      (sign_bit << sign_shift) +
      (BigInt::from_int(0b11111) << special_prefix_shift) +
      (exponent_head << coeff_bits) +
      payload_bits
    }
    FpClass::Finite => {
      let digits = decimal_interchange_coefficient_digits(applied, precision)
      let msd = digits[0].to_int() - '0'.to_int()
      let continuation = digits[1:].to_owned()
      let exponent = applied.exponent10 + bias
      let exp_msb = exponent >> exp_bits
      let exp_continuation = exponent % (1 << exp_bits)
      let combination = if msd >= 8 {
        0b11000 | (exp_msb << 1) | (msd - 8)
      } else {
        (exp_msb << 3) | msd
      }
      let coefficient_bits = decimal_interchange_digits_to_coefficient_bits(
        continuation,
      )
      (sign_bit << sign_shift) +
      (BigInt::from_int(combination) << special_prefix_shift) +
      (BigInt::from_int(exp_continuation) << coeff_bits) +
      coefficient_bits
    }
  }
  (interchange_hex_string(bits, format), flags)
}

///|
