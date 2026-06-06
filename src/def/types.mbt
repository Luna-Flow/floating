pub(all) enum Sign {
  Negative
  Zero
  Positive
} derive(Eq)

pub(all) enum FpClass {
  Finite
  Infinity
  NaN
} derive(Eq)

pub(all) enum RoundingMode {
  ToNearestEven
  TowardZero
  TowardPositive
  TowardNegative
  AwayFromZero
} derive(Eq)

pub(open) trait Floating {
  fn classify(Self) -> FpClass
  fn sign(Self) -> Sign
  fn precision(Self) -> Int
  fn with_precision(Self, Int, RoundingMode) -> Self
  fn normalized(Self) -> Self
}

pub fn[F : Floating] is_finite(x : F) -> Bool {
  Floating::classify(x) == Finite
}

pub fn[F : Floating] is_nan(x : F) -> Bool {
  Floating::classify(x) == NaN
}

pub fn[F : Floating] is_infinite(x : F) -> Bool {
  Floating::classify(x) == Infinity
}

pub fn[F : Floating] is_zero(x : F) -> Bool {
  Floating::classify(x) == Finite && Floating::sign(x) == Zero
}
