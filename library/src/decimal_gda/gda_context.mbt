///|
/// The rounding algorithm of a context (GDA 1.70, abstract representation of
/// context). When the exact result lies strictly between two representable
/// neighbours: `Down` takes the one nearer zero, `Up` the one farther from zero,
/// `Ceiling` the larger and `Floor` the smaller. `HalfEven`, `HalfUp` and
/// `HalfDown` take the nearer one and break an exact tie to the even last digit,
/// away from zero and toward zero. `ZeroFiveUp` rounds toward zero unless that
/// leaves a last digit of 0 or 5, in which case it rounds away from zero.
#derive(Eq)
pub(all) enum GdaRoundingMode {
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
/// A signal of the GDA specification: `Clamped`, `DivisionByZero`, `Inexact`,
/// `InvalidOperation`, `Overflow`, `Rounded`, `Subnormal` and `Underflow`, and
/// `LostDigits` of the subset arithmetic. Each has a flag in the flags of a
/// context and a trap-enabler in its `GdaTrapSet`. The conditions conversion
/// syntax, division impossible, division undefined and invalid context signal
/// `InvalidOperation`.
#derive(Eq)
pub(all) enum GdaSignal {
  /// The nine signals of GDA 1.70 (page 15 and, for `LostDigits`, Appendix A):
  /// each has a flag and a trap-enabler. The finer conditions of the Invalid
  /// operation signal are flags of `GdaFlags` only.
  Clamped
  DivisionByZero
  Inexact
  InvalidOperation
  LostDigits
  Overflow
  Rounded
  Subnormal
  Underflow
}

///|
/// A set of conditions: those raised by one operation, or the flags of a
/// context. It holds the thirteen conditions the library raises: the exceptional
/// conditions of the GDA specification other than insufficient storage, and
/// `lost_digits` of the subset arithmetic.
///
/// Read each condition with the method of the same name. `contains` tests a
/// signal instead: `contains(InvalidOperation)` is true when any of
/// `invalid_operation`, `conversion_syntax`, `division_impossible`,
/// `division_undefined` or `invalid_context` is set. Build a set with `new` and
/// `combine`.
#derive(Eq)
pub struct GdaFlags {
  priv conversion_syntax : Bool
  priv division_by_zero : Bool
  priv division_impossible : Bool
  priv division_undefined : Bool
  priv invalid_context : Bool
  priv invalid_operation : Bool
  priv overflow : Bool
  priv underflow : Bool
  priv subnormal : Bool
  priv inexact : Bool
  priv rounded : Bool
  priv clamped : Bool
  priv lost_digits : Bool
}

///|
/// The set of enabled trap-enablers of a context, one for each `GdaSignal`.
/// `GdaTrapSet::new()` enables none; `with_signal` enables or disables one.
/// Read a trap-enabler with `contains` or the method of the signal's name.
#derive(Eq)
pub struct GdaTrapSet {
  priv clamped : Bool
  priv division_by_zero : Bool
  priv inexact : Bool
  priv invalid_operation : Bool
  priv lost_digits : Bool
  priv overflow : Bool
  priv rounded : Bool
  priv subnormal : Bool
  priv underflow : Bool
}

///|
/// An immutable GDA context: the arithmetic policy, the flags raised so far and
/// the enabled traps. The policy is the precision, the rounding algorithm, the
/// exponent range `e_min..e_max`, `clamp` and `extended` (extended or subset
/// arithmetic).
///
/// Flags and traps never change the numerical result of an operation. They
/// decide the next context and whether the `GdaOutcome` is `Completed` or
/// `Trapped`. Build one with `GdaContext::new`, `try_new`, `basic_default` or
/// `decimal32`, `decimal64` and `decimal128`; the `with_*` methods return a
/// changed copy.
pub struct GdaContext {
  priv precision_ : Int32
  priv rounding_ : GdaRoundingMode
  priv e_min_ : Int32
  priv e_max_ : Int32
  priv clamp_ : Bool
  priv extended_ : Bool
  priv flags_ : GdaFlags
  priv traps_ : GdaTrapSet
  // derived from the fields above, built once by `GdaContext::new`
  priv decimal_ : DecimalContext
  priv mathematical_ : DecimalContext
}

///|
/// The result of every GDA operation: `Completed(value, next_context, raised)`
/// when no enabled trap fired, or `Trapped(signal, value, next_context, raised)`
/// when one did. Both carry the result the specification defines, the context
/// with the updated flags and the conditions raised by this operation only;
/// `Trapped` also names the signal that fired.
///
/// Read the shared parts with `value`, `next_context` and `raised`. A trapped
/// outcome becomes a completed one only through `resume_defined`.
pub enum GdaOutcome[T] {
  Completed(T, GdaContext, GdaFlags)
  Trapped(GdaSignal, T, GdaContext, GdaFlags)
}

///|
/// The GDA "defined result" of a trapped outcome: `Completed` is returned
/// unchanged, `Trapped(s, v, C, R)` becomes `Completed(v, C, none)`.
pub fn[T] GdaOutcome::resume_defined(self : GdaOutcome[T]) -> GdaOutcome[T] {
  match self {
    Completed(_, _, _) => self
    Trapped(_, value, context, _) => Completed(value, context, GdaFlags::new())
  }
}

///|
pub fn GdaFlags::new() -> GdaFlags {
  gda_flags_none_value
}

///|
/// The empty flag set, built once. Invariant: `GdaFlags` is an immutable record
/// compared by value (no `mut` field, no setter, every "update" is a copy
/// `{ ..flags, field: v }`), so every `GdaFlags::new()` may share this one value
/// instead of allocating 13 fields, and `combine` may return one of its
/// operands when the other is clear. The test "shared empty flag sets are
/// never written" pins it.
let gda_flags_none_value : GdaFlags = {
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

///|
/// Whether the `inexact` status flag is set.
pub fn GdaFlags::inexact(self : GdaFlags) -> Bool {
  self.inexact
}

///|
/// Whether the `rounded` status flag is set.
pub fn GdaFlags::rounded(self : GdaFlags) -> Bool {
  self.rounded
}

///|
/// Whether the `lost_digits` status flag is set.
pub fn GdaFlags::lost_digits(self : GdaFlags) -> Bool {
  self.lost_digits
}

///|
/// Whether the `invalid_operation` status flag is set.
pub fn GdaFlags::invalid_operation(self : GdaFlags) -> Bool {
  self.invalid_operation
}

///|
/// Whether the `division_by_zero` status flag is set.
pub fn GdaFlags::division_by_zero(self : GdaFlags) -> Bool {
  self.division_by_zero
}

///|
/// Whether the `overflow` status flag is set.
pub fn GdaFlags::overflow(self : GdaFlags) -> Bool {
  self.overflow
}

///|
/// Whether the `underflow` status flag is set.
pub fn GdaFlags::underflow(self : GdaFlags) -> Bool {
  self.underflow
}

///|
/// Whether the `subnormal` status flag is set.
pub fn GdaFlags::subnormal(self : GdaFlags) -> Bool {
  self.subnormal
}

///|
/// Whether the `clamped` status flag is set.
pub fn GdaFlags::clamped(self : GdaFlags) -> Bool {
  self.clamped
}

///|
/// Whether the `conversion_syntax` status flag is set.
pub fn GdaFlags::conversion_syntax(self : GdaFlags) -> Bool {
  self.conversion_syntax
}

///|
/// Whether the `division_impossible` status flag is set.
pub fn GdaFlags::division_impossible(self : GdaFlags) -> Bool {
  self.division_impossible
}

///|
/// Whether the `division_undefined` status flag is set.
pub fn GdaFlags::division_undefined(self : GdaFlags) -> Bool {
  self.division_undefined
}

///|
/// Whether the `invalid_context` status flag is set.
pub fn GdaFlags::invalid_context(self : GdaFlags) -> Bool {
  self.invalid_context
}

///|
/// Whether the signal was raised. `InvalidOperation` is raised by the Invalid
/// operation condition and by the four conditions that GDA 1.70 says signal it
/// (pages 51 and 52): conversion syntax, division impossible, division
/// undefined and invalid context. The accessor `invalid_operation()` reads the
/// plain Invalid operation condition only.
pub fn GdaFlags::contains(self : GdaFlags, signal : GdaSignal) -> Bool {
  match signal {
    Clamped => self.clamped
    DivisionByZero => self.division_by_zero
    Inexact => self.inexact
    InvalidOperation =>
      self.invalid_operation ||
      self.conversion_syntax ||
      self.division_impossible ||
      self.division_undefined ||
      self.invalid_context
    LostDigits => self.lost_digits
    Overflow => self.overflow
    Rounded => self.rounded
    Subnormal => self.subnormal
    Underflow => self.underflow
  }
}

///|
pub fn GdaFlags::combine(self : GdaFlags, other : GdaFlags) -> GdaFlags {
  if gda_flags_are_clear(other) {
    return self
  }
  if gda_flags_are_clear(self) {
    return other
  }
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
pub fn GdaTrapSet::new() -> GdaTrapSet {
  {
    clamped: false,
    division_by_zero: false,
    inexact: false,
    invalid_operation: false,
    lost_digits: false,
    overflow: false,
    rounded: false,
    subnormal: false,
    underflow: false,
  }
}

///|
/// Whether the `inexact` trap is set.
pub fn GdaTrapSet::inexact(self : GdaTrapSet) -> Bool {
  self.inexact
}

///|
/// Whether the `rounded` trap is set.
pub fn GdaTrapSet::rounded(self : GdaTrapSet) -> Bool {
  self.rounded
}

///|
/// Whether the `lost_digits` trap is set.
pub fn GdaTrapSet::lost_digits(self : GdaTrapSet) -> Bool {
  self.lost_digits
}

///|
/// Whether the `invalid_operation` trap is set.
pub fn GdaTrapSet::invalid_operation(self : GdaTrapSet) -> Bool {
  self.invalid_operation
}

///|
/// Whether the `division_by_zero` trap is set.
pub fn GdaTrapSet::division_by_zero(self : GdaTrapSet) -> Bool {
  self.division_by_zero
}

///|
/// Whether the `overflow` trap is set.
pub fn GdaTrapSet::overflow(self : GdaTrapSet) -> Bool {
  self.overflow
}

///|
/// Whether the `underflow` trap is set.
pub fn GdaTrapSet::underflow(self : GdaTrapSet) -> Bool {
  self.underflow
}

///|
/// Whether the `subnormal` trap is set.
pub fn GdaTrapSet::subnormal(self : GdaTrapSet) -> Bool {
  self.subnormal
}

///|
/// Whether the `clamped` trap is set.
pub fn GdaTrapSet::clamped(self : GdaTrapSet) -> Bool {
  self.clamped
}

///|
pub fn GdaTrapSet::with_signal(
  self : GdaTrapSet,
  signal : GdaSignal,
  enabled~ : Bool = true,
) -> GdaTrapSet {
  match signal {
    Clamped => { ..self, clamped: enabled, }
    DivisionByZero => { ..self, division_by_zero: enabled, }
    Inexact => { ..self, inexact: enabled, }
    InvalidOperation => { ..self, invalid_operation: enabled, }
    LostDigits => { ..self, lost_digits: enabled, }
    Overflow => { ..self, overflow: enabled, }
    Rounded => { ..self, rounded: enabled, }
    Subnormal => { ..self, subnormal: enabled, }
    Underflow => { ..self, underflow: enabled, }
  }
}

///|
pub fn GdaTrapSet::contains(self : GdaTrapSet, signal : GdaSignal) -> Bool {
  match signal {
    Clamped => self.clamped
    DivisionByZero => self.division_by_zero
    Inexact => self.inexact
    InvalidOperation => self.invalid_operation
    LostDigits => self.lost_digits
    Overflow => self.overflow
    Rounded => self.rounded
    Subnormal => self.subnormal
    Underflow => self.underflow
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
  self.decimal_
}

///|
fn GdaContext::mathematical_decimal_context(
  self : GdaContext,
) -> DecimalContext {
  self.mathematical_
}

///|
/// The `DecimalContext` of the GDA parameters, validated once.
fn gda_build_decimal_context(
  precision : Int32,
  rounding : GdaRoundingMode,
  e_min : Int32,
  e_max : Int32,
  clamp : Bool,
  extended : Bool,
) -> DecimalContext {
  DecimalContext::new(
    precision~,
    rounding=arithmetic_rounding(rounding),
    decimal_rounding=decimal_rounding(rounding),
    e_min~,
    e_max~,
    clamp~,
    extended~,
  )
}

///|
fn GdaContext::build(
  precision~ : Int32 = 34,
  rounding~ : GdaRoundingMode = GdaRoundingMode::HalfEven,
  e_min~ : Int32 = -999_999_999,
  e_max~ : Int32 = 999_999_999,
  clamp~ : Bool = false,
  extended~ : Bool = true,
  traps~ : GdaTrapSet = GdaTrapSet::new(),
) -> Result[GdaContext, String] {
  let bounds = @internal.DecimalExponentBounds::new(precision, e_min, e_max)
  guard bounds.is_valid() else {
    let message = if precision <= 0 || precision > 999_999_999 {
      "GdaContext precision must be in 1..=999999999"
    } else if e_min < -999_999_999 || e_min > 0 {
      "GdaContext e_min must be within -999999999..=0"
    } else if e_max < 0 || e_max > 999_999_999 {
      "GdaContext e_max must be within 0..=999999999"
    } else {
      "GdaContext e_min must not exceed e_max"
    }
    return Err(message)
  }
  // GDA 1.70 page 10: Emin and Emax have magnitudes that differ by at most
  // one, so Emin is -Emax, 1 - Emax (IEEE 754) or -Emax - 1.
  guard e_min == -e_max || e_min == 1 - e_max || e_min == -e_max - 1 else {
    return Err(
      "GdaContext e_min must be -e_max, 1 - e_max or -e_max - 1 (GDA 1.70, page 10)",
    )
  }
  let decimal_ = gda_build_decimal_context(
    precision, rounding, e_min, e_max, clamp, extended,
  )
  Ok({
    precision_: precision,
    rounding_: rounding,
    e_min_: e_min,
    e_max_: e_max,
    clamp_: clamp,
    extended_: extended,
    flags_: GdaFlags::new(),
    traps_: traps,
    decimal_,
    mathematical_: {
      ..decimal_,
      rounding: @lf_arith.RoundingMode::ToNearestEven,
      decimal_rounding: DecimalRoundingMode::HalfEven,
    },
  })
}

///|
/// Builds a context, or aborts with the message that names the invalid
/// parameter (like `BinaryContext::new`). `try_new` returns the same check as
/// an `Err` instead.
pub fn GdaContext::new(
  precision~ : Int32 = 34,
  rounding~ : GdaRoundingMode = GdaRoundingMode::HalfEven,
  e_min~ : Int32 = -999_999_999,
  e_max~ : Int32 = 999_999_999,
  clamp~ : Bool = false,
  extended~ : Bool = true,
  traps~ : GdaTrapSet = GdaTrapSet::new(),
) -> GdaContext {
  match
    GdaContext::build(
      precision~,
      rounding~,
      e_min~,
      e_max~,
      clamp~,
      extended~,
      traps~,
    ) {
    Ok(context) => context
    Err(reason) => abort(reason)
  }
}

///|
pub fn GdaContext::try_new(
  precision~ : Int32 = 34,
  rounding~ : GdaRoundingMode = GdaRoundingMode::HalfEven,
  e_min~ : Int32 = -999_999_999,
  e_max~ : Int32 = 999_999_999,
  clamp~ : Bool = false,
  extended~ : Bool = true,
  traps~ : GdaTrapSet = GdaTrapSet::new(),
) -> Result[GdaContext, @def.ArithmeticError] {
  match
    GdaContext::build(
      precision~,
      rounding~,
      e_min~,
      e_max~,
      clamp~,
      extended~,
      traps~,
    ) {
    Ok(context) => Ok(context)
    Err(reason) => Err(@def.ArithmeticError::domain_error(reason))
  }
}

///|
/// The basic default context of GDA 1.70 (page 16): precision 9, round-half-up,
/// trap-enablers for every signal but inexact, rounded and subnormal. It also
/// selects the X3.274 subset (`extended=false`, Appendix A). The values are
/// created once and shared.
pub fn GdaContext::basic_default() -> GdaContext {
  gda_basic_context_cache
}

///|
/// An extended default context of GDA 1.70 (page 16) for the IEEE 754 decimal32
/// format: precision 7, exponent range -95 to 96, clamped, no traps. `rounding`
/// is round-half-even unless given.
pub fn GdaContext::decimal32(rounding? : GdaRoundingMode) -> GdaContext {
  match rounding {
    None | Some(HalfEven) => gda_decimal32_context_cache
    Some(mode) =>
      GdaContext::new(
        precision=7,
        rounding=mode,
        e_min=-95,
        e_max=96,
        clamp=true,
      )
  }
}

///|
/// The extended default context for decimal64: precision 16, exponent range
/// -383 to 384, clamped, no traps.
pub fn GdaContext::decimal64(rounding? : GdaRoundingMode) -> GdaContext {
  match rounding {
    None | Some(HalfEven) => gda_decimal64_context_cache
    Some(mode) =>
      GdaContext::new(
        precision=16,
        rounding=mode,
        e_min=-383,
        e_max=384,
        clamp=true,
      )
  }
}

///|
/// The extended default context for decimal128: precision 34, exponent range
/// -6143 to 6144, clamped, no traps.
pub fn GdaContext::decimal128(rounding? : GdaRoundingMode) -> GdaContext {
  match rounding {
    None | Some(HalfEven) => gda_decimal128_context_cache
    Some(mode) =>
      GdaContext::new(
        precision=34,
        rounding=mode,
        e_min=-6143,
        e_max=6144,
        clamp=true,
      )
  }
}

///|
/// Returns a copy with another precision. Aborts, naming the parameter, when
/// the result is not a valid context. The status, traps and refinement limit
/// are kept.
pub fn GdaContext::with_precision(
  self : GdaContext,
  precision : Int32,
) -> GdaContext {
  self.rebuilt(
    precision~,
    rounding=self.rounding_,
    e_min=self.e_min_,
    e_max=self.e_max_,
  )
}

///|
/// Returns a copy with another rounding mode.
pub fn GdaContext::with_rounding(
  self : GdaContext,
  rounding : GdaRoundingMode,
) -> GdaContext {
  self.rebuilt(
    precision=self.precision_,
    rounding~,
    e_min=self.e_min_,
    e_max=self.e_max_,
  )
}

///|
/// Returns a copy with another exponent range. `e_min` must be `-e_max`,
/// `1 - e_max` or `-e_max - 1` (GDA 1.70, page 10); otherwise it aborts.
pub fn GdaContext::with_exponent_range(
  self : GdaContext,
  e_min~ : Int32,
  e_max~ : Int32,
) -> GdaContext {
  self.rebuilt(
    precision=self.precision_,
    rounding=self.rounding_,
    e_min~,
    e_max~,
  )
}

///|
fn GdaContext::rebuilt(
  self : GdaContext,
  precision~ : Int32,
  rounding~ : GdaRoundingMode,
  e_min~ : Int32,
  e_max~ : Int32,
) -> GdaContext {
  let fresh = GdaContext::new(
    precision~,
    rounding~,
    e_min~,
    e_max~,
    clamp=self.clamp_,
    extended=self.extended_,
    traps=self.traps_,
  )
  { ..fresh, flags_: self.flags_, }.with_refinement_limit(
    self.refinement_limit(),
  )
}

///|
let gda_basic_context_cache : GdaContext = GdaContext::new(
  precision=9,
  rounding=GdaRoundingMode::HalfUp,
  extended=false,
  traps={
    ..GdaTrapSet::new(),
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
pub fn GdaContext::radix(_self : GdaContext) -> Int32 {
  10
}

///|
pub fn GdaContext::precision(self : GdaContext) -> Int32 {
  self.precision_
}

///|
pub fn GdaContext::e_min(self : GdaContext) -> Int32 {
  self.e_min_
}

///|
pub fn GdaContext::e_max(self : GdaContext) -> Int32 {
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
/// Returns the flags of the context: every condition raised by the operations
/// that produced it. Operations only ever add to them; `clear_flags` and `reset`
/// empty them.
pub fn GdaContext::flags(self : GdaContext) -> GdaFlags {
  self.flags_
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
  { ..self, traps_: traps, }
}

///|
/// The number of refinement steps the certified elementary functions (`exp`,
/// `ln`, `log10`, `power`) may take before they report that the result could
/// not be certified: `Some(12)` by default. `None` removes the count limit; the
/// work precision still stops at a resource bound.
pub fn GdaContext::refinement_limit(self : GdaContext) -> Int32? {
  self.decimal_.refinement_limit()
}

///|
/// Returns a copy of the context with the refinement limit set to `limit`
/// (a limit below 1 is clamped to one refinement step).
pub fn GdaContext::with_refinement_limit(
  self : GdaContext,
  limit : Int32?,
) -> GdaContext {
  {
    ..self,
    decimal_: self.decimal_.with_refinement_limit(limit),
    mathematical_: self.mathematical_.with_refinement_limit(limit),
  }
}

///|
pub fn GdaContext::trap(
  self : GdaContext,
  signal : GdaSignal,
  enabled~ : Bool = true,
) -> GdaContext {
  { ..self, traps_: self.traps_.with_signal(signal, enabled~), }
}

///|
pub fn GdaContext::clear_flags(self : GdaContext) -> GdaContext {
  { ..self, flags_: GdaFlags::new(), }
}

///|
pub fn GdaContext::reset(self : GdaContext) -> GdaContext {
  { ..self, flags_: GdaFlags::new(), traps_: GdaTrapSet::new(), }
}

///|
fn trapped_signal(raised : GdaFlags, traps : GdaTrapSet) -> GdaSignal? {
  // The order is the one the trap handlers have always seen: the conditions
  // that deliver no usable number first, then the exponent range, then the
  // informational signals.
  if raised.contains(InvalidOperation) && traps.contains(InvalidOperation) {
    return Some(InvalidOperation)
  }
  if raised.contains(DivisionByZero) && traps.contains(DivisionByZero) {
    return Some(DivisionByZero)
  }
  if raised.contains(Overflow) && traps.contains(Overflow) {
    return Some(Overflow)
  }
  if raised.contains(Underflow) && traps.contains(Underflow) {
    return Some(Underflow)
  }
  if raised.contains(Subnormal) && traps.contains(Subnormal) {
    return Some(Subnormal)
  }
  if raised.contains(Inexact) && traps.contains(Inexact) {
    return Some(Inexact)
  }
  if raised.contains(Rounded) && traps.contains(Rounded) {
    return Some(Rounded)
  }
  if raised.contains(Clamped) && traps.contains(Clamped) {
    return Some(Clamped)
  }
  if raised.contains(LostDigits) && traps.contains(LostDigits) {
    return Some(LostDigits)
  }
  None
}

///|
/// The outcome of an operation that raised the conditions `raised` (not
/// empty, no invalid operation): the status of the new context is the union of
/// the old status and `raised`, the first trapped condition makes it `Trapped`.
fn[T] complete_gda_raised(
  value : T,
  context : GdaContext,
  raised : GdaFlags,
) -> GdaOutcome[T] {
  let next_context = gda_context_with_flags(context, raised)
  match trapped_signal(raised, context.traps_) {
    Some(signal) => Trapped(signal, value, next_context, raised)
    None => Completed(value, next_context, raised)
  }
}

///|
/// Whether every condition of `delta` is already in `status`.
fn gda_flags_include(status : GdaFlags, delta : GdaFlags) -> Bool {
  (!delta.conversion_syntax || status.conversion_syntax) &&
  (!delta.division_by_zero || status.division_by_zero) &&
  (!delta.division_impossible || status.division_impossible) &&
  (!delta.division_undefined || status.division_undefined) &&
  (!delta.invalid_context || status.invalid_context) &&
  (!delta.invalid_operation || status.invalid_operation) &&
  (!delta.overflow || status.overflow) &&
  (!delta.underflow || status.underflow) &&
  (!delta.subnormal || status.subnormal) &&
  (!delta.inexact || status.inexact) &&
  (!delta.rounded || status.rounded) &&
  (!delta.clamped || status.clamped) &&
  (!delta.lost_digits || status.lost_digits)
}

///|
/// The context after an operation that raised `delta`: its status is the union
/// of the old status and `delta`. When the status already contains `delta` (the
/// steady state of a loop of operations that raise the same conditions) the
/// context itself is returned and no record is built; contexts are immutable
/// values compared by value, so sharing the input is not observable. A clear
/// status takes `delta` itself instead of a 13-field union.
fn gda_context_with_flags(context : GdaContext, delta : GdaFlags) -> GdaContext {
  if gda_flags_include(context.flags_, delta) {
    context
  } else {
    {
      ..context,
      flags_: if gda_flags_are_clear(context.flags_) {
        delta
      } else {
        context.flags_.combine(delta)
      },
    }
  }
}

///|
fn gda_flags_are_clear(flags : GdaFlags) -> Bool {
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
fn[T] complete_gda(
  value : T,
  context : GdaContext,
  decimal_flags : DecimalFlags,
) -> GdaOutcome[T] {
  if decimal_flags_are_clear(decimal_flags) {
    return Completed(value, context, GdaFlags::new())
  }
  let raised = gda_flags_from_decimal(decimal_flags)
  let status_delta = if raised.contains(GdaSignal::InvalidOperation) {
    { ..raised, invalid_operation: true, }
  } else {
    raised
  }
  let next_context = gda_context_with_flags(context, status_delta)
  match trapped_signal(raised, context.traps_) {
    Some(signal) => Trapped(signal, value, next_context, raised)
    None => Completed(value, next_context, raised)
  }
}

///|
/// The outcome of an operation that raised nothing: `value` and `context`
/// unchanged. It is the starting point of a pipeline and the identity of
/// `absorb`.
pub fn[T] GdaOutcome::completed(
  value : T,
  context : GdaContext,
) -> GdaOutcome[T] {
  Completed(value, context, GdaFlags::new())
}

///|
/// The outcome of an operation after the flags and the trap of another outcome
/// are merged in: `self` keeps its value, its context (traps included) and its
/// own trap; the conditions that `other` raised join `raised` and the sticky
/// status of the next context; when `self` completed and `other` trapped, the
/// result is `Trapped` with the signal of `other`. The traps of `self` are not
/// tested against the conditions of `other`: `other` decided its own traps. It is
/// the merge that a checked pipeline needs when its right operand is a pipeline
/// too (`GdaDecimalChecked`).
pub fn[T, U] GdaOutcome::absorb(
  self : GdaOutcome[T],
  other : GdaOutcome[U],
) -> GdaOutcome[T] {
  let extra = other.raised()
  let status_delta = if extra.contains(GdaSignal::InvalidOperation) {
    { ..extra, invalid_operation: true, }
  } else {
    extra
  }
  match self {
    Completed(value, context, raised) => {
      let next = { ..context, flags_: context.flags_.combine(status_delta), }
      let merged = raised.combine(extra)
      match other {
        Trapped(signal, _, _, _) => Trapped(signal, value, next, merged)
        Completed(_, _, _) => Completed(value, next, merged)
      }
    }
    Trapped(signal, value, context, raised) =>
      Trapped(
        signal,
        value,
        { ..context, flags_: context.flags_.combine(status_delta), },
        raised.combine(extra),
      )
  }
}

///|
/// Returns the result the specification defines, also for a `Trapped` outcome.
pub fn[T] GdaOutcome::value(self : GdaOutcome[T]) -> T {
  match self {
    Completed(value, _, _) | Trapped(_, value, _, _) => value
  }
}

///|
/// Returns the context with the flags of this operation added: the context to
/// use for the next operation. An operation that raised nothing returns the
/// context it received.
pub fn[T] GdaOutcome::next_context(self : GdaOutcome[T]) -> GdaContext {
  match self {
    Completed(_, context, _) | Trapped(_, _, context, _) => context
  }
}

///|
/// Returns the conditions raised by this operation alone, not those already in
/// the flags of the context.
pub fn[T] GdaOutcome::raised(self : GdaOutcome[T]) -> GdaFlags {
  match self {
    Completed(_, _, raised) | Trapped(_, _, _, raised) => raised
  }
}

///|
pub extend GdaRoundingMode with Eq::{not_equal, equal}

///|
pub extend GdaSignal with Eq::{not_equal, equal}

///|
pub extend GdaFlags with Eq::{not_equal, equal}

///|
pub extend GdaTrapSet with Eq::{not_equal, equal}
