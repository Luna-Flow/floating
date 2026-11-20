///|
#derive(Eq, Debug)
pub(all) enum BinaryRoundingMode {
  RoundTiesToEven
  RoundTiesToAway
  RoundTowardZero
  RoundTowardPositive
  RoundTowardNegative
  RoundAwayFromZero
}

///|
#derive(Eq, Debug)
pub(all) enum TininessDetection {
  BeforeRounding
  AfterRounding
}

///|
#derive(Eq, Debug)
pub(all) enum BinaryInterchangeFormat {
  Binary16
  Binary32
  Binary64
  Binary128
}

///|
/// Largest exponent of the leading bit that a finite `BinFloat` may carry.
/// Unbounded contexts use this as their effective `e_max`.
pub let binary_implementation_e_max : Int32 = 1073741823

///|
/// Smallest normal leading-bit exponent. Unbounded contexts use this as their
/// effective `e_min`, with gradual underflow below it.
pub let binary_implementation_e_min : Int32 = -1073741823

///|
/// Largest context precision. Together with the exponent range above it keeps
/// every coefficient exponent inside the 32-bit `Int` range.
pub let binary_precision_max : Int32 = 268435456

///|
#derive(Eq, Debug)
pub struct BinaryContext {
  priv precision : Int32
  priv rounding : BinaryRoundingMode
  priv e_min : Int32?
  priv e_max : Int32?
  priv tininess : TininessDetection
  priv refinement_limit : Int32?
}

///|
#derive(Eq, Debug)
pub struct BinaryFlags {
  priv inexact : Bool
  priv underflow : Bool
  priv overflow : Bool
  priv division_by_zero : Bool
  priv invalid_operation : Bool
}

///|
pub fn BinaryFlags::new() -> BinaryFlags {
  {
    inexact: false,
    underflow: false,
    overflow: false,
    division_by_zero: false,
    invalid_operation: false,
  }
}

///|
pub fn BinaryFlags::combine(
  self : BinaryFlags,
  other : BinaryFlags,
) -> BinaryFlags {
  {
    inexact: self.inexact || other.inexact,
    underflow: self.underflow || other.underflow,
    overflow: self.overflow || other.overflow,
    division_by_zero: self.division_by_zero || other.division_by_zero,
    invalid_operation: self.invalid_operation || other.invalid_operation,
  }
}

///|
pub fn BinaryFlags::inexact(self : BinaryFlags) -> Bool {
  self.inexact
}

///|
pub fn BinaryFlags::underflow(self : BinaryFlags) -> Bool {
  self.underflow
}

///|
pub fn BinaryFlags::overflow(self : BinaryFlags) -> Bool {
  self.overflow
}

///|
pub fn BinaryFlags::division_by_zero(self : BinaryFlags) -> Bool {
  self.division_by_zero
}

///|
pub fn BinaryFlags::invalid_operation(self : BinaryFlags) -> Bool {
  self.invalid_operation
}

///|
fn binary_inexact_flags(underflow : Bool) -> BinaryFlags {
  { ..BinaryFlags::new(), inexact: true, underflow, }
}

///|
fn binary_overflow_flags() -> BinaryFlags {
  { ..BinaryFlags::new(), inexact: true, overflow: true, }
}

///|
fn binary_division_by_zero_flags() -> BinaryFlags {
  { ..BinaryFlags::new(), division_by_zero: true, }
}

///|
fn binary_invalid_flags() -> BinaryFlags {
  { ..BinaryFlags::new(), invalid_operation: true, }
}

///|
pub fn BinaryRoundingMode::from_arithmetic(
  mode : RoundingMode,
) -> BinaryRoundingMode {
  match mode {
    RoundingMode::ToNearestEven => RoundTiesToEven
    RoundingMode::TowardZero => RoundTowardZero
    RoundingMode::TowardPositive => RoundTowardPositive
    RoundingMode::TowardNegative => RoundTowardNegative
    RoundingMode::AwayFromZero => RoundAwayFromZero
  }
}

///|
pub fn BinaryRoundingMode::to_arithmetic(
  self : BinaryRoundingMode,
) -> RoundingMode? {
  match self {
    RoundTiesToEven => Some(RoundingMode::ToNearestEven)
    RoundTiesToAway => None
    RoundTowardZero => Some(RoundingMode::TowardZero)
    RoundTowardPositive => Some(RoundingMode::TowardPositive)
    RoundTowardNegative => Some(RoundingMode::TowardNegative)
    RoundAwayFromZero => Some(RoundingMode::AwayFromZero)
  }
}

///|
pub fn BinaryContext::new(
  precision : Int32,
  rounding~ : BinaryRoundingMode = BinaryRoundingMode::RoundTiesToEven,
  e_min? : Int32,
  e_max? : Int32,
  tininess~ : TininessDetection = TininessDetection::AfterRounding,
) -> BinaryContext {
  guard precision > 0 else {
    abort("BinaryContext::new: precision must be positive")
  }
  guard precision <= binary_precision_max else {
    abort("BinaryContext::new: precision exceeds binary_precision_max")
  }
  match (e_min, e_max) {
    (Some(lower), Some(upper)) => {
      guard lower <= upper else {
        abort("BinaryContext::new: e_min must not exceed e_max")
      }
    }
    _ => ()
  }
  { precision, rounding, e_min, e_max, tininess, refinement_limit: Some(12), }
}

///|
pub fn BinaryContext::try_new(
  precision : Int32,
  rounding~ : BinaryRoundingMode = BinaryRoundingMode::RoundTiesToEven,
  e_min? : Int32,
  e_max? : Int32,
  tininess~ : TininessDetection = TininessDetection::AfterRounding,
) -> Result[BinaryContext, @def.ArithmeticError] {
  guard precision > 0 else {
    return Err(
      @def.ArithmeticError::domain_error(
        "BinaryContext::try_new: precision must be positive",
      ),
    )
  }
  guard precision <= binary_precision_max else {
    return Err(
      @def.ArithmeticError::domain_error(
        "BinaryContext::try_new: precision exceeds binary_precision_max",
      ),
    )
  }
  match (e_min, e_max) {
    (Some(lower), Some(upper)) if lower <= upper => ()
    (Some(_), None) | (None, Some(_)) | (None, None) => ()
    (Some(_), Some(_)) =>
      return Err(
        @def.ArithmeticError::domain_error(
          "BinaryContext::try_new: e_min must not exceed e_max",
        ),
      )
  }
  Ok({
    precision,
    rounding,
    e_min,
    e_max,
    tininess,
    refinement_limit: Some(12),
  })
}

///|
pub fn BinaryContext::unbounded(
  precision : Int32,
  rounding~ : BinaryRoundingMode = BinaryRoundingMode::RoundTiesToEven,
) -> BinaryContext {
  BinaryContext::new(precision, rounding~)
}

///|
pub fn BinaryContext::from_arithmetic_context(
  context : @lf_arith.ArithmeticContext,
) -> BinaryContext {
  let rounding = BinaryRoundingMode::from_arithmetic(context.rounding)
  match (context.e_min, context.e_max) {
    (Some(e_min), Some(e_max)) =>
      BinaryContext::new(context.precision, rounding~, e_min~, e_max~)
    (Some(e_min), None) =>
      BinaryContext::new(context.precision, rounding~, e_min~)
    (None, Some(e_max)) =>
      BinaryContext::new(context.precision, rounding~, e_max~)
    (None, None) => BinaryContext::unbounded(context.precision, rounding~)
  }
}

///|
/// The number of refinement steps the certified elementary functions may take
/// before they report a certification failure, `Some(12)` by default. `None`
/// means no count limit; the work precision still stops at a resource bound
/// (see `with_refinement_limit`).
pub fn BinaryContext::refinement_limit(self : BinaryContext) -> Int32? {
  self.refinement_limit
}

///|
/// Returns a copy of the context with the refinement limit of the certified
/// elementary functions set to `limit`. `None` removes the count limit; the work
/// precision of the loop is then bounded by `binary_refinement_work_cap`. A
/// limit below 1 is clamped to 1 refinement step.
pub fn BinaryContext::with_refinement_limit(
  self : BinaryContext,
  limit : Int32?,
) -> BinaryContext {
  { ..self, refinement_limit: limit, }
}

///|
pub fn BinaryContext::precision(self : BinaryContext) -> Int32 {
  self.precision
}

///|
pub fn BinaryContext::rounding(self : BinaryContext) -> BinaryRoundingMode {
  self.rounding
}

///|
pub fn BinaryContext::e_min(self : BinaryContext) -> Int32? {
  self.e_min
}

///|
pub fn BinaryContext::e_max(self : BinaryContext) -> Int32? {
  self.e_max
}

///|
pub fn BinaryContext::tininess(self : BinaryContext) -> TininessDetection {
  self.tininess
}

///|
fn BinaryContext::range_e_max(self : BinaryContext) -> Int32 {
  match self.e_max {
    Some(e_max) => Int32::min(e_max, binary_implementation_e_max)
    None => binary_implementation_e_max
  }
}

///|
fn BinaryContext::range_e_min(self : BinaryContext) -> Int32 {
  match self.e_min {
    Some(e_min) => Int32::max(e_min, binary_implementation_e_min)
    None => binary_implementation_e_min
  }
}

///|
pub fn BinaryInterchangeFormat::precision(
  self : BinaryInterchangeFormat,
) -> Int32 {
  match self {
    Binary16 => 11
    Binary32 => 24
    Binary64 => 53
    Binary128 => 113
  }
}

///|
pub fn BinaryInterchangeFormat::e_min(self : BinaryInterchangeFormat) -> Int32 {
  match self {
    Binary16 => -14
    Binary32 => -126
    Binary64 => -1022
    Binary128 => -16382
  }
}

///|
pub fn BinaryInterchangeFormat::e_max(self : BinaryInterchangeFormat) -> Int32 {
  match self {
    Binary16 => 15
    Binary32 => 127
    Binary64 => 1023
    Binary128 => 16383
  }
}

///|
pub fn BinaryInterchangeFormat::context(
  self : BinaryInterchangeFormat,
  rounding~ : BinaryRoundingMode = BinaryRoundingMode::RoundTiesToEven,
  tininess~ : TininessDetection = TininessDetection::AfterRounding,
) -> BinaryContext {
  BinaryContext::new(
    self.precision(),
    rounding~,
    e_min=self.e_min(),
    e_max=self.e_max(),
    tininess~,
  )
}

///|
pub fn BinaryContext::binary16(
  rounding~ : BinaryRoundingMode = BinaryRoundingMode::RoundTiesToEven,
  tininess~ : TininessDetection = TininessDetection::AfterRounding,
) -> BinaryContext {
  BinaryInterchangeFormat::Binary16.context(rounding~, tininess~)
}

///|
pub fn BinaryContext::binary32(
  rounding~ : BinaryRoundingMode = BinaryRoundingMode::RoundTiesToEven,
  tininess~ : TininessDetection = TininessDetection::AfterRounding,
) -> BinaryContext {
  BinaryInterchangeFormat::Binary32.context(rounding~, tininess~)
}

///|
pub fn BinaryContext::binary64(
  rounding~ : BinaryRoundingMode = BinaryRoundingMode::RoundTiesToEven,
  tininess~ : TininessDetection = TininessDetection::AfterRounding,
) -> BinaryContext {
  BinaryInterchangeFormat::Binary64.context(rounding~, tininess~)
}

///|
pub fn BinaryContext::binary128(
  rounding~ : BinaryRoundingMode = BinaryRoundingMode::RoundTiesToEven,
  tininess~ : TininessDetection = TininessDetection::AfterRounding,
) -> BinaryContext {
  BinaryInterchangeFormat::Binary128.context(rounding~, tininess~)
}

///|
pub extend BinaryRoundingMode with Eq::{not_equal, equal}

///|
pub extend BinaryRoundingMode with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend TininessDetection with Eq::{not_equal, equal}

///|
pub extend TininessDetection with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend BinaryInterchangeFormat with Eq::{not_equal, equal}

///|
pub extend BinaryInterchangeFormat with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend BinaryContext with Eq::{not_equal, equal}

///|
pub extend BinaryContext with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend BinaryFlags with Eq::{not_equal, equal}

///|
pub extend BinaryFlags with @moonbitlang/core/debug.Debug::{to_repr}
