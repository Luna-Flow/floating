///|
pub(all) enum BinaryRoundingMode {
  RoundTiesToEven
  RoundTiesToAway
  RoundTowardZero
  RoundTowardPositive
  RoundTowardNegative
  RoundAwayFromZero
} derive(Eq, Debug)

///|
pub(all) enum TininessDetection {
  BeforeRounding
  AfterRounding
} derive(Eq, Debug)

///|
pub(all) enum BinaryInterchangeFormat {
  Binary16
  Binary32
  Binary64
  Binary128
} derive(Eq, Debug)

///|
pub struct BinaryContext {
  priv precision : Int
  priv rounding : BinaryRoundingMode
  priv e_min : Int?
  priv e_max : Int?
  priv tininess : TininessDetection
} derive(Eq, Debug)

///|
pub struct BinaryFlags {
  priv inexact : Bool
  priv underflow : Bool
  priv overflow : Bool
  priv division_by_zero : Bool
  priv invalid_operation : Bool
} derive(Eq, Debug)

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
pub fn BinaryFlags::to_testfloat_bits(self : BinaryFlags) -> Int {
  (if self.inexact { 0x01 } else { 0 }) |
  (if self.underflow { 0x02 } else { 0 }) |
  (if self.overflow { 0x04 } else { 0 }) |
  (if self.division_by_zero { 0x08 } else { 0 }) |
  (if self.invalid_operation { 0x10 } else { 0 })
}

///|
fn binary_inexact_flags(underflow : Bool) -> BinaryFlags {
  { ..BinaryFlags::new(), inexact: true, underflow }
}

///|
fn binary_overflow_flags() -> BinaryFlags {
  { ..BinaryFlags::new(), inexact: true, overflow: true }
}

///|
fn binary_division_by_zero_flags() -> BinaryFlags {
  { ..BinaryFlags::new(), division_by_zero: true }
}

///|
fn binary_invalid_flags() -> BinaryFlags {
  { ..BinaryFlags::new(), invalid_operation: true }
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
  precision : Int,
  rounding? : BinaryRoundingMode = BinaryRoundingMode::RoundTiesToEven,
  e_min? : Int,
  e_max? : Int,
  tininess? : TininessDetection = TininessDetection::AfterRounding,
) -> BinaryContext {
  guard precision > 0 else {
    abort("BinaryContext::new: precision must be positive")
  }
  match (e_min, e_max) {
    (Some(lower), Some(upper)) => {
      guard lower <= upper else {
        abort("BinaryContext::new: e_min must not exceed e_max")
      }
    }
    (None, None) => ()
    _ => abort("BinaryContext::new: exponent bounds must be paired")
  }
  { precision, rounding, e_min, e_max, tininess }
}

///|
pub fn BinaryContext::try_new(
  precision : Int,
  rounding? : BinaryRoundingMode = BinaryRoundingMode::RoundTiesToEven,
  e_min? : Int,
  e_max? : Int,
  tininess? : TininessDetection = TininessDetection::AfterRounding,
) -> Result[BinaryContext, @def.ArithmeticError] {
  guard precision > 0 else {
    return Err(
      @def.ArithmeticError::domain_error(
        "BinaryContext::try_new: precision must be positive",
      ),
    )
  }
  match (e_min, e_max) {
    (Some(lower), Some(upper)) if lower <= upper => ()
    (None, None) => ()
    _ =>
      return Err(
        @def.ArithmeticError::domain_error(
          "BinaryContext::try_new: exponent bounds must be paired and ordered",
        ),
      )
  }
  Ok({ precision, rounding, e_min, e_max, tininess })
}

///|
pub fn BinaryContext::unbounded(
  precision : Int,
  rounding? : BinaryRoundingMode = BinaryRoundingMode::RoundTiesToEven,
) -> BinaryContext {
  BinaryContext::new(precision, rounding~)
}

///|
pub fn BinaryContext::from_arithmetic_context(
  context : @lf_arith.ArithmeticContext,
) -> BinaryContext {
  BinaryContext::unbounded(
    context.precision,
    rounding=BinaryRoundingMode::from_arithmetic(context.rounding),
  )
}

///|
pub fn BinaryContext::precision(self : BinaryContext) -> Int {
  self.precision
}

///|
pub fn BinaryContext::rounding(self : BinaryContext) -> BinaryRoundingMode {
  self.rounding
}

///|
pub fn BinaryContext::e_min(self : BinaryContext) -> Int? {
  self.e_min
}

///|
pub fn BinaryContext::e_max(self : BinaryContext) -> Int? {
  self.e_max
}

///|
pub fn BinaryContext::tininess(self : BinaryContext) -> TininessDetection {
  self.tininess
}

///|
pub fn BinaryInterchangeFormat::precision(
  self : BinaryInterchangeFormat,
) -> Int {
  match self {
    Binary16 => 11
    Binary32 => 24
    Binary64 => 53
    Binary128 => 113
  }
}

///|
pub fn BinaryInterchangeFormat::e_min(self : BinaryInterchangeFormat) -> Int {
  match self {
    Binary16 => -14
    Binary32 => -126
    Binary64 => -1022
    Binary128 => -16382
  }
}

///|
pub fn BinaryInterchangeFormat::e_max(self : BinaryInterchangeFormat) -> Int {
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
  rounding? : BinaryRoundingMode = BinaryRoundingMode::RoundTiesToEven,
  tininess? : TininessDetection = TininessDetection::AfterRounding,
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
  rounding? : BinaryRoundingMode = BinaryRoundingMode::RoundTiesToEven,
  tininess? : TininessDetection = TininessDetection::AfterRounding,
) -> BinaryContext {
  BinaryInterchangeFormat::Binary16.context(rounding~, tininess~)
}

///|
pub fn BinaryContext::binary32(
  rounding? : BinaryRoundingMode = BinaryRoundingMode::RoundTiesToEven,
  tininess? : TininessDetection = TininessDetection::AfterRounding,
) -> BinaryContext {
  BinaryInterchangeFormat::Binary32.context(rounding~, tininess~)
}

///|
pub fn BinaryContext::binary64(
  rounding? : BinaryRoundingMode = BinaryRoundingMode::RoundTiesToEven,
  tininess? : TininessDetection = TininessDetection::AfterRounding,
) -> BinaryContext {
  BinaryInterchangeFormat::Binary64.context(rounding~, tininess~)
}

///|
pub fn BinaryContext::binary128(
  rounding? : BinaryRoundingMode = BinaryRoundingMode::RoundTiesToEven,
  tininess? : TininessDetection = TininessDetection::AfterRounding,
) -> BinaryContext {
  BinaryInterchangeFormat::Binary128.context(rounding~, tininess~)
}
