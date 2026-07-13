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
  priv inner : @decimal.DecimalContext
  priv rounding_ : GdaRoundingMode
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
fn gda_flags_from_decimal(flags : @decimal.DecimalFlags) -> GdaFlags {
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
fn decimal_rounding(mode : GdaRoundingMode) -> @decimal.DecimalRoundingMode {
  match mode {
    HalfEven => @decimal.HalfEven
    HalfUp => @decimal.HalfUp
    HalfDown => @decimal.HalfDown
    Down => @decimal.Down
    Ceiling => @decimal.Ceiling
    Floor => @decimal.Floor
    Up => @decimal.Up
    ZeroFiveUp => @decimal.ZeroFiveUp
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
  {
    inner: @decimal.DecimalContext::new(
      precision~,
      decimal_rounding=decimal_rounding(rounding),
      e_min~,
      e_max~,
      clamp~,
      extended~,
      tininess=@decimal.DecimalTininessDetection::BeforeRounding,
    ).gda(),
    rounding_: rounding,
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
  Ok(
    GdaContext::new(
      precision~,
      rounding~,
      e_min~,
      e_max~,
      clamp~,
      extended~,
      traps~,
    ),
  )
}

///|
pub fn GdaContext::basic() -> GdaContext {
  GdaContext::new(
    precision=9,
    rounding=GdaRoundingMode::HalfEven,
    extended=false,
  )
}

///|
pub fn GdaContext::default() -> GdaContext {
  GdaContext::basic()
}

///|
pub fn GdaContext::decimal32() -> GdaContext {
  GdaContext::new(precision=7, e_min=-95, e_max=96, clamp=true)
}

///|
pub fn GdaContext::decimal64() -> GdaContext {
  GdaContext::new(precision=16, e_min=-383, e_max=384, clamp=true)
}

///|
pub fn GdaContext::decimal128() -> GdaContext {
  GdaContext::new(precision=34, e_min=-6143, e_max=6144, clamp=true)
}

///|
pub fn GdaContext::radix(_self : GdaContext) -> Int {
  10
}

///|
pub fn GdaContext::precision(self : GdaContext) -> Int {
  self.inner.precision()
}

///|
pub fn GdaContext::e_min(self : GdaContext) -> Int {
  self.inner.e_min()
}

///|
pub fn GdaContext::e_max(self : GdaContext) -> Int {
  self.inner.e_max()
}

///|
pub fn GdaContext::clamp(self : GdaContext) -> Bool {
  self.inner.clamp()
}

///|
pub fn GdaContext::extended(self : GdaContext) -> Bool {
  self.inner.extended()
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
  let precedence = [
    GdaSignal::InvalidOperation,
    GdaSignal::DivisionByZero,
    GdaSignal::DivisionUndefined,
    GdaSignal::DivisionImpossible,
    GdaSignal::InvalidContext,
    GdaSignal::ConversionSyntax,
    GdaSignal::Overflow,
    GdaSignal::Underflow,
    GdaSignal::Subnormal,
    GdaSignal::Inexact,
    GdaSignal::Rounded,
    GdaSignal::Clamped,
    GdaSignal::LostDigits,
  ]
  for signal in precedence {
    if raised.contains(signal) && traps.contains(signal) {
      return Some(signal)
    }
  }
  None
}

///|
fn[T] complete_gda(
  value : T,
  context : GdaContext,
  decimal_flags : @decimal.DecimalFlags,
) -> GdaOutcome[T] {
  let raised = gda_flags_from_decimal(decimal_flags)
  let next_context = { ..context, status_: context.status_.combine(raised) }
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
