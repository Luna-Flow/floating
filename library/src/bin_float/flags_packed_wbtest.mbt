// `BinaryFlags` is a scalar (a newtype over an abstract newtype over `UInt`): its
// accessors, `combine`, equality and printed form are those of the record of six
// Booleans it replaced.

///|
#derive(Debug)
struct PackedFlagsReference {
  inexact : Bool
  underflow : Bool
  overflow : Bool
  division_by_zero : Bool
  invalid_operation : Bool
  not_computed : Bool
}

///|
fn packed_flags_from(mask : Int32) -> BinaryFlags {
  let mut bits = 0U
  if (mask & 1) != 0 {
    bits = bits | binary_flag_inexact
  }
  if (mask & 2) != 0 {
    bits = bits | binary_flag_underflow
  }
  if (mask & 4) != 0 {
    bits = bits | binary_flag_overflow
  }
  if (mask & 8) != 0 {
    bits = bits | binary_flag_division_by_zero
  }
  if (mask & 16) != 0 {
    bits = bits | binary_flag_invalid_operation
  }
  if (mask & 32) != 0 {
    bits = bits | binary_flag_not_computed
  }
  BinaryFlags::from_bits(bits)
}

///|
test "every combination of the six flags reads, combines and prints as the record did" {
  for mask in 0..<64 {
    let flags = packed_flags_from(mask)
    assert_eq(flags.inexact(), (mask & 1) != 0)
    assert_eq(flags.underflow(), (mask & 2) != 0)
    assert_eq(flags.overflow(), (mask & 4) != 0)
    assert_eq(flags.division_by_zero(), (mask & 8) != 0)
    assert_eq(flags.invalid_operation(), (mask & 16) != 0)
    assert_eq(flags.not_computed(), (mask & 32) != 0)
    // the printed form is the derived one of the record
    let reference : PackedFlagsReference = {
      inexact: (mask & 1) != 0,
      underflow: (mask & 2) != 0,
      overflow: (mask & 4) != 0,
      division_by_zero: (mask & 8) != 0,
      invalid_operation: (mask & 16) != 0,
      not_computed: (mask & 32) != 0,
    }
    assert_eq(
      @debug.to_string(flags).replace_all(old="BinaryFlags", new=""),
      @debug.to_string(reference).replace_all(
        old="PackedFlagsReference",
        new="",
      ),
    )
    for other in 0..<64 {
      let combined = flags.combine(packed_flags_from(other))
      assert_true(combined == packed_flags_from(mask | other))
      assert_eq(flags == packed_flags_from(other), mask == other)
    }
    // the TestFloat mask is the five low flags in TestFloat order
    assert_eq(flags.to_testfloat_bits(), mask & 31)
  }
  assert_true(BinaryFlags::new() == packed_flags_from(0))
}
