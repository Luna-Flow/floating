///|
#derive(Eq, Debug)
pub(all) enum BinaryRoundingMode {
  RoundTiesToEven
  RoundTiesToAway
  RoundTowardZero
  RoundTowardPositive
  RoundTowardNegative
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
/// Largest exponent of the leading bit that a finite `BinFloat` may carry, and
/// the `e_max` of a context given by its precision alone (the extendable
/// precision format of IEEE 754-2019 3.7).
pub let binary_implementation_e_max : Int32 = 1073741823

///|
/// Smallest normal leading-bit exponent, `1 - binary_implementation_e_max`
/// (IEEE 754-2019 3.3: `emin = 1 - emax`), with gradual underflow below it. It is
/// the `e_min` of every context whose `e_max` is the implementation limit, and
/// no stored value has a leading bit below `e_min - precision + 1`.
pub let binary_implementation_e_min : Int32 = -1073741822

///|
/// Largest context precision. Together with the exponent range above it keeps
/// every coefficient exponent inside the 32-bit `Int` range.
pub let binary_precision_max : Int32 = 268435456

///|
#derive(Eq, Debug)
pub struct BinaryContext {
  priv precision : Int32
  priv rounding : BinaryRoundingMode
  priv e_max : Int32
  // 0 for every public context; the internal range shift of decimal parsing
  priv e_min_offset : Int32
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
  priv not_computed : Bool
}

///|
pub fn BinaryFlags::new() -> BinaryFlags {
  {
    inexact: false,
    underflow: false,
    overflow: false,
    division_by_zero: false,
    invalid_operation: false,
    not_computed: false,
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
    not_computed: self.not_computed || other.not_computed,
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
/// Whether the `not_computed` flag is set: the operation could not be carried out
/// within a limit of the implementation (a certification that did not conclude, a
/// context beyond what the kernels support) and the value is a NaN. It is not a
/// flag of IEEE 754-2019 and is distinct from `invalid_operation`, which reports an
/// operation whose result the standard defines as invalid.
pub fn BinaryFlags::not_computed(self : BinaryFlags) -> Bool {
  self.not_computed
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
/// The IEEE 754-2019 4.3 attribute of an `@arithmetic` rounding mode, or `None`
/// for `AwayFromZero`, which is not one of them.
pub fn BinaryRoundingMode::from_arithmetic(
  mode : RoundingMode,
) -> BinaryRoundingMode? {
  match mode {
    RoundingMode::ToNearestEven => Some(RoundTiesToEven)
    RoundingMode::TowardZero => Some(RoundTowardZero)
    RoundingMode::TowardPositive => Some(RoundTowardPositive)
    RoundingMode::TowardNegative => Some(RoundTowardNegative)
    RoundingMode::AwayFromZero => None
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
  }
}

///|
fn binary_context_error(
  operation : String,
  precision : Int32,
  e_max : Int32,
) -> String? {
  if precision < 1 || precision > binary_precision_max {
    Some(
      "\{operation}: precision must be within 1..=\{binary_precision_max} (got \{precision})",
    )
  } else if e_max < 1 || e_max > binary_implementation_e_max {
    Some(
      "\{operation}: e_max must be within 1..=\{binary_implementation_e_max} (got \{e_max})",
    )
  } else {
    None
  }
}

///|
/// A context of IEEE 754-2019 3.3: the precision `p`, the exponent `e_max` and
/// `e_min = 1 - e_max`, a rounding-direction attribute (4.3) and a tininess
/// rule (7.5). Without `e_max` the context is the extendable precision format
/// of 3.7 given by `p` alone, whose `e_max` is `binary_implementation_e_max`.
/// Aborts on a precision outside `1..=binary_precision_max` or an `e_max`
/// outside `1..=binary_implementation_e_max`.
pub fn BinaryContext::new(
  precision~ : Int32 = 53,
  e_max? : Int32,
  rounding~ : BinaryRoundingMode = BinaryRoundingMode::RoundTiesToEven,
  tininess~ : TininessDetection = TininessDetection::AfterRounding,
) -> BinaryContext {
  let e_max = match e_max {
    Some(value) => value
    None => binary_implementation_e_max
  }
  match binary_context_error("BinaryContext::new", precision, e_max) {
    Some(error) => abort(error)
    None => ()
  }
  {
    precision,
    rounding,
    e_max,
    e_min_offset: 0,
    tininess,
    refinement_limit: Some(12),
  }
}

///|
/// `new` returning an error instead of aborting.
pub fn BinaryContext::try_new(
  precision~ : Int32 = 53,
  e_max? : Int32,
  rounding~ : BinaryRoundingMode = BinaryRoundingMode::RoundTiesToEven,
  tininess~ : TininessDetection = TininessDetection::AfterRounding,
) -> Result[BinaryContext, @def.ArithmeticError] {
  let e_max = match e_max {
    Some(value) => value
    None => binary_implementation_e_max
  }
  match binary_context_error("BinaryContext::try_new", precision, e_max) {
    Some(error) => Err(@def.ArithmeticError::domain_error(error))
    None =>
      Ok({
        precision,
        rounding,
        e_max,
        e_min_offset: 0,
        tininess,
        refinement_limit: Some(12),
      })
  }
}

///|
/// The working context of the kernels: `precision` bits in the implementation
/// range, not validated (a work precision may exceed `binary_precision_max`).
fn binary_working_context(
  precision : Int32,
  rounding~ : BinaryRoundingMode = BinaryRoundingMode::RoundTiesToEven,
) -> BinaryContext {
  {
    precision,
    rounding,
    e_max: binary_implementation_e_max,
    e_min_offset: 0,
    tininess: TininessDetection::AfterRounding,
    refinement_limit: Some(12),
  }
}

///|
/// The context of an `@arithmetic.ArithmeticContext`. `AwayFromZero` is not an
/// IEEE 754-2019 attribute, an `e_min` must equal `1 - e_max` (an `e_min` alone
/// gives `e_max = 1 - e_min`), and the precision must be within
/// `1..=binary_precision_max`; otherwise the result is an error. `clamp` is
/// ignored.
pub fn BinaryContext::from_arithmetic_context(
  context : @lf_arith.ArithmeticContext,
) -> Result[BinaryContext, @def.ArithmeticError] {
  guard BinaryRoundingMode::from_arithmetic(context.rounding) is Some(rounding) else {
    return Err(
      @def.ArithmeticError::domain_error(
        "BinaryContext::from_arithmetic_context: AwayFromZero is not an IEEE 754-2019 rounding-direction attribute",
      ),
    )
  }
  match (context.e_min, context.e_max) {
    (Some(e_min), Some(e_max)) =>
      if e_min != 1 - e_max {
        Err(
          @def.ArithmeticError::domain_error(
            "BinaryContext::from_arithmetic_context: e_min must be 1 - e_max (IEEE 754-2019 3.3)",
          ),
        )
      } else {
        BinaryContext::try_new(precision=context.precision, e_max~, rounding~)
      }
    (Some(e_min), None) =>
      BinaryContext::try_new(
        precision=context.precision,
        e_max=1 - e_min,
        rounding~,
      )
    (None, Some(e_max)) =>
      BinaryContext::try_new(precision=context.precision, e_max~, rounding~)
    (None, None) =>
      BinaryContext::try_new(precision=context.precision, rounding~)
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
/// A copy with another precision; aborts outside `1..=binary_precision_max`.
pub fn BinaryContext::with_precision(
  self : BinaryContext,
  precision : Int32,
) -> BinaryContext {
  match
    binary_context_error("BinaryContext::with_precision", precision, self.e_max) {
    Some(error) => abort(error)
    None => { ..self, precision, }
  }
}

///|
pub fn BinaryContext::with_rounding(
  self : BinaryContext,
  rounding : BinaryRoundingMode,
) -> BinaryContext {
  { ..self, rounding, }
}

///|
/// A copy with another `e_max` (and so `e_min = 1 - e_max`); aborts outside
/// `1..=binary_implementation_e_max`.
pub fn BinaryContext::with_e_max(
  self : BinaryContext,
  e_max : Int32,
) -> BinaryContext {
  match
    binary_context_error("BinaryContext::with_e_max", self.precision, e_max) {
    Some(error) => abort(error)
    None => { ..self, e_max, }
  }
}

///|
pub fn BinaryContext::with_tininess(
  self : BinaryContext,
  tininess : TininessDetection,
) -> BinaryContext {
  { ..self, tininess, }
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
/// The smallest exponent of a normal number, `1 - e_max`.
pub fn BinaryContext::e_min(self : BinaryContext) -> Int32 {
  self.range_e_min()
}

///|
pub fn BinaryContext::e_max(self : BinaryContext) -> Int32 {
  self.e_max
}

///|
pub fn BinaryContext::tininess(self : BinaryContext) -> TininessDetection {
  self.tininess
}

///|
fn BinaryContext::range_e_max(self : BinaryContext) -> Int32 {
  self.e_max
}

///|
fn BinaryContext::range_e_min(self : BinaryContext) -> Int32 {
  1 - self.e_max + self.e_min_offset
}

///|
/// The context with both bounds moved down by `shift` (decimal parsing rounds a
/// product in a range shifted by the power of two it factors out); not a
/// 3.3-shaped context, and never visible to a caller.
fn BinaryContext::shifted_range(
  self : BinaryContext,
  shift : Int64,
) -> BinaryContext {
  let e_max = (self.e_max.to_int64() - shift).to_int()
  let e_min = (self.range_e_min().to_int64() - shift).to_int()
  { ..self, e_max, e_min_offset: e_min - (1 - e_max), }
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
    precision=self.precision(),
    e_max=self.e_max(),
    rounding~,
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
