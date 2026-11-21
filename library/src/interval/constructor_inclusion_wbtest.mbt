///|
/// Every `interval` constructor must return an interval that contains its
/// input. `from_int` and `from_coefficient` used to round the value to the
/// requested precision first and wrap the rounded result as a singleton, which
/// excluded the input whenever it needed more bits than the precision.
test "Interval::from_int contains integers wider than the precision" {
  for n in [100001, 65537, 123456789, 2147483647, -100001, -2147483647] {
    let exact = @binary.Binary::from_int(n, precision=32)
    for precision in [16, 8, 24, 53] {
      let interval = Interval::from_int(n, precision~)
      assert_true(interval.is_member(exact))
    }
  }
}

///|
test "Interval::from_coefficient contains coefficients wider than the precision" {
  let coefficient = @binary.BinCoeff::from_uint64(100001UL)
  for negative in [false, true] {
    let exact = @binary.Binary::from_coefficient(
      coefficient,
      precision=Int32::max(1, coefficient.bit_length()),
      negative~,
    )
    for precision in [16, 8, 24] {
      let interval = Interval::from_coefficient(
        coefficient,
        precision~,
        negative~,
      )
      assert_true(interval.is_member(exact))
    }
  }
}

///|
test "Interval::from_int stays exact when the precision is wide enough" {
  let interval = Interval::from_int(100001, precision=53)
  assert_eq(interval.radius().classify(), FpClass::Finite)
  assert_true(interval.radius().is_zero())
}
