///|
// Public constructors and binary/decimal conversion helpers.

pub fn Decimal::make(
  coefficient : BigInt,
  exponent10 : Int,
  precision : Int,
  mode? : RoundingMode = RoundingMode::ToNearestEven,
) -> Decimal {
  normalize_decimal(coefficient, exponent10, precision, mode)
}

///|
pub fn Decimal::zero(precision? : Int = 34) -> Decimal {
  Decimal::make(bigint_zero(), 0, precision)
}

///|
pub fn Decimal::negative_zero(precision? : Int = 34) -> Decimal {
  normalize_decimal_parts(
    true,
    bigint_zero(),
    0,
    precision,
    RoundingMode::ToNearestEven,
  )
}

///|
pub fn Decimal::one(precision? : Int = 34) -> Decimal {
  Decimal::make(bigint_one(), 0, precision)
}

///|
pub fn Decimal::inf(sign : Sign, precision? : Int = 34) -> Decimal {
  make_special(
    FpClass::Infinity,
    sign == Sign::Negative,
    bigint_zero(),
    precision,
    false,
  )
}

///|
pub fn Decimal::nan(precision? : Int = 34) -> Decimal {
  make_special(FpClass::NaN, false, bigint_zero(), precision, false)
}

///|
pub fn Decimal::quiet_nan(
  payload? : BigInt = bigint_zero(),
  negative? : Bool = false,
  precision? : Int = 34,
) -> Decimal {
  make_special(FpClass::NaN, negative, payload, precision, false)
}

///|
pub fn Decimal::signaling_nan(
  payload? : BigInt = bigint_zero(),
  negative? : Bool = false,
  precision? : Int = 34,
) -> Decimal {
  make_special(FpClass::NaN, negative, payload, precision, true)
}

///|
pub fn Decimal::from_int(n : Int, precision? : Int = 34) -> Decimal {
  Decimal::make(BigInt::from_int(n), 0, precision)
}

///|
pub fn Decimal::from_bigint(n : BigInt, precision? : Int = 34) -> Decimal {
  Decimal::make(n, 0, precision)
}

///|
pub fn Decimal::from_double(x : Double, precision? : Int = 34) -> Decimal {
  let precision = Int::max(1, precision)
  let bits = x.reinterpret_as_uint64()
  let negative = bits >> 63 != 0UL
  let exponent_bits = ((bits >> 52) & 0x7ffUL).to_int()
  let fraction_bits = bits & 0x000f_ffff_ffff_ffffUL
  if exponent_bits == 0x7ff && fraction_bits != 0UL {
    return Decimal::quiet_nan(negative~, precision~)
  }
  if exponent_bits == 0 && fraction_bits == 0UL {
    return if negative {
      Decimal::negative_zero(precision~)
    } else {
      Decimal::zero(precision~)
    }
  }
  let bin = @bin_float.BinFloat::from_double(x, precision=53)
  match bin.classify() {
    FpClass::NaN => Decimal::nan(precision~)
    FpClass::Infinity => Decimal::inf(bin.sign(), precision~)
    FpClass::Finite => Decimal::from_bin_float(bin, precision~)
  }
}

///|
pub fn Decimal::from_float(x : Float, precision? : Int = 34) -> Decimal {
  Decimal::from_double(x.to_double(), precision~)
}

///|
pub fn Decimal::to_bin_float(
  self : Decimal,
  precision? : Int = self.precision_,
  mode? : RoundingMode = RoundingMode::ToNearestEven,
) -> @bin_float.BinFloat {
  match self.class {
    FpClass::NaN => @bin_float.BinFloat::nan(precision~)
    FpClass::Infinity => @bin_float.BinFloat::inf(self.sign(), precision~)
    FpClass::Finite => {
      if self.coefficient.is_zero() {
        return @bin_float.BinFloat::zero(precision~)
      }
      if self.exponent10 >= 0 {
        let sig = if self.negative {
          -coeff_bigint(self.coefficient)
        } else {
          coeff_bigint(self.coefficient)
        }
        return @bin_float.BinFloat::make(
          sig * pow5(self.exponent10),
          self.exponent10,
          precision,
          mode~,
        )
      }
      let scale = -self.exponent10
      let binary_shift = precision + scale * 4
      let numerator = abs_bigint(coeff_bigint(self.coefficient)) << binary_shift
      let denominator = pow10(scale)
      let q = round_positive_div(
        numerator,
        denominator,
        self.sign() == Sign::Negative,
        mode,
      )
      let sig = if self.sign() == Sign::Negative { -q } else { q }
      @bin_float.BinFloat::make(sig, -binary_shift, precision, mode~)
    }
  }
}

///|
pub fn Decimal::from_bin_float(
  x : @bin_float.BinFloat,
  precision? : Int = x.precision(),
) -> Decimal {
  match x.classify() {
    FpClass::NaN => Decimal::nan(precision~)
    FpClass::Infinity => Decimal::inf(x.sign(), precision~)
    FpClass::Finite =>
      if x.is_zero() {
        Decimal::zero(precision~)
      } else if x.exponent2() >= 0 {
        Decimal::make(x.significand() << x.exponent2(), 0, precision)
      } else {
        let k = -x.exponent2()
        Decimal::make(x.significand() * pow5(k), -k, precision)
      }
  }
}

///|
