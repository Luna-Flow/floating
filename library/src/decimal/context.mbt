///|
// Decimal public types and context/flag helpers.

///|
#derive(Debug)
pub struct Decimal {
  priv class : FpClass
  priv negative : Bool
  priv coefficient : DecCoeff
  priv exponent10 : Int32
  priv precision_ : Int32
  priv signaling_nan : Bool
}

///|

///|
#derive(Eq)
pub(all) enum DecimalRoundingMode {
  HalfEven
  HalfUp
  HalfDown
  Down
  Ceiling
  Floor
  Up
  ZeroFiveUp
}

///|
#derive(Eq)
pub(all) enum DecimalTininessDetection {
  BeforeRounding
  AfterRounding
}

///|
#derive(Eq)
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
}

///|
#derive(Eq)
pub(all) enum DecimalInterchangeFormat {
  Decimal32
  Decimal64
  Decimal128
}

///|
#derive(Eq)
pub(all) enum DecimalInterchangeEncoding {
  DPD
  BID
}

///|
pub struct DecimalInterchange {
  priv format : DecimalInterchangeFormat
  priv encoding : DecimalInterchangeEncoding
  priv bits : BigInt
}

///|
#derive(Eq)
pub struct DecimalContext {
  priv precision : Int32
  priv rounding : RoundingMode
  priv decimal_rounding : DecimalRoundingMode
  priv e_min : Int32
  priv e_max : Int32
  priv clamp : Bool
  priv extended : Bool
  priv tininess : DecimalTininessDetection
  priv refinement_limit : Int32?
  priv clamp_fold : Bool
}

///|
#derive(Eq)
pub struct DecimalFlags {
  priv inexact : Bool
  priv rounded : Bool
  priv lost_digits : Bool
  priv invalid_operation : Bool
  priv division_by_zero : Bool
  priv overflow : Bool
  priv underflow : Bool
  priv subnormal : Bool
  priv clamped : Bool
  priv conversion_syntax : Bool
  priv division_impossible : Bool
  priv division_undefined : Bool
  priv invalid_context : Bool
}

///|
priv struct DecimalMathConstantCache {
  scale : Int32
  ln2 : DecCoeff
  ln5 : DecCoeff
  ln10 : DecCoeff
}

///|
priv struct DecimalExpBoundaryCacheEntry {
  precision : Int32
  e_min : Int32
  e_max : Int32
  clamp : Bool
  lower : Decimal
  upper : Decimal
}

///|
let decimal_math_constant_cache : @ref.Ref[DecimalMathConstantCache] = @ref.Ref({
    scale: 0,
    ln2: dec_coeff_zero(),
    ln5: dec_coeff_zero(),
    ln10: dec_coeff_zero(),
  },
)

///|
let decimal_exp_boundary_cache : Array[DecimalExpBoundaryCacheEntry] = []

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
/// Whether the `inexact` status flag is set.
pub fn DecimalFlags::inexact(self : DecimalFlags) -> Bool {
  self.inexact
}

///|
/// Whether the `rounded` status flag is set.
pub fn DecimalFlags::rounded(self : DecimalFlags) -> Bool {
  self.rounded
}

///|
/// Whether the `lost_digits` status flag is set.
pub fn DecimalFlags::lost_digits(self : DecimalFlags) -> Bool {
  self.lost_digits
}

///|
/// Whether the `invalid_operation` status flag is set.
pub fn DecimalFlags::invalid_operation(self : DecimalFlags) -> Bool {
  self.invalid_operation
}

///|
/// Whether the `division_by_zero` status flag is set.
pub fn DecimalFlags::division_by_zero(self : DecimalFlags) -> Bool {
  self.division_by_zero
}

///|
/// Whether the `overflow` status flag is set.
pub fn DecimalFlags::overflow(self : DecimalFlags) -> Bool {
  self.overflow
}

///|
/// Whether the `underflow` status flag is set.
pub fn DecimalFlags::underflow(self : DecimalFlags) -> Bool {
  self.underflow
}

///|
/// Whether the `subnormal` status flag is set.
pub fn DecimalFlags::subnormal(self : DecimalFlags) -> Bool {
  self.subnormal
}

///|
/// Whether the `clamped` status flag is set.
pub fn DecimalFlags::clamped(self : DecimalFlags) -> Bool {
  self.clamped
}

///|
/// Whether the `conversion_syntax` status flag is set.
pub fn DecimalFlags::conversion_syntax(self : DecimalFlags) -> Bool {
  self.conversion_syntax
}

///|
/// Whether the `division_impossible` status flag is set.
pub fn DecimalFlags::division_impossible(self : DecimalFlags) -> Bool {
  self.division_impossible
}

///|
/// Whether the `division_undefined` status flag is set.
pub fn DecimalFlags::division_undefined(self : DecimalFlags) -> Bool {
  self.division_undefined
}

///|
/// Whether the `invalid_context` status flag is set.
pub fn DecimalFlags::invalid_context(self : DecimalFlags) -> Bool {
  self.invalid_context
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
/// True when a condition that delivers no usable number, or a division by
/// zero, is set: `invalid_operation`, `conversion_syntax`, `division_by_zero`,
/// `division_undefined`, `division_impossible` or `invalid_context`. IEEE
/// 754-2019 7.2 signals invalid operation when there is "no usefully
/// definable result"; division by zero is included so that the checked
/// arithmetic forms can return `Err`. Overflow, underflow, inexact and the
/// other conditions deliver a usable result and are not errors.
pub fn DecimalFlags::has_error(self : DecimalFlags) -> Bool {
  // `conversion_syntax` is a condition of the Invalid operation signal, like
  // `division_impossible` and `division_undefined`. Leaving it out made a
  // failed parse, which raises only this flag, look like a successful result.
  self.invalid_operation ||
  self.conversion_syntax ||
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
/// Largest exponent bound that `DecimalContext::try_new` accepts for `e_max`
/// (and, negated, the smallest for `e_min`). The context parameters are
/// checked against these three constants, so the values cannot drift from the
/// validation. The certified elementary functions accept a narrower range
/// (`|e| <= 999999` and `p <= 999999`); outside it they return NaN with
/// `invalid_context`. See "DecimalContext::new, try_new" in the `decimal` API
/// manual (doc/manual/api/decimal.md).
pub let decimal_implementation_e_max : Int32 = @internal.decimal_exponent_limit

///|
/// Smallest `e_min` that `DecimalContext::try_new` accepts, the negation of
/// `decimal_implementation_e_max`. The certified elementary functions have
/// their own, narrower limit (see `decimal_implementation_e_max`).
pub let decimal_implementation_e_min : Int32 = -@internal.decimal_exponent_limit

///|
/// Largest precision that `DecimalContext::try_new` accepts. The certified
/// elementary functions have their own, lower limit (see
/// `decimal_implementation_e_max`).
pub let decimal_precision_max : Int32 = @internal.decimal_exponent_limit

///|
fn DecimalContext::build(
  precision~ : Int32 = 34,
  rounding~ : RoundingMode = RoundingMode::ToNearestEven,
  decimal_rounding? : DecimalRoundingMode,
  e_min~ : Int32 = decimal_implementation_e_min,
  e_max~ : Int32 = decimal_implementation_e_max,
  clamp~ : Bool = false,
  extended~ : Bool = true,
  tininess~ : DecimalTininessDetection = DecimalTininessDetection::BeforeRounding,
) -> Result[DecimalContext, String] {
  let bounds = @internal.DecimalExponentBounds::new(precision, e_min, e_max)
  guard bounds.is_valid() else {
    let reason = if precision <= 0 || precision > decimal_precision_max {
      "precision must be within 1..=\{decimal_precision_max}"
    } else if e_min < decimal_implementation_e_min || e_min > 0 {
      "e_min must be within \{decimal_implementation_e_min}..=0"
    } else if e_max < 0 || e_max > decimal_implementation_e_max {
      "e_max must be within 0..=\{decimal_implementation_e_max}"
    } else {
      "e_min must not exceed e_max"
    }
    return Err(reason)
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
    refinement_limit: Some(12),
    clamp_fold: false,
  })
}

///|
/// Builds a context, or aborts with the message that names the invalid
/// parameter (like `BinaryContext::new`). `try_new` returns the same check as
/// an `Err` instead.
pub fn DecimalContext::new(
  precision~ : Int32 = 34,
  rounding~ : RoundingMode = RoundingMode::ToNearestEven,
  decimal_rounding? : DecimalRoundingMode,
  e_min~ : Int32 = decimal_implementation_e_min,
  e_max~ : Int32 = decimal_implementation_e_max,
  clamp~ : Bool = false,
  extended~ : Bool = true,
  tininess~ : DecimalTininessDetection = DecimalTininessDetection::BeforeRounding,
) -> DecimalContext {
  match
    DecimalContext::build(
      precision~,
      rounding~,
      decimal_rounding?,
      e_min~,
      e_max~,
      clamp~,
      extended~,
      tininess~,
    ) {
    Ok(context) => context
    Err(reason) => abort("DecimalContext::new: " + reason)
  }
}

///|
pub fn DecimalContext::try_new(
  precision~ : Int32 = 34,
  rounding~ : RoundingMode = RoundingMode::ToNearestEven,
  decimal_rounding? : DecimalRoundingMode,
  e_min~ : Int32 = decimal_implementation_e_min,
  e_max~ : Int32 = decimal_implementation_e_max,
  clamp~ : Bool = false,
  extended~ : Bool = true,
  tininess~ : DecimalTininessDetection = DecimalTininessDetection::BeforeRounding,
) -> Result[DecimalContext, @def.ArithmeticError] {
  match
    DecimalContext::build(
      precision~,
      rounding~,
      decimal_rounding?,
      e_min~,
      e_max~,
      clamp~,
      extended~,
      tininess~,
    ) {
    Ok(context) => Ok(context)
    Err(reason) => Err(@def.ArithmeticError::domain_error(reason))
  }
}

///|
pub fn DecimalContext::precision(self : DecimalContext) -> Int32 {
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
pub fn DecimalContext::is754version2019(_self : DecimalContext) -> Bool {
  true
}

///|
pub fn DecimalContext::decimal_rounding(
  self : DecimalContext,
) -> DecimalRoundingMode {
  self.decimal_rounding
}

///|
pub fn DecimalContext::e_min(self : DecimalContext) -> Int32 {
  self.e_min
}

///|
pub fn DecimalContext::e_max(self : DecimalContext) -> Int32 {
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
/// The number of refinement steps the certified elementary functions may take
/// before they report a certification failure, `Some(12)` by default. `None`
/// means no count limit; the work precision still stops at a resource bound
/// (see `with_refinement_limit`).
pub fn DecimalContext::refinement_limit(self : DecimalContext) -> Int32? {
  self.refinement_limit
}

///|
/// Returns a copy of the context with the refinement limit of the certified
/// elementary functions set to `limit`. `None` removes the count limit; the work
/// precision of each loop is then bounded (at least 8,000,000 bits, or 256 times
/// the initial work precision). A limit below 1 is clamped to 1 refinement step.
pub fn DecimalContext::with_refinement_limit(
  self : DecimalContext,
  limit : Int32?,
) -> DecimalContext {
  { ..self, refinement_limit: limit, }
}

///|
/// Whether a zero `quantize` result above `e_max - precision + 1` is folded
/// down to that exponent with `clamped` under `clamp`, `false` by default and in
/// every preset (see `with_clamp_fold`).
pub fn DecimalContext::clamp_fold(self : DecimalContext) -> Bool {
  self.clamp_fold
}

///|
/// Returns a copy of the context with the clamp fold-down of zero `quantize`
/// results set to `fold`. IEEE 754-2019 §5.3.2 says nothing about a zero result
/// whose exponent cannot be encoded (above `e_max - precision + 1`, 369 in
/// decimal64): by default `quantize` returns the exponent asked for, as before.
/// With `fold` and `clamp`, the exponent is folded down to the largest encodable
/// one and `clamped` is raised, as `decFinalize` of decNumber does for a zero
/// result. Non-zero results and contexts without `clamp` are not affected.
pub fn DecimalContext::with_clamp_fold(
  self : DecimalContext,
  fold : Bool,
) -> DecimalContext {
  { ..self, clamp_fold: fold, }
}

///|
pub fn DecimalContext::ieee754(self : DecimalContext) -> DecimalContext {
  self
}

///|
fn decimal_exact_work_context() -> DecimalContext {
  {
    precision: 0,
    rounding: RoundingMode::ToNearestEven,
    decimal_rounding: DecimalRoundingMode::HalfEven,
    e_min: decimal_implementation_e_min,
    e_max: decimal_implementation_e_max,
    clamp: false,
    extended: true,
    tininess: DecimalTininessDetection::BeforeRounding,
    refinement_limit: Some(12),
    clamp_fold: false,
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
) -> Result[DecimalContext, @def.ArithmeticError] {
  DecimalContext::try_new(
    precision=ctx.precision,
    rounding=ctx.rounding,
    e_min=ctx.e_min.unwrap_or(decimal_implementation_e_min),
    e_max=ctx.e_max.unwrap_or(decimal_implementation_e_max),
    clamp=ctx.clamp,
  )
}

///|
pub fn DecimalInterchangeFormat::context(
  self : DecimalInterchangeFormat,
) -> DecimalContext {
  match self {
    Decimal32 => DecimalContext::decimal32().ieee754()
    Decimal64 => DecimalContext::decimal64().ieee754()
    Decimal128 => DecimalContext::decimal128().ieee754()
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

///|
pub extend Decimal with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend DecimalRoundingMode with Eq::{not_equal, equal}

///|
pub extend DecimalTininessDetection with Eq::{not_equal, equal}

///|
pub extend DecimalSignal with Eq::{not_equal, equal}

///|
pub extend DecimalInterchangeFormat with Eq::{not_equal, equal}

///|
pub extend DecimalInterchangeEncoding with Eq::{not_equal, equal}

///|
pub extend DecimalContext with Eq::{not_equal, equal}

///|
pub extend DecimalFlags with Eq::{not_equal, equal}

///|
// The kernel's rounding enum has the same eight directions; it is a different
// type so that the kernel does not depend on this package.
fn DecimalRoundingMode::kernel(self : DecimalRoundingMode) -> DecCoeffRounding {
  match self {
    HalfEven => DecCoeffRounding::HalfEven
    HalfUp => DecCoeffRounding::HalfUp
    HalfDown => DecCoeffRounding::HalfDown
    Down => DecCoeffRounding::Down
    Ceiling => DecCoeffRounding::Ceiling
    Floor => DecCoeffRounding::Floor
    Up => DecCoeffRounding::Up
    ZeroFiveUp => DecCoeffRounding::ZeroFiveUp
  }
}
