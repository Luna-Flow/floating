// `BinFloat`'s `==` is the numerical equality of IEEE 754-2019 5.6.1 (`-0 == +0`, a
// NaN unequal to itself, precisions ignored). The tests below that checked a
// result as a datum (the sign of a zero, the precision of the value, the kind of a
// NaN) check it with `identical`, the structural equality `==` used to be.

///|
fn assert_identical(
  actual : BinFloat,
  expected : BinFloat,
  msg~ : String = "",
) -> Unit raise {
  if !actual.identical(expected) {
    fail(
      "\{msg}: \{actual} (precision \{actual.precision()}) is not identical to \{expected} (precision \{expected.precision()})",
    )
  }
}

///|
/// The same for a value with its flags: `(value, flags)` of a contextual operation.
fn assert_identical_with_flags(
  actual : (BinFloat, BinaryFlags),
  expected : (BinFloat, BinaryFlags),
  msg~ : String = "",
) -> Unit raise {
  assert_identical(actual.0, expected.0, msg~)
  if actual.1 != expected.1 {
    fail(
      "\{msg}: the flags differ (inexact \{actual.1.inexact()} against \{expected.1.inexact()})",
    )
  }
}
