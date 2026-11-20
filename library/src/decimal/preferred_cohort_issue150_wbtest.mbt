///|
/// IEEE 754-2019 §5.4.1 (convertFromInt: preferred exponent 0), §5.4.2
/// (exact binary to decimal: the exponent closest to the preferred one) and
/// §5.2 (an inexact result takes the least possible exponent, i.e. exactly p
/// digits). Expected values: Python `fractions`/`decimal` cross-check.
test "integer and binary constructors return the IEEE preferred cohort (#150)" {
  let s = fn(x : Decimal) { x.to_string() }
  inspect(s(Decimal::from_int(1000)), content="1000")
  inspect(s(Decimal::from_int(-1000)), content="-1000")
  inspect(s(Decimal::from_int(0)), content="0")
  inspect(
    s(Decimal::from_bigint(100000000000000000000N)),
    content="100000000000000000000",
  )
  inspect(s(Decimal::from_int(1000, precision=3)), content="1.00E+3")
  inspect(s(Decimal::from_int(1234, precision=3)), content="1.23E+3")
  inspect(s(Decimal::from_int(99999, precision=3)), content="1.00E+5")
  inspect(s(Decimal::from_int(-99999, precision=3)), content="-1.00E+5")
  inspect(s(Decimal::from_int(100, precision=3)), content="100")
  inspect(
    s(Decimal::from_double(0.1, precision=16)),
    content="0.1000000000000000",
  )
  inspect(
    s(Decimal::from_double(0.1, precision=17)),
    content="0.10000000000000001",
  )
  inspect(s(Decimal::from_double(0.5)), content="0.5")
  inspect(s(Decimal::from_double(0.25)), content="0.25")
  inspect(s(Decimal::from_double(100.0)), content="100")
  inspect(s(Decimal::from_double(2.0)), content="2")
  inspect(s(Decimal::from_double(-1.5)), content="-1.5")
  inspect(s(Decimal::from_double(1.0e22)), content="10000000000000000000000")
  inspect(s(Decimal::from_double(-1.0e22, precision=5)), content="-1.0000E+22")
  inspect(s(Decimal::from_double(1.5e300, precision=3)), content="1.50E+300")
  inspect(s(Decimal::from_float(0.25)), content="0.25")
  inspect(s(Decimal::from_float(100.0)), content="100")
  inspect(
    s(
      Decimal::from_bin_float(
        @bin_float.BinFloat::from_double(6.0, precision=53),
      ),
    ),
    content="6",
  )
}
