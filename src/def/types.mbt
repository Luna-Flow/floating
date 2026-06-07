///|

///|
pub(all) enum Sign {
  Negative
  Zero
  Positive
} derive(Eq)

///|
pub(all) enum PartialOrder {
  Less
  Equal
  Greater
  Unordered
} derive(Eq)

///|
pub(open) trait Floating {
  fn classify(Self) -> @arithmetic.FpClass
  fn sign(Self) -> Sign
  fn precision(Self) -> Int
  fn with_precision(Self, Int, @arithmetic.RoundingMode) -> Self
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
