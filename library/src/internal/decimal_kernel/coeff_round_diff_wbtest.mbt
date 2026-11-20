///|
// Differential test of the rounding shift by a power of ten against the
// previous implementation (copy, shift, trim, a second scan for the rounding
// digits, a copy and a pass for the increment), kept here as private
// reference code. Results are compared bit for bit, representation included,
// for all eight directions, both signs, and the shifts at and around the limb
// and digit boundaries.

///|
let round_diff_cases : Int32 = 300

///|
fn reference_round_div_pow10(
  numerator : DecCoeff,
  shift : Int32,
  negative : Bool,
  mode : DecCoeffRounding,
) -> (DecCoeff, Bool) {
  let (quotient, has_remainder, half_cmp) = dec_coeff_div_pow10_round_info_repr(
    numerator, shift,
  )
  if !has_remainder {
    return (quotient, false)
  }
  let should_increment = match mode {
    Down => false
    Ceiling => !negative
    Floor => negative
    Up => true
    ZeroFiveUp => {
      let last = dec_coeff_limb_at(quotient, 0).reinterpret_as_int() % 10
      last == 0 || last == 5
    }
    HalfEven => half_cmp > 0 || (half_cmp == 0 && dec_coeff_is_odd(quotient))
    HalfUp => half_cmp >= 0
    HalfDown => half_cmp > 0
  }
  (
    if should_increment {
      dec_coeff_magnitude_add_unit(quotient, 1)
    } else {
      quotient
    },
    has_remainder,
  )
}

///|
let round_diff_modes : Array[DecCoeffRounding] = [
  HalfEven,
  HalfUp,
  HalfDown,
  Down,
  Ceiling,
  Floor,
  Up,
  ZeroFiveUp,
]

///|
fn round_diff_value(
  state : Ref[UInt64],
  length : Int32,
  nines : UInt64,
) -> DecCoeff {
  let limbs = Array::make(length, 0U)
  for index in 0..<length {
    let pick = sqrt_diff_next(state) % 12UL
    let width = (sqrt_diff_next(state) % 9UL).to_int() + 1
    limbs[index] = if pick < nines {
      (dec_coeff_base - 1).reinterpret_as_uint()
    } else if pick == 11UL {
      0U
    } else if pick == 10UL {
      // a half: 5 followed by zeros
      (5 * dec_coeff_small_powers10[width - 1].to_int()).reinterpret_as_uint()
    } else {
      (sqrt_diff_next(state) % dec_coeff_small_powers10[width]).to_uint()
    }
  }
  if limbs[length - 1] == 0U {
    limbs[length - 1] = (sqrt_diff_next(state) % 999999999UL + 1UL).to_uint()
  }
  dec_coeff_from_unit_accumulator(limbs, length)
}

///|
fn round_diff_check(
  value : DecCoeff,
  shift : Int32,
  negative : Bool,
  mode : DecCoeffRounding,
) -> Unit raise {
  let (expected, expected_inexact) = reference_round_div_pow10(
    value, shift, negative, mode,
  )
  let (actual, actual_inexact) = dec_coeff_round_div_pow10(
    value, shift, negative, mode,
  )
  if !sqrt_diff_same(expected, actual) || expected_inexact != actual_inexact {
    fail(
      "round_div_pow10 differs for \{value.to_string()} shift \{shift} negative \{negative} mode \{round_diff_modes.search(mode).unwrap()}",
    )
  }
  // the persistent operand is unchanged and the owned entry agrees
  if value is Limbs(units, digits) {
    let (owned, owned_inexact) = dec_coeff_round_div_pow10_owned(
      units.copy(),
      digits,
      shift,
      negative,
      mode,
    )
    if !sqrt_diff_same(expected, owned) || expected_inexact != owned_inexact {
      fail(
        "round_div_pow10_owned differs for \{value.to_string()} shift \{shift} mode \{round_diff_modes.search(mode).unwrap()}",
      )
    }
  }
}

///|
fn round_diff_value_shifts(
  state : Ref[UInt64],
  value : DecCoeff,
) -> Array[Int32] {
  let digits = value.digits10()
  let shifts = [
    0,
    1,
    8,
    9,
    10,
    17,
    18,
    19,
    digits - 10,
    digits - 9,
    digits - 8,
    digits - 2,
    digits - 1,
    digits,
    digits + 1,
  ]
  for _ in 0..<3 {
    shifts.push((sqrt_diff_next(state) % (digits + 2).to_uint64()).to_int())
  }
  shifts.filter(shift => shift >= 0)
}

///|
fn round_diff_class(length : Int32, seed : UInt64) -> Unit raise {
  let state = Ref(seed)
  for iteration in 0..<round_diff_cases {
    // the share of all-nine limbs rotates so that carries run through
    let nines = (iteration % 4).to_uint64() * 3UL
    let value = round_diff_value(state, length, nines)
    for shift in round_diff_value_shifts(state, value) {
      for mode in round_diff_modes {
        round_diff_check(value, shift, false, mode)
        round_diff_check(value, shift, true, mode)
      }
    }
  }
}

///|
test "round_div_pow10 equals the reference, 1 limb" {
  round_diff_class(1, 0x9E3779B97F4A7C15UL)
}

///|
test "round_div_pow10 equals the reference, 2 limbs" {
  round_diff_class(2, 0xD1B54A32D192ED03UL)
}

///|
test "round_div_pow10 equals the reference, 3 limbs" {
  round_diff_class(3, 0x2545F4914F6CDD1DUL)
}

///|
test "round_div_pow10 equals the reference, 6 limbs" {
  round_diff_class(6, 0x94D049BB133111EBUL)
}

///|
test "round_div_pow10 equals the reference, 12 limbs" {
  round_diff_class(12, 0xBF58476D1CE4E5B9UL)
}

///|
test "round_div_pow10 equals the reference, 56 limbs" {
  round_diff_class(56, 0x6A09E667F3BCC909UL)
}

///|
test "round_div_pow10 equals the reference, 112 limbs" {
  round_diff_class(112, 0xBB67AE8584CAA73BUL)
}

///|
test "round_div_pow10 equals the reference on powers of ten and nines" {
  for digits in 1..<400 {
    let power = dec_coeff_power10_repr(digits)
    let nines = dec_coeff_magnitude_sub_unit(power, 1)
    for value in [power, nines, dec_coeff_multiply_by_unit_repr(power, 5)] {
      for shift in 0..<(digits + 3) {
        for mode in round_diff_modes {
          round_diff_check(value, shift, false, mode)
          round_diff_check(value, shift, true, mode)
        }
      }
    }
  }
}
