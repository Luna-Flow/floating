///|
/// `[RD(pi), RU(pi)]` at `precision` bits, from the two hexadecimal bounds of
/// pi in `oracle_repair_rows_wbtest.mbt` (Machin's formula in Python integers).
fn pi_reference_bounds(precision : Int32) -> (@binary.Binary, @binary.Binary) {
  let lo = @binary.Binary::from_hex(pi_ref_lo_hex, 2200).unwrap()
  let hi = @binary.Binary::from_hex(pi_ref_hi_hex, 2200).unwrap()
  (
    lo.with_precision(
      precision,
      @binary.BinaryRoundingMode::RoundTowardNegative,
    ),
    hi.with_precision(
      precision,
      @binary.BinaryRoundingMode::RoundTowardPositive,
    ),
  )
}

///|
// oracle: A
// source: pi by Machin's formula, 16 atan(1/5) - 4 atan(1/239), in Python integers with 2048 fractional bits (tools/generate_decimal_oracle_rows.py through tools/interval_pi_oracle.py, which proves that [RD(lo), RU(hi)] at p bits is [RD(pi), RU(pi)] for every p from 2 to 2048); the earlier oracle was the previous construction 4 atan(1) through the interval atan
// shares: Binary::from_hex (reads the literal, exact at 2200 bits) and Binary::with_precision (directed rounding to p bits), as in the interval package's pi table; Binary::compare
test "decimal pi enclosure equals 4 atan(1) bit for bit" {
  let mut precision = 1
  while precision <= 300 {
    let fresh = decimal_pi_ball(precision)
    let (lower, upper) = pi_reference_bounds(precision)
    assert_true(
      fresh.lower_bound().compare(lower) == 0,
      msg="lower bound differs at precision \{precision}",
    )
    assert_true(
      fresh.upper_bound().compare(upper) == 0,
      msg="upper bound differs at precision \{precision}",
    )
    assert_eq(fresh.precision(), precision)
    precision += if precision < 80 { 1 } else { 17 }
  }
  for precision in [512, 1000, 2048] {
    let fresh = decimal_pi_ball(precision)
    let (lower, upper) = pi_reference_bounds(precision)
    assert_true(fresh.lower_bound().compare(lower) == 0)
    assert_true(fresh.upper_bound().compare(upper) == 0)
  }
}

///|
// oracle: A
// source: the bounds of pi of the block above divided by 4 (a power of two: exact), pi/4 = atan(1); the earlier oracle was the interval atan(1) of the library
// shares: Binary::from_hex, Binary::with_precision, Binary::make, mul_ctx by 2^-2 (exact, no rounding) and Binary::compare
test "decimal quarter pi multiples equal quarters of the atan(1) interval" {
  for precision in [1, 2, 7, 24, 53, 64, 113, 200, 333] {
    let pi = decimal_pi_enclosure(precision)
    let scale = @binary.Binary::make(@binary.BinCoeff::one(), -2, 2)
    let exact = @binary.BinaryContext::new(precision~)
    let quarter_lower = pi.0.mul_ctx(scale, exact).0
    let quarter_upper = pi.1.mul_ctx(scale, exact).0
    let (lower, upper) = pi_reference_bounds(precision)
    assert_true(
      quarter_lower.compare(lower.mul_ctx(scale, exact).0) == 0,
      msg="lower quarter at precision \{precision}",
    )
    assert_true(
      quarter_upper.compare(upper.mul_ctx(scale, exact).0) == 0,
      msg="upper quarter at precision \{precision}",
    )
  }
}
