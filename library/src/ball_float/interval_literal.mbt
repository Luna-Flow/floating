///|
/// Interval literals, IEEE 1788-2015 9.7 and 12.11 (grammar of Tables 9.5 and 12.2), and the
/// constructor `textToInterval` of 12.12.7 and 13.2: `BallFloat::from_string` and
/// `BallFloatDecorated::from_string`.
///
/// The portable literals are, with case ignored and no whitespace except the optional
/// spaces and tabs the grammar allows inside the brackets:
/// - number literals: decimal `[sign] digits [. digits] [e integer]`, hexadecimal
///   `[sign] 0x hexdigits [. hexdigits] p integer`, rational `integer / positive-natural`,
///   and `inf` or `infinity` with an optional sign;
/// - inf-sup `[ l , u ]` where an omitted bound is infinite (`[,]` is Entire), the point
///   `[ m ]`, the special `[]`, `[empty]`, `[entire]`, and `[nai]`;
/// - uncertain `m ? r v e` with `m` a decimal literal without exponent, `r` empty (half an
///   ulp), a natural number of ulps, or `?` (unbounded), `v` empty, `u` or `d`, and `e` an
///   exponent field; no whitespace;
/// - decorated `bare_dec` with `dec` one of `trv`, `def`, `dac`, `com`.
///
/// The bounds are parsed exactly and rounded outward to the precision: the lower bound
/// down and the upper bound up, so the result is the hull of the value of the literal.

///|
/// The longest string (in characters) that is parsed. 12.11.5 allows an implementation to
/// "restrict support of some input strings (too long strings ...)", and then requires that
/// the constructor "shall always return a Level 2 interval (possibly Entire in this case)
/// that contains the Level 1 interval": a longer string gives Entire (decorated: `dac`, or
/// the `trv` or `def` the literal ends with).
pub let interval_literal_max_length : Int32 = 65536

///|
/// The largest exponent magnitude for which the exact comparison of two bounds of different
/// radices forms a power: beyond it the comparison is decided from the magnitudes when they
/// differ by a wide margin, and is otherwise undecided (12.12.7 case (b): the result then
/// contains both bounds).
let literal_exact_exponent_limit : Int64 = 65536L

///|
/// An exponent field is saturated at this magnitude: the value is then beyond every
/// representable range.
let literal_exponent_saturation : Int64 = 1000000000000000L

///|
priv enum NumLit {
  // an infinite bound, negative or not
  LInf(Bool)
  // negative, decimal digits of the significand (no point), exponent of ten
  LDec(Bool, String, Int64)
  // negative, hexadecimal digits of the significand (no point), exponent of two
  LHex(Bool, String, Int64)
  // negative, decimal digits of the numerator, decimal digits of the denominator
  LRat(Bool, String, String)
}

///|
priv enum LitForm {
  LEmpty
  LEntire
  LNai
  // the bounds of an inf-sup or uncertain literal; None is an omitted (infinite) bound
  LBounds(NumLit?, NumLit?)
}

///|
priv struct ParsedLiteral {
  form : LitForm
  decoration : Decoration?
}

///|
priv struct Cursor {
  chars : Array[Char]
  mut pos : Int32
}

///|
fn Cursor::at_end(self : Cursor) -> Bool {
  self.pos >= self.chars.length()
}

///|
fn Cursor::peek(self : Cursor) -> Char {
  if self.pos < self.chars.length() {
    self.chars[self.pos]
  } else {
    '\u{0}'
  }
}

///|
fn Cursor::peek_at(self : Cursor, offset : Int32) -> Char {
  let index = self.pos + offset
  if index < self.chars.length() {
    self.chars[index]
  } else {
    '\u{0}'
  }
}

///|
fn lit_lower(c : Char) -> Char {
  if c >= 'A' && c <= 'Z' {
    (c.to_int() + 32).unsafe_to_char()
  } else {
    c
  }
}

///|
fn lit_is_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
fn lit_is_hex_digit(c : Char) -> Bool {
  let l = lit_lower(c)
  lit_is_digit(l) || (l >= 'a' && l <= 'f')
}

///|
fn Cursor::skip_spaces(self : Cursor) -> Unit {
  while self.peek() == ' ' || self.peek() == '\t' {
    self.pos += 1
  }
}

///|
fn Cursor::peek_word(self : Cursor, word : String) -> Bool {
  let mut offset = 0
  for expected in word {
    if lit_lower(self.peek_at(offset)) != expected {
      return false
    }
    offset += 1
  }
  true
}

///|
fn lit_error(reason : String) -> @def.ArithmeticError {
  @def.ArithmeticError::parse_error("interval literal: " + reason)
}

///|
/// An integer literal: an optional sign and a nonempty sequence of decimal digits, as an
/// `Int64` saturated at the exponent limit.
fn Cursor::parse_integer(
  self : Cursor,
  what : String,
) -> Result[Int64, @def.ArithmeticError] {
  let mut negative = false
  if self.peek() == '+' || self.peek() == '-' {
    negative = self.peek() == '-'
    self.pos += 1
  }
  if !lit_is_digit(self.peek()) {
    return Err(
      lit_error(
        what +
        ": an integer literal is an optional sign and a nonempty sequence of decimal digits",
      ),
    )
  }
  let mut value : Int64 = 0L
  while lit_is_digit(self.peek()) {
    if value < literal_exponent_saturation {
      value = value * 10L + (self.peek().to_int() - 48).to_int64()
    }
    self.pos += 1
  }
  if value > literal_exponent_saturation {
    value = literal_exponent_saturation
  }
  Ok(if negative { -value } else { value })
}

///|
fn lit_strip_zeros(digits : String) -> String {
  let chars = digits.to_array()
  let mut start = 0
  while start < chars.length() && chars[start] == '0' {
    start += 1
  }
  if start == chars.length() {
    return "0"
  }
  digits[start:].to_owned()
}

///|
/// A number literal (9.7.2 and 12.11.2). `in_interval` marks that a sign or a bare
/// number is read as a bound.
fn Cursor::parse_number(self : Cursor) -> Result[NumLit, @def.ArithmeticError] {
  let mut negative = false
  if self.peek() == '+' || self.peek() == '-' {
    negative = self.peek() == '-'
    self.pos += 1
  }
  if self.peek_word("infinity") {
    self.pos += 8
    return Ok(LInf(negative))
  }
  if self.peek_word("inf") {
    self.pos += 3
    return Ok(LInf(negative))
  }
  if self.peek() == '0' && lit_lower(self.peek_at(1)) == 'x' {
    self.pos += 2
    let digits : Array[Char] = []
    let mut fraction = 0
    let mut seen_point = false
    let mut any = false
    while lit_is_hex_digit(self.peek()) || (self.peek() == '.' && !seen_point) {
      if self.peek() == '.' {
        seen_point = true
      } else {
        digits.push(lit_lower(self.peek()))
        any = true
        if seen_point {
          fraction += 1
        }
      }
      self.pos += 1
    }
    if !any {
      return Err(
        lit_error(
          "hexadecimal number literal: the significand needs at least one hexadecimal digit",
        ),
      )
    }
    if lit_lower(self.peek()) != 'p' {
      return Err(
        lit_error(
          "hexadecimal number literal: the exponent field p and an integer literal are required",
        ),
      )
    }
    self.pos += 1
    let exponent = match
      self.parse_integer("hexadecimal number literal exponent") {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    return Ok(
      LHex(
        negative,
        lit_strip_zeros(String::from_array(digits)),
        exponent - 4L * fraction.to_int64(),
      ),
    )
  }
  // decimal significand: digits* "." digits+ | digits+ "." | digits+
  let digits : Array[Char] = []
  let mut fraction = 0
  let mut seen_point = false
  let mut any = false
  while lit_is_digit(self.peek()) || (self.peek() == '.' && !seen_point) {
    if self.peek() == '.' {
      seen_point = true
    } else {
      digits.push(self.peek())
      any = true
      if seen_point {
        fraction += 1
      }
    }
    self.pos += 1
  }
  if !any {
    return Err(
      lit_error(
        "number literal: expected a decimal digit, 0x, inf or infinity (a significand needs at least one digit)",
      ),
    )
  }
  if self.peek() == '/' {
    if seen_point {
      return Err(
        lit_error(
          "rational literal: the numerator must be an integer literal (no point)",
        ),
      )
    }
    self.pos += 1
    let denominator_digits : Array[Char] = []
    while lit_is_digit(self.peek()) {
      denominator_digits.push(self.peek())
      self.pos += 1
    }
    let stripped = lit_strip_zeros(String::from_array(denominator_digits))
    if denominator_digits.length() == 0 || stripped == "0" {
      return Err(
        lit_error(
          "rational literal: the denominator must be a positive natural number",
        ),
      )
    }
    return Ok(
      LRat(negative, lit_strip_zeros(String::from_array(digits)), stripped),
    )
  }
  let mut exponent : Int64 = 0L
  if lit_lower(self.peek()) == 'e' {
    self.pos += 1
    exponent = match self.parse_integer("decimal number literal exponent") {
      Ok(value) => value
      Err(error) => return Err(error)
    }
  }
  Ok(
    LDec(
      negative,
      lit_strip_zeros(String::from_array(digits)),
      exponent - fraction.to_int64(),
    ),
  )
}

///|
fn lit_is_zero(n : NumLit) -> Bool {
  match n {
    LInf(_) => false
    LDec(_, digits, _) => digits == "0"
    LHex(_, digits, _) => digits == "0"
    LRat(_, numerator, _) => numerator == "0"
  }
}

///|
fn lit_negative(n : NumLit) -> Bool {
  match n {
    LInf(negative) => negative
    LDec(negative, _, _) => negative
    LHex(negative, _, _) => negative
    LRat(negative, _, _) => negative
  }
}

///|
fn lit_coeff(digits : String, radix : Int32) -> @bin_float.BinCoeff {
  match @bin_float.BinCoeff::parse(digits, radix~) {
    Ok(value) => value
    // the digits were validated by the cursor: a failure is a broken invariant
    Err(message) =>
      abort(
        "interval literal: the digits \{digits} (radix \{radix}) do not parse: \{message}",
      )
  }
}

///|
fn lit_inf(negative : Bool, precision : Int32) -> @bin_float.BinFloat {
  if negative {
    neg_inf(precision)
  } else {
    pos_inf(precision)
  }
}

///|
/// `RD` (`up = false`) or `RU` to `precision` bits of the exact value of `n`.
fn lit_round(n : NumLit, up : Bool, precision : Int32) -> @bin_float.BinFloat {
  let mode = if up {
    @bin_float.BinaryRoundingMode::RoundTowardPositive
  } else {
    @bin_float.BinaryRoundingMode::RoundTowardNegative
  }
  let context = @bin_float.BinaryContext::new(precision~, rounding=mode)
  match n {
    LInf(negative) => lit_inf(negative, precision)
    LDec(negative, digits, exponent) =>
      if digits == "0" {
        @bin_float.BinFloat::zero(precision~)
      } else {
        let text = (if negative { "-" } else { "" }) +
          digits +
          "e" +
          exponent.to_string()
        match @bin_float.BinFloat::from_string_ctx(text, context) {
          Ok((value, _)) => value
          // the text was built from validated digits and a saturated exponent: `from_string_ctx`
          // accepts every exponent (tested up to 10^15 and beyond), so a failure is a broken
          // invariant
          Err(error) =>
            abort(
              "interval literal: from_string_ctx rejected \{text}: \{error.message}",
            )
        }
      }
    LHex(negative, digits, exponent) =>
      if digits == "0" {
        @bin_float.BinFloat::zero(precision~)
      } else {
        // `from_hex_ctx` reads an exponent field of any length (it saturates, issue 597), so the
        // saturated exponent of the literal goes through as it is
        let text = (if negative { "-" } else { "" }) +
          "0x" +
          digits +
          "p" +
          exponent.to_string()
        match @bin_float.BinFloat::from_hex_ctx(text, context) {
          Ok((value, _)) => value
          Err(error) =>
            abort(
              "interval literal: from_hex_ctx rejected \{text}: \{error.message}",
            )
        }
      }
    LRat(negative, numerator, denominator) => {
      let num = lit_coeff(numerator, 10)
      if num.is_zero() {
        return @bin_float.BinFloat::zero(precision~)
      }
      let den = lit_coeff(denominator, 10)
      // the magnitude is rounded in the direction that gives the wanted side
      let magnitude_up = up != negative
      let scale = Int32::max(
        0,
        precision + 3 + den.bit_length() - num.bit_length(),
      )
      let (quotient, remainder) = coeff_div_rem(
        coeff_shift_left(num, scale),
        den,
      )
      let top = if magnitude_up && !remainder.is_zero() {
        coeff_increment(quotient)
      } else {
        quotient
      }
      let rounded = exact_make(top, -scale).with_precision(
        precision,
        if magnitude_up {
          @bin_float.BinaryRoundingMode::RoundTowardPositive
        } else {
          @bin_float.BinaryRoundingMode::RoundTowardNegative
        },
      )
      if negative {
        rounded.neg()
      } else {
        rounded
      }
    }
  }
}

///|
/// `value * radix^exponent` of a finite literal as a numerator and a denominator, if the
/// exponent is within the exact limit.
fn lit_exact(n : NumLit) -> (@bin_float.BinCoeff, @bin_float.BinCoeff)? {
  match n {
    LInf(_) => None
    LDec(_, digits, exponent) => {
      let mantissa = lit_coeff(digits, 10)
      if exponent > literal_exact_exponent_limit ||
        exponent < -literal_exact_exponent_limit {
        None
      } else if exponent >= 0L {
        Some(
          (
            coeff_mul(
              mantissa,
              coeff_pow_small(
                @bin_float.BinCoeff::from_uint64(10UL),
                exponent.to_int(),
              ),
            ),
            coeff_one(),
          ),
        )
      } else {
        Some(
          (
            mantissa,
            coeff_pow_small(
              @bin_float.BinCoeff::from_uint64(10UL),
              (-exponent).to_int(),
            ),
          ),
        )
      }
    }
    LHex(_, digits, exponent) => {
      let mantissa = lit_coeff(digits, 16)
      if exponent > literal_exact_exponent_limit ||
        exponent < -literal_exact_exponent_limit {
        None
      } else if exponent >= 0L {
        Some((coeff_shift_left(mantissa, exponent.to_int()), coeff_one()))
      } else {
        Some((mantissa, coeff_shift_left(coeff_one(), (-exponent).to_int())))
      }
    }
    LRat(_, numerator, denominator) =>
      Some((lit_coeff(numerator, 10), lit_coeff(denominator, 10)))
  }
}

///|
/// The order of the magnitudes `|a|` and `|b|` of two finite nonzero literals, exactly:
/// -1, 0, 1, or None if it cannot be decided within the exact limit.
fn lit_compare_magnitude(a : NumLit, b : NumLit) -> Int32? {
  // two decimal literals: compare the adjusted exponents, then the aligned digits
  match (a, b) {
    (LDec(_, da, ea), LDec(_, db, eb)) => {
      let (na, xa) = lit_trim_trailing(da, ea)
      let (nb, xb) = lit_trim_trailing(db, eb)
      let top_a = xa + na.length().to_int64()
      let top_b = xb + nb.length().to_int64()
      if top_a != top_b {
        return Some(if top_a < top_b { -1 } else { 1 })
      }
      let width = Int32::max(na.length(), nb.length())
      let left = na + String::make(width - na.length(), '0')
      let right = nb + String::make(width - nb.length(), '0')
      return Some(if left == right { 0 } else if left < right { -1 } else { 1 })
    }
    (LHex(_, da, ea), LHex(_, db, eb)) => {
      // two hexadecimal literals: compare the positions of the leading bits, then the
      // aligned coefficients (the shift is below the bit lengths, so it is small)
      let ma = lit_coeff(da, 16)
      let mb = lit_coeff(db, 16)
      let top_a = ea + ma.bit_length().to_int64()
      let top_b = eb + mb.bit_length().to_int64()
      if top_a != top_b {
        return Some(if top_a < top_b { -1 } else { 1 })
      }
      return Some(
        if ea >= eb {
          coeff_compare(coeff_shift_left(ma, (ea - eb).to_int()), mb)
        } else {
          coeff_compare(ma, coeff_shift_left(mb, (eb - ea).to_int()))
        },
      )
    }
    _ => ()
  }
  // a quick decision from roundings at 64 bits
  let low_a = lit_round(a, false, 64)
  let high_a = lit_round(a, true, 64)
  let low_b = lit_round(b, false, 64)
  let high_b = lit_round(b, true, 64)
  let negative_a = lit_negative(a)
  let negative_b = lit_negative(b)
  // roundings of the signed values: compare magnitudes through their absolute values
  let (mag_low_a, mag_high_a) = if negative_a {
    (high_a.neg(), low_a.neg())
  } else {
    (low_a, high_a)
  }
  let (mag_low_b, mag_high_b) = if negative_b {
    (high_b.neg(), low_b.neg())
  } else {
    (low_b, high_b)
  }
  if mag_high_a.compare(mag_low_b) < 0 {
    return Some(-1)
  }
  if mag_low_a.compare(mag_high_b) > 0 {
    return Some(1)
  }
  match (lit_exact(a), lit_exact(b)) {
    (Some((na, da)), Some((nb, db))) =>
      Some(coeff_compare(coeff_mul(na, db), coeff_mul(nb, da)))
    _ => None
  }
}

///|
/// A decimal significand without trailing zeros, with the exponent adjusted.
fn lit_trim_trailing(digits : String, exponent : Int64) -> (String, Int64) {
  let chars = digits.to_array()
  let mut end = chars.length()
  let mut shift = 0L
  while end > 1 && chars[end - 1] == '0' {
    end -= 1
    shift += 1L
  }
  (digits[:end].to_owned(), exponent + shift)
}

///|
/// The order of two literals of the same finite kind or infinite: -1, 0, 1, or None.
fn lit_compare(a : NumLit, b : NumLit) -> Int32? {
  let sign_of = fn(n : NumLit) -> Int32 {
    match n {
      LInf(negative) => if negative { -2 } else { 2 }
      _ => if lit_is_zero(n) { 0 } else if lit_negative(n) { -1 } else { 1 }
    }
  }
  let sa = sign_of(a)
  let sb = sign_of(b)
  if sa != sb {
    return Some(if sa < sb { -1 } else { 1 })
  }
  if sa == 0 || sa == 2 || sa == -2 {
    return Some(0)
  }
  match lit_compare_magnitude(a, b) {
    Some(order) => Some(if sa < 0 { -order } else { order })
    None => None
  }
}

///|
/// The uncertain form `m ? r v e`: the bounds `m - r ulp` and `m + r ulp` (9.7.4 b), the
/// ulp being 10 to the power of minus the number of digits after the point of `m`.
fn Cursor::parse_uncertain(
  self : Cursor,
) -> Result[LitForm, @def.ArithmeticError] {
  let mut negative = false
  if self.peek() == '+' || self.peek() == '-' {
    negative = self.peek() == '-'
    self.pos += 1
  }
  let digit_chars : Array[Char] = []
  let mut fraction = 0
  let mut seen_point = false
  while lit_is_digit(self.peek()) || (self.peek() == '.' && !seen_point) {
    if self.peek() == '.' {
      seen_point = true
    } else {
      digit_chars.push(self.peek())
      if seen_point {
        fraction += 1
      }
    }
    self.pos += 1
  }
  let digits = String::from_array(digit_chars)
  if digits == "" {
    return Err(
      lit_error(
        "uncertain form: the base point m needs at least one decimal digit",
      ),
    )
  }
  if self.peek() != '?' {
    return Err(
      lit_error(
        "uncertain form: the question mark must follow the base point m directly (no whitespace, one point at most)",
      ),
    )
  }
  self.pos += 1
  // the radius: empty (half an ulp), a natural number of ulps, or "?" (unbounded)
  let radius_chars : Array[Char] = []
  let mut unbounded = false
  if self.peek() == '?' {
    unbounded = true
    self.pos += 1
  } else {
    while lit_is_digit(self.peek()) {
      radius_chars.push(self.peek())
      self.pos += 1
    }
  }
  let radius = String::from_array(radius_chars)
  let mut direction = 'n'
  if lit_lower(self.peek()) == 'u' || lit_lower(self.peek()) == 'd' {
    direction = lit_lower(self.peek())
    self.pos += 1
  }
  let mut exponent : Int64 = 0L
  if lit_lower(self.peek()) == 'e' {
    self.pos += 1
    exponent = match self.parse_integer("uncertain form exponent") {
      Ok(value) => value
      Err(error) => return Err(error)
    }
  }
  // the scale of the integers below: ten to the power of exponent - fraction (- 1 for a
  // half ulp)
  let m = lit_coeff(digits, 10)
  let mut scale = exponent - fraction.to_int64()
  let (center, radius_value) = if unbounded {
    (m, coeff_one())
  } else if radius == "" {
    // half an ulp: 10 m +- 5 at one more digit
    scale = scale - 1L
    (
      coeff_mul(m, @bin_float.BinCoeff::from_uint64(10UL)),
      @bin_float.BinCoeff::from_uint64(5UL),
    )
  } else {
    (m, lit_coeff(radius, 10))
  }
  let center_literal = LDec(
    negative,
    lit_strip_zeros(center.to_string()),
    scale,
  )
  if unbounded {
    // m?? is Entire, m??u is [m, +inf] and m??d is [-inf, m]
    return Ok(
      match direction {
        'u' => LBounds(Some(center_literal), Some(LInf(false)))
        'd' => LBounds(Some(LInf(true)), Some(center_literal))
        _ => LEntire
      },
    )
  }
  // signed integers: lower = center - radius, upper = center + radius
  let signed_sum = fn(add_radius : Bool) -> NumLit {
    // value = (-1)^negative * center + (add_radius ? radius : -radius)
    let radius_negative = !add_radius
    if negative == radius_negative {
      LDec(
        negative,
        lit_strip_zeros(coeff_add(center, radius_value).to_string()),
        scale,
      )
    } else if coeff_compare(center, radius_value) >= 0 {
      LDec(
        negative,
        lit_strip_zeros(coeff_sub(center, radius_value).to_string()),
        scale,
      )
    } else {
      LDec(
        radius_negative,
        lit_strip_zeros(coeff_sub(radius_value, center).to_string()),
        scale,
      )
    }
  }
  let lower = if direction == 'u' { center_literal } else { signed_sum(false) }
  let upper = if direction == 'd' { center_literal } else { signed_sum(true) }
  Ok(LBounds(Some(lower), Some(upper)))
}

///|
fn Cursor::parse_bare(self : Cursor) -> Result[LitForm, @def.ArithmeticError] {
  if self.peek() != '[' {
    // the uncertain form: m ? ...; find the question mark in the first token
    let mut index = self.pos
    while index < self.chars.length() &&
          (
            lit_is_digit(self.chars[index]) ||
            self.chars[index] == '.' ||
            self.chars[index] == '+' ||
            self.chars[index] == '-'
          ) {
      index += 1
    }
    if index < self.chars.length() && self.chars[index] == '?' {
      return self.parse_uncertain()
    }
    return Err(
      lit_error(
        "a bare interval literal is an inf-sup form [l,u], a point [m], a special form [], [empty] or [entire], or an uncertain form m?r",
      ),
    )
  }
  self.pos += 1
  self.skip_spaces()
  if self.peek() == ']' {
    self.pos += 1
    return Ok(LEmpty)
  }
  if self.peek_word("empty") {
    let saved = self.pos
    self.pos += 5
    self.skip_spaces()
    if self.peek() == ']' {
      self.pos += 1
      return Ok(LEmpty)
    }
    self.pos = saved
  }
  if self.peek_word("entire") {
    let saved = self.pos
    self.pos += 6
    self.skip_spaces()
    if self.peek() == ']' {
      self.pos += 1
      return Ok(LEntire)
    }
    self.pos = saved
  }
  if self.peek_word("nai") {
    let saved = self.pos
    self.pos += 3
    self.skip_spaces()
    if self.peek() == ']' {
      self.pos += 1
      return Ok(LNai)
    }
    self.pos = saved
  }
  // inf-sup or point
  let mut lower : NumLit? = None
  if self.peek() != ',' {
    lower = match self.parse_number() {
      Ok(value) => Some(value)
      Err(error) => return Err(error)
    }
    self.skip_spaces()
  }
  if self.peek() == ']' {
    // a point [m]
    self.pos += 1
    return match lower {
      Some(m) => Ok(LBounds(Some(m), Some(m)))
      None =>
        Err(lit_error("point form: [] without a number is the empty interval"))
    }
  }
  if self.peek() != ',' {
    return Err(
      lit_error(
        "inf-sup form: expected a comma or a closing bracket after the lower bound (no whitespace is allowed inside a number literal)",
      ),
    )
  }
  self.pos += 1
  self.skip_spaces()
  let mut upper : NumLit? = None
  if self.peek() != ']' {
    upper = match self.parse_number() {
      Ok(value) => Some(value)
      Err(error) => return Err(error)
    }
    self.skip_spaces()
  }
  if self.peek() != ']' {
    return Err(
      lit_error(
        "inf-sup form: expected the closing bracket after the upper bound (one comma only, no whitespace inside a number literal)",
      ),
    )
  }
  self.pos += 1
  Ok(LBounds(lower, upper))
}

///|
/// A literal, bare or decorated: `bare`, `bare_dec`, or `[nai]`.
fn parse_interval_literal(
  text : String,
) -> Result[ParsedLiteral, @def.ArithmeticError] {
  let cursor : Cursor = { chars: text.to_array(), pos: 0, }
  let form = match cursor.parse_bare() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let mut decoration : Decoration? = None
  if !cursor.at_end() {
    if cursor.peek() != '_' {
      return Err(
        lit_error(
          "unexpected character after the interval (no whitespace or comment is allowed; a decoration is written _trv, _def, _dac or _com)",
        ),
      )
    }
    cursor.pos += 1
    if form is LNai {
      return Err(lit_error("[nai] takes no decoration"))
    }
    decoration = if cursor.peek_word("trv") {
      Some(Trv)
    } else if cursor.peek_word("def") {
      Some(Def)
    } else if cursor.peek_word("dac") {
      Some(Dac)
    } else if cursor.peek_word("com") {
      Some(Com)
    } else {
      None
    }
    if decoration is None {
      return Err(
        lit_error(
          "decoration literal: expected trv, def, dac or com after the underscore",
        ),
      )
    }
    cursor.pos += 3
    if !cursor.at_end() {
      return Err(
        lit_error("unexpected characters after the decoration literal"),
      )
    }
  }
  Ok({ form, decoration, })
}

///|
fn literal_precision_error(precision : Int32) -> @def.ArithmeticError? {
  match precision_error(precision) {
    Some(message) => Some(@def.ArithmeticError::domain_error(message))
    None => None
  }
}

///|
/// The bounds of a literal as a `BallFloat` at `precision`: lower down, upper up.
fn literal_bounds(
  lower : NumLit?,
  upper : NumLit?,
  precision : Int32,
) -> Result[BallFloat, @def.ArithmeticError] {
  if lower is Some(LInf(false)) {
    return Err(
      lit_error(
        "inf-sup form: the lower bound may not be +inf (l < +inf is required)",
      ),
    )
  }
  if upper is Some(LInf(true)) {
    return Err(
      lit_error(
        "inf-sup form: the upper bound may not be -inf (u > -inf is required)",
      ),
    )
  }
  // l <= u, decided exactly (12.12.7: no false negative); an undecided pair of finite
  // bounds (12.12.7 case (b)) gives an interval that contains both
  if lower is Some(l) && upper is Some(u) {
    match lit_compare(l, u) {
      Some(order) =>
        if order > 0 {
          return Err(
            lit_error(
              "inf-sup form: the lower bound is greater than the upper bound (l <= u is required)",
            ),
          )
        }
      None => {
        let low_l = lit_round(l, false, precision)
        let low_u = lit_round(u, false, precision)
        let high_l = lit_round(l, true, precision)
        let high_u = lit_round(u, true, precision)
        let low = if low_l.compare(low_u) <= 0 { low_l } else { low_u }
        let high = if high_l.compare(high_u) >= 0 { high_l } else { high_u }
        return BallFloat::try_from_bounds(low, high, precision~)
      }
    }
  }
  let lo_float = match lower {
    Some(n) => lit_round(n, false, precision)
    None => neg_inf(precision)
  }
  let hi_float = match upper {
    Some(n) => lit_round(n, true, precision)
    None => pos_inf(precision)
  }
  BallFloat::try_from_bounds(lo_float, hi_float, precision~)
}

///|
fn literal_level_one_bounded(form : LitForm) -> Bool {
  match form {
    LEmpty => true
    LEntire => false
    LNai => false
    LBounds(Some(LInf(_)), _) => false
    LBounds(_, Some(LInf(_))) => false
    LBounds(None, _) => false
    LBounds(_, None) => false
    LBounds(Some(_), Some(_)) => true
  }
}

///|
fn literal_interval(
  form : LitForm,
  precision : Int32,
) -> Result[BallFloat, @def.ArithmeticError] {
  match form {
    LEmpty => Ok(BallFloat::empty(precision~))
    LEntire => Ok(BallFloat::entire(precision~))
    LNai =>
      Err(
        lit_error(
          "[nai] is a decorated literal: use BallFloatDecorated::from_string",
        ),
      )
    LBounds(lower, upper) => literal_bounds(lower, upper, precision)
  }
}

///|
/// IEEE 1788-2015 `textToInterval` (12.12.7, 13.2) for a bare interval: the interval
/// literal `s`, as the hull of its value at `precision` bits (the lower bound rounded down
/// and the upper bound up; the bounds are parsed exactly, and `l <= u` is decided from the
/// exact values). The forms are listed at the top of this file. `Err` is the failed call of
/// the standard (the result Empty and the exception `UndefinedOperation`) and carries
/// the rule of the grammar or of 12.11 that the string breaks; a decoration or `[nai]` in
/// a bare literal is such a failure. A string longer than `interval_literal_max_length`
/// gives Entire, which contains its value (12.11.5). Only when two finite bounds of
/// different radices are equal in magnitude with an exponent beyond 65,536 does the
/// comparison stay undecided (case (b) of 12.12.7, `PossiblyUndefinedOperation`): then the
/// result contains both bounds.
pub fn BallFloat::from_string(
  s : String,
  precision~ : Int32 = 53,
) -> Result[BallFloat, @def.ArithmeticError] {
  match literal_precision_error(precision) {
    Some(error) => return Err(error)
    None => ()
  }
  if s.length() > interval_literal_max_length.to_int() {
    return Ok(BallFloat::entire(precision~))
  }
  let parsed = match parse_interval_literal(s) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if parsed.decoration is Some(_) {
    return Err(
      lit_error(
        "a bare interval literal has no decoration: use BallFloatDecorated::from_string",
      ),
    )
  }
  literal_interval(parsed.form, precision)
}

///|
/// The decoration a too-long literal ends with, else `Dac` (Entire is unbounded and
/// nonempty, so the decoration of a bare literal is `dac`).
fn literal_long_decoration(s : String) -> Decoration {
  let n = s.length()
  if n >= 4 {
    let tail = s[n - 4:n].to_owned().to_lower()
    if tail == "_trv" {
      return Trv
    }
    if tail == "_def" {
      return Def
    }
  }
  Dac
}

///|
/// IEEE 1788-2015 `textToInterval` for a decorated interval (12.12.7): `bare_dec` with the
/// decoration `trv`, `def`, `dac` or `com`, a bare literal (decorated by `newDec`), or
/// `[nai]`, which is `Ok(NaI)`. The call fails (`Err`, the standard's result NaI with the
/// exception `UndefinedOperation`) if the bare literal fails, if the decoration is not
/// permitted for the value (11.4: only `trv` for Empty, `com` only for a bounded interval)
/// or does not parse. A decoration `com` becomes `dac` if rounding made a bounded literal
/// unbounded (overflow), as 12.12.7 requires.
pub fn BallFloatDecorated::from_string(
  s : String,
  precision~ : Int32 = 53,
) -> Result[BallFloatDecorated, @def.ArithmeticError] {
  match literal_precision_error(precision) {
    Some(error) => return Err(error)
    None => ()
  }
  if s.length() > interval_literal_max_length.to_int() {
    return Ok(
      BallFloatDecorated::new(
        BallFloat::entire(precision~),
        decoration=literal_long_decoration(s),
      ),
    )
  }
  let parsed = match parse_interval_literal(s) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if parsed.form is LNai {
    return Ok(BallFloatDecorated::nai(precision~))
  }
  let interval = match literal_interval(parsed.form, precision) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  match parsed.decoration {
    None => Ok(BallFloatDecorated::new(interval, decoration=Com))
    Some(decoration) => {
      let empty = parsed.form is LEmpty
      if empty && decoration != Trv {
        return Err(
          lit_error(
            "decorated literal: the empty interval is only permitted with the decoration trv (11.4)",
          ),
        )
      }
      if decoration == Com && !literal_level_one_bounded(parsed.form) {
        return Err(
          lit_error(
            "decorated literal: the decoration com needs a bounded interval (11.4)",
          ),
        )
      }
      // com becomes dac if the bounded literal was rounded to an unbounded interval
      Ok(BallFloatDecorated::new(interval, decoration~))
    }
  }
}
