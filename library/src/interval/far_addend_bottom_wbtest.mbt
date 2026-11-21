// A far addend, and the two ends of the exponent range, in an endpoint sum (IEEE
// 1788-2015 12.10: tightest).
//
// ORACLE (level A): every expected value is written out in this file as a
// hexadecimal coefficient and an exponent; no `binary` operation produces one.
// The code under test is compared with them by `Binary::compare` and
// `Binary::make` only.
//   c + 2^-1073741902 = (253 * 2^120 + 1) * 2^-1073741902
//                     = 0xFD, 29 hex zeros, 0x1, times 2^-1073741902 (128 bits)
//   the largest finite number of 200 bits = (2^200 - 1) * 2^(e_max + 1 - 200)
//                     = 50 hex digits F, times 2^1073741624
//
// Before the change the stand-in for a far addend (a surrogate of the old exact route) was made
// at one bit and rounded away to the quantum of one bit, `2^e_min`, much larger than
// the addend: `fma` was looser than the tightest interval by that unit (#629). The
// exact product and sum of `fma` were made at their own bit length, so a value
// above the range was clamped at the largest finite number of that many bits (#631).
//

///|
fn fab_value(
  coefficient : UInt64,
  exponent : Int32,
  precision : Int32,
) -> @binary.Binary {
  let bits = Int32::max(
    precision,
    @binary.binary_implementation_e_min - exponent + 1,
  )
  @binary.Binary::make(
    @binary.BinCoeff::from_uint64(coefficient),
    exponent,
    bits,
  )
}

///|
fn fab_hex(
  text : String,
  exponent : Int32,
  precision : Int32,
) -> @binary.Binary {
  match @binary.BinCoeff::parse(text, radix=16) {
    Ok(coefficient) => @binary.Binary::make(coefficient, exponent, precision)
    Err(error) => abort(error)
  }
}

///|
fn fab_zeros(n : Int32) -> String {
  let mut text = ""
  for _ in 0..<n {
    text = text + "0"
  }
  text
}

///|
/// c + 2^-1073741902 at 128 bits, written out.
fn fab_expected_sum() -> @binary.Binary {
  fab_hex("FD" + fab_zeros(29) + "1", -1073741902, 128)
}

///|
/// The largest finite number of 200 bits, written out.
fn fab_expected_max_200() -> @binary.Binary {
  let mut text = ""
  for _ in 0..<50 {
    text = text + "F"
  }
  fab_hex(text, 1073741624, 200)
}

///|
test "fma with a product far below the range floor adds one p-bit unit, not 2^e_min" {
  // c = 253 * 2^-1073741782 (8 bits, a normal value), p = 128: its unit is
  // 2^-1073741902; the product is about 2^-2147483600
  let precision = 128
  let c = fab_value(253UL, -1073741782, precision)
  let tiny = fab_value(1UL, -1073741800, precision)
  let a = Interval::from_bounds(tiny, tiny, precision~)
  let sum = a.fma(a, Interval::from_bounds(c, c, precision~))
  // the product is positive: the tightest lower bound is c itself
  assert_true(sum.lower_bound().compare(c) == 0)
  assert_true(sum.upper_bound().compare(fab_expected_sum()) == 0)
}

///|
test "add of a value far below the range floor is rounded to the unit of the precision" {
  let precision = 128
  let c = fab_value(253UL, -1073741782, precision)
  let tiny = fab_value(1UL, -1073741800 - 100000, precision)
  let a = Interval::from_bounds(c, c, precision~)
  let b = Interval::from_bounds(tiny, tiny, precision~)
  let sum = a.add(b)
  assert_true(sum.lower_bound().compare(c) == 0)
  assert_true(sum.upper_bound().compare(fab_expected_sum()) == 0)
}

///|
test "fma of a product above the range has the largest finite number of the precision as its lower bound" {
  // 3 * 2^(e_max - 1) times 3 is above the range: its lower bound was the largest
  // finite number of the 4 bits of the exact product, not of the precision
  let precision = 200
  let e_max = @binary.binary_implementation_e_max
  let a = @binary.Binary::make(
    @binary.BinCoeff::from_uint64(3UL),
    e_max - 1,
    precision,
  )
  let x = Interval::from_bounds(a, a, precision~)
  let three = Interval::from_int(3, precision~)
  let zero = Interval::from_bounds(
    @binary.Binary::zero(precision~),
    @binary.Binary::zero(precision~),
    precision~,
  )
  let r = x.fma(three, zero)
  assert_true(r.lower_bound().compare(fab_expected_max_200()) == 0)
  assert_true(r.upper_bound().classify() == FpClass::Infinity)
  // the sum above the range, the product exact and finite: [M, +inf] as well
  let sum = x.fma(Interval::from_int(1, precision~), x)
  assert_true(sum.lower_bound().compare(fab_expected_max_200()) == 0)
  assert_true(sum.upper_bound().classify() == FpClass::Infinity)
}

///|
test "add, sub and cancel with endpoints of an inflated precision stay cheap and tight" {
  let precision = 128
  let big = @binary.Binary::make(
    @binary.BinCoeff::from_uint64(7UL),
    1000000,
    268435456,
  )
  let small = @binary.Binary::make(
    @binary.BinCoeff::from_uint64(5UL),
    -1000000,
    268435456,
  )
  let x = Interval::from_bounds(big, big, precision~)
  let y = Interval::from_bounds(small, small, precision~)
  // 7 * 2^1000000 + 5 * 2^-1000000: the lower bound of the sum is 7 * 2^1000000
  let sum = x.add(y)
  assert_true(sum.lower_bound().compare(big) == 0)
  let difference = x.sub(y)
  assert_true(difference.upper_bound().compare(big) == 0)
  // widths 0 and 0: cancel gives a point only when the widths are equal; the
  // second interval is wider
  let z = Interval::from_bounds(small, big, precision~)
  assert_true(x.cancel_minus(z).is_entire())
}
