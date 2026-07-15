///|
// Decimal public types and context/flag helpers.

///|
pub struct Decimal {
  priv class : FpClass
  priv negative : Bool
  priv coefficient : GdaCoeff
  priv exponent10 : Int
  priv precision_ : Int
  priv signaling_nan : Bool
} derive(Debug)

///|

///|
pub(all) enum DecimalRoundingMode {
  HalfEven
  HalfUp
  HalfDown
  Down
  Ceiling
  Floor
  Up
  ZeroFiveUp
} derive(Eq)

///|
pub(all) enum DecimalTininessDetection {
  BeforeRounding
  AfterRounding
} derive(Eq)

///|
pub(all) enum DecimalSignal {
  ConversionSyntax
  DivisionByZero
  DivisionImpossible
  DivisionUndefined
  InvalidContext
  InvalidOperation
  Overflow
  Underflow
  Subnormal
  Inexact
  Rounded
  Clamped
  LostDigits
} derive(Eq)

///|
pub(all) enum GdaInterchangeFormat {
  Decimal32
  Decimal64
  Decimal128
} derive(Eq)

///|
pub struct GdaInterchange {
  priv format : GdaInterchangeFormat
  priv bits : BigInt
}

///|
pub struct DecimalContext {
  priv precision : Int
  priv rounding : RoundingMode
  priv decimal_rounding : DecimalRoundingMode
  priv e_min : Int
  priv e_max : Int
  priv clamp : Bool
  priv extended : Bool
  priv tininess : DecimalTininessDetection
} derive(Eq)

///|
pub struct DecimalFlags {
  inexact : Bool
  rounded : Bool
  lost_digits : Bool
  invalid_operation : Bool
  division_by_zero : Bool
  overflow : Bool
  underflow : Bool
  subnormal : Bool
  clamped : Bool
  conversion_syntax : Bool
  division_impossible : Bool
  division_undefined : Bool
  invalid_context : Bool
} derive(Eq)

///|
priv struct DecimalMathConstantCache {
  scale : Int
  ln2 : GdaCoeff
  ln5 : GdaCoeff
  ln10 : GdaCoeff
}

///|
priv struct DecimalExpBoundaryCacheEntry {
  precision : Int
  e_min : Int
  e_max : Int
  clamp : Bool
  lower : Decimal
  upper : Decimal
}

///|
let decimal_math_constant_cache : @ref.Ref[DecimalMathConstantCache] = @ref.new({
    scale: 0,
    ln2: gda_coeff_zero(),
    ln5: gda_coeff_zero(),
    ln10: gda_coeff_zero(),
  },
)

///|
let decimal_exp_boundary_cache : Array[DecimalExpBoundaryCacheEntry] = []

///|
let decimal_exp_boundary_cache_capacity = 8

///|
let decimal_exp_boundary_cache_next : @ref.Ref[Int] = @ref.new(0)

///|
pub fn DecimalFlags::new() -> DecimalFlags {
  {
    inexact: false,
    rounded: false,
    lost_digits: false,
    invalid_operation: false,
    division_by_zero: false,
    overflow: false,
    underflow: false,
    subnormal: false,
    clamped: false,
    conversion_syntax: false,
    division_impossible: false,
    division_undefined: false,
    invalid_context: false,
  }
}

///|
pub fn DecimalFlags::combine(
  self : DecimalFlags,
  other : DecimalFlags,
) -> DecimalFlags {
  {
    inexact: self.inexact || other.inexact,
    rounded: self.rounded || other.rounded,
    lost_digits: self.lost_digits || other.lost_digits,
    invalid_operation: self.invalid_operation || other.invalid_operation,
    division_by_zero: self.division_by_zero || other.division_by_zero,
    overflow: self.overflow || other.overflow,
    underflow: self.underflow || other.underflow,
    subnormal: self.subnormal || other.subnormal,
    clamped: self.clamped || other.clamped,
    conversion_syntax: self.conversion_syntax || other.conversion_syntax,
    division_impossible: self.division_impossible || other.division_impossible,
    division_undefined: self.division_undefined || other.division_undefined,
    invalid_context: self.invalid_context || other.invalid_context,
  }
}

///|
pub fn DecimalFlags::has_error(self : DecimalFlags) -> Bool {
  self.invalid_operation ||
  self.division_by_zero ||
  self.division_undefined ||
  self.division_impossible ||
  self.invalid_context
}

///|
pub fn DecimalFlags::contains(
  self : DecimalFlags,
  signal : DecimalSignal,
) -> Bool {
  match signal {
    ConversionSyntax => self.conversion_syntax
    DivisionByZero => self.division_by_zero
    DivisionImpossible => self.division_impossible
    DivisionUndefined => self.division_undefined
    InvalidContext => self.invalid_context
    InvalidOperation => self.invalid_operation
    Overflow => self.overflow
    Underflow => self.underflow
    Subnormal => self.subnormal
    Inexact => self.inexact
    Rounded => self.rounded
    Clamped => self.clamped
    LostDigits => self.lost_digits
  }
}

///|
pub fn DecimalContext::new(
  precision? : Int = 34,
  rounding? : RoundingMode = RoundingMode::ToNearestEven,
  decimal_rounding? : DecimalRoundingMode,
  e_min? : Int = -999_999_999,
  e_max? : Int = 999_999_999,
  clamp? : Bool = false,
  extended? : Bool = true,
  tininess? : DecimalTininessDetection = DecimalTininessDetection::BeforeRounding,
) -> DecimalContext {
  guard precision > 0 else {
    abort("DecimalContext::new: precision must be positive")
  }
  guard e_min <= e_max else {
    abort("DecimalContext::new: e_min must not exceed e_max")
  }
  let decimal_rounding = match decimal_rounding {
    Some(mode) => mode
    None => DecimalRoundingMode::from_arithmetic(rounding)
  }
  {
    precision,
    rounding,
    decimal_rounding,
    e_min,
    e_max,
    clamp,
    extended,
    tininess,
  }
}

///|
pub fn DecimalContext::try_new(
  precision? : Int = 34,
  rounding? : RoundingMode = RoundingMode::ToNearestEven,
  decimal_rounding? : DecimalRoundingMode,
  e_min? : Int = -999_999_999,
  e_max? : Int = 999_999_999,
  clamp? : Bool = false,
  extended? : Bool = true,
  tininess? : DecimalTininessDetection = DecimalTininessDetection::BeforeRounding,
) -> Result[DecimalContext, @def.ArithmeticError] {
  guard precision > 0 else {
    return Err(
      @def.ArithmeticError::domain_error(
        "DecimalContext::try_new: precision must be positive",
      ),
    )
  }
  guard e_min <= e_max else {
    return Err(
      @def.ArithmeticError::domain_error(
        "DecimalContext::try_new: e_min must not exceed e_max",
      ),
    )
  }
  let decimal_rounding = match decimal_rounding {
    Some(mode) => mode
    None => DecimalRoundingMode::from_arithmetic(rounding)
  }
  Ok({
    precision,
    rounding,
    decimal_rounding,
    e_min,
    e_max,
    clamp,
    extended,
    tininess,
  })
}

///|
pub fn DecimalContext::precision(self : DecimalContext) -> Int {
  self.precision
}

///|
pub fn DecimalContext::rounding(self : DecimalContext) -> RoundingMode {
  self.rounding
}

///|
pub fn DecimalContext::with_rounding(
  self : DecimalContext,
  rounding : RoundingMode,
) -> DecimalContext {
  {
    ..self,
    rounding,
    decimal_rounding: DecimalRoundingMode::from_arithmetic(rounding),
  }
}

///|
pub fn DecimalContext::decimal_rounding(
  self : DecimalContext,
) -> DecimalRoundingMode {
  self.decimal_rounding
}

///|
pub fn DecimalContext::e_min(self : DecimalContext) -> Int {
  self.e_min
}

///|
pub fn DecimalContext::e_max(self : DecimalContext) -> Int {
  self.e_max
}

///|
pub fn DecimalContext::clamp(self : DecimalContext) -> Bool {
  self.clamp
}

///|
pub fn DecimalContext::extended(self : DecimalContext) -> Bool {
  self.extended
}

///|
pub fn DecimalContext::tininess(
  self : DecimalContext,
) -> DecimalTininessDetection {
  self.tininess
}

///|
pub fn DecimalContext::with_tininess(
  self : DecimalContext,
  tininess : DecimalTininessDetection,
) -> DecimalContext {
  { ..self, tininess, }
}

///|
fn decimal_exact_work_context() -> DecimalContext {
  {
    precision: 0,
    rounding: RoundingMode::ToNearestEven,
    decimal_rounding: DecimalRoundingMode::HalfEven,
    e_min: -999_999_999,
    e_max: 999_999_999,
    clamp: false,
    extended: true,
    tininess: DecimalTininessDetection::BeforeRounding,
  }
}

///|
pub fn DecimalContext::exact() -> DecimalContext {
  decimal_exact_work_context()
}

///|
pub fn DecimalContext::decimal32() -> DecimalContext {
  DecimalContext::new(
    precision=7,
    rounding=RoundingMode::ToNearestEven,
    e_min=-95,
    e_max=96,
    clamp=true,
  )
}

///|
pub fn DecimalContext::decimal64() -> DecimalContext {
  DecimalContext::new(
    precision=16,
    rounding=RoundingMode::ToNearestEven,
    e_min=-383,
    e_max=384,
    clamp=true,
  )
}

///|
pub fn DecimalContext::decimal128() -> DecimalContext {
  DecimalContext::new(
    precision=34,
    rounding=RoundingMode::ToNearestEven,
    e_min=-6143,
    e_max=6144,
    clamp=true,
  )
}

///|
pub fn DecimalContext::from_arithmetic_context(
  ctx : @lf_arith.ArithmeticContext,
) -> DecimalContext {
  DecimalContext::new(precision=ctx.precision, rounding=ctx.rounding)
}

///|
pub fn GdaInterchangeFormat::context(
  self : GdaInterchangeFormat,
) -> DecimalContext {
  match self {
    Decimal32 => DecimalContext::decimal32()
    Decimal64 => DecimalContext::decimal64()
    Decimal128 => DecimalContext::decimal128()
  }
}

///|
pub fn DecimalRoundingMode::from_arithmetic(
  mode : RoundingMode,
) -> DecimalRoundingMode {
  match mode {
    RoundingMode::ToNearestEven => HalfEven
    RoundingMode::TowardZero => Down
    RoundingMode::TowardPositive => Ceiling
    RoundingMode::TowardNegative => Floor
    RoundingMode::AwayFromZero => Up
  }
}

///|
pub fn DecimalRoundingMode::to_arithmetic(
  self : DecimalRoundingMode,
) -> RoundingMode? {
  match self {
    HalfEven => Some(RoundingMode::ToNearestEven)
    Down => Some(RoundingMode::TowardZero)
    Ceiling => Some(RoundingMode::TowardPositive)
    Floor => Some(RoundingMode::TowardNegative)
    Up => Some(RoundingMode::AwayFromZero)
    HalfUp | HalfDown | ZeroFiveUp => None
  }
}
