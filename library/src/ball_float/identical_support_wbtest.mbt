// `BinFloat`'s `==` is the numerical equality of IEEE 754-2019 5.6.1 (`-0 == +0`, a
// NaN unequal to itself, precisions ignored). The tests of this package that
// checked a bound or a result as a datum (the sign of a zero, the precision of
// the value) check it with `identical`, the structural equality `==` used to be.

///|
fn assert_identical(
  actual : @bin_float.BinFloat,
  expected : @bin_float.BinFloat,
  msg~ : String = "",
) -> Unit raise {
  if !actual.identical(expected) {
    fail(
      "\{msg}: \{actual} (precision \{actual.precision()}) is not identical to \{expected} (precision \{expected.precision()})",
    )
  }
}
