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
/// The rounding-direction attribute of a decimal context (IEEE 754-2019 4.3):
/// the two to-nearest attributes of 4.3.1 and the three directed ones of 4.3.2.
#derive(Eq)
pub(all) enum DecimalRoundingMode {
  RoundTiesToEven
  RoundTiesToAway
  RoundTowardZero
  RoundTowardPositive
  RoundTowardNegative
}

///|
/// The eight rounding algorithms of the kernels (GDA 1.70 names). Not public:
/// IEEE 754-2019 4.3 has five attributes, and the other three (`HalfDown`, `Up`,
/// `ZeroFiveUp`) are working modes of the certified functions and of the
/// division guard digit.
#derive(Eq)
#warnings("-unused_constructor")
priv enum DecimalRound {
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
  priv decimal_rounding : DecimalRound
  priv e_min : Int32
  priv e_max : Int32
  // Whether finite results are members of the format of `precision` and
  // `e_max` (the exponent `q` of a result is at most `e_max - p + 1`, IEEE
  // 754-2019 3.3). Every public context sets it; the working contexts of the
  // library clear it where the digits of a result must not be folded down.
  priv clamp : Bool
  priv refinement_limit : Int32?
  // The largest precision for which the elementary functions and the `pow`
  // family compute an ordinary operand (`None`: no limit). It takes part in
  // `==` of contexts, like `refinement_limit`.
  priv elementary_precision_limit : Int32?
}

///|
#derive(Eq)
pub struct DecimalFlags {
  priv inexact : Bool
  priv underflow : Bool
  priv overflow : Bool
  priv division_by_zero : Bool
  priv invalid_operation : Bool
  // Raised when a result could not be computed at all (a limit of the
  // implementation, not a property of the operands): the value is NaN.
  priv not_computed : Bool
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
  decimal_flags_none_value
}

///|
/// The empty flag set, built once. Invariant: `DecimalFlags` is an immutable
/// record compared by value (no `mut` field, no setter, every "update" is a
/// copy `{ ..flags, field: v }`), so every `DecimalFlags::new()` may share this
/// one value instead of allocating 6 fields, and `combine` may return one of its
/// operands when the other is clear. The test "the shared empty flag set is
/// never written" pins it.
let decimal_flags_none_value : DecimalFlags = {
  inexact: false,
  underflow: false,
  overflow: false,
  division_by_zero: false,
  invalid_operation: false,
  not_computed: false,
}

///|
fn decimal_flags_are_clear(flags : DecimalFlags) -> Bool {
  !flags.inexact &&
  !flags.underflow &&
  !flags.overflow &&
  !flags.division_by_zero &&
  !flags.invalid_operation &&
  !flags.not_computed
}

///|
/// Whether the `inexact` status flag is set.
pub fn DecimalFlags::inexact(self : DecimalFlags) -> Bool {
  self.inexact
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
/// Whether the `not_computed` status flag is set: the operation could not be
/// carried out within a limit of the implementation and the value is NaN.
pub fn DecimalFlags::not_computed(self : DecimalFlags) -> Bool {
  self.not_computed
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
pub fn DecimalFlags::combine(
  self : DecimalFlags,
  other : DecimalFlags,
) -> DecimalFlags {
  if decimal_flags_are_clear(other) {
    return self
  }
  if decimal_flags_are_clear(self) {
    return other
  }
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
/// True when no usable number is delivered or a division by zero happened:
/// `invalid_operation` (IEEE 754-2019 7.2: no usefully definable result),
/// `not_computed` or `division_by_zero`. Division by zero is included so that
/// the checked arithmetic forms can return `Err`. Overflow, underflow and
/// inexact deliver a usable result and are not errors.
pub fn DecimalFlags::has_error(self : DecimalFlags) -> Bool {
  self.invalid_operation || self.not_computed || self.division_by_zero
}

///|
/// Largest `e_max` that `DecimalContext::try_new` accepts. The certified
/// elementary functions accept a narrower range (`e_max <= 999999` and
/// `p <= 999999`); outside it they return NaN with `not_computed`. See
/// "DecimalContext::new, try_new" in the `decimal` API manual
/// (doc/manual/api/decimal.md).
pub let decimal_implementation_e_max : Int32 = @internal.decimal_exponent_limit

///|
/// Smallest `e_min` of a context, `1 - decimal_implementation_e_max`
/// (IEEE 754-2019 3.3: `e_min = 1 - e_max`). The certified elementary
/// functions have their own, narrower limit (see `decimal_implementation_e_max`).
pub let decimal_implementation_e_min : Int32 = 1 -
  @internal.decimal_exponent_limit

///|
/// Largest precision that `DecimalContext::try_new` accepts. The certified
/// elementary functions have their own, lower limit (see
/// `decimal_implementation_e_max`).
pub let decimal_precision_max : Int32 = @internal.decimal_exponent_limit

///|
/// The exponent range of a context given by its precision alone: the larger of
/// 999,999 (the widest range in which every operation of the package runs) and
/// `1000 p`, which IEEE 754-2019 3.7 requires of an extendable format given by
/// `p` alone (`p` of at least 51 digits). `None` when that exceeds
/// `decimal_implementation_e_max`.
fn decimal_default_e_max(precision : Int32) -> Int32? {
  let wanted = Int64::max(999_999L, precision.to_int64() * 1000L)
  if wanted > decimal_implementation_e_max.to_int64() {
    None
  } else {
    Some(wanted.to_int())
  }
}

///|
/// A context without validation, for the working contexts of the library.
fn DecimalContext::raw(
  precision : Int32,
  e_min : Int32,
  e_max : Int32,
  clamp~ : Bool = false,
  round~ : DecimalRound = DecimalRound::HalfEven,
) -> DecimalContext {
  {
    precision,
    decimal_rounding: round,
    e_min,
    e_max,
    clamp,
    refinement_limit: Some(12),
    elementary_precision_limit: Some(decimal_elementary_precision_limit),
  }
}

///|
fn DecimalContext::build(
  precision~ : Int32,
  rounding~ : DecimalRoundingMode,
  e_max? : Int32,
) -> Result[DecimalContext, String] {
  guard precision >= 1 && precision <= decimal_precision_max else {
    return Err("precision must be within 1..=\{decimal_precision_max}")
  }
  let e_max = match e_max {
    Some(value) => value
    None =>
      match decimal_default_e_max(precision) {
        Some(value) => value
        None =>
          return Err(
            "e_max must be given for precision \{precision}: 1000 * precision exceeds \{decimal_implementation_e_max}",
          )
      }
  }
  guard e_max >= 1 && e_max <= decimal_implementation_e_max else {
    return Err("e_max must be within 1..=\{decimal_implementation_e_max}")
  }
  Ok(
    DecimalContext::raw(
      precision,
      1 - e_max,
      e_max,
      clamp=true,
      round=rounding.round(),
    ),
  )
}

///|
/// Builds the context of an IEEE 754-2019 decimal format with `precision`
/// digits and the exponent range `[1 - e_max, e_max]` (3.3), or aborts with the
/// message that names the invalid parameter (like `BinaryContext::new`).
/// Without `e_max` the range is `max(999999, 1000 * precision)`. `try_new`
/// returns the same check as an `Err` instead.
pub fn DecimalContext::new(
  precision~ : Int32 = 34,
  e_max? : Int32,
  rounding~ : DecimalRoundingMode = DecimalRoundingMode::RoundTiesToEven,
) -> DecimalContext {
  match DecimalContext::build(precision~, rounding~, e_max?) {
    Ok(context) => context
    Err(reason) => abort("DecimalContext::new: " + reason)
  }
}

///|
pub fn DecimalContext::try_new(
  precision~ : Int32 = 34,
  e_max? : Int32,
  rounding~ : DecimalRoundingMode = DecimalRoundingMode::RoundTiesToEven,
) -> Result[DecimalContext, @def.ArithmeticError] {
  match DecimalContext::build(precision~, rounding~, e_max?) {
    Ok(context) => Ok(context)
    Err(reason) => Err(@def.ArithmeticError::domain_error(reason))
  }
}

///|
pub fn DecimalContext::precision(self : DecimalContext) -> Int32 {
  self.precision
}

///|
pub fn DecimalContext::rounding(self : DecimalContext) -> DecimalRoundingMode {
  match self.decimal_rounding.public() {
    Some(mode) => mode
    None => abort("DecimalContext::rounding: internal working rounding mode")
  }
}

///|
pub fn DecimalContext::with_rounding(
  self : DecimalContext,
  rounding : DecimalRoundingMode,
) -> DecimalContext {
  { ..self, decimal_rounding: rounding.round(), }
}

///|
/// The same context with another precision. Aborts when the precision is
/// outside `1..=decimal_precision_max`, like `new`.
pub fn DecimalContext::with_precision(
  self : DecimalContext,
  precision : Int32,
) -> DecimalContext {
  guard precision >= 1 && precision <= decimal_precision_max else {
    abort(
      "DecimalContext::with_precision: precision must be within 1..=\{decimal_precision_max}",
    )
  }
  { ..self, precision, }
}

///|
/// The same context with the exponent range `[1 - e_max, e_max]`. Aborts when
/// `e_max` is outside `1..=decimal_implementation_e_max`, like `new`.
pub fn DecimalContext::with_e_max(
  self : DecimalContext,
  e_max : Int32,
) -> DecimalContext {
  guard e_max >= 1 && e_max <= decimal_implementation_e_max else {
    abort(
      "DecimalContext::with_e_max: e_max must be within 1..=\{decimal_implementation_e_max}",
    )
  }
  { ..self, e_min: 1 - e_max, e_max, }
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
/// The largest context precision, in decimal digits, for which the elementary
/// functions and the `pow` family compute an ordinary operand: `Some(999_999)`
/// by default. `None` means no limit (see `with_elementary_precision_limit`).
pub fn DecimalContext::elementary_precision_limit(
  self : DecimalContext,
) -> Int32? {
  self.elementary_precision_limit
}

///|
/// Returns a copy of the context with the precision limit of the elementary
/// functions and of the `pow` family set to `limit`. `Some(n)` refuses an
/// ordinary operand in a context whose precision is above `n` (`not_computed`,
/// `Err` in the `try_` forms), at once; `None` removes the limit.
///
/// The default is an engineering limit, not a property of the operations: above
/// it the library does not bound the running time or the memory, and that range
/// is not covered by the conformance gates, with no guarantee. The results come
/// from the same certified kernels, so a returned value is still correctly
/// rounded. Where the certified kernel cannot represent the working precision
/// (above 80,807,093 digits) the functions that go through it return the
/// context-limit error whatever the limit (`decimal_certified_work_refusal`);
/// the square-root route of `pow` (exponent 0.5, `sqrt_ctx`) and the exact
/// routes are not refused there and run on. The cases that IEEE 754-2019 9.2.1
/// lists are values whatever the limit.
pub fn DecimalContext::with_elementary_precision_limit(
  self : DecimalContext,
  limit : Int32?,
) -> DecimalContext {
  { ..self, elementary_precision_limit: limit, }
}

///|
/// The working context of the exact steps of the library: precision 0 means
/// "every digit". Not a context of any IEEE format and not public.
fn decimal_exact_work_context() -> DecimalContext {
  DecimalContext::raw(
    0, decimal_implementation_e_min, decimal_implementation_e_max,
  )
}

///|
pub fn DecimalContext::decimal32(
  rounding~ : DecimalRoundingMode = DecimalRoundingMode::RoundTiesToEven,
) -> DecimalContext {
  DecimalContext::new(precision=7, e_max=96, rounding~)
}

///|
pub fn DecimalContext::decimal64(
  rounding~ : DecimalRoundingMode = DecimalRoundingMode::RoundTiesToEven,
) -> DecimalContext {
  DecimalContext::new(precision=16, e_max=384, rounding~)
}

///|
pub fn DecimalContext::decimal128(
  rounding~ : DecimalRoundingMode = DecimalRoundingMode::RoundTiesToEven,
) -> DecimalContext {
  DecimalContext::new(precision=34, e_max=6144, rounding~)
}

///|
pub fn DecimalContext::from_arithmetic_context(
  ctx : @lf_arith.ArithmeticContext,
) -> Result[DecimalContext, @def.ArithmeticError] {
  let rounding = match DecimalRoundingMode::from_arithmetic(ctx.rounding) {
    Some(mode) => mode
    None =>
      return Err(
        @def.ArithmeticError::domain_error(
          "AwayFromZero is not a rounding-direction attribute of IEEE 754-2019 4.3",
        ),
      )
  }
  // `clamp` is a property of every IEEE format, not an option: it is ignored.
  let e_max = match (ctx.e_min, ctx.e_max) {
    (_, Some(e_max)) => {
      match ctx.e_min {
        Some(e_min) if e_min != 1 - e_max =>
          return Err(
            @def.ArithmeticError::domain_error(
              "e_min must be 1 - e_max (IEEE 754-2019 3.3)",
            ),
          )
        _ => ()
      }
      Some(e_max)
    }
    (Some(e_min), None) => Some(1 - e_min)
    (None, None) => None
  }
  DecimalContext::try_new(precision=ctx.precision, e_max?, rounding~)
}

///|
pub fn DecimalInterchangeFormat::context(
  self : DecimalInterchangeFormat,
) -> DecimalContext {
  match self {
    Decimal32 => DecimalContext::decimal32()
    Decimal64 => DecimalContext::decimal64()
    Decimal128 => DecimalContext::decimal128()
  }
}

///|
/// The IEEE rounding attribute for an `@arithmetic` mode; `None` for
/// `AwayFromZero`, which IEEE 754-2019 4.3 does not define.
pub fn DecimalRoundingMode::from_arithmetic(
  mode : RoundingMode,
) -> DecimalRoundingMode? {
  match mode {
    RoundingMode::ToNearestEven => Some(RoundTiesToEven)
    RoundingMode::TowardZero => Some(RoundTowardZero)
    RoundingMode::TowardPositive => Some(RoundTowardPositive)
    RoundingMode::TowardNegative => Some(RoundTowardNegative)
    RoundingMode::AwayFromZero => None
  }
}

///|
/// The `@arithmetic` mode for an attribute; `None` for `RoundTiesToAway`.
pub fn DecimalRoundingMode::to_arithmetic(
  self : DecimalRoundingMode,
) -> RoundingMode? {
  match self {
    RoundTiesToEven => Some(RoundingMode::ToNearestEven)
    RoundTowardZero => Some(RoundingMode::TowardZero)
    RoundTowardPositive => Some(RoundingMode::TowardPositive)
    RoundTowardNegative => Some(RoundingMode::TowardNegative)
    RoundTiesToAway => None
  }
}

///|
fn DecimalRoundingMode::round(self : DecimalRoundingMode) -> DecimalRound {
  match self {
    RoundTiesToEven => HalfEven
    RoundTiesToAway => HalfUp
    RoundTowardZero => Down
    RoundTowardPositive => Ceiling
    RoundTowardNegative => Floor
  }
}

///|
fn DecimalRound::public(self : DecimalRound) -> DecimalRoundingMode? {
  match self {
    HalfEven => Some(RoundTiesToEven)
    HalfUp => Some(RoundTiesToAway)
    Down => Some(RoundTowardZero)
    Ceiling => Some(RoundTowardPositive)
    Floor => Some(RoundTowardNegative)
    HalfDown | Up | ZeroFiveUp => None
  }
}

///|
pub extend Decimal with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend DecimalRoundingMode with Eq::{not_equal, equal}

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
fn DecimalRound::kernel(self : DecimalRound) -> DecCoeffRounding {
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
