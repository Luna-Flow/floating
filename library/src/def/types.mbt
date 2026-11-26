///|

///|
/// The sign classification of a value, as returned by `Floating::signum`.
/// Either signed zero and every NaN are `Zero`; a negative value, `-inf`
/// included, is `Negative`; a positive value, `+inf` included, is `Positive`.
/// It does not tell `-0` from `+0`: use the sign test of the concrete type for
/// that, for example `Binary::is_negative_zero`.
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
/// The result of an IEEE 754 comparison: exactly one of `Less`, `Equal`,
/// `Greater` and `Unordered` holds between two data. `Unordered` is the result
/// when an operand is a NaN; `-0` and `+0` are `Equal`. The comparison methods
/// of the number types, such as `Binary::compare_quiet`, return it with their
/// flags. It is not a total order, so the type has no `Compare` instance.
#derive(Eq)
pub(all) enum PartialOrder {
  Less
  Equal
  Greater
  Unordered
}

///|
/// The observation interface shared by the scalar types of this library
/// (`Binary` and the two `Decimal` types), so that generic code can classify
/// a value and change its precision. `classify` returns `Finite`, `Infinity`
/// or `NaN` (zero is `Finite`); `signum` returns the `Sign`; `precision` is
/// the working precision stored on the value (bits for `Binary`, decimal
/// digits for `Decimal`); `with_precision` re-expresses the value at another
/// precision, rounding to nearest-even; `normalized` returns the canonical
/// representative of the value.
pub(open) trait Floating {
  fn classify(Self) -> @arithmetic.FpClass
  fn signum(Self) -> Sign
  fn precision(Self) -> Int32
  fn with_precision(Self, Int32) -> Self
  fn normalized(Self) -> Self
}

///|
/// Returns true when `x` is a finite number: not an infinity and not a NaN. Zeros are finite.
pub fn[F : Floating] is_finite(x : F) -> Bool {
  Floating::classify(x) == @arithmetic.FpClass::Finite
}

///|
/// Returns true when `x` is a NaN, quiet or signaling.
pub fn[F : Floating] is_nan(x : F) -> Bool {
  Floating::classify(x) == @arithmetic.FpClass::NaN
}

///|
/// Returns true when `x` is `+inf` or `-inf`.
pub fn[F : Floating] is_infinite(x : F) -> Bool {
  Floating::classify(x) == @arithmetic.FpClass::Infinity
}

///|
/// Returns true when `x` is `+0` or `-0`. A NaN is not zero.
pub fn[F : Floating] is_zero(x : F) -> Bool {
  Floating::classify(x) == @arithmetic.FpClass::Finite &&
  Floating::signum(x) == Zero
}

///|
pub extend Sign with Eq::{not_equal, equal}

///|
pub extend PartialOrder with Eq::{not_equal, equal}
