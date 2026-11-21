// Text output of intervals (IEEE 1788-2015 13.3 `intervalToText` and 13.4 `intervalToExact`,
// `exactToInterval`).
//
// Three renderings, by what they promise:
// - `Show` (and `to_string`): the portable inf-sup literal `[l, u]` (`[l, u]_dec` for a
//   decorated interval). Each decimal bound is rounded outward, so the text is a literal of an
//   interval containing the value (13.3), and it reads back at the same precision with at most
//   one unit in the last place of widening at each end.
// - `to_exact_string`: hexadecimal bounds, which are exact (13.4); `from_exact_string` recovers
//   the datum (`identical`).
// - `to_ball_string`: the midpoint-radius view `m +/- r`; it is not a literal.

///|
/// A bound whose leading bit is beyond this magnitude is written in hexadecimal by `Show`:
/// its decimal expansion needs a power of ten of that size, which costs more than the text is
/// worth (the library's exponent range reaches 2^30).
let interval_text_decimal_exponent_limit : Int32 = 4096

///|
fn text_ctx(
  precision : Int32,
  rounding : @bin_float.BinaryRoundingMode,
) -> @bin_float.BinaryContext {
  @bin_float.BinaryContext::new(precision~, rounding~)
}

///|
/// `d.ddde+x` without trailing zeros of the mantissa and without `e+0`.
fn tidy_scientific(text : String) -> String {
  let at = match text.find("e") {
    Some(index) => index
    None => return text
  }
  let mut mantissa = text[0:at].to_owned()
  let exponent = text[at + 1:].to_owned()
  if mantissa.contains(".") {
    let mut end = mantissa.length()
    while end > 1 && mantissa.unsafe_get(end - 1) == '0' {
      end -= 1
    }
    if end > 1 && mantissa.unsafe_get(end - 1) == '.' {
      end -= 1
    }
    mantissa = mantissa[0:end].to_owned()
  }
  if exponent == "+0" || exponent == "-0" {
    mantissa
  } else {
    mantissa + "e" + exponent
  }
}

///|
/// Whether the `digits`-digit decimal rounded in the outward direction, read back at
/// `precision` in the same direction, is at most one unit in the last place from `x`.
fn endpoint_close_enough(
  x : @bin_float.BinFloat,
  digits : Int32,
  upward : Bool,
  precision : Int32,
) -> (String, Bool) {
  let direction = if upward {
    @bin_float.BinaryRoundingMode::RoundTowardPositive
  } else {
    @bin_float.BinaryRoundingMode::RoundTowardNegative
  }
  let context = text_ctx(precision, direction)
  let (text, _) = x.to_decimal_string_ctx(digits, context)
  match @bin_float.BinFloat::from_string_ctx(text, context) {
    Ok((r, _)) => {
      let near = if upward {
        r.compare(x) == 0 || r.next_down_ctx(context).0.compare(x) <= 0
      } else {
        r.compare(x) == 0 || r.next_up_ctx(context).0.compare(x) >= 0
      }
      (text, near)
    }
    Err(_) => (text, false)
  }
}

///|
/// The text of one finite or infinite bound: `upward` says whether the bound is an upper one
/// (rounded up) or a lower one (rounded down). The fewest significant digits that keep the
/// text within one unit in the last place of the bound are used (found by bisection: the
/// distance does not grow with the digit count).
fn endpoint_text(
  x : @bin_float.BinFloat,
  upward : Bool,
  precision : Int32,
) -> String {
  if x.is_infinite() {
    return if x.is_negative() { "-inf" } else { "inf" }
  }
  if x.is_zero() {
    return "0"
  }
  let top = match x.ilogb() {
    Some(value) => value
    None => 0
  }
  if top.abs() > interval_text_decimal_exponent_limit {
    return exact_bound_text(x)
  }
  let mut low : Int32 = 1
  let mut high : Int32 = (precision.to_double() * 0.30102999566398120)
    .ceil()
    .to_int() +
    3
  let mut best = endpoint_close_enough(x, high, upward, precision).0
  while low < high {
    let middle = (low + high) / 2
    let (text, near) = endpoint_close_enough(x, middle, upward, precision)
    if near {
      best = text
      high = middle
    } else {
      low = middle + 1
    }
  }
  tidy_scientific(best)
}

///|
/// The inf-sup literal of an interval: `[empty]`, `[entire]` or `[l, u]` with bounds rounded
/// outward (13.3). `from_string(text, precision=self.precision())` contains the interval.
fn interval_portable_text(x : BallFloat) -> String {
  if x.is_empty() {
    "[empty]"
  } else if x.is_entire() {
    "[entire]"
  } else {
    let p = x.precision()
    "[" +
    endpoint_text(x.lo_, false, p) +
    ", " +
    endpoint_text(x.hi_, true, p) +
    "]"
  }
}

///|
fn exact_bound_text(x : @bin_float.BinFloat) -> String {
  if x.is_infinite() {
    return if x.is_negative() { "-inf" } else { "inf" }
  }
  // A zero bound is written without a sign (13.4: no signed zero): the observers return -0 for
  // a zero lower bound (12.12.8), and the text of [0, 1] is [0x0p0, 0x1p0], like the literal.
  if x.is_zero() {
    return "0x0p0"
  }
  // The stored coefficient of a nonzero finite `BinFloat` is odd, so the text is the value's
  // and does not depend on how it was made: every constructor and operation builds the value
  // through `normalize_finite` (bin_float.mbt), which strips the trailing zero bits into the
  // exponent (`normalize_finite_odd`, the `final_shift` step). The test "the stored coefficient
  // is odd" in interval_text_wbtest.mbt guards the invariant.
  (if x.is_negative() { "-" } else { "" }) +
  "0x" +
  x.coefficient().to_radix_string(16) +
  "p" +
  x.exponent2().to_string()
}

///|
/// `[empty]`, `[entire]` or `[l, u]` with hexadecimal bounds that are the bounds themselves
/// (an infinite bound is `inf` or `-inf`): IEEE 1788-2015 13.4 `intervalToExact`.
/// `from_exact_string` gives back an identical interval when it is told the precision.
pub fn BallFloat::to_exact_string(self : BallFloat) -> String {
  if self.is_empty() {
    "[empty]"
  } else if self.is_entire() {
    "[entire]"
  } else {
    "[" + exact_bound_text(self.lo_) + ", " + exact_bound_text(self.hi_) + "]"
  }
}

///|
/// The midpoint-radius view `m +/- r` (an interval with an infinite bound is shown as
/// `[l, u]` of binary numbers, an empty one as `[empty]`). It is for reading, not a literal
/// of the standard: use `to_string` or `to_exact_string` for text that can be parsed back.
/// Both numbers are written as `BinFloat::to_string` writes them, so the cost does not depend
/// on the exponent range (an interval whose bounds have exponents a billion apart is written
/// in a few characters).
pub fn BallFloat::to_ball_string(self : BallFloat) -> String {
  if self.is_empty() {
    "[empty]"
  } else if self.is_common_interval() {
    self.center().to_string() + " +/- " + self.half_width().to_string()
  } else {
    "[" + self.lo_.to_string() + ", " + self.hi_.to_string() + "]"
  }
}

///|
/// The two bound strings of an exact text, or the reason it is not one: `[l, u]` with each
/// bound `inf`, `-inf`, `+inf` or a hexadecimal number (a decimal bound is refused, because
/// reading it would round). `[empty]` and `[entire]` are the other two forms.
fn exact_text_bounds(
  s : String,
) -> Result[(String, String)?, @def.ArithmeticError] {
  let body = s.trim().to_owned()
  let lowered = body.to_lower()
  if lowered == "[empty]" || lowered == "[entire]" {
    return Ok(None)
  }
  if !body.has_prefix("[") || !body.has_suffix("]") {
    return Err(lit_error("an exact text is [l, u], [empty] or [entire]"))
  }
  let inner = body[1:body.length() - 1].to_owned()
  let parts = inner.split(",").map(fn(p) { p.to_owned() }).collect()
  if parts.length() != 2 {
    return Err(lit_error("an exact text has two bounds"))
  }
  let bounds = []
  for part in parts {
    let bound = part.trim().to_owned()
    let lower = bound.to_lower()
    let magnitude = if lower.has_prefix("-") || lower.has_prefix("+") {
      lower[1:].to_owned()
    } else {
      lower
    }
    if !(magnitude.has_prefix("0x") ||
      magnitude == "inf" ||
      magnitude == "infinity") {
      return Err(
        lit_error(
          "an exact text has hexadecimal bounds, `" + bound + "` is not",
        ),
      )
    }
    bounds.push(bound)
  }
  Ok(Some((bounds[0], bounds[1])))
}

///|
/// The number of hexadecimal digits of the mantissa of a hexadecimal bound text (the point is
/// not a digit): four times it is at least the bit count of the number. It only sizes the
/// context of the reader; it does not decide exactness.
fn hex_mantissa_digits(text : String) -> Int32 {
  let lower = text.to_lower()
  let mut count = 0
  let mut seen_x = false
  for c in lower {
    if !seen_x {
      if c == 'x' {
        seen_x = true
      }
    } else if c == 'p' {
      break
    } else if c != '.' {
      count += 1
    }
  }
  count
}

///|
/// One bound of an exact text, read exactly: the converter of IEEE 754-2019 5.12.3
/// (`BinFloat::from_hex_ctx`) in a context wide enough for the digits of the text and for the
/// precision of the interval, so that it rounds only when the bound cannot be represented
/// at all, and then reports `inexact` (the test of the reader, not a count of digits). The
/// bound keeps its own bit count, whatever the precision of the interval: 13.4 asks for the
/// datum back, and the type has intervals with ends of more bits than the precision (an end
/// of `new` or `cancel_minus` kept unrounded). A bound is refused when it is beyond the
/// exponent range of the library (overflow or underflow in the reader), or finer than the
/// grid of the larger of its own bit count and the precision below the range floor, which no
/// stored bound is.
fn exact_bound(
  text : String,
  precision : Int32,
) -> Result[@bin_float.BinFloat, @def.ArithmeticError] {
  let wide = Int64::max(
    precision.to_int64(),
    4L * hex_mantissa_digits(text).to_int64(),
  )
  if wide > @bin_float.binary_precision_max.to_int64() {
    return Err(
      lit_error("the bound `" + text + "` has more bits than the library holds"),
    )
  }
  match
    @bin_float.BinFloat::from_hex_ctx(
      text,
      @bin_float.BinaryContext::new(precision=wide.to_int()),
    ) {
    Err(error) => Err(error)
    Ok((value, flags)) =>
      if flags.inexact() {
        Err(
          lit_error(
            "the bound `" +
            text +
            "` is beyond the exponent range of the library",
          ),
        )
      } else if value.is_zero() ||
        value.is_infinite() ||
        value.exponent2() >=
        @bin_float.binary_implementation_e_min -
        Int32::max(precision, value.coefficient().bit_length()) +
        1 {
        // A bound with more bits than the precision keeps the label of its own bit count (the
        // type comment of `BallFloat`), whatever the context of the reader was: an exact
        // relabel, so the label does not depend on how many zero digits the text has.
        let bits = value.coefficient().bit_length()
        if !value.is_zero() && !value.is_infinite() && bits > precision {
          Ok(
            value.with_precision(
              bits,
              @bin_float.BinaryRoundingMode::RoundTiesToEven,
            ),
          )
        } else {
          Ok(value)
        }
      } else {
        Err(
          lit_error(
            "the bound `" +
            text +
            "` is finer than the grid below the range floor",
          ),
        )
      }
  }
}

///|
/// IEEE 1788-2015 13.4 `exactToInterval`: the interval of an exact text, read exactly and
/// never widened. `precision` is the precision of the interval, not a limit on the bounds: a
/// bound with more bits than `precision` is kept as it is, as the type keeps such ends (an end
/// of `new` or of `cancel_minus` that is not rounded), so `from_exact_string(x.to_exact_string(),
/// precision=x.precision())` is `identical` to `x` for every interval of the type. The call is
/// refused (a parse error naming the reason) only for what cannot be an interval of the
/// library: a decimal or malformed bound, a bound beyond the exponent range, a lower bound
/// above the upper one. A point after the digits, leading and trailing zero digits and upper
/// case are read.
pub fn BallFloat::from_exact_string(
  s : String,
  precision~ : Int32 = 53,
) -> Result[BallFloat, @def.ArithmeticError] {
  match literal_precision_error(precision) {
    Some(error) => return Err(error)
    None => ()
  }
  match exact_text_bounds(s) {
    Err(error) => Err(error)
    Ok(None) =>
      if s.trim().to_owned().to_lower() == "[empty]" {
        Ok(BallFloat::empty(precision~))
      } else {
        Ok(BallFloat::entire(precision~))
      }
    Ok(Some((lower_text, upper_text))) =>
      match exact_bound(lower_text, precision) {
        Err(error) => Err(error)
        Ok(lower) =>
          match exact_bound(upper_text, precision) {
            Err(error) => Err(error)
            Ok(upper) =>
              match interval_validation_error(lower, upper) {
                Some(reason) =>
                  Err(lit_error("an exact text is not an interval: " + reason))
                None => Ok(store_interval(lower, upper, precision))
              }
          }
      }
  }
}

///|
/// The decorated exact text: `[nai]`, or the exact text of the interval, `_`, and the
/// decoration.
pub fn BallFloatDecorated::to_exact_string(self : BallFloatDecorated) -> String {
  if self.is_nai() {
    "[nai]"
  } else {
    self.interval_.to_exact_string() + "_" + self.decoration_.to_string()
  }
}

///|
/// `exactToInterval` for a decorated interval: `[nai]` or an exact text followed by `_` and a
/// decoration (`trv`, `def`, `dac`, `com`); see `BallFloat::from_exact_string`.
pub fn BallFloatDecorated::from_exact_string(
  s : String,
  precision~ : Int32 = 53,
) -> Result[BallFloatDecorated, @def.ArithmeticError] {
  let body = s.trim().to_owned()
  if body.to_lower() == "[nai]" {
    return Ok(BallFloatDecorated::nai(precision~))
  }
  let cut = match body.rev_find("_") {
    Some(index) => index
    None =>
      return Err(
        lit_error("an exact decorated text ends with _trv, _def, _dac or _com"),
      )
  }
  let interval_text = body[0:cut].to_owned()
  let decoration = match body[cut + 1:].to_owned().to_lower() {
    "trv" => Trv
    "def" => Def
    "dac" => Dac
    "com" => Com
    other => return Err(lit_error("unknown decoration `" + other + "`"))
  }
  match BallFloat::from_exact_string(interval_text, precision~) {
    Err(error) => Err(error)
    Ok(interval) => {
      let result = BallFloatDecorated::new(interval, decoration~)
      if result.decoration() == decoration {
        Ok(result)
      } else {
        Err(
          lit_error(
            "the decoration `" +
            decoration.to_string() +
            "` does not fit the interval",
          ),
        )
      }
    }
  }
}
