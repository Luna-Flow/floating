///|
struct LegacyBigIntBinFloat {
  class_ : FpClass
  significand_ : BigInt
  exponent2_ : Int
  precision_ : Int
  negative_zero_ : Bool
  nan_negative_ : Bool
  signaling_nan_ : Bool
  nan_payload_ : BigInt
}

///|
fn legacy_bin_zero() -> BigInt {
  BigInt::from_int(0)
}

///|
fn legacy_bin_one() -> BigInt {
  BigInt::from_int(1)
}

///|
fn legacy_bin_abs(value : BigInt) -> BigInt {
  if value < legacy_bin_zero() {
    -value
  } else {
    value
  }
}

///|
fn legacy_bin_remove_factor2(
  significand : BigInt,
  exponent2 : Int,
) -> (BigInt, Int) {
  if significand.is_zero() {
    (legacy_bin_zero(), 0)
  } else {
    let shift = legacy_bin_abs(significand).ctz()
    (significand >> shift, exponent2 + shift)
  }
}

///|
fn legacy_bin_should_increment(
  quotient : BigInt,
  remainder : BigInt,
  divisor : BigInt,
  negative : Bool,
  mode : RoundingMode,
) -> Bool {
  if remainder.is_zero() {
    return false
  }
  match mode {
    RoundingMode::TowardZero => false
    RoundingMode::TowardPositive => !negative
    RoundingMode::TowardNegative => negative
    RoundingMode::AwayFromZero => true
    RoundingMode::ToNearestEven => {
      let comparison = (remainder << 1).compare(divisor)
      comparison > 0 ||
      (comparison == 0 && !(quotient % BigInt::from_int(2)).is_zero())
    }
  }
}

///|
fn legacy_bin_round_shift(
  magnitude : BigInt,
  shift : Int,
  negative : Bool,
  mode : RoundingMode,
) -> BigInt {
  if shift <= 0 {
    return magnitude
  }
  let quotient = magnitude >> shift
  let remainder = magnitude - (quotient << shift)
  let divisor = legacy_bin_one() << shift
  if legacy_bin_should_increment(quotient, remainder, divisor, negative, mode) {
    quotient + legacy_bin_one()
  } else {
    quotient
  }
}

///|
fn legacy_bin_round_positive_div(
  numerator : BigInt,
  denominator : BigInt,
  negative : Bool,
  mode : RoundingMode,
) -> BigInt {
  let quotient = numerator / denominator
  let remainder = numerator % denominator
  if legacy_bin_should_increment(
      quotient, remainder, denominator, negative, mode,
    ) {
    quotient + legacy_bin_one()
  } else {
    quotient
  }
}

///|
fn legacy_bin_ratio_floor_log2(numerator : BigInt, denominator : BigInt) -> Int {
  let bit_difference = numerator.bit_length() - denominator.bit_length()
  let below_candidate = if bit_difference >= 0 {
    numerator < denominator << bit_difference
  } else {
    numerator << -bit_difference < denominator
  }
  if below_candidate {
    bit_difference - 1
  } else {
    bit_difference
  }
}

///|
fn LegacyBigIntBinFloat::make(
  significand : BigInt,
  exponent2 : Int,
  precision : Int,
  negative_zero? : Bool = false,
  mode? : RoundingMode = RoundingMode::ToNearestEven,
) -> LegacyBigIntBinFloat {
  let precision = Int::max(1, precision)
  if significand.is_zero() {
    return {
      class_: FpClass::Finite,
      significand_: legacy_bin_zero(),
      exponent2_: 0,
      precision_: precision,
      negative_zero_: negative_zero,
      nan_negative_: false,
      signaling_nan_: false,
      nan_payload_: legacy_bin_zero(),
    }
  }
  let (significand0, exponent0) = legacy_bin_remove_factor2(
    significand, exponent2,
  )
  let negative = significand0 < legacy_bin_zero()
  let magnitude0 = legacy_bin_abs(significand0)
  let bits = magnitude0.bit_length()
  let (magnitude1, exponent1) = if bits > precision {
    let shift = bits - precision
    (
      legacy_bin_round_shift(magnitude0, shift, negative, mode),
      exponent0 + shift,
    )
  } else {
    (magnitude0, exponent0)
  }
  let significand1 = if negative { -magnitude1 } else { magnitude1 }
  let (significand2, exponent2) = legacy_bin_remove_factor2(
    significand1, exponent1,
  )
  {
    class_: FpClass::Finite,
    significand_: significand2,
    exponent2_: exponent2,
    precision_: precision,
    negative_zero_: false,
    nan_negative_: false,
    signaling_nan_: false,
    nan_payload_: legacy_bin_zero(),
  }
}

///|
fn LegacyBigIntBinFloat::zero(
  precision? : Int = 53,
  negative? : Bool = false,
) -> LegacyBigIntBinFloat {
  LegacyBigIntBinFloat::make(
    legacy_bin_zero(),
    0,
    precision,
    negative_zero=negative,
  )
}

///|
fn LegacyBigIntBinFloat::inf(
  negative : Bool,
  precision? : Int = 53,
) -> LegacyBigIntBinFloat {
  {
    class_: FpClass::Infinity,
    significand_: if negative {
      -legacy_bin_one()
    } else {
      legacy_bin_one()
    },
    exponent2_: 0,
    precision_: Int::max(1, precision),
    negative_zero_: false,
    nan_negative_: false,
    signaling_nan_: false,
    nan_payload_: legacy_bin_zero(),
  }
}

///|
fn LegacyBigIntBinFloat::nan(
  precision? : Int = 53,
  negative? : Bool = false,
  signaling? : Bool = false,
  payload? : BigInt = legacy_bin_zero(),
) -> LegacyBigIntBinFloat {
  let payload = legacy_bin_abs(payload)
  {
    class_: FpClass::NaN,
    significand_: legacy_bin_zero(),
    exponent2_: 0,
    precision_: Int::max(1, precision),
    negative_zero_: false,
    nan_negative_: negative,
    signaling_nan_: signaling,
    nan_payload_: if signaling && payload.is_zero() {
      legacy_bin_one()
    } else {
      payload
    },
  }
}

///|
fn LegacyBigIntBinFloat::classify(self : LegacyBigIntBinFloat) -> FpClass {
  self.class_
}

///|
fn LegacyBigIntBinFloat::precision(self : LegacyBigIntBinFloat) -> Int {
  self.precision_
}

///|
fn LegacyBigIntBinFloat::sign(self : LegacyBigIntBinFloat) -> Sign {
  match self.class_ {
    FpClass::NaN => Sign::Zero
    FpClass::Finite if self.significand_.is_zero() => Sign::Zero
    _ =>
      if self.significand_ < legacy_bin_zero() {
        Sign::Negative
      } else {
        Sign::Positive
      }
  }
}

///|
fn LegacyBigIntBinFloat::is_negative(self : LegacyBigIntBinFloat) -> Bool {
  match self.class_ {
    FpClass::NaN => self.nan_negative_
    FpClass::Finite if self.significand_.is_zero() => self.negative_zero_
    _ => self.significand_ < legacy_bin_zero()
  }
}

///|
fn LegacyBigIntBinFloat::is_zero(self : LegacyBigIntBinFloat) -> Bool {
  self.class_ == FpClass::Finite && self.significand_.is_zero()
}

///|
fn LegacyBigIntBinFloat::coefficient(self : LegacyBigIntBinFloat) -> BigInt {
  legacy_bin_abs(self.significand_)
}

///|
fn LegacyBigIntBinFloat::exponent2(self : LegacyBigIntBinFloat) -> Int {
  self.exponent2_
}

///|
fn LegacyBigIntBinFloat::is_signaling_nan(self : LegacyBigIntBinFloat) -> Bool {
  self.class_ == FpClass::NaN && self.signaling_nan_
}

///|
fn LegacyBigIntBinFloat::nan_payload(self : LegacyBigIntBinFloat) -> BigInt {
  if self.class_ == FpClass::NaN {
    self.nan_payload_
  } else {
    legacy_bin_zero()
  }
}

///|
fn LegacyBigIntBinFloat::with_precision(
  self : LegacyBigIntBinFloat,
  precision : Int,
  mode : RoundingMode,
) -> LegacyBigIntBinFloat {
  match self.class_ {
    FpClass::Finite =>
      LegacyBigIntBinFloat::make(
        self.significand_,
        self.exponent2_,
        precision,
        negative_zero=self.negative_zero_,
        mode~,
      )
    FpClass::Infinity => { ..self, precision_: Int::max(1, precision) }
    FpClass::NaN => { ..self, precision_: Int::max(1, precision) }
  }
}

///|
fn LegacyBigIntBinFloat::neg(
  self : LegacyBigIntBinFloat,
) -> LegacyBigIntBinFloat {
  match self.class_ {
    FpClass::NaN => { ..self, nan_negative_: !self.nan_negative_ }
    FpClass::Finite if self.significand_.is_zero() =>
      { ..self, negative_zero_: !self.negative_zero_ }
    _ => { ..self, significand_: -self.significand_ }
  }
}

///|
fn legacy_bin_quiet_nan(
  value : LegacyBigIntBinFloat,
  precision : Int,
) -> LegacyBigIntBinFloat {
  LegacyBigIntBinFloat::nan(
    precision~,
    negative=value.nan_negative_,
    signaling=false,
    payload=value.nan_payload_,
  )
}

///|
fn legacy_bin_nan_pair(
  left : LegacyBigIntBinFloat,
  right : LegacyBigIntBinFloat,
  precision : Int,
) -> LegacyBigIntBinFloat? {
  if left.class_ == FpClass::NaN {
    Some(legacy_bin_quiet_nan(left, precision))
  } else if right.class_ == FpClass::NaN {
    Some(legacy_bin_quiet_nan(right, precision))
  } else {
    None
  }
}

///|
fn LegacyBigIntBinFloat::add(
  self : LegacyBigIntBinFloat,
  other : LegacyBigIntBinFloat,
) -> LegacyBigIntBinFloat {
  let precision = Int::max(self.precision_, other.precision_)
  match legacy_bin_nan_pair(self, other, precision) {
    Some(value) => return value
    None => ()
  }
  match (self.class_, other.class_) {
    (FpClass::Infinity, FpClass::Infinity) =>
      if self.is_negative() == other.is_negative() {
        self.with_precision(precision, RoundingMode::ToNearestEven)
      } else {
        LegacyBigIntBinFloat::nan(precision~)
      }
    (FpClass::Infinity, _) =>
      self.with_precision(precision, RoundingMode::ToNearestEven)
    (_, FpClass::Infinity) =>
      other.with_precision(precision, RoundingMode::ToNearestEven)
    (FpClass::Finite, FpClass::Finite) => {
      let target = Int::min(self.exponent2_, other.exponent2_)
      let left = self.significand_ << (self.exponent2_ - target)
      let right = other.significand_ << (other.exponent2_ - target)
      let sum = left + right
      LegacyBigIntBinFloat::make(
        sum,
        target,
        precision,
        negative_zero=sum.is_zero() && self.is_negative() && other.is_negative(),
      )
    }
    _ => abort("unreachable LegacyBigIntBinFloat::add class pair")
  }
}

///|
fn LegacyBigIntBinFloat::sub(
  self : LegacyBigIntBinFloat,
  other : LegacyBigIntBinFloat,
) -> LegacyBigIntBinFloat {
  self.add(other.neg())
}

///|
fn LegacyBigIntBinFloat::mul(
  self : LegacyBigIntBinFloat,
  other : LegacyBigIntBinFloat,
) -> LegacyBigIntBinFloat {
  let precision = Int::max(self.precision_, other.precision_)
  match legacy_bin_nan_pair(self, other, precision) {
    Some(value) => return value
    None => ()
  }
  let negative = self.is_negative() != other.is_negative()
  match (self.class_, other.class_) {
    (FpClass::Infinity, FpClass::Finite)
    | (FpClass::Finite, FpClass::Infinity) if self.is_zero() || other.is_zero() =>
      LegacyBigIntBinFloat::nan(precision~)
    (FpClass::Infinity, _) | (_, FpClass::Infinity) =>
      LegacyBigIntBinFloat::inf(negative, precision~)
    (FpClass::Finite, FpClass::Finite) => {
      let product = self.significand_ * other.significand_
      LegacyBigIntBinFloat::make(
        product,
        self.exponent2_ + other.exponent2_,
        precision,
        negative_zero=product.is_zero() && negative,
      )
    }
    _ => abort("unreachable LegacyBigIntBinFloat::mul class pair")
  }
}

///|
fn LegacyBigIntBinFloat::pow_positive(
  self : LegacyBigIntBinFloat,
  exponent : Int,
) -> LegacyBigIntBinFloat {
  guard exponent > 0 else { abort("legacy positive exponent must be positive") }
  let precision = self.precision_
  match self.class_ {
    FpClass::Finite => {
      let powered = self.significand_.pow(BigInt::from_int(exponent))
      LegacyBigIntBinFloat::make(
        powered,
        self.exponent2_ * exponent,
        precision,
        negative_zero=powered.is_zero() &&
          self.is_negative() &&
          exponent % 2 != 0,
      )
    }
    FpClass::Infinity =>
      LegacyBigIntBinFloat::inf(
        self.is_negative() && exponent % 2 != 0,
        precision~,
      )
    FpClass::NaN => LegacyBigIntBinFloat::nan(precision~)
  }
}

///|
fn LegacyBigIntBinFloat::div(
  self : LegacyBigIntBinFloat,
  other : LegacyBigIntBinFloat,
) -> LegacyBigIntBinFloat {
  let precision = Int::max(self.precision_, other.precision_)
  match legacy_bin_nan_pair(self, other, precision) {
    Some(value) => return value
    None => ()
  }
  let negative = self.is_negative() != other.is_negative()
  match (self.class_, other.class_) {
    (FpClass::Infinity, FpClass::Infinity) =>
      LegacyBigIntBinFloat::nan(precision~)
    (FpClass::Finite, FpClass::Finite) if self.is_zero() && other.is_zero() =>
      LegacyBigIntBinFloat::nan(precision~)
    (FpClass::Infinity, _) => LegacyBigIntBinFloat::inf(negative, precision~)
    (FpClass::Finite, FpClass::Finite) if other.is_zero() =>
      LegacyBigIntBinFloat::inf(negative, precision~)
    (_, FpClass::Infinity) => LegacyBigIntBinFloat::zero(precision~, negative~)
    (FpClass::Finite, FpClass::Finite) if self.is_zero() =>
      LegacyBigIntBinFloat::zero(precision~, negative~)
    (FpClass::Finite, FpClass::Finite) => {
      let numerator = legacy_bin_abs(self.significand_)
      let denominator = legacy_bin_abs(other.significand_)
      let ratio_top = legacy_bin_ratio_floor_log2(numerator, denominator)
      let scale = precision - 1 - ratio_top
      let (scaled_numerator, scaled_denominator) = if scale >= 0 {
        (numerator << scale, denominator)
      } else {
        (numerator, denominator << -scale)
      }
      let quotient = legacy_bin_round_positive_div(
        scaled_numerator,
        scaled_denominator,
        negative,
        RoundingMode::ToNearestEven,
      )
      LegacyBigIntBinFloat::make(
        if negative {
          -quotient
        } else {
          quotient
        },
        self.exponent2_ - other.exponent2_ - scale,
        precision,
        negative_zero=quotient.is_zero() && negative,
      )
    }
    _ => abort("unreachable LegacyBigIntBinFloat::div class pair")
  }
}

///|
fn legacy_bin_integer_sqrt_floor(value : BigInt) -> BigInt {
  if value <= legacy_bin_one() {
    return value
  }
  let mut root = legacy_bin_one() << ((value.bit_length() + 1) / 2)
  let mut next = (root + value / root) / BigInt::from_int(2)
  while next < root {
    root = next
    next = (root + value / root) / BigInt::from_int(2)
  }
  root
}

///|
fn legacy_bin_round_sqrt(
  value : LegacyBigIntBinFloat,
  precision : Int,
) -> LegacyBigIntBinFloat {
  let odd_exponent = value.exponent2_ % 2 != 0
  let radicand = if odd_exponent {
    value.significand_ << 1
  } else {
    value.significand_
  }
  let even_exponent = if odd_exponent {
    value.exponent2_ - 1
  } else {
    value.exponent2_
  }
  let root_top = (radicand.bit_length() - 1) / 2
  let scale = precision - 1 - root_top
  let scaled_radicand = radicand << (2 * scale)
  let floor_root = legacy_bin_integer_sqrt_floor(scaled_radicand)
  let remainder = scaled_radicand - floor_root * floor_root
  let increment = !remainder.is_zero() &&
    remainder << 2 > (floor_root << 2) + legacy_bin_one()
  let rounded_root = if increment {
    floor_root + legacy_bin_one()
  } else {
    floor_root
  }
  LegacyBigIntBinFloat::make(rounded_root, even_exponent / 2 - scale, precision)
}

///|
fn LegacyBigIntBinFloat::sqrt(
  self : LegacyBigIntBinFloat,
) -> Result[LegacyBigIntBinFloat, String] {
  match self.class_ {
    FpClass::NaN => Ok(legacy_bin_quiet_nan(self, self.precision_))
    FpClass::Infinity =>
      if self.is_negative() {
        Err("sqrt requires a non-negative value")
      } else {
        Ok(LegacyBigIntBinFloat::inf(false, precision=self.precision_))
      }
    FpClass::Finite if self.is_zero() =>
      Ok(
        LegacyBigIntBinFloat::zero(
          precision=self.precision_,
          negative=self.is_negative(),
        ),
      )
    FpClass::Finite if self.is_negative() =>
      Err("sqrt requires a non-negative value")
    FpClass::Finite => Ok(legacy_bin_round_sqrt(self, self.precision_))
  }
}

///|
fn legacy_bin_float_from_candidate(value : BinFloat) -> LegacyBigIntBinFloat {
  let magnitude = BigInt::from_string(value.coefficient().to_string())
  match value.classify() {
    FpClass::Finite =>
      LegacyBigIntBinFloat::make(
        if value.is_negative() && !magnitude.is_zero() {
          -magnitude
        } else {
          magnitude
        },
        value.exponent2(),
        value.precision(),
        negative_zero=value.is_negative(),
      )
    FpClass::Infinity =>
      LegacyBigIntBinFloat::inf(
        value.is_negative(),
        precision=value.precision(),
      )
    FpClass::NaN =>
      LegacyBigIntBinFloat::nan(
        precision=value.precision(),
        negative=value.is_negative(),
        signaling=value.is_signaling_nan(),
        payload=BigInt::from_string(value.nan_payload().to_string()),
      )
  }
}
