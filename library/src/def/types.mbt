///|

///|
#derive(Eq)
pub(all) enum Sign {
  Negative
  Zero
  Positive
}

///|
/// The ten classes of IEEE 754-2019 clause 5.7.2 (`class`). Normal and
/// subnormal depend on the format's minimum exponent, so the classifying
/// functions take the context that fixes it.
#derive(Eq)
pub(all) enum IeeeClass {
  SignalingNaN
  QuietNaN
  NegativeInfinity
  NegativeNormal
  NegativeSubnormal
  NegativeZero
  PositiveZero
  PositiveSubnormal
  PositiveNormal
  PositiveInfinity
}

///|
#derive(Eq)
pub(all) enum PartialOrder {
  Less
  Equal
  Greater
  Unordered
}

///|
pub(open) trait Floating {
  fn classify(Self) -> @arithmetic.FpClass
  fn sign(Self) -> Sign
  fn precision(Self) -> Int32
  fn with_precision(Self, Int32) -> Self
  fn normalized(Self) -> Self
}

///|
pub fn[F : Floating] is_finite(x : F) -> Bool {
  Floating::classify(x) == @arithmetic.FpClass::Finite
}

///|
pub fn[F : Floating] is_nan(x : F) -> Bool {
  Floating::classify(x) == @arithmetic.FpClass::NaN
}

///|
pub fn[F : Floating] is_infinite(x : F) -> Bool {
  Floating::classify(x) == @arithmetic.FpClass::Infinity
}

///|
pub fn[F : Floating] is_zero(x : F) -> Bool {
  Floating::classify(x) == @arithmetic.FpClass::Finite &&
  Floating::sign(x) == Zero
}

///|
pub extend Sign with Eq::{not_equal, equal}

///|
pub extend PartialOrder with Eq::{not_equal, equal}
