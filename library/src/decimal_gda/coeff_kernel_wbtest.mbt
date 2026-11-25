///|
using @internal {digits10}

///|
fn reference_ln_atanh_scaled(
  numerator : BigInt,
  denominator : BigInt,
  scale : Int32,
) -> BigInt {
  guard numerator > bigint_zero() && denominator > bigint_zero() else {
    abort("reference ln atanh expects positive inputs")
  }
  if numerator == denominator {
    return bigint_zero()
  }
  let extra_digits = 8
  let work_scale = scale + extra_digits
  let negative = numerator < denominator
  let delta = if negative {
    denominator - numerator
  } else {
    numerator - denominator
  }
  let sum = numerator + denominator
  let scale_factor = pow10(work_scale)
  let delta2 = delta * delta
  let sum2 = sum * sum
  let mut power_num = delta
  let mut power_den = sum
  let mut divisor_index = 1N
  let mut total = bigint_zero()
  let stop_threshold = pow10(extra_digits)
  let mut active = true
  while active {
    let divisor = power_den * divisor_index
    let term = 2N * scale_factor * power_num / divisor
    total = total + term
    if term <= stop_threshold {
      active = false
    } else {
      power_num = power_num * delta2
      power_den = power_den * sum2
      divisor_index = divisor_index + 2N
    }
  }
  let rounded = round_positive_decimal_div(
    total,
    pow10(extra_digits),
    negative,
    DecimalRoundingMode::HalfEven,
  )
  if negative {
    -rounded
  } else {
    rounded
  }
}

///|
// oracle: A, E
// source: Python decimal (libmpdec) `Context(prec=400).ln(Decimal(k))` scaled by 10^scale and rounded half even, for k = 2, 5, 10 (rows below, written out); the library constants carry guard digits and are not correctly rounded, so the table bounds them (at most 2 units of the last place); the exact values are pinned by the previous BigInt atanh algorithm kept as `reference_ln_atanh_scaled`
// shares: dec_coeff_from_bigint_repr and to_bigint (conversion between the test BigInt and the kernel coefficient) ; for the bound; `round_positive_decimal_div` for the pinned part
// underneath: the previous algorithm is bounded by the same table at the same scales (level A)
test "BigInt-free ln constants preserve the old scaled integers" {
  let rows : Array[(Int32, String, String, String)] = [
    (1, "7", "16", "23"),
    (2, "69", "161", "230"),
    (8, "69314718", "160943791", "230258509"),
    (9, "693147181", "1609437912", "2302585093"),
    (10, "6931471806", "16094379124", "23025850930"),
    (
      34, "6931471805599453094172321214581766", "16094379124341003746007593332261876",
      "23025850929940456840179914546843642",
    ),
    (
      40, "6931471805599453094172321214581765680755", "16094379124341003746007593332261876395256",
      "23025850929940456840179914546843642076011",
    ),
    (
      64, "6931471805599453094172321214581765680755001343602552541206800095", "16094379124341003746007593332261876395256013542685177219126478915",
      "23025850929940456840179914546843642076011014886287729760333279010",
    ),
    (
      128, "69314718055994530941723212145817656807550013436025525412068000949339362196969471560586332699641868754200148102057068573368552024",
      "160943791243410037460075933322618763952560135426851772191264789147417898770765776463013387809317961079996630302171556289972400523",
      "230258509299404568401799145468436420760110148862877297603332790096757260967735248023599720508959829834196778404228624863340952547",
    ),
    (
      257, "69314718055994530941723212145817656807550013436025525412068000949339362196969471560586332699641868754200148102057068573368552023575813055703267075163507596193072757082837143519030703862389167347112335011536449795523912047517268157493206515552473413952588295",
      "160943791243410037460075933322618763952560135426851772191264789147417898770765776463013387809317961079996630302171556289972400522932467619963361661746370572755217963749718324565349285620234152505727015519360087977738972568819354071276615473122180952794852129",
      "230258509299404568401799145468436420760110148862877297603332790096757260967735248023599720508959829834196778404228624863340952546508280675666628736909878168948290720832555468084379989482623319852839350530896537773262884616336622228769821988674654366747440424",
    ),
  ]
  let saved_cache = decimal_math_constant_cache.val
  decimal_math_constant_cache.val = {
    scale: 0,
    ln2: dec_coeff_zero(),
    ln5: dec_coeff_zero(),
    ln10: dec_coeff_zero(),
  }
  for row in rows {
    let (scale, text2, text5, text10) = row
    let table2 = @string.parse_bigint(text2)
    let table5 = @string.parse_bigint(text5)
    let table10 = @string.parse_bigint(text10)
    let expected_ln2 = reference_ln_atanh_scaled(2N, 1N, scale)
    let expected_lnfq = reference_ln_atanh_scaled(5N, 4N, scale)
    let expected_ln10 = expected_ln2 * 3N + expected_lnfq
    let expected_ln5 = expected_ln10 - expected_ln2
    let actual_ln2 = decimal_ln_atanh_scaled_coeff(
      dec_coeff_from_int(2),
      dec_coeff_from_int(1),
      scale,
    )
    let actual_reverse = decimal_ln_atanh_scaled_coeff(
      dec_coeff_from_int(1),
      dec_coeff_from_int(2),
      scale,
    )
    assert_false(actual_ln2.negative)
    assert_true(actual_reverse.negative)
    assert_eq(actual_ln2.magnitude.to_bigint(), expected_ln2)
    assert_eq(actual_reverse.magnitude.to_bigint(), expected_ln2)
    let (ln2, ln5, ln10) = decimal_transcendental_ln_constants(scale)
    assert_eq(ln2.to_bigint(), expected_ln2)
    assert_eq(ln5.to_bigint(), expected_ln5)
    assert_eq(ln10.to_bigint(), expected_ln10)
    // the independent bound: within 2 units of the correctly rounded value
    let two = BigInt::from_int(2)
    assert_true(abs_bigint(ln2.to_bigint() - table2) <= two)
    assert_true(abs_bigint(ln5.to_bigint() - table5) <= two)
    assert_true(abs_bigint(ln10.to_bigint() - table10) <= two)
  }
  let high = decimal_transcendental_ln_constants(257)
  let low = decimal_transcendental_ln_constants(34)
  assert_eq(
    low.2.to_bigint(),
    round_positive_decimal_div(
      high.2.to_bigint(),
      pow10(223),
      false,
      DecimalRoundingMode::HalfEven,
    ),
  )
  decimal_math_constant_cache.val = saved_cache
}

///|
// oracle: A
// source: core BigInt `/` and `%` of the same operands (MoonBit core, not this library), and the identity q * d + r = n
// shares: dec_coeff_from_bigint_repr and to_bigint (conversion between the test BigInt and the kernel coefficient) ;; the operands are built by dec_coeff_from_bigint_repr and read back by to_bigint, an error in either breaks the equality
test "Knuth quotient clamp preserves the full normalized remainder" {
  let numerator = 81531386803002131355773364661909970000000000000000000000000000000000000000000000000000000000000000000N
  let denominator = 8153138680300213135577336466220607N
  let (quotient, remainder) = dec_coeff_div_rem_knuth_repr(
    dec_coeff_from_bigint_repr(numerator),
    dec_coeff_from_bigint_repr(denominator),
  )
  assert_eq(quotient.to_bigint(), numerator / denominator)
  assert_eq(remainder.to_bigint(), numerator % denominator)
  assert_eq(
    quotient.to_bigint() * denominator + remainder.to_bigint(),
    numerator,
  )
}

///|
fn reference_round_positive_decimal_div_pow10(
  numerator : BigInt,
  shift : Int32,
  negative : Bool,
  mode : DecimalRoundingMode,
) -> (BigInt, Bool) {
  // test-local: core BigInt `/` and `%` by 10^shift and a table of the eight
  // rounding rules of GDA 1.70, nothing of the library
  let divisor = BigInt::from_int(10).pow(BigInt::from_int(shift))
  let quotient = numerator / divisor
  let remainder = numerator % divisor
  if remainder.is_zero() {
    return (quotient, false)
  }
  let twice = remainder * BigInt::from_int(2)
  let last = (quotient % BigInt::from_int(10)).to_int()
  let up = match mode {
    Down => false
    Up => true
    Ceiling => !negative
    Floor => negative
    ZeroFiveUp => last == 0 || last == 5
    HalfUp => twice >= divisor
    HalfDown => twice > divisor
    HalfEven =>
      twice > divisor ||
      (
        twice == divisor &&
        quotient % BigInt::from_int(2) == BigInt::from_int(1)
      )
  }
  (if up { quotient + BigInt::from_int(1) } else { quotient }, true)
}

///|
fn reference_decimal_exact_int(rhs : Decimal) -> Int32? {
  decimal_power_integer_count(rhs, 999_999_999)
}

///|
fn reference_remove_factor(base : Int32, n : BigInt) -> BigInt {
  let factor = BigInt::from_int(base)
  let mut value = n
  while (value % factor).is_zero() {
    value = value / factor
  }
  value
}

///|
fn reference_gcd_bigint(a : BigInt, b : BigInt) -> BigInt {
  let mut x = abs_bigint(a)
  let mut y = abs_bigint(b)
  while !y.is_zero() {
    let remainder = x % y
    x = y
    y = remainder
  }
  if x.is_zero() {
    bigint_one()
  } else {
    x
  }
}

///|
fn reference_has_finite_decimal_expansion(
  numerator : BigInt,
  denominator : BigInt,
) -> Bool {
  let divisor = denominator / reference_gcd_bigint(numerator, denominator)
  let without_twos = reference_remove_factor(2, abs_bigint(divisor))
  let without_fives = reference_remove_factor(5, without_twos)
  without_fives == bigint_one()
}

///|
// oracle: A
// source: written out: 12345000 / 10^3 = 12345 and 5000 / 10^2 = 50, divisibility by hand
// shares: dec_coeff_from_bigint_repr and to_bigint (conversion between the test BigInt and the kernel coefficient)
test "decimal coefficient exact power-of-ten division uses unit shifts" {
  match
    exact_divide_by_power_of_ten_repr(dec_coeff_from_bigint_repr(12345000N), 3) {
    Some(value) => assert_eq(value.to_bigint(), 12345N)
    None => fail("expected exact division by 10^3")
  }
  match
    exact_divide_by_power_of_ten_repr(dec_coeff_from_bigint_repr(5000N), 2) {
    Some(value) => assert_eq(value.to_bigint(), 50N)
    None => fail("expected exact division by 10^2")
  }
  assert_true(
    exact_divide_by_power_of_ten_repr(dec_coeff_from_bigint_repr(12345N), 1)
    is None,
  )
}

///|
// oracle: A
// source: written out: 4999 < 5000 = 10^4 / 2 < 5001 and a 21-digit case, by hand
// shares: dec_coeff_from_bigint_repr and to_bigint (conversion between the test BigInt and the kernel coefficient)
test "decimal half-power comparison uses decimal leading digits" {
  assert_eq(
    dec_coeff_compare_half_power10(dec_coeff_from_bigint_repr(4999N)),
    -1,
  )
  assert_eq(
    dec_coeff_compare_half_power10(dec_coeff_from_bigint_repr(5000N)),
    0,
  )
  assert_eq(
    dec_coeff_compare_half_power10(dec_coeff_from_bigint_repr(5001N)),
    1,
  )
  assert_eq(
    dec_coeff_compare_half_power10(
      dec_coeff_from_bigint_repr(500000000000000000001N),
    ),
    1,
  )
}

///|
// oracle: A
// source: written out: carry and borrow cases in base 10^9 units, derived by hand
// shares: nothing
test "decimal decNumber-style unit add/sub matches carry and borrow cases" {
  let acc1 : Array[UInt32] = [0U, 0U, 0U, 0U]
  let lhs1 : Array[UInt32] = [
    (dec_coeff_base - 1).reinterpret_as_uint(),
    (dec_coeff_base - 1).reinterpret_as_uint(),
  ]
  let rhs1 : Array[UInt32] = [2U]
  let len1 = dec_coeff_unit_add_sub(lhs1, 2, rhs1, 1, 0, acc1, 1)
  assert_eq(len1, 3)
  assert_eq(acc1[0], 1)
  assert_eq(acc1[1], 0)
  assert_eq(acc1[2], 1)

  let acc2 : Array[UInt32] = [0U, 0U, 0U]
  let lhs2 : Array[UInt32] = [0U, 1U]
  let rhs2 : Array[UInt32] = [1U]
  let len2 = dec_coeff_unit_add_sub(lhs2, 2, rhs2, 1, 0, acc2, -1)
  assert_eq(len2, 2)
  assert_eq(acc2[0], (dec_coeff_base - 1).reinterpret_as_uint())
  assert_eq(acc2[1], 0)

  let acc3 : Array[UInt32] = [0U, 0U, 0U]
  let lhs3 : Array[UInt32] = [5U]
  let rhs3 : Array[UInt32] = [7U]
  let len3 = dec_coeff_unit_add_sub(lhs3, 1, rhs3, 1, 0, acc3, -1)
  assert_eq(len3, -1)
  assert_eq(acc3[0], 2)
}

///|
// oracle: A
// source: written out: 1000000 - 999999 = 1, 999999 + 1000000 carries to 1000001 in the other sign case, and cancellation gives +0, by hand
// shares: dec_coeff_from_bigint_repr and to_bigint (conversion between the test BigInt and the kernel coefficient)
test "decimal signed coefficient add matches remainder identity arithmetic" {
  let lhs = dec_coeff_from_bigint_repr(1000000N)
  let rhs = dec_coeff_from_bigint_repr(999999N)
  let (positive, one) = dec_coeff_signed_add_repr(false, lhs, true, rhs)
  assert_false(positive)
  assert_eq(one.to_bigint(), 1N)

  let (negative, minus_one) = dec_coeff_signed_add_repr(true, lhs, false, rhs)
  assert_true(negative)
  assert_eq(minus_one.to_bigint(), 1N)

  let (carry_negative, carry) = dec_coeff_signed_add_repr(
    false,
    dec_coeff_from_bigint_repr(999999N),
    false,
    dec_coeff_from_bigint_repr(2N),
  )
  assert_false(carry_negative)
  assert_eq(carry.to_bigint(), 1000001N)

  let (zero_negative, zero) = dec_coeff_signed_add_repr(false, lhs, true, lhs)
  assert_false(zero_negative)
  assert_true(zero.is_zero())
}

///|
// oracle: A
// source: written out: 10^20 is above +-999,999,999 in magnitude and 384 equals 384, by hand
// shares: dec_coeff_from_bigint_repr and to_bigint (conversion between the test BigInt and the kernel coefficient)
test "decimal signed coefficient compare proves power exponent bounds" {
  let huge = dec_coeff_from_bigint_repr(100000000000000000000N)
  assert_eq(dec_coeff_signed_compare_int_repr(false, huge, 999_999_999), 1)
  assert_eq(dec_coeff_signed_compare_int_repr(true, huge, -999_999_999), -1)
  assert_eq(
    dec_coeff_signed_compare_int_repr(
      false,
      dec_coeff_from_nonnegative_int(384),
      384,
    ),
    0,
  )
}

///|
// oracle: A
// source: written out: 999.999 + 0.001 = 1000000 and 1000 - 0.001 = 999999 at exponent -3, 10^55 + 10000, derived by hand
// shares: Decimal::from_string (reads the operands), dec_coeff_from_bigint_repr and to_bigint (conversion between the test BigInt and the kernel coefficient)
test "decimal exact aligned sum keeps GDA unit accumulator representation" {
  let carry_lhs = Decimal::from_string("999.999", precision=16).unwrap()
  let carry_rhs = Decimal::from_string("0.001", precision=16).unwrap()
  let (carry_negative, carry) = decimal_exact_aligned_sum_result(
    carry_lhs, carry_rhs, -3,
  )
  assert_false(carry_negative)
  assert_eq(carry.to_bigint(), 1000000N)

  let borrow_lhs = Decimal::from_string("1000", precision=16).unwrap()
  let borrow_rhs = Decimal::from_string("-0.001", precision=16).unwrap()
  let (borrow_negative, borrow) = decimal_exact_aligned_sum_result(
    borrow_lhs, borrow_rhs, -3,
  )
  assert_false(borrow_negative)
  assert_eq(borrow.to_bigint(), 999999N)

  let (reverse_negative, reverse) = decimal_exact_aligned_sum_result(
    borrow_rhs,
    Decimal::from_string("-1000", precision=16).unwrap(),
    -3,
  )
  assert_true(reverse_negative)
  assert_eq(reverse.to_bigint(), 1000001N)

  let huge_lhs = Decimal::from_string("10000E+1", precision=64).unwrap()
  let tiny_rhs = Decimal::from_string("10000E-50", precision=64).unwrap()
  let (huge_negative, huge) = decimal_exact_aligned_sum_result(
    huge_lhs, tiny_rhs, -50,
  )
  assert_false(huge_negative)
  assert_eq(huge.to_bigint(), pow10(55) + 10000N)
  assert_eq(huge.digits10(), 56)
}

///|
// oracle: A
// source: written out and checked with CPython: 999.999 + 0.001 = 1000.000 (exponent -3, not reduced) and 1.20 - 1.20 = 0.00 with a positive sign
// shares: Decimal::from_string (reads the operands), dec_coeff_from_bigint_repr and to_bigint (conversion between the test BigInt and the kernel coefficient)
test "decimal plain add normalizes the GDA unit accumulator directly" {
  let sum = Decimal::from_string("999.999", precision=7)
    .unwrap()
    .add(Decimal::from_string("0.001", precision=7).unwrap())
  // the sum is exact at the least exponent: 1000.000, not the reduced 1E+3
  assert_eq(sum.coefficient.to_bigint(), 1000000N)
  assert_eq(sum.exponent10, -3)
  assert_false(sum.negative)

  let cancellation = Decimal::from_string("1.20", precision=7)
    .unwrap()
    .add(Decimal::from_string("-1.20", precision=7).unwrap())
  assert_true(cancellation.coefficient.is_zero())
  assert_false(cancellation.negative)
}

///|
// oracle: A
// source: CPython add, precision 7, exponent range of the maximum: 1E+1000000000 + 1E-1000000000 = 1.000000E+1000000000 (x r), and + 0E-1000000000 gives the same value (r only); the library accepts operands above Emax 999999999, which the CPython context allows with its maximum range; the block checks coefficient 1000000, exponent 999999994
// shares: Decimal::from_string (reads the operands), dec_coeff_from_bigint_repr and to_bigint (conversion between the test BigInt and the kernel coefficient)
test "decimal plain add avoids expanding absorbed extreme exponents" {
  let high = Decimal::from_string("1E+1000000000", precision=7).unwrap()
  let tiny = Decimal::from_string("1E-1000000000", precision=7).unwrap()
  let sum = high.add(tiny)
  // inexact: seven digits at the least exponent, not reduced
  assert_eq(sum.coefficient.to_bigint(), 1000000N)
  assert_eq(sum.exponent10, 999999994)
  assert_eq(sum.precision_, 7)

  let zero = Decimal::from_string("0E-1000000000", precision=7).unwrap()
  let zero_sum = high.add(zero)
  assert_eq(zero_sum.coefficient.to_bigint(), 1000000N)
  assert_eq(zero_sum.exponent10, 999999994)
}

///|
// oracle: A
// source: CPython add, precision 3, half even: 1 + 0.005 = 1.00 and 1.01 + 0.005 = 1.02 (exact ties to even), 1.00 - 0.005 = 0.995 (verified 2026-11-25)
// shares: Decimal::from_string (reads the operands), Decimal::to_string (prints the result)
test "decimal plain add preserves half-even absorption boundaries" {
  let even_tie = Decimal::from_string("1", precision=3)
    .unwrap()
    .add(Decimal::from_string("0.005", precision=3).unwrap())
  assert_eq(even_tie.to_string(), "1.00")

  let odd_tie = Decimal::from_string("1.01", precision=3)
    .unwrap()
    .add(Decimal::from_string("0.005", precision=3).unwrap())
  assert_eq(odd_tie.to_string(), "1.02")

  let cancellation_boundary = Decimal::from_string("1.00", precision=3)
    .unwrap()
    .add(Decimal::from_string("-0.005", precision=3).unwrap())
  assert_eq(cancellation_boundary.to_string(), "0.995")
}

///|
// oracle: A
// source: written out and checked with CPython integers: 999 * 999 = 998001 and 1219326311247834171483
// shares: dec_coeff_from_bigint_repr and to_bigint (conversion between the test BigInt and the kernel coefficient)
test "decimal decNumber-style coefficient multiply matches long multiplication" {
  assert_eq(
    dec_coeff_multiply_repr(
      dec_coeff_from_bigint_repr(0N),
      dec_coeff_from_bigint_repr(12345N),
    ).to_bigint(),
    0N,
  )
  assert_eq(
    dec_coeff_multiply_repr(
      dec_coeff_from_bigint_repr(999N),
      dec_coeff_from_bigint_repr(999N),
    ).to_bigint(),
    998001N,
  )
  assert_eq(
    dec_coeff_multiply_repr(
      dec_coeff_from_bigint_repr(1234567890123N),
      dec_coeff_from_bigint_repr(987654321N),
    ).to_bigint(),
    1219326311247834171483N,
  )
}

///|
// oracle: A
// source: written out by the rules of to-scientific-string and to-engineering-string (GDA 1.70): a 30-digit coefficient at exponents -35 and 5, derived by hand
// shares: Decimal::to_string (prints the result)
test "decimal coefficient and finite format builders preserve digit sequences" {
  let digits = "123456789012345678901234567890"
  let coefficient = dec_coeff_from_decimal_digits_repr(digits).unwrap()
  assert_eq(coefficient.to_string(), digits)
  assert_eq(
    format_plain_finite(
      finite_with_exponent_repr(false, coefficient, -35, digits.length()),
    ),
    "0.00000123456789012345678901234567890",
  )
  let scientific = finite_with_exponent_repr(
    true,
    coefficient,
    5,
    digits.length(),
  )
  assert_eq(
    format_sci_finite(scientific),
    "-1.23456789012345678901234567890E+34",
  )
  assert_eq(
    format_eng_finite(scientific),
    "-12.3456789012345678901234567890E+33",
  )
}

///|
// oracle: A
// source: written out and checked with CPython divmod: 1000 / 7 = 142 r 6, 1234567890123 and 1234567967901238 r 766790339
// shares: dec_coeff_from_bigint_repr and to_bigint (conversion between the test BigInt and the kernel coefficient)
test "decimal decNumber-style coefficient divide returns quotient and residue" {
  let (q0, r0) = dec_coeff_div_rem_repr(
    dec_coeff_from_bigint_repr(0N),
    dec_coeff_from_bigint_repr(37N),
  )
  assert_eq(q0.to_bigint(), 0N)
  assert_eq(r0.to_bigint(), 0N)
  let (q1, r1) = dec_coeff_div_rem_repr(
    dec_coeff_from_bigint_repr(1000N),
    dec_coeff_from_bigint_repr(7N),
  )
  assert_eq(q1.to_bigint(), 142N)
  assert_eq(r1.to_bigint(), 6N)
  let (q2, r2) = dec_coeff_div_rem_repr(
    dec_coeff_from_bigint_repr(1219326311247834171483N),
    dec_coeff_from_bigint_repr(987654321N),
  )
  assert_eq(q2.to_bigint(), 1234567890123N)
  assert_eq(r2.to_bigint(), 0N)
  let (q3, r3) = dec_coeff_div_rem_repr(
    dec_coeff_from_bigint_repr(1234567890123456789012345N),
    dec_coeff_from_bigint_repr(999999937N),
  )
  assert_eq(q3.to_bigint(), 1234567967901238N)
  assert_eq(r3.to_bigint(), 766790339N)
}

///|
// oracle: A
// source: core BigInt +, -, *, / and % on the boundary values 0, 1, 9, 10, 10^k - 1, 10^k, 10^k + 1 up to 34 digits (two assertions compare dec_coeff_unit_len(x) with itself and prove nothing)
// shares: dec_coeff_from_bigint_repr and to_bigint (conversion between the test BigInt and the kernel coefficient)
test "optimized decimal coefficient primitives match BigInt boundaries" {
  let boundaries : Array[BigInt] = [
    0N, 1N, 2N, 9N, 10N, 99N, 999N, 1000N, 1001N, 999999N, 1000000N, 1000001N, 999999999N,
    1000000000N, 1000000001N, 999999999999999999N, 1000000000000000000N, 1000000000000000001N,
    9999999999999999999999999999999999N, 10000000000000000000000000000000000N,
  ]
  for left_bigint in boundaries {
    let left = dec_coeff_from_bigint_repr(left_bigint)
    for right_bigint in boundaries {
      let right = dec_coeff_from_bigint_repr(right_bigint)
      let sum = dec_coeff_magnitude_add_repr(left, right)
      assert_eq(sum.to_bigint(), left_bigint + right_bigint)
      assert_eq(dec_coeff_unit_len(sum), dec_coeff_unit_len(sum))
      let product = dec_coeff_multiply_repr(left, right)
      assert_eq(product.to_bigint(), left_bigint * right_bigint)
      if left_bigint >= right_bigint {
        let difference = dec_coeff_magnitude_sub_repr(left, right)
        assert_eq(difference.to_bigint(), left_bigint - right_bigint)
        assert_eq(
          dec_coeff_unit_len(difference),
          dec_coeff_unit_len(difference),
        )
      }
      if !right_bigint.is_zero() {
        let (quotient, remainder) = dec_coeff_div_rem_repr(left, right)
        assert_eq(quotient.to_bigint(), left_bigint / right_bigint)
        assert_eq(remainder.to_bigint(), left_bigint % right_bigint)
      }
    }
  }
}

///|
// oracle: A
// source: core BigInt arithmetic on a deterministic LCG matrix of 96 operand pairs below 10^120 (the comparison compare_repr < 0 is a self-consistency check)
// shares: dec_coeff_from_bigint_repr and to_bigint (conversion between the test BigInt and the kernel coefficient)
test "optimized decimal coefficient primitives match deterministic BigInt matrix" {
  let modulus = pow10(120) - 159N
  let mut left_state = 123456789N
  let mut right_state = 987654321N
  for index in 1..<97 {
    let index_bigint = BigInt::from_int(index)
    left_state = (left_state * 1000003N + index_bigint * 97N + 17N) % modulus
    right_state = (right_state * 1000033N + index_bigint * 193N + 29N) % modulus
    let divisor_bigint = right_state + 1N
    let decimal_shift = index % 37
    let numerator_bigint = left_state * pow10(decimal_shift) + right_state
    let left = dec_coeff_from_bigint_repr(left_state)
    let right = dec_coeff_from_bigint_repr(right_state)
    let numerator = dec_coeff_from_bigint_repr(numerator_bigint)
    let divisor = dec_coeff_from_bigint_repr(divisor_bigint)
    assert_eq(
      dec_coeff_magnitude_add_repr(left, right).to_bigint(),
      left_state + right_state,
    )
    assert_eq(
      dec_coeff_multiply_repr(left, right).to_bigint(),
      left_state * right_state,
    )
    let (quotient, remainder) = dec_coeff_div_rem_repr(numerator, divisor)
    assert_eq(quotient.to_bigint(), numerator_bigint / divisor_bigint)
    assert_eq(remainder.to_bigint(), numerator_bigint % divisor_bigint)
    assert_true(dec_coeff_compare_repr(remainder, divisor) < 0)
  }
}

///|
// oracle: A
// source: core BigInt `/` and `%` by the divisors 1, 2, 3, 5, 7, 10, 97, 499, 998, 999
// shares: dec_coeff_from_bigint_repr and to_bigint (conversion between the test BigInt and the kernel coefficient)
test "optimized decimal coefficient single-unit division matches BigInt" {
  let numerator_bigint = pow10(180) - 123456789N
  let numerator = dec_coeff_from_bigint_repr(numerator_bigint)
  for divisor in [1, 2, 3, 5, 7, 10, 97, 499, 998, 999] {
    let divisor_bigint = BigInt::from_int(divisor)
    let (quotient, remainder) = dec_coeff_div_rem_repr(
      numerator,
      dec_coeff_from_int(divisor),
    )
    assert_eq(quotient.to_bigint(), numerator_bigint / divisor_bigint)
    assert_eq(remainder.to_bigint(), numerator_bigint % divisor_bigint)
  }
}

///|
// oracle: A
// source: n = d * q + r constructed in core BigInt from boundary denominators and quotients; the expected q and r are known by construction
// shares: dec_coeff_from_bigint_repr and to_bigint (conversion between the test BigInt and the kernel coefficient)
test "optimized decimal coefficient quotient estimate matches constructed cases" {
  let denominators : Array[BigInt] = [
    1000N, 1001N, 1999N, 500999N, 999999N, 1000001N, 999999937N, 999999999N, 1000000000N,
    1000000001N, 999999999999999999N, 1000000000000000000N, 1000000000000000001N,
    100000000000000000000000000003N,
  ]
  let quotients : Array[BigInt] = [
    1N, 2N, 499N, 998N, 999N, 1000N, 1001N, 499999N, 999999N, 1000000N, 999999999999999999N,
  ]
  for denominator_bigint in denominators {
    let denominator = dec_coeff_from_bigint_repr(denominator_bigint)
    let remainders = [0N, 1N, denominator_bigint / 2N, denominator_bigint - 1N]
    for expected_quotient in quotients {
      for expected_remainder in remainders {
        let numerator_bigint = denominator_bigint * expected_quotient +
          expected_remainder
        let (quotient, remainder) = dec_coeff_div_rem_repr(
          dec_coeff_from_bigint_repr(numerator_bigint),
          denominator,
        )
        assert_eq(quotient.to_bigint(), expected_quotient)
        assert_eq(remainder.to_bigint(), expected_remainder)
      }
    }
  }
}

///|
// oracle: A, S
// source: the defining property of the integer square root, root^2 + rem = value with 0 <= rem <= 2 * root, which fixes the root uniquely, checked with core BigInt arithmetic on values up to 10^160; it is a characterisation, not a table of values
// shares: the conversion functions dec_coeff_from_bigint_repr and to_bigint
test "decimal integer sqrt_rem preserves exact decomposition" {
  for
    value in [
      0N,
      1N,
      2N,
      3N,
      4N,
      15N,
      16N,
      17N,
      999999998000000001N,
      999999999999999999N,
      pow10(160) - 1N,
    ] {
    let (root, remainder) = dec_coeff_integer_sqrt_rem_repr(
      dec_coeff_from_bigint_repr(value),
    )
    let root_bigint = root.to_bigint()
    assert_eq(root_bigint * root_bigint + remainder.to_bigint(), value)
    assert_true(remainder.to_bigint() < root_bigint * 2N + 1N)
  }
}

///|
fn dec_coeff_test_dense_pattern(length : Int32, salt : Int32) -> DecCoeff {
  let limbs = Array::make(length, 0U)
  for index in 0..<length {
    let value = ((index + 1) * 104729 + salt * 13007) % (dec_coeff_base - 1) + 1
    limbs[index] = value.reinterpret_as_uint()
  }
  limbs[length - 1] = (dec_coeff_base - 1 - salt).reinterpret_as_uint()
  dec_coeff_from_unit_accumulator(limbs, limbs.length())
}

///|
// oracle: B
// source: numerator = d * q + r with q and r constructed from dense digit patterns; the division must return exactly q and r
// shares: multiply_repr and magnitude_add_repr build the numerator
// primitives: multiply_repr, magnitude_add_repr (level A: the blocks "optimized decimal coefficient primitives match BigInt boundaries" and "... deterministic BigInt matrix" of this file compare them with core BigInt)
test "Burnikel-Ziegler recursive block boundaries match exact quotients" {
  for length in [17, 31, 32, 33, 47, 48, 49, 63, 64, 65] {
    let denominator = dec_coeff_test_dense_pattern(length, 3)
    let expected_quotient = dec_coeff_test_dense_pattern(length + 7, 5)
    let expected_remainder = dec_coeff_slice(
      denominator,
      0,
      Int32::max(1, length / 2),
    )
    let numerator = dec_coeff_magnitude_add_repr(
      dec_coeff_multiply_repr(denominator, expected_quotient),
      expected_remainder,
    )
    let (quotient, remainder) = dec_coeff_div_rem_burnikel_ziegler(
      numerator, denominator,
    )
    assert_eq(quotient.to_bigint(), expected_quotient.to_bigint())
    assert_eq(remainder.to_bigint(), expected_remainder.to_bigint())
    assert_eq(
      quotient.to_bigint() * denominator.to_bigint() + remainder.to_bigint(),
      numerator.to_bigint(),
    )
    assert_true(remainder.to_bigint() < denominator.to_bigint())
  }
}

///|
// oracle: B
// source: numerator = d * q + r with q and r constructed from dense digit patterns; the division must return exactly q and r
// shares: multiply_repr and magnitude_add_repr build the numerator
// primitives: multiply_repr, magnitude_add_repr (level A: the blocks "optimized decimal coefficient primitives match BigInt boundaries" and "... deterministic BigInt matrix" of this file compare them with core BigInt)
test "Newton reciprocal division converges without fallback" {
  let denominator = dec_coeff_test_dense_pattern(64, 7)
  let expected_quotient = dec_coeff_test_dense_pattern(71, 11)
  let expected_remainder = dec_coeff_slice(denominator, 0, 29)
  let numerator = dec_coeff_magnitude_add_repr(
    dec_coeff_multiply_repr(denominator, expected_quotient),
    expected_remainder,
  )
  match dec_coeff_div_rem_newton_try(numerator, denominator) {
    Some((quotient, remainder)) => {
      assert_eq(quotient.to_bigint(), expected_quotient.to_bigint())
      assert_eq(remainder.to_bigint(), expected_remainder.to_bigint())
      assert_eq(
        quotient.to_bigint() * denominator.to_bigint() + remainder.to_bigint(),
        numerator.to_bigint(),
      )
      assert_true(remainder.to_bigint() < denominator.to_bigint())
    }
    None => fail("Newton reciprocal unexpectedly requested BZ fallback")
  }
}

///|
// oracle: A
// source: core BigInt `/` and `%` of the same operands, formed from powers of ten at 18, 36 and 72 digits
// shares: dec_coeff_from_bigint_repr and to_bigint (conversion between the test BigInt and the kernel coefficient)
test "normalized Knuth division matches BigInt at limb boundaries" {
  let cases : Array[(BigInt, BigInt)] = [
    (pow10(18) + 123456789N, pow10(9) + 7N),
    (pow10(36) - 1N, pow10(18) - 987654321N),
    (pow10(72) + 555555555555N, pow10(27) + 999999999N),
  ]
  for pair in cases {
    let numerator_bigint = pair.0
    let denominator_bigint = pair.1
    let numerator = dec_coeff_from_bigint_repr(numerator_bigint)
    let denominator = dec_coeff_from_bigint_repr(denominator_bigint)
    let (quotient, remainder) = dec_coeff_div_rem_knuth_repr(
      numerator, denominator,
    )
    assert_eq(quotient.to_bigint(), numerator_bigint / denominator_bigint)
    assert_eq(remainder.to_bigint(), numerator_bigint % denominator_bigint)
    assert_eq(
      quotient.to_bigint() * denominator_bigint + remainder.to_bigint(),
      numerator_bigint,
    )
    assert_true(remainder.to_bigint() < denominator_bigint)
  }
}

///|
// oracle: A
// source: written out. 125/10 = 12.5, an exact tie: half even gives 12, half up gives 13; 123456789012345678901 = 97 * 1272750402189130710 + 31 (Python divmod), a negative operand rounded toward negative infinity takes the magnitude up, 1272750402189130711
// shares: dec_coeff_from_bigint_repr and to_bigint (conversion between the test BigInt and the kernel coefficient)
test "decimal coefficient repr rounded division is isomorphic to BigInt path" {
  let numerator = dec_coeff_from_bigint_repr(125N)
  let denominator = dec_coeff_from_bigint_repr(10N)
  assert_eq(
    round_positive_decimal_div_repr(
      numerator,
      denominator,
      false,
      DecimalRoundingMode::HalfEven,
    ).to_bigint(),
    12N,
  )
  assert_eq(
    round_positive_decimal_div_repr(
      numerator,
      denominator,
      false,
      DecimalRoundingMode::HalfUp,
    ).to_bigint(),
    13N,
  )
  assert_eq(
    round_positive_decimal_div_repr(
      dec_coeff_from_bigint_repr(123456789012345678901N),
      dec_coeff_from_bigint_repr(97N),
      true,
      DecimalRoundingMode::Floor,
    ).to_bigint(),
    1272750402189130711N,
  )
}

///|
// oracle: A
// source: CPython divide: 1 / 8 = 0.125 (coefficient 125, exponent -3) and -2 / 3 at precision 3 = -0.667
// shares: dec_coeff_from_bigint_repr and to_bigint (conversion between the test BigInt and the kernel coefficient)
test "decimal plain division keeps GDA quotient units through normalization" {
  let exact = Decimal::from_int(1, precision=16).div(
    Decimal::from_int(8, precision=16),
  )
  assert_eq(exact.coefficient.to_bigint(), 125N)
  assert_eq(exact.exponent10, -3)
  assert_false(exact.negative)

  let rounded = Decimal::from_int(-2, precision=3).div(
    Decimal::from_int(3, precision=3),
  )
  assert_eq(rounded.coefficient.to_bigint(), 667N)
  assert_eq(rounded.exponent10, -3)
  assert_true(rounded.negative)
}

///|
// oracle: A
// source: written out: 123E+2 / 10 = 1230; 125 / 10 and 135 / 10 are exact ties, half even gives 12 and 14
// shares: Decimal::from_string (reads the operands), dec_coeff_from_bigint_repr and to_bigint (conversion between the test BigInt and the kernel coefficient)
test "decimal integer quotient stays in GDA unit accumulator representation" {
  let ten = Decimal::from_string("1E+1", precision=16).unwrap()
  let shifted = integer_quotient_by_power_of_ten_repr(
    Decimal::from_string("123E+2", precision=16).unwrap(),
    ten,
    false,
  ).unwrap()
  assert_eq(shifted.to_bigint(), 1230N)

  let truncated = integer_quotient_by_power_of_ten_repr(
    Decimal::from_int(125, precision=16),
    ten,
    false,
  ).unwrap()
  let even_tie = integer_quotient_by_power_of_ten_repr(
    Decimal::from_int(125, precision=16),
    ten,
    true,
  ).unwrap()
  let odd_tie = integer_quotient_by_power_of_ten_repr(
    Decimal::from_int(135, precision=16),
    ten,
    true,
  ).unwrap()
  assert_eq(truncated.to_bigint(), 12N)
  assert_eq(even_tie.to_bigint(), 12N)
  assert_eq(odd_tie.to_bigint(), 14N)
}

///|
// oracle: A
// source: CPython `Context(prec=5, rounding=ROUND_HALF_EVEN).plus`: 1234500 gives 1.2345E+6 (Rounded, not Inexact), 1234567 gives 1.2346E+6 (Inexact and Rounded); the block checks the coefficient 12345 and 12346 at exponent 2
// shares: Decimal::from_string (reads the operands), dec_coeff_from_bigint_repr and to_bigint (conversion between the test BigInt and the kernel coefficient)
test "decimal subset operand rounding stays coefficient-native" {
  let ctx = DecimalContext::new(
    precision=5,
    extended=false,
    decimal_rounding=DecimalRoundingMode::HalfEven,
  )
  let (exact, exact_flags) = round_operand_for_subset(
    Decimal::from_string("1234500", precision=16).unwrap(),
    ctx,
  )
  assert_eq(exact.coefficient.to_bigint(), 12345N)
  assert_eq(exact.exponent10, 2)
  assert_true(exact_flags.rounded)
  assert_false(exact_flags.inexact)

  let (inexact, inexact_flags) = round_operand_for_subset(
    Decimal::from_string("1234567", precision=16).unwrap(),
    ctx,
  )
  assert_eq(inexact.coefficient.to_bigint(), 12346N)
  assert_eq(inexact.exponent10, 2)
  assert_true(inexact_flags.rounded)
  assert_true(inexact_flags.inexact)
}

///|
// oracle: A
// source: CPython plus, precision 3: 1.23E+3 from 1234 inexact and rounded; written out: negative zero compares equal to zero and above -1, below 1
// shares: Decimal::from_string (reads the operands), dec_coeff_from_bigint_repr and to_bigint (conversion between the test BigInt and the kernel coefficient)
test "decimal unary finalize and zero compare stay coefficient-native" {
  let ctx = DecimalContext::new(precision=3)
  let value = Decimal::from_string("1234", precision=16).unwrap()
  let (applied, flags) = value.apply_ctx(ctx)
  assert_eq(applied.coefficient.to_bigint(), 123N)
  assert_eq(applied.exponent10, 1)
  assert_true(flags.rounded)
  assert_true(flags.inexact)

  let zero = Decimal::negative_zero(precision=16)
  assert_eq(compare_finite(zero, Decimal::from_int(-1, precision=16)), 1)
  assert_eq(compare_finite(zero, Decimal::from_int(1, precision=16)), -1)
  assert_eq(compare_finite(zero, Decimal::zero(precision=16)), 0)
}

///|
// oracle: A
// source: written out. 12345 / 10^2 = 123.45, half even gives 123 and is inexact; 5 / 10^1 = 0.5, an exact tie, half up gives 1 and is inexact
// shares: dec_coeff_from_bigint_repr and to_bigint (conversion between the test BigInt and the kernel coefficient)
test "decimal coefficient repr power-of-ten rounding matches BigInt path" {
  let (repr_half, repr_half_inexact) = round_positive_decimal_div_pow10_repr(
    dec_coeff_from_bigint_repr(12345N),
    2,
    false,
    DecimalRoundingMode::HalfEven,
  )
  assert_eq(repr_half.to_bigint(), 123N)
  assert_true(repr_half_inexact)
  let (repr_tiny, repr_tiny_inexact) = round_positive_decimal_div_pow10_repr(
    dec_coeff_from_bigint_repr(5N),
    1,
    false,
    DecimalRoundingMode::HalfUp,
  )
  assert_eq(repr_tiny.to_bigint(), 1N)
  assert_true(repr_tiny_inexact)
}

///|
// oracle: B
// source: test-local reference `reference_round_positive_decimal_div_pow10`: core BigInt `/` and `%` by 10^shift and a table of the eight rounding rules of GDA 1.70 (it no longer calls the library division); all eight modes at exact ties and just around them, both signs, shifts up to the digit count + 2
// shares: Decimal::to_string (prints the result), dec_coeff_from_bigint_repr and to_bigint (conversion between the test BigInt and the kernel coefficient)
// primitives: core BigInt / and % and pow; the mode table is written in the test
test "decimal power-of-ten rounding specialization matches every mode" {
  let values : Array[BigInt] = [
    0N,
    1N,
    4N,
    5N,
    6N,
    9N,
    10N,
    49N,
    50N,
    51N,
    99N,
    100N,
    499999999N,
    500000000N,
    500000001N,
    999999999N,
    1000000000N,
    1000000001N,
    499999999999999999N,
    500000000000000000N,
    500000000000000001N,
    pow10(81) + 5N * pow10(40),
    pow10(90) - 1N,
  ]
  let modes = [
    DecimalRoundingMode::HalfEven,
    DecimalRoundingMode::HalfUp,
    DecimalRoundingMode::HalfDown,
    DecimalRoundingMode::Down,
    DecimalRoundingMode::Ceiling,
    DecimalRoundingMode::Floor,
    DecimalRoundingMode::Up,
    DecimalRoundingMode::ZeroFiveUp,
  ]
  for value in values {
    let digits = value.to_string().length()
    for shift in 0..<(digits + 3) {
      for negative in [false, true] {
        for mode in modes {
          let (actual, actual_inexact) = round_positive_decimal_div_pow10_repr(
            dec_coeff_from_bigint_repr(value),
            shift,
            negative,
            mode,
          )
          let (expected, expected_inexact) = reference_round_positive_decimal_div_pow10(
            value, shift, negative, mode,
          )
          assert_eq(actual.to_bigint(), expected)
          assert_eq(actual_inexact, expected_inexact)
        }
      }
    }
  }
}

///|
// oracle: A
// source: written out from the rule of the context: precision 0 means "as many digits as the operand" (7 digits for 1234500), a fixed precision is itself (34 and 9); GDA 1.70 context precision
// shares: dec_coeff_from_bigint_repr and to_bigint (conversion between the test BigInt and the kernel coefficient)
test "decimal coefficient-native precision helper matches bigint precision helper" {
  let coeff = dec_coeff_from_bigint_repr(1234500N)
  assert_eq(
    finite_precision_for_coeff(coeff, DecimalContext::new(precision=34)),
    34,
  )
  assert_eq(
    finite_precision_for_coeff(coeff, DecimalContext::new(precision=9)),
    9,
  )
}

///|
// oracle: A
// source: written out: 12345^3 = 1881365963625 (CPython integers agree), which has 13 digits, so a cap of 13 fits and a cap of 12 does not
// shares: dec_coeff_from_bigint_repr and to_bigint (conversion between the test BigInt and the kernel coefficient)
test "decimal coefficient exact powers stay native and honor precision caps" {
  let base = dec_coeff_from_bigint_repr(12345N)
  assert_eq(dec_coeff_exact_power_repr(base, 3).to_bigint(), 1881365963625N)
  match dec_coeff_exact_power_if_fits_repr(base, 3, 13) {
    Some(value) => assert_eq(value.to_bigint(), 1881365963625N)
    None => fail("expected coefficient-native exact power to fit")
  }
  assert_true(dec_coeff_exact_power_if_fits_repr(base, 3, 12) is None)
}

///|
// oracle: A
// source: written out: 40^3 = 64E+3 and 1/40 = 25E-3 (CPython power and divide agree)
// shares: Decimal::from_string (reads the operands), dec_coeff_from_bigint_repr and to_bigint (conversion between the test BigInt and the kernel coefficient)
test "decimal exact integer power and reciprocal keep coefficient units" {
  let exact_ctx = DecimalContext::new(precision=34)
  let base = Decimal::from_string("4E+1", precision=16).unwrap()
  let (positive, positive_flags) = decimal_power_integer_exact_result(
    base, 3, exact_ctx,
  ).unwrap()
  assert_eq(positive.coefficient.to_bigint(), 64N)
  assert_eq(positive.exponent10, 3)
  assert_false(positive_flags.rounded)
  assert_false(positive_flags.inexact)

  let (reciprocal, reciprocal_flags) = exact_decimal_reciprocal(
    Decimal::from_string("4E+1", precision=16).unwrap(),
    exact_ctx,
  ).unwrap()
  assert_eq(reciprocal.coefficient.to_bigint(), 25N)
  assert_eq(reciprocal.exponent10, -3)
  assert_false(reciprocal_flags.rounded)
  assert_false(reciprocal_flags.inexact)
}

///|
// oracle: A
// source: written out: 123456789^2 = 15241578750190521 (CPython integers), sqrt(1.4400) = 1.20, sqrt(2) is inexact (CPython sqrt agrees)
// shares: Decimal::from_string (reads the operands), dec_coeff_from_bigint_repr and to_bigint (conversion between the test BigInt and the kernel coefficient)
test "decimal exact square root uses GDA Newton unit operations" {
  let perfect = Decimal::from_string("15241578750190521", precision=32).unwrap()
  let exact = exact_finite_sqrt(perfect, 32).unwrap()
  assert_eq(exact.coefficient.to_bigint(), 123456789N)
  assert_eq(exact.exponent10, 0)

  let scaled = Decimal::from_string("1.4400", precision=16).unwrap()
  let scaled_exact = exact_finite_sqrt(scaled, 16).unwrap()
  assert_eq(scaled_exact.coefficient.to_bigint(), 120N)
  assert_eq(scaled_exact.exponent10, -2)

  assert_true(
    exact_finite_sqrt(Decimal::from_string("2", precision=16).unwrap(), 16)
    is None,
  )
}

///|
// oracle: A
// source: written out: floor(-1250 / 2303) = -1 and -1250 + 2303 = 1053, by hand
// shares: Decimal::from_string (reads the operands), dec_coeff_from_bigint_repr and to_bigint (conversion between the test BigInt and the kernel coefficient)
test "decimal exp range reduction keeps runtime coefficient units" {
  let value = Decimal::from_string("-1.25", precision=16).unwrap()
  let (negative, scaled) = decimal_finite_to_scaled_repr(value, 3)
  assert_true(negative)
  assert_eq(scaled.to_bigint(), 1250N)

  let ln10 = dec_coeff_from_bigint_repr(2303N)
  let exponent = decimal_floor_div_scaled_repr(negative, scaled, ln10)
  assert_eq(exponent, -1)
  let product = dec_coeff_multiply_repr(
    dec_coeff_from_nonnegative_int(abs_int(exponent)),
    ln10,
  )
  let (reduced_negative, reduced) = dec_coeff_signed_add_repr(
    negative,
    scaled,
    exponent >= 0,
    product,
  )
  assert_false(reduced_negative)
  assert_eq(reduced.to_bigint(), 1053N)
}

///|
// oracle: A
// source: written out: 1234500E-2 = 12345, -42.000 = -42, 12.34 is not an integer, 1234567890123 is beyond the limit, derived by hand
// shares: Decimal::from_string (reads the operands), dec_coeff_from_bigint_repr and to_bigint (conversion between the test BigInt and the kernel coefficient)
test "decimal exact integer helpers match normalized finite values" {
  let integer = Decimal::from_string("1234500E-2", precision=16).unwrap()
  let negative = Decimal::from_string("-42.000", precision=16).unwrap()
  let fractional = Decimal::from_string("12.34", precision=16).unwrap()
  let huge = Decimal::from_string("1234567890123", precision=16).unwrap()

  match decimal_exact_integer_coeff(integer) {
    Some((negative, magnitude)) => {
      assert_false(negative)
      assert_eq(magnitude.to_bigint(), 12345N)
    }
    None => fail("expected exact positive integer coefficient")
  }
  match decimal_exact_integer_coeff(negative) {
    Some((negative, magnitude)) => {
      assert_true(negative)
      assert_eq(magnitude.to_bigint(), 42N)
    }
    None => fail("expected exact negative integer coefficient")
  }
  assert_true(decimal_exact_integer_coeff(fractional) is None)

  assert_true(reference_decimal_exact_int(integer) == Some(12345))
  assert_true(reference_decimal_exact_int(negative) == Some(-42))
  assert_true(reference_decimal_exact_int(fractional) is None)
  assert_true(reference_decimal_exact_int(huge) is None)

  assert_true(decimal_power_integer_count(integer, 20_000) == Some(12345))
  assert_true(decimal_power_integer_count(negative, 100) == Some(-42))
  assert_true(decimal_power_integer_count(huge, 999_999_999) is None)
}

///|
// oracle: A
// source: written out: the count limit 999,999,999 against 1E+9 and 1E+999999999, and the parity of a power of ten, derived by hand
// shares: Decimal::from_string (reads the operands)
test "decimal bounded power helpers avoid expanding huge positive exponents" {
  let huge = Decimal::from_string("1E+999999999", precision=16).unwrap()
  assert_true(decimal_power_integer_count(huge, 999_999_999) is None)
  assert_true(decimal_power_gda_integer_count(huge) is None)
  assert_true(decimal_power_integer_is_odd(huge) == Some(false))

  let boundary = Decimal::from_string("1E+9", precision=16).unwrap()
  assert_true(decimal_power_integer_count(boundary, 999_999_999) is None)
  assert_true(
    decimal_power_integer_count(boundary, 1_000_000_000) == Some(1_000_000_000),
  )
}

///|
// oracle: A
// source: written out: -8.000 is even, -7 is odd, 0E-4 is even, 3.5 has no parity, by hand
// shares: Decimal::from_string (reads the operands)
test "decimal integer parity helper rejects fractional values and tracks signless oddness" {
  let even = Decimal::from_string("-8.000", precision=16).unwrap()
  let odd = Decimal::from_string("-7", precision=16).unwrap()
  let zero = Decimal::from_string("0E-4", precision=16).unwrap()
  let fractional = Decimal::from_string("3.5", precision=16).unwrap()

  assert_true(decimal_power_integer_is_odd(even) == Some(false))
  assert_true(decimal_power_integer_is_odd(odd) == Some(true))
  assert_true(decimal_power_integer_is_odd(zero) == Some(false))
  assert_true(decimal_power_integer_is_odd(fractional) is None)
}

///|
// oracle: A
// source: CPython `Context(prec=9, Emin=-999, Emax=999).create_decimal`: 1E-1000000008 half even gives 0E-1007 (flags x r u s c; the block checks underflow, subnormal and clamped), -1E-1000000008 rounded up gives -1E-1007 (flags x r u s; the block checks underflow and subnormal)
// shares: Decimal::from_string (reads the operands), dec_coeff_from_bigint_repr and to_bigint (conversion between the test BigInt and the kernel coefficient)
test "decimal extreme tiny parsing preserves directed rounding flags" {
  let half_even_ctx = DecimalContext::new(
    precision=9,
    decimal_rounding=DecimalRoundingMode::HalfEven,
    e_min=-999,
    e_max=999,
  )
  let (half_even, half_even_flags) = Decimal::from_string_ctx(
    "1E-1000000008", half_even_ctx,
  )
  assert_true(half_even.coefficient.is_zero())
  assert_eq(half_even.exponent10, -1007)
  assert_true(half_even_flags.underflow)
  assert_true(half_even_flags.subnormal)
  assert_true(half_even_flags.clamped)

  let upward_ctx = DecimalContext::new(
    precision=9,
    decimal_rounding=DecimalRoundingMode::Up,
    e_min=-999,
    e_max=999,
  )
  let (upward, upward_flags) = Decimal::from_string_ctx(
    "-1E-1000000008", upward_ctx,
  )
  assert_eq(upward.coefficient.to_bigint(), 1N)
  assert_true(upward.negative)
  assert_eq(upward.exponent10, -1007)
  assert_true(upward_flags.underflow)
  assert_true(upward_flags.subnormal)
}

///|
// oracle: A
// source: written out: 123 and -45 have the count, -0 gives 0, 12E-1 and 10^12 have none, by hand
// shares: Decimal::from_string (reads the operands)
test "scaleb count extracts exponent-zero integers from coeff repr" {
  let ctx = DecimalContext::new(
    precision=9,
    decimal_rounding=DecimalRoundingMode::HalfEven,
    e_min=-999,
    e_max=999,
  )
  let positive = Decimal::from_string("123", precision=16).unwrap()
  let negative = Decimal::from_string("-45", precision=16).unwrap()
  let negative_zero = Decimal::from_string("-0", precision=16).unwrap()
  let exact_nonzero_exponent = Decimal::from_string("12E-1", precision=16).unwrap()
  let huge = Decimal::from_string("1000000000000", precision=16).unwrap()

  assert_true(scaleb_count(positive, ctx) == Some(123))
  assert_true(scaleb_count(negative, ctx) == Some(-45))
  assert_true(scaleb_count(negative_zero, ctx) == Some(0))
  assert_true(scaleb_count(exact_nonzero_exponent, ctx) is None)
  assert_true(scaleb_count(huge, ctx) is None)
}

///|
// oracle: A
// source: written out: 1234500 / 10^3 = 1234 remainder 500
// shares: dec_coeff_from_bigint_repr and to_bigint (conversion between the test BigInt and the kernel coefficient)
test "decimal coefficient repr div-rem by power of ten matches bigint path" {
  let coeff = dec_coeff_from_bigint_repr(1234500N)
  let divisor = dec_coeff_power10_repr(3)
  let (quotient, remainder) = dec_coeff_div_rem_repr(coeff, divisor)
  assert_eq(quotient.to_bigint(), 1234N)
  assert_eq(remainder.to_bigint(), 500N)
}

///|
// oracle: B
// source: test-local predicate on core BigInt: gcd, then removal of the factors 2 and 5, over cases up to 3 * 10^2000
// shares: abs_bigint (a sign removal)
// primitives: abs_bigint, a one-line sign removal, and core BigInt % and /
test "decimal coefficient finite-expansion predicate matches bigint predicate" {
  let cases : Array[(BigInt, BigInt)] = [
    (0N, 21N),
    (1N, 6N),
    (3N, 6N),
    (7N, 40N),
    (7N, 21N),
    (21N, 42N),
    (14N, 84N),
    (3N * pow10(90), 3N * pow10(70)),
    (pow10(90), 3N * pow10(70)),
    (1N, pow10(2000)),
    (1N, 3N * pow10(2000)),
    (3N, 3N * pow10(2000)),
  ]
  for pair in cases {
    assert_eq(
      has_finite_decimal_expansion_repr(
        dec_coeff_from_bigint_repr(pair.0),
        dec_coeff_from_bigint_repr(pair.1),
      ),
      reference_has_finite_decimal_expansion(pair.0, pair.1),
    )
  }
}

///|
fn bigint_logical_binary_digits(
  lhs : BigInt,
  rhs : BigInt,
  precision : Int32,
  op : (Bool, Bool) -> Bool,
) -> BigInt {
  let ten = BigInt::from_int(10)
  let mut lhs = lhs
  let mut rhs = rhs
  let mut place = bigint_one()
  let mut result = bigint_zero()
  for _ in 0..<precision {
    let lhs_digit = lhs % ten == bigint_one()
    let rhs_digit = rhs % ten == bigint_one()
    if op(lhs_digit, rhs_digit) {
      result = result + place
    }
    lhs = lhs / ten
    rhs = rhs / ten
    place = place * ten
  }
  result
}

///|
fn bigint_logical_invert_digits(value : BigInt, precision : Int32) -> BigInt {
  let ten = BigInt::from_int(10)
  let mut value = value
  let mut place = bigint_one()
  let mut result = bigint_zero()
  for _ in 0..<precision {
    if value % ten != bigint_one() {
      result = result + place
    }
    value = value / ten
    place = place * ten
  }
  result
}

///|
fn bigint_shift_digits(
  coefficient : BigInt,
  count : Int32,
  precision : Int32,
) -> BigInt {
  if coefficient.is_zero() {
    return coefficient
  }
  if count == 0 {
    return coefficient
  }
  if count > 0 {
    coefficient * pow10(count) % pow10(precision)
  } else {
    coefficient / pow10(-count)
  }
}

///|
fn bigint_rotate_digits(
  coefficient : BigInt,
  count : Int32,
  precision : Int32,
) -> BigInt {
  if coefficient.is_zero() {
    return coefficient
  }
  let width = pow10(precision)
  let normalized = coefficient % width
  let mut shift = count % precision
  if shift < 0 {
    shift += precision
  }
  if shift == 0 {
    return normalized
  }
  let left = normalized * pow10(shift) % width
  let right = normalized / pow10(precision - shift)
  left + right
}

///|
// oracle: B
// source: test-local digit loops over core BigInt `%` and `/` (and, or, xor of digit strings)
// shares: dec_coeff_from_bigint_repr and to_bigint (conversion between the test BigInt and the kernel coefficient)
// primitives: core BigInt % and / (MoonBit core); dec_coeff_from_bigint_repr builds the inputs
test "decimal logical coefficient helpers match bigint digit formulas" {
  for
    values in [
      (101011N, 110001N, 8),
      (
        1010101010101010101010101010101010N, 1100110011001100110011001100110011N,
        34,
      ),
    ] {
    let lhs = dec_coeff_from_bigint_repr(values.0)
    let rhs = dec_coeff_from_bigint_repr(values.1)
    assert_eq(
      logical_binary_digits_repr(lhs, rhs, values.2, fn(a, b) { a && b }).to_bigint(),
      bigint_logical_binary_digits(values.0, values.1, values.2, fn(a, b) {
        a && b
      }),
    )
    assert_eq(
      logical_binary_digits_repr(lhs, rhs, values.2, fn(a, b) { a || b }).to_bigint(),
      bigint_logical_binary_digits(values.0, values.1, values.2, fn(a, b) {
        a || b
      }),
    )
    assert_eq(
      logical_binary_digits_repr(lhs, rhs, values.2, fn(a, b) { a != b }).to_bigint(),
      bigint_logical_binary_digits(values.0, values.1, values.2, fn(a, b) {
        a != b
      }),
    )
  }
}

///|
// oracle: B
// source: core BigInt compare of lhs with rhs * 10^exponent, both written out in the test
// shares: pow10 (internal package: a cache of core BigInt::pow)
// primitives: pow10, a cache of core BigInt::pow
test "decimal scaled comparison matches exact virtual shift" {
  let values = [
    1N, 999999999N, 1000000000N, 1000000001N, 999999999999999999N, 123456789012345678901234567890N,
  ]
  for lhs in values {
    for rhs in values {
      for exponent in [0, 1, 8, 9, 10, 17, 18, 37] {
        assert_eq(
          dec_coeff_compare_scaled_repr(
            dec_coeff_from_bigint_repr(lhs),
            dec_coeff_from_bigint_repr(rhs),
            exponent,
          ),
          compare_int(lhs.compare(rhs * pow10(exponent)), 0),
        )
      }
    }
  }
}

///|
// oracle: B
// source: test-local digit loops (invert, shift, rotate) over core BigInt
// shares: pow10 (internal package: a cache of core BigInt::pow)
// primitives: pow10, a cache of core BigInt::pow; core BigInt % and /
test "decimal logical invert and digit motion helpers match bigint formulas" {
  let ctx = DecimalContext::new(precision=8)
  let coeff = dec_coeff_from_bigint_repr(101011N)
  assert_eq(
    logical_invert_digits_repr(coeff, ctx).to_bigint(),
    bigint_logical_invert_digits(101011N, 8),
  )
  assert_eq(
    coefficient_shift_digits_repr(coeff, 2, 8).to_bigint(),
    bigint_shift_digits(101011N, 2, 8),
  )
  assert_eq(
    coefficient_shift_digits_repr(coeff, -3, 8).to_bigint(),
    bigint_shift_digits(101011N, -3, 8),
  )
  assert_eq(
    coefficient_rotate_digits_repr(coeff, 2, 8).to_bigint(),
    bigint_rotate_digits(101011N, 2, 8),
  )
  assert_eq(
    coefficient_rotate_digits_repr(coeff, -3, 8).to_bigint(),
    bigint_rotate_digits(101011N, -3, 8),
  )
}

///|
// oracle: A
// source: Python decimal (libmpdec) `Context(prec=6, rounding=ROUND_HALF_EVEN, Emin=-20, Emax=20, clamp=0).divide`; rows written out with the flags it raises (letters x r i z o u s c); replaces a block whose expected value was a copy of the previous BigInt pipeline built from library helpers
// shares: Decimal::from_string (reads the operands), Decimal::to_string (prints the result)
test "decimal div_ctx repr pipeline matches bigint divide normalization" {
  let ctx = DecimalContext::new(
    precision=6,
    decimal_rounding=DecimalRoundingMode::HalfEven,
    e_min=-20,
    e_max=20,
    clamp=false,
  )
  for
    row in [
      ("7.50", "16", "0.46875", "........"),
      ("22", "7", "3.14286", "xr......"),
    ] {
    let (a, b, result, flags) = row
    let lhs = Decimal::from_string(a, precision=8).unwrap()
    let rhs = Decimal::from_string(b, precision=8).unwrap()
    let actual = lhs.div_ctx(rhs, ctx)
    assert_eq(
      (a, b, actual.0.to_string(), normalization_flags_text(actual.1)),
      (a, b, result, flags),
    )
  }
}

///|
// oracle: A
// source: Python decimal (libmpdec) `Context(prec=5, rounding=ROUND_HALF_UP, Emin=-12, Emax=12, clamp=1).divide` by the integers 8 and 3; rows written out with the flags it raises (letters x r i z o u s c); replaces a block whose expected value was a copy of the previous BigInt pipeline built from library helpers
// shares: Decimal::from_string (reads the operands), Decimal::to_string (prints the result)
test "decimal math small-int division repr pipeline matches bigint divide normalization" {
  let work_ctx = DecimalContext::new(
    precision=5,
    decimal_rounding=DecimalRoundingMode::HalfUp,
    e_min=-12,
    e_max=12,
    clamp=true,
  )
  for
    row in [
      ("7.50", 8, "0.9375", "........"),
      ("-2", 3, "-0.66667", "xr......"),
    ] {
    let (text, divisor, result, flags) = row
    let value = Decimal::from_string(text, precision=8).unwrap()
    let actual = decimal_div_finite_by_small_int_work(value, divisor, work_ctx)
    assert_eq(
      (text, divisor, actual.0.to_string(), normalization_flags_text(actual.1)),
      (text, divisor, result, flags),
    )
  }
}

///|
// oracle: A
// source: Python decimal (libmpdec) `Context(prec=5, rounding=ROUND_HALF_EVEN, Emin=-15, Emax=15, clamp=0).divide`; rows written out with the flags it raises (letters x r i z o u s c); replaces a block whose expected value was a copy of the previous BigInt pipeline built from library helpers
// shares: Decimal::from_string (reads the operands), Decimal::to_string (prints the result)
test "decimal math finite division repr pipeline matches bigint divide normalization" {
  let work_ctx = DecimalContext::new(
    precision=5,
    decimal_rounding=DecimalRoundingMode::HalfEven,
    e_min=-15,
    e_max=15,
    clamp=false,
  )
  for
    row in [
      ("7.50", "16", "0.46875", "........"),
      ("-22", "7", "-3.1429", "xr......"),
    ] {
    let (a, b, result, flags) = row
    let lhs = Decimal::from_string(a, precision=8).unwrap()
    let rhs = Decimal::from_string(b, precision=8).unwrap()
    let actual = decimal_div_finite_work(lhs, rhs, work_ctx)
    assert_eq(
      (a, b, actual.0.to_string(), normalization_flags_text(actual.1)),
      (a, b, result, flags),
    )
  }
}

///|
// oracle: A
// source: Python decimal (libmpdec) `Context(prec=6, rounding=ROUND_HALF_EVEN, Emin=-20, Emax=20, clamp=0)`: `plus(1234500E-3)` = 1234.50 (rounded, not inexact), `multiply(12.5, -0.08)` = -1.000; rows written out with the flags it raises (letters x r i z o u s c); replaces a block whose expected value was a copy of the previous BigInt pipeline built from library helpers
// shares: Decimal::from_string (reads the operands), Decimal::to_string (prints the result)
test "decimal repr math normalization and multiplication match bigint path" {
  let work_ctx = DecimalContext::new(
    precision=6,
    decimal_rounding=DecimalRoundingMode::HalfEven,
    e_min=-20,
    e_max=20,
    clamp=false,
  )
  let value = Decimal::from_string("1234500E-3", precision=16).unwrap()
  let normalized = decimal_normalize_finite_work(value, work_ctx)
  assert_eq(
    (normalized.0.to_string(), normalization_flags_text(normalized.1)),
    ("1234.50", ".r......"),
  )
  let lhs = Decimal::from_string("12.5", precision=8).unwrap()
  let rhs = Decimal::from_string("-0.08", precision=8).unwrap()
  let product = decimal_mul_finite_work(lhs, rhs, work_ctx)
  assert_eq(
    (product.0.to_string(), normalization_flags_text(product.1)),
    ("-1.000", "........"),
  )
  let product_ctx = lhs.mul_ctx(rhs, work_ctx)
  assert_eq(
    (product_ctx.0.to_string(), normalization_flags_text(product_ctx.1)),
    ("-1.000", "........"),
  )
}

///|
// oracle: A
// source: Python decimal (libmpdec) `Context(prec=4, rounding=ROUND_HALF_UP, Emin=-6, Emax=6, clamp=1).scaleb(Decimal("12.34"), n)`: n = -2 gives 0.1234, n = -10 gives 1E-9 (inexact, rounded, underflow, subnormal); rows written out with the flags it raises (letters x r i z o u s c); replaces a block whose expected value was a copy of the previous BigInt pipeline built from library helpers
// shares: Decimal::from_string (reads the operands), Decimal::to_string (prints the result)
test "decimal scaleb repr construction matches bigint path" {
  let ctx = DecimalContext::new(
    precision=4,
    decimal_rounding=DecimalRoundingMode::HalfUp,
    e_min=-6,
    e_max=6,
    clamp=true,
  )
  let value = Decimal::from_string("12.34", precision=8).unwrap()
  for row in [(-2, "0.1234", "........"), (-10, "1E-9", "xr...us.")] {
    let (n, result, flags) = row
    let actual = scaleb_finite_result_ctx(value, n, ctx)
    assert_eq(
      (n, actual.0.to_string(), normalization_flags_text(actual.1)),
      (n, result, flags),
    )
  }
}

///|
fn normalization_flags_text(flags : DecimalFlags) -> String {
  (if flags.inexact { "x" } else { "." }) +
  (if flags.rounded { "r" } else { "." }) +
  (if flags.invalid_operation { "i" } else { "." }) +
  (if flags.division_by_zero { "z" } else { "." }) +
  (if flags.overflow { "o" } else { "." }) +
  (if flags.underflow { "u" } else { "." }) +
  (if flags.subnormal { "s" } else { "." }) +
  (if flags.clamped { "c" } else { "." })
}

///|
/// Oracle (level A): Python `decimal` (libmpdec) `Context(prec=7,
/// rounding=ROUND_HALF_UP, Emin=-20, Emax=20, clamp=1).plus(Decimal(text))`
/// with its flags; written out. These rows replace a block whose expected value
/// was `normalize_decimal_parts_ctx`, a wrapper of the function under test.
// oracle: A
// source: CPython `Context(prec=7, rounding=ROUND_HALF_UP, Emin=-20, Emax=20, clamp=1).plus(Decimal(text))` with its flags, all 16 rows written out (see the comment above the block)
// shares: Decimal::from_string (reads the operands), Decimal::to_string (prints the result)
test "repr normalization gives the libmpdec result and flags on finite values" {
  let ctx = DecimalContext::new(
    precision=7,
    decimal_rounding=DecimalRoundingMode::HalfUp,
    e_min=-20,
    e_max=20,
    clamp=true,
  )
  let rows = [
    ("1234500E-3", "1234.500", "........"),
    ("12345678E-3", "12345.68", "xr......"),
    ("12345675E-3", "12345.68", "xr......"),
    ("99999995E-3", "100000.0", "xr......"),
    ("1E+25", "inf", "xr..o..."),
    ("1E+20", "1.000000E+20", ".......c"),
    ("1E+21", "inf", "xr..o..."),
    ("1E-25", "1E-25", "......s."),
    ("15E-26", "1.5E-25", "......s."),
    ("5E-27", "1E-26", "xr...us."),
    ("-5E-27", "-1E-26", "xr...us."),
    ("123E-30", "0E-26", "xr...usc"),
    ("0E+30", "0E+14", ".......c"),
    ("1000000E+14", "1.000000E+20", "........"),
    ("9999999E+14", "9.999999E+20", "........"),
    ("99999995E+13", "inf", "xr..o..."),
  ]
  for row in rows {
    let (text, result, flags) = row
    let value = Decimal::from_string(text, precision=16).unwrap()
    let actual = normalize_decimal_parts_ctx_repr(
      value.negative,
      value.coefficient,
      value.exponent10,
      ctx,
    )
    assert_eq(
      (text, actual.0.to_string(), normalization_flags_text(actual.1)),
      (text, result, flags),
    )
  }
}

///|
/// Oracle (level A): Python `decimal` `Context(prec=5, rounding=ROUND_HALF_EVEN)`
/// `.plus(Decimal(text)).normalize()` (round, then strip the trailing zeros); written
/// out. Replaces a block whose expected value was a wrapper of the function under test.
// oracle: A
// source: CPython `Context(prec=5, rounding=ROUND_HALF_EVEN).plus(Decimal(text)).normalize()`, all 9 rows written out (see the comment above the block)
// shares: Decimal::from_string (reads the operands), Decimal::to_string (prints the result)
test "repr gda normalization rounds to the precision and reduces, as libmpdec" {
  let rows = [
    ("9999500E-4", "999.95"),
    ("1234500E-3", "1234.5"),
    ("12345E-3", "12.345"),
    ("1250000E-4", "125"),
    ("99999E+3", "9.9999E+7"),
    ("123456E+2", "1.2346E+7"),
    ("0.00E+5", "0"),
    ("5E-2", "0.05"),
    ("-5000E-3", "-5"),
  ]
  for row in rows {
    let (text, result) = row
    let value = Decimal::from_string(text, precision=16).unwrap()
    let actual = normalize_decimal_parts_gda_repr(
      value.negative,
      value.coefficient,
      value.exponent10,
      5,
      DecimalRoundingMode::HalfEven,
    )
    assert_eq((text, actual.to_string()), (text, result))
  }
}
