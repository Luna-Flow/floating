///|
/// A non-negative arbitrary-precision integer, used as the coefficient of a
/// `BinFloat` and as the bit pattern of an interchange encoding. The type is
/// opaque; the arithmetic lives in the internal kernel package
/// `Luna-Flow/floating/internal/bin_kernel`, and each method here forwards to
/// it (a newtype costs nothing: no extra allocation and no extra call).
#derive(Debug)
struct BinCoeff(@bin_kernel.Coeff)

///|
pub fn BinCoeff::zero() -> BinCoeff {
  BinCoeff(@bin_kernel.Coeff::zero())
}

///|
pub fn BinCoeff::one() -> BinCoeff {
  BinCoeff(@bin_kernel.Coeff::one())
}

///|
pub fn BinCoeff::from_uint64(value : UInt64) -> BinCoeff {
  BinCoeff(@bin_kernel.Coeff::from_uint64(value))
}

///|
pub fn BinCoeff::from_bytes_be(source : BytesView) -> BinCoeff {
  BinCoeff(@bin_kernel.Coeff::from_bytes_be(source))
}

///|
pub fn BinCoeff::is_zero(self : BinCoeff) -> Bool {
  self.0.is_zero()
}

///|
pub fn BinCoeff::bit_length(self : BinCoeff) -> Int32 {
  self.0.bit_length()
}

///|
pub fn BinCoeff::ctz(self : BinCoeff) -> Int32 {
  self.0.ctz()
}

///|
pub fn BinCoeff::to_uint64(self : BinCoeff) -> UInt64? {
  self.0.to_uint64()
}

///|
pub fn BinCoeff::test_bit(self : BinCoeff, index : Int32) -> Bool {
  self.0.test_bit(index)
}

///|
pub fn BinCoeff::to_bytes_be(self : BinCoeff) -> Bytes {
  self.0.to_bytes_be()
}

///|
pub fn BinCoeff::to_radix_string(self : BinCoeff, radix : Int32) -> String {
  self.0.to_radix_string(radix)
}

///|
pub fn BinCoeff::compare(self : BinCoeff, other : BinCoeff) -> Int32 {
  self.0.compare(other.0)
}

///|
pub fn BinCoeff::add(self : BinCoeff, other : BinCoeff) -> BinCoeff {
  BinCoeff(self.0.add(other.0))
}

///|
pub fn BinCoeff::mul(self : BinCoeff, other : BinCoeff) -> BinCoeff {
  BinCoeff(self.0.mul(other.0))
}

///|
pub fn BinCoeff::sub_checked(
  self : BinCoeff,
  other : BinCoeff,
) -> Result[BinCoeff, String] {
  self.0.sub_checked(other.0).map(fn(value) { BinCoeff(value) })
}

///|
pub fn BinCoeff::square(self : BinCoeff) -> BinCoeff {
  BinCoeff(self.0.square())
}

///|
pub fn BinCoeff::shift_left(self : BinCoeff, shift : Int32) -> BinCoeff {
  BinCoeff(self.0.shift_left(shift))
}

///|
pub fn BinCoeff::shift_right(self : BinCoeff, shift : Int32) -> BinCoeff {
  BinCoeff(self.0.shift_right(shift))
}

///|
pub fn BinCoeff::bit_and(self : BinCoeff, other : BinCoeff) -> BinCoeff {
  BinCoeff(self.0.bit_and(other.0))
}

///|
pub fn BinCoeff::bit_or(self : BinCoeff, other : BinCoeff) -> BinCoeff {
  BinCoeff(self.0.bit_or(other.0))
}

///|
pub fn BinCoeff::bit_xor(self : BinCoeff, other : BinCoeff) -> BinCoeff {
  BinCoeff(self.0.bit_xor(other.0))
}

///|
pub fn BinCoeff::div_rem_checked(
  self : BinCoeff,
  other : BinCoeff,
) -> Result[(BinCoeff, BinCoeff), String] {
  self.0
  .div_rem_checked(other.0)
  .map(fn(pair) { (BinCoeff(pair.0), BinCoeff(pair.1)) })
}

///|
pub fn BinCoeff::gcd(self : BinCoeff, other : BinCoeff) -> BinCoeff {
  BinCoeff(self.0.gcd(other.0))
}

///|
pub fn BinCoeff::pow_nat(self : BinCoeff, exponent : UInt32) -> BinCoeff {
  BinCoeff(self.0.pow_nat(exponent))
}

///|
pub fn BinCoeff::parse(
  text : String,
  radix~ : Int32 = 10,
) -> Result[BinCoeff, String] {
  @bin_kernel.Coeff::parse(text, radix~).map(fn(value) { BinCoeff(value) })
}

///|
pub impl Eq for BinCoeff with fn equal(self, other) {
  self.0 == other.0
}

///|
pub impl Compare for BinCoeff with fn compare(self, other) {
  BinCoeff::compare(self, other)
}

///|
pub impl Show for BinCoeff with fn to_string(self) {
  self.to_radix_string(10)
}

///|
pub extend BinCoeff with Show::{to_string}

///|
pub impl Add for BinCoeff with fn add(self, other) {
  BinCoeff::add(self, other)
}

///|
pub impl Mul for BinCoeff with fn mul(self, other) {
  BinCoeff::mul(self, other)
}

///|
pub impl Shl for BinCoeff with fn shl(self, shift) {
  self.shift_left(shift)
}

///|
pub impl Shr for BinCoeff with fn shr(self, shift) {
  self.shift_right(shift)
}

///|
pub extend BinCoeff with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend BinCoeff with Eq::{not_equal, equal}

///|
pub extend BinCoeff with Compare::{op_lt, op_le, op_ge, op_gt}

///|
pub extend BinCoeff with Show::{output}

///|
pub extend BinCoeff with Shl::{shl}

///|
pub extend BinCoeff with Shr::{shr}
