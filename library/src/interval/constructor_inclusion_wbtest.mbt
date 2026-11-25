///|
// Every `interval` constructor must return an interval that contains its
// input. `from_int` and `from_coefficient` used to round the value to the
// requested precision first and wrap the rounded result as a singleton, which
// excluded the input whenever it needed more bits than the precision.
// oracle: S
// source: containment only: the interval from_int(n, p) contains the integer n (Binary::from_int at 32 bits is exact for these n), for p = 8, 16, 24, 53; the ends are not checked
// shares: Binary::from_int, Interval::from_int and is_member (the code under test)
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
// oracle: S
// source: containment only: the interval from_coefficient(100001, p) contains 100001 for p = 8, 16, 24 and both signs; the ends are not checked
// shares: Binary::from_coefficient, BinCoeff::from_uint64, Interval::from_coefficient and is_member (the code under test)
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
// oracle: A
// source: 100001 < 2^53 is exact in 53 bits, so the interval is a point and its radius is 0 (IEEE 1788-2015 12.12.8, rad of a point)
// shares: Interval::from_int, radius and is_zero (the code under test)
test "Interval::from_int stays exact when the precision is wide enough" {
  let interval = Interval::from_int(100001, precision=53)
  assert_eq(interval.radius().classify(), FpClass::Finite)
  assert_true(interval.radius().is_zero())
}
