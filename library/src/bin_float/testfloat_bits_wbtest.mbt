// The five flags as the TestFloat bit mask (inexact 0x01, underflow 0x02,
// overflow 0x04, divideByZero 0x08, invalid 0x10), for the tests of this package.
// The TestFloat front end in `tooling/` builds the same mask on its own.

///|
fn BinaryFlags::to_testfloat_bits(self : BinaryFlags) -> Int32 {
  (if self.inexact() { 0x01 } else { 0 }) |
  (if self.underflow() { 0x02 } else { 0 }) |
  (if self.overflow() { 0x04 } else { 0 }) |
  (if self.division_by_zero() { 0x08 } else { 0 }) |
  (if self.invalid_operation() { 0x10 } else { 0 })
}
