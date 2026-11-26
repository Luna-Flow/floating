///|
/// `not_computed` is a sixth flag of `BinaryFlags`: clear in `new()`, kept by
/// `combine`, compared by `==`, and not one of the five bits of TestFloat.

///|
// oracle: S
// source: the written contract of the sixth flag of this library (clear in new, kept by combine, part of equality, not one of the five TestFloat bits, the other flags unaffected); not_computed is not an IEEE 754-2019 flag, so no external value exists
// shares: BinaryFlags::new, from_bits, combine, the accessors and to_testfloat_bits are the code under test; binary_flag_not_computed and binary_invalid_flags build the flags
test "BinaryFlags not_computed is carried by new, combine and equality" {
  let clear = BinaryFlags::new()
  assert_false(clear.not_computed())
  let raised : BinaryFlags = BinaryFlags::from_bits(binary_flag_not_computed)
  assert_true(raised.not_computed())
  assert_false(raised.invalid_operation())
  assert_true(raised != clear)
  assert_true(clear.combine(raised).not_computed())
  assert_true(raised.combine(clear).not_computed())
  assert_true(raised.combine(raised) == raised)
  assert_false(clear.combine(clear).not_computed())
  // the other flags are unaffected by it
  let both = raised.combine(binary_invalid_flags())
  assert_true(both.not_computed() && both.invalid_operation())
  assert_false(both.inexact() || both.underflow() || both.overflow())
  assert_false(both.division_by_zero())
  // not an IEEE flag: the TestFloat mask ignores it
  assert_eq(raised.to_testfloat_bits(), 0)
  assert_eq(both.to_testfloat_bits(), 0x10)
}

///|
/// No operation raises it yet: the results of ordinary and of failing operations
/// have it clear (the elementary functions will raise it in a later step).

///|
// oracle: S
// source: the written rule that ordinary and failing operations (3 + 3, 3 / 0, sqrt(-3)) leave not_computed clear; a rule of this library, not of the standard
// shares: Binary::from_int and zero build the operands; add_ctx, div_ctx and sqrt_ctx are the code under test; not_computed reads the flag
test "BinaryFlags not_computed is not raised by operations yet" {
  let ctx = BinaryContext::binary64()
  let x = Binary::from_int(3)
  assert_false(x.add_ctx(x, ctx).1.not_computed())
  assert_false(x.div_ctx(Binary::zero(), ctx).1.not_computed())
  assert_false(x.neg().sqrt_ctx(ctx).1.not_computed())
}
