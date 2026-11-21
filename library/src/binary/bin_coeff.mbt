///|
/// A non-negative arbitrary-precision integer, used as the coefficient of a
/// `Binary` and as the bit pattern of an interchange encoding. The type is
/// abstract: neither the constructor nor the field is visible outside `binary`, and the
/// inner type belongs to the internal kernel package
/// `Luna-Flow/floating/internal/bin_kernel`, which carries no compatibility
/// promise. Code outside the package works through the methods below; the
/// packages of this module that need the kernel type use `to_kernel` and
/// `from_kernel`. The wrapper is a newtype (no extra allocation and no extra
/// call).
struct BinCoeff(@bin_kernel.Coeff)

///|
/// Bridge to the kernel type, for the packages of this module only. The type it
/// returns is internal and may change in any release; reading the field of the
/// wrapper directly is not supported either.
#internal(internal, "bridge to the internal kernel type, for the packages of this module")
pub fn BinCoeff::to_kernel(self : BinCoeff) -> @bin_kernel.Coeff {
  self.0
}

///|
/// Bridge from the kernel type, for the packages of this module only.
#internal(internal, "bridge from the internal kernel type, for the packages of this module")
pub fn BinCoeff::from_kernel(value : @bin_kernel.Coeff) -> BinCoeff {
  BinCoeff(value)
}

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
pub fn BinCoeff::to_uint64(self : BinCoeff) -> UInt64? {
  self.0.to_uint64()
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
pub impl Debug for BinCoeff with fn to_repr(self) {
  @debug.Repr::integer(self.0.to_string())
}

///|
pub extend BinCoeff with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend BinCoeff with Eq::{not_equal, equal}

///|
pub extend BinCoeff with Compare::{op_lt, op_le, op_ge, op_gt}

///|
pub extend BinCoeff with Show::{output}
