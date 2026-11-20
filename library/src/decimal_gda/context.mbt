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
priv enum DecimalRoundingMode {
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
pub(all) enum GdaInterchangeFormat {
  Decimal32
  Decimal64
  Decimal128
}

///|
pub struct GdaInterchange {
  priv format : GdaInterchangeFormat
  priv bits : BigInt
}

///|
priv struct DecimalContext {
  precision : Int32
  rounding : RoundingMode
  decimal_rounding : DecimalRoundingMode
  e_min : Int32
  e_max : Int32
  clamp : Bool
  extended : Bool
  refinement_limit : Int32?
}

///|
#derive(Eq)
priv struct DecimalFlags {
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
let decimal_exp_boundary_cache_capacity = 8

///|
let decimal_exp_boundary_cache_next : @ref.Ref[Int32] = @ref.Ref(0)

///|
fn DecimalFlags::new() -> DecimalFlags {
  decimal_flags_none_value
}

///|
/// The empty flag set, built once: the record is immutable, so every
/// `DecimalFlags::new()` shares it instead of allocating 13 fields.
let decimal_flags_none_value : DecimalFlags = {
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

///|
fn DecimalFlags::combine(
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
fn DecimalFlags::has_error(self : DecimalFlags) -> Bool {
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
fn DecimalContext::build(
  precision~ : Int32 = 34,
  rounding~ : RoundingMode = RoundingMode::ToNearestEven,
  decimal_rounding? : DecimalRoundingMode,
  e_min~ : Int32 = -999_999_999,
  e_max~ : Int32 = 999_999_999,
  clamp~ : Bool = false,
  extended~ : Bool = true,
) -> Result[DecimalContext, String] {
  let bounds = @internal.DecimalExponentBounds::new(precision, e_min, e_max)
  guard bounds.is_valid() else {
    let reason = if precision <= 0 || precision > 999_999_999 {
      "precision must be within 1..=999999999"
    } else if e_min < -999_999_999 || e_min > 0 {
      "e_min must be within -999999999..=0"
    } else if e_max < 0 || e_max > 999_999_999 {
      "e_max must be within 0..=999999999"
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
    refinement_limit: Some(12),
  })
}

///|
/// Builds a context, or aborts with the message that names the invalid
/// parameter (like `BinaryContext::new`). `try_new` returns the same check as
/// an `Err` instead.
fn DecimalContext::new(
  precision~ : Int32 = 34,
  rounding~ : RoundingMode = RoundingMode::ToNearestEven,
  decimal_rounding? : DecimalRoundingMode,
  e_min~ : Int32 = -999_999_999,
  e_max~ : Int32 = 999_999_999,
  clamp~ : Bool = false,
  extended~ : Bool = true,
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
    ) {
    Ok(context) => context
    Err(reason) => abort("DecimalContext::new: " + reason)
  }
}

///|
fn DecimalContext::try_new(
  precision~ : Int32 = 34,
  rounding~ : RoundingMode = RoundingMode::ToNearestEven,
  decimal_rounding? : DecimalRoundingMode,
  e_min~ : Int32 = -999_999_999,
  e_max~ : Int32 = 999_999_999,
  clamp~ : Bool = false,
  extended~ : Bool = true,
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
    ) {
    Ok(context) => Ok(context)
    Err(reason) => Err(@def.ArithmeticError::domain_error(reason))
  }
}

///|
fn DecimalContext::e_min(self : DecimalContext) -> Int32 {
  self.e_min
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
    refinement_limit: Some(12),
  }
}

///|
fn DecimalContext::decimal32() -> DecimalContext {
  DecimalContext::new(
    precision=7,
    rounding=RoundingMode::ToNearestEven,
    e_min=-95,
    e_max=96,
    clamp=true,
  )
}

///|
fn DecimalContext::decimal64() -> DecimalContext {
  DecimalContext::new(
    precision=16,
    rounding=RoundingMode::ToNearestEven,
    e_min=-383,
    e_max=384,
    clamp=true,
  )
}

///|
fn DecimalContext::decimal128() -> DecimalContext {
  DecimalContext::new(
    precision=34,
    rounding=RoundingMode::ToNearestEven,
    e_min=-6143,
    e_max=6144,
    clamp=true,
  )
}

///|
fn DecimalContext::from_arithmetic_context(
  ctx : @lf_arith.ArithmeticContext,
) -> Result[DecimalContext, @def.ArithmeticError] {
  DecimalContext::try_new(
    precision=ctx.precision,
    rounding=ctx.rounding,
    e_min=ctx.e_min.unwrap_or(-999_999_999),
    e_max=ctx.e_max.unwrap_or(999_999_999),
    clamp=ctx.clamp,
  )
}

///|
fn GdaInterchangeFormat::decimal_context(
  self : GdaInterchangeFormat,
) -> DecimalContext {
  match self {
    Decimal32 => DecimalContext::decimal32()
    Decimal64 => DecimalContext::decimal64()
    Decimal128 => DecimalContext::decimal128()
  }
}

///|
fn DecimalRoundingMode::from_arithmetic(
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
pub extend Decimal with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend GdaInterchangeFormat with Eq::{not_equal, equal}

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

///|
/// The extended default context of the interchange format (GDA 1.70, Default
/// contexts, page 16): precision 7, 16 or 34, round-half-even, no traps.
pub fn GdaInterchangeFormat::context(self : GdaInterchangeFormat) -> GdaContext {
  match self {
    Decimal32 => GdaContext::decimal32()
    Decimal64 => GdaContext::decimal64()
    Decimal128 => GdaContext::decimal128()
  }
}

///|
/// The number of refinement steps the certified elementary functions may take
/// before they report a certification failure, `Some(12)` by default. `None`
/// means no count limit; the work precision still stops at a resource bound
/// (see `with_refinement_limit`).
fn DecimalContext::refinement_limit(self : DecimalContext) -> Int32? {
  self.refinement_limit
}

///|
/// Returns a copy of the context with the refinement limit of the certified
/// elementary functions set to `limit`. `None` removes the count limit; the work
/// precision of each loop is then bounded (at least 8,000,000 bits, or 256 times
/// the initial work precision). A limit below 1 is clamped to 1 refinement step.
fn DecimalContext::with_refinement_limit(
  self : DecimalContext,
  limit : Int32?,
) -> DecimalContext {
  { ..self, refinement_limit: limit, }
}
