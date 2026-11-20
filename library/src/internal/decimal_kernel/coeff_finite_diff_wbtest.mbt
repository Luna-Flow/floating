///|
// Differential test of `has_finite_decimal_expansion_repr` (the criterion "the
// part of the denominator prime to 10 divides the numerator", with the factors
// 2 and 5 read from the lowest limb when both valuations are below 9) against
// two references kept here as private code: the previous implementation of the
// function (factors removed by division, then a remainder test) and the
// decision of the gcd route of `decimal` (`exact_decimal_division_result`): the
// reduced denominator `denominator / gcd(numerator, denominator)` has no prime
// other than 2 and 5.

///|
let finite_diff_cases : Int32 = 300

///|
/// the same for the classes of 24 limbs and more, whose gcd reference is slow
let finite_diff_cases_large : Int32 = 300

///|
fn reference_has_finite_expansion(
  numerator : DecCoeff,
  denominator : DecCoeff,
) -> Bool {
  guard !denominator.is_zero() else {
    abort("reference expects denominator > 0")
  }
  let (without_tens, _, _) = trim_trailing_decimal_zeros_repr(denominator, 0)
  let without_twos = dec_coeff_remove_factor_unit_repr(without_tens, 2)
  let without_fives = dec_coeff_remove_factor_unit_repr(without_twos, 5)
  if dec_coeff_compare_repr(without_fives, dec_coeff_from_int(1)) == 0 {
    return true
  }
  dec_coeff_div_rem_repr(numerator, without_fives).1.is_zero()
}

///|
fn reference_gcd_finite(numerator : DecCoeff, denominator : DecCoeff) -> Bool {
  let gcd = dec_coeff_gcd_repr(numerator, denominator)
  let (reduced, _) = dec_coeff_div_rem_repr(denominator, gcd)
  let (without_twos, _) = dec_coeff_count_factor_unit_repr(reduced, 2)
  let (without_fives, _) = dec_coeff_count_factor_unit_repr(without_twos, 5)
  dec_coeff_matches_unit_repr(without_fives, 1)
}

///|
fn finite_diff_check(
  numerator : DecCoeff,
  denominator : DecCoeff,
) -> Unit raise {
  let actual = has_finite_decimal_expansion_repr(numerator, denominator)
  let old = reference_has_finite_expansion(numerator, denominator)
  if actual != old {
    fail(
      "finite expansion differs from the previous function for \{numerator.to_string()} / \{denominator.to_string()}",
    )
  }
  if !numerator.is_zero() {
    let by_gcd = reference_gcd_finite(numerator, denominator)
    if actual != by_gcd {
      fail(
        "finite expansion differs from the gcd decision for \{numerator.to_string()} / \{denominator.to_string()}",
      )
    }
  }
}

///|
fn finite_diff_power(base : Int32, exponent : Int32) -> DecCoeff {
  let mut value = dec_coeff_from_int(1)
  for _ in 0..<exponent {
    value = dec_coeff_multiply_by_unit_repr(value, base)
  }
  value
}

///|
fn finite_diff_class(limbs : Int32, seed : UInt64) -> Unit raise {
  let state = Ref(seed)
  let cases = if limbs >= 24 {
    finite_diff_cases_large
  } else {
    finite_diff_cases
  }
  for iteration in 0..<cases {
    let nines = (iteration % 4).to_uint64() * 3UL
    let numerator = round_diff_value(state, limbs, nines)
    let part = round_diff_value(state, (limbs + 1) / 2, nines)
    // factors 2 and 5 of every valuation: none, small, equal to 9, above 9
    // (the lowest limb zero when both are at least 9)
    let twos = [0, 1, 3, 8, 9, 10, 20, 37][(sqrt_diff_next(state) % 8UL).to_int()]
    let fives = [0, 1, 4, 8, 9, 11, 25][(sqrt_diff_next(state) % 7UL).to_int()]
    let denominator = dec_coeff_multiply_repr(
      dec_coeff_multiply_repr(part, finite_diff_power(2, twos)),
      finite_diff_power(5, fives),
    )
    // a numerator that is and one that is not a multiple of the part prime
    // to 10 (when `part` has factors 2 or 5 itself the cases mix)
    finite_diff_check(numerator, denominator)
    finite_diff_check(dec_coeff_multiply_repr(numerator, part), denominator)
    finite_diff_check(
      dec_coeff_multiply_repr(numerator, denominator),
      denominator,
    )
    finite_diff_check(
      dec_coeff_magnitude_add_unit(dec_coeff_multiply_repr(numerator, part), 1),
      denominator,
    )
    finite_diff_check(denominator, denominator)
    finite_diff_check(dec_coeff_zero(), denominator)
    finite_diff_check(dec_coeff_from_int(1), denominator)
  }
}

///|
test "finite expansion decision equals the references, 1 limb" {
  finite_diff_class(1, 0x9E3779B97F4A7C15UL)
}

///|
test "finite expansion decision equals the references, 2 to 4 limbs" {
  finite_diff_class(2, 0xD1B54A32D192ED03UL)
  finite_diff_class(3, 0x2545F4914F6CDD1DUL)
  finite_diff_class(4, 0x94D049BB133111EBUL)
}

///|
test "finite expansion decision equals the references, 6 to 12 limbs" {
  finite_diff_class(6, 0xBF58476D1CE4E5B9UL)
  finite_diff_class(12, 0x6A09E667F3BCC909UL)
}

///|
test "finite expansion decision equals the references, 24 and 56 limbs" {
  finite_diff_class(24, 0xBB67AE8584CAA73BUL)
  finite_diff_class(56, 0x3C6EF372FE94F82BUL)
}

///|
test "finite expansion decision, 120 limbs" {
  finite_diff_class(120, 0xA54FF53A5F1D36F1UL)
}

///|
test "finite expansion decision, special denominators" {
  for exponent in 0..<80 {
    let ten = dec_coeff_power10_repr(exponent)
    let two = finite_diff_power(2, exponent)
    let five = finite_diff_power(5, exponent)
    for
      denominator in [
        ten,
        two,
        five,
        dec_coeff_multiply_repr(two, five),
        dec_coeff_magnitude_add_unit(ten, 1),
        dec_coeff_magnitude_sub_unit(dec_coeff_multiply_by_unit_repr(ten, 3), 0),
        dec_coeff_multiply_by_unit_repr(ten, 7),
      ] {
      if !denominator.is_zero() {
        for
          numerator in [
            dec_coeff_from_int(1),
            dec_coeff_from_int(7),
            ten,
            dec_coeff_multiply_by_unit_repr(ten, 21),
            dec_coeff_magnitude_add_unit(ten, 1),
          ] {
          finite_diff_check(numerator, denominator)
        }
      }
    }
  }
}
