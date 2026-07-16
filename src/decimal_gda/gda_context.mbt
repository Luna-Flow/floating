///|
pub(all) enum GdaRoundingMode {
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
pub(all) enum GdaSignal {
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
pub struct GdaFlags {
  conversion_syntax : Bool
  division_by_zero : Bool
  division_impossible : Bool
  division_undefined : Bool
  invalid_context : Bool
  invalid_operation : Bool
  overflow : Bool
  underflow : Bool
  subnormal : Bool
  inexact : Bool
  rounded : Bool
  clamped : Bool
  lost_digits : Bool
} derive(Eq)

///|
pub struct GdaTrapSet {
  conversion_syntax : Bool
  division_by_zero : Bool
  division_impossible : Bool
  division_undefined : Bool
  invalid_context : Bool
  invalid_operation : Bool
  overflow : Bool
  underflow : Bool
  subnormal : Bool
  inexact : Bool
  rounded : Bool
  clamped : Bool
  lost_digits : Bool
} derive(Eq)

///|
pub struct GdaContext {
  priv precision_ : Int
  priv rounding_ : GdaRoundingMode
  priv e_min_ : Int
  priv e_max_ : Int
  priv clamp_ : Bool
  priv extended_ : Bool
  priv status_ : GdaFlags
  priv traps_ : GdaTrapSet
}

///|
pub(all) enum GdaOutcome[T] {
  Completed(T, GdaContext, GdaFlags)
  Trapped(GdaSignal, T, GdaContext, GdaFlags)
}

///|
pub fn GdaFlags::none() -> GdaFlags {
  {
    conversion_syntax: false,
    division_by_zero: false,
    division_impossible: false,
    division_undefined: false,
    invalid_context: false,
    invalid_operation: false,
    overflow: false,
    underflow: false,
    subnormal: false,
    inexact: false,
    rounded: false,
    clamped: false,
    lost_digits: false,
  }
}

///|
pub fn GdaFlags::contains(self : GdaFlags, signal : GdaSignal) -> Bool {
  match signal {
    ConversionSyntax => self.conversion_syntax
    DivisionByZero => self.division_by_zero
    DivisionImpossible => self.division_impossible
    DivisionUndefined => self.division_undefined
    InvalidContext => self.invalid_context
    InvalidOperation =>
      self.invalid_operation ||
      self.conversion_syntax ||
      self.division_impossible ||
      self.division_undefined ||
      self.invalid_context
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
pub fn GdaFlags::combine(self : GdaFlags, other : GdaFlags) -> GdaFlags {
  {
    conversion_syntax: self.conversion_syntax || other.conversion_syntax,
    division_by_zero: self.division_by_zero || other.division_by_zero,
    division_impossible: self.division_impossible || other.division_impossible,
    division_undefined: self.division_undefined || other.division_undefined,
    invalid_context: self.invalid_context || other.invalid_context,
    invalid_operation: self.invalid_operation || other.invalid_operation,
    overflow: self.overflow || other.overflow,
    underflow: self.underflow || other.underflow,
    subnormal: self.subnormal || other.subnormal,
    inexact: self.inexact || other.inexact,
    rounded: self.rounded || other.rounded,
    clamped: self.clamped || other.clamped,
    lost_digits: self.lost_digits || other.lost_digits,
  }
}

///|
fn gda_flags_from_decimal(flags : DecimalFlags) -> GdaFlags {
  {
    conversion_syntax: flags.conversion_syntax,
    division_by_zero: flags.division_by_zero,
    division_impossible: flags.division_impossible,
    division_undefined: flags.division_undefined,
    invalid_context: flags.invalid_context,
    invalid_operation: flags.invalid_operation,
    overflow: flags.overflow,
    underflow: flags.underflow,
    subnormal: flags.subnormal,
    inexact: flags.inexact,
    rounded: flags.rounded,
    clamped: flags.clamped,
    lost_digits: flags.lost_digits,
  }
}

///|
fn decimal_flags_are_clear(flags : DecimalFlags) -> Bool {
  !flags.conversion_syntax &&
  !flags.division_by_zero &&
  !flags.division_impossible &&
  !flags.division_undefined &&
  !flags.invalid_context &&
  !flags.invalid_operation &&
  !flags.overflow &&
  !flags.underflow &&
  !flags.subnormal &&
  !flags.inexact &&
  !flags.rounded &&
  !flags.clamped &&
  !flags.lost_digits
}

///|
pub fn GdaTrapSet::none() -> GdaTrapSet {
  {
    conversion_syntax: false,
    division_by_zero: false,
    division_impossible: false,
    division_undefined: false,
    invalid_context: false,
    invalid_operation: false,
    overflow: false,
    underflow: false,
    subnormal: false,
    inexact: false,
    rounded: false,
    clamped: false,
    lost_digits: false,
  }
}

///|
pub fn GdaTrapSet::with_signal(
  self : GdaTrapSet,
  signal : GdaSignal,
  enabled? : Bool = true,
) -> GdaTrapSet {
  match signal {
    ConversionSyntax => { ..self, conversion_syntax: enabled }
    DivisionByZero => { ..self, division_by_zero: enabled }
    DivisionImpossible => { ..self, division_impossible: enabled }
    DivisionUndefined => { ..self, division_undefined: enabled }
    InvalidContext => { ..self, invalid_context: enabled }
    InvalidOperation => { ..self, invalid_operation: enabled }
    Overflow => { ..self, overflow: enabled }
    Underflow => { ..self, underflow: enabled }
    Subnormal => { ..self, subnormal: enabled }
    Inexact => { ..self, inexact: enabled }
    Rounded => { ..self, rounded: enabled }
    Clamped => { ..self, clamped: enabled }
    LostDigits => { ..self, lost_digits: enabled }
  }
}

///|
pub fn GdaTrapSet::contains(self : GdaTrapSet, signal : GdaSignal) -> Bool {
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
fn decimal_rounding(mode : GdaRoundingMode) -> DecimalRoundingMode {
  match mode {
    HalfEven => DecimalRoundingMode::HalfEven
    HalfUp => DecimalRoundingMode::HalfUp
    HalfDown => DecimalRoundingMode::HalfDown
    Down => DecimalRoundingMode::Down
    Ceiling => DecimalRoundingMode::Ceiling
    Floor => DecimalRoundingMode::Floor
    Up => DecimalRoundingMode::Up
    ZeroFiveUp => DecimalRoundingMode::ZeroFiveUp
  }
}

///|
fn arithmetic_rounding(mode : GdaRoundingMode) -> @lf_arith.RoundingMode {
  match mode {
    HalfEven | HalfUp | HalfDown => @lf_arith.RoundingMode::ToNearestEven
    Down => @lf_arith.RoundingMode::TowardZero
    Ceiling => @lf_arith.RoundingMode::TowardPositive
    Floor => @lf_arith.RoundingMode::TowardNegative
    Up | ZeroFiveUp => @lf_arith.RoundingMode::AwayFromZero
  }
}

///|
fn GdaContext::decimal_context(self : GdaContext) -> DecimalContext {
  {
    precision: self.precision_,
    rounding: arithmetic_rounding(self.rounding_),
    decimal_rounding: decimal_rounding(self.rounding_),
    e_min: self.e_min_,
    e_max: self.e_max_,
    clamp: self.clamp_,
    extended: self.extended_,
    tininess: DecimalTininessDetection::BeforeRounding,
  }
}

///|
fn GdaContext::mathematical_decimal_context(
  self : GdaContext,
) -> DecimalContext {
  {
    ..self.decimal_context(),
    rounding: @lf_arith.RoundingMode::ToNearestEven,
    decimal_rounding: DecimalRoundingMode::HalfEven,
  }
}

///|
pub fn GdaContext::new(
  precision? : Int = 34,
  rounding? : GdaRoundingMode = GdaRoundingMode::HalfEven,
  e_min? : Int = -999_999_999,
  e_max? : Int = 999_999_999,
  clamp? : Bool = false,
  extended? : Bool = true,
  traps? : GdaTrapSet = GdaTrapSet::none(),
) -> GdaContext {
  guard precision > 0 else {
    abort("GdaContext::new: precision must be positive")
  }
  guard e_min <= e_max else {
    abort("GdaContext::new: e_min must not exceed e_max")
  }
  {
    precision_: precision,
    rounding_: rounding,
    e_min_: e_min,
    e_max_: e_max,
    clamp_: clamp,
    extended_: extended,
    status_: GdaFlags::none(),
    traps_: traps,
  }
}

///|
pub fn GdaContext::try_new(
  precision? : Int = 34,
  rounding? : GdaRoundingMode = GdaRoundingMode::HalfEven,
  e_min? : Int = -999_999_999,
  e_max? : Int = 999_999_999,
  clamp? : Bool = false,
  extended? : Bool = true,
  traps? : GdaTrapSet = GdaTrapSet::none(),
) -> Result[GdaContext, @def.ArithmeticError] {
  guard precision > 0 else {
    return Err(
      @def.ArithmeticError::domain_error(
        "GdaContext::try_new: precision must be positive",
      ),
    )
  }
  guard e_min <= e_max else {
    return Err(
      @def.ArithmeticError::domain_error(
        "GdaContext::try_new: e_min must not exceed e_max",
      ),
    )
  }
  Ok({
    precision_: precision,
    rounding_: rounding,
    e_min_: e_min,
    e_max_: e_max,
    clamp_: clamp,
    extended_: extended,
    status_: GdaFlags::none(),
    traps_: traps,
  })
}

///|
pub fn GdaContext::basic() -> GdaContext {
  gda_basic_context_cache
}

///|
pub fn GdaContext::default() -> GdaContext {
  gda_basic_context_cache
}

///|
pub fn GdaContext::decimal32() -> GdaContext {
  gda_decimal32_context_cache
}

///|
pub fn GdaContext::decimal64() -> GdaContext {
  gda_decimal64_context_cache
}

///|
pub fn GdaContext::decimal128() -> GdaContext {
  gda_decimal128_context_cache
}

///|
let gda_basic_context_cache : GdaContext = GdaContext::new(
  precision=9,
  rounding=GdaRoundingMode::HalfUp,
  extended=false,
  traps={
    ..GdaTrapSet::none(),
    division_by_zero: true,
    invalid_operation: true,
    overflow: true,
    underflow: true,
    clamped: true,
  },
)

///|
let gda_decimal32_context_cache : GdaContext = GdaContext::new(
  precision=7,
  e_min=-95,
  e_max=96,
  clamp=true,
)

///|
let gda_decimal64_context_cache : GdaContext = GdaContext::new(
  precision=16,
  e_min=-383,
  e_max=384,
  clamp=true,
)

///|
let gda_decimal128_context_cache : GdaContext = GdaContext::new(
  precision=34,
  e_min=-6143,
  e_max=6144,
  clamp=true,
)

///|
pub fn GdaContext::radix(_self : GdaContext) -> Int {
  10
}

///|
pub fn GdaContext::precision(self : GdaContext) -> Int {
  self.precision_
}

///|
pub fn GdaContext::e_min(self : GdaContext) -> Int {
  self.e_min_
}

///|
pub fn GdaContext::e_max(self : GdaContext) -> Int {
  self.e_max_
}

///|
pub fn GdaContext::clamp(self : GdaContext) -> Bool {
  self.clamp_
}

///|
pub fn GdaContext::extended(self : GdaContext) -> Bool {
  self.extended_
}

///|
pub fn GdaContext::rounding(self : GdaContext) -> GdaRoundingMode {
  self.rounding_
}

///|
pub fn GdaContext::status(self : GdaContext) -> GdaFlags {
  self.status_
}

///|
pub fn GdaContext::traps(self : GdaContext) -> GdaTrapSet {
  self.traps_
}

///|
pub fn GdaContext::with_traps(
  self : GdaContext,
  traps : GdaTrapSet,
) -> GdaContext {
  { ..self, traps_: traps }
}

///|
pub fn GdaContext::trap(
  self : GdaContext,
  signal : GdaSignal,
  enabled? : Bool = true,
) -> GdaContext {
  { ..self, traps_: self.traps_.with_signal(signal, enabled~) }
}

///|
pub fn GdaContext::clear_status(self : GdaContext) -> GdaContext {
  { ..self, status_: GdaFlags::none() }
}

///|
pub fn GdaContext::reset(self : GdaContext) -> GdaContext {
  { ..self, status_: GdaFlags::none(), traps_: GdaTrapSet::none() }
}

///|
fn trapped_signal(raised : GdaFlags, traps : GdaTrapSet) -> GdaSignal? {
  if raised.contains(GdaSignal::InvalidOperation) && traps.invalid_operation {
    Some(GdaSignal::InvalidOperation)
  } else if raised.division_by_zero && traps.division_by_zero {
    Some(GdaSignal::DivisionByZero)
  } else if raised.division_undefined && traps.division_undefined {
    Some(GdaSignal::DivisionUndefined)
  } else if raised.division_impossible && traps.division_impossible {
    Some(GdaSignal::DivisionImpossible)
  } else if raised.invalid_context && traps.invalid_context {
    Some(GdaSignal::InvalidContext)
  } else if raised.conversion_syntax && traps.conversion_syntax {
    Some(GdaSignal::ConversionSyntax)
  } else if raised.overflow && traps.overflow {
    Some(GdaSignal::Overflow)
  } else if raised.underflow && traps.underflow {
    Some(GdaSignal::Underflow)
  } else if raised.subnormal && traps.subnormal {
    Some(GdaSignal::Subnormal)
  } else if raised.inexact && traps.inexact {
    Some(GdaSignal::Inexact)
  } else if raised.rounded && traps.rounded {
    Some(GdaSignal::Rounded)
  } else if raised.clamped && traps.clamped {
    Some(GdaSignal::Clamped)
  } else if raised.lost_digits && traps.lost_digits {
    Some(GdaSignal::LostDigits)
  } else {
    None
  }
}

///|
fn[T] complete_gda(
  value : T,
  context : GdaContext,
  decimal_flags : DecimalFlags,
) -> GdaOutcome[T] {
  if decimal_flags_are_clear(decimal_flags) {
    return Completed(value, context, GdaFlags::none())
  }
  let raised = gda_flags_from_decimal(decimal_flags)
  let status_delta = if raised.contains(GdaSignal::InvalidOperation) {
    { ..raised, invalid_operation: true }
  } else {
    raised
  }
  let next_context = {
    ..context,
    status_: context.status_.combine(status_delta),
  }
  match trapped_signal(raised, context.traps_) {
    Some(signal) => Trapped(signal, value, next_context, raised)
    None => Completed(value, next_context, raised)
  }
}

///|
pub fn[T] GdaOutcome::value(self : GdaOutcome[T]) -> T {
  match self {
    Completed(value, _, _) | Trapped(_, value, _, _) => value
  }
}

///|
pub fn[T] GdaOutcome::next_context(self : GdaOutcome[T]) -> GdaContext {
  match self {
    Completed(_, context, _) | Trapped(_, _, context, _) => context
  }
}

///|
pub fn[T] GdaOutcome::raised(self : GdaOutcome[T]) -> GdaFlags {
  match self {
    Completed(_, _, raised) | Trapped(_, _, _, raised) => raised
  }
}
