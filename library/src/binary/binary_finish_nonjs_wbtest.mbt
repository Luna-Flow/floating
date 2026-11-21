///|
/// Reference: the finish of 0.11 (before `bin_finish_words`), kept verbatim.
fn ref_low_nonzero(value : Coeff, count : Int32) -> Bool {
  let whole = count / 64
  let rest = count % 64
  for index in 0..<whole {
    if bin_coeff_word(value, index) != 0UL {
      return true
    }
  }
  rest != 0 && (bin_coeff_word(value, whole) & ((1UL << rest) - 1UL)) != 0UL
}

///|
fn ref_finish(
  negative : Bool,
  magnitude : Coeff,
  exponent : Int32,
  precision : Int32,
  inexact : Bool,
) -> Binary {
  let bits = magnitude.bit_length()
  if bits <= precision {
    let zeros = magnitude.ctz()
    if zeros == 0 {
      return finite_normalized(negative, magnitude, exponent, precision)
    }
    return finite_normalized(
      negative,
      magnitude.shift_right(zeros),
      exponent + zeros,
      precision,
    )
  }
  let shift = bits - precision
  let count = (precision + 63) / 64
  let words = FixedArray::make(count, 0UL)
  let word_shift = shift / 64
  let bit_shift = shift % 64
  for index in 0..<count {
    let low = bin_coeff_word(magnitude, word_shift + index)
    words.unsafe_set(
      index,
      if bit_shift == 0 {
        low
      } else {
        (low >> bit_shift) |
        (bin_coeff_word(magnitude, word_shift + index + 1) << (64 - bit_shift))
      },
    )
  }
  let mut result_exponent = exponent + shift
  let round_index = shift - 1
  if ((bin_coeff_word(magnitude, round_index / 64) >> (round_index % 64)) & 1UL) ==
    1UL {
    let sticky = inexact || ref_low_nonzero(magnitude, round_index)
    if sticky || (words.unsafe_get(0) & 1UL) == 1UL {
      let mut index = 0
      while index < count {
        let next = words.unsafe_get(index) + 1UL
        words.unsafe_set(index, next)
        if next != 0UL {
          break
        }
        index += 1
      }
      if index == count {
        words.unsafe_set(0, 1UL)
        result_exponent += 64 * count
      }
    }
  }
  let mut first = 0
  while words.unsafe_get(first) == 0UL {
    first += 1
  }
  let zeros = 64 * first + words.unsafe_get(first).reinterpret_as_int64().ctz()
  if zeros > 0 {
    let skip = zeros / 64
    let rest = zeros % 64
    for index in 0..<count {
      let low = if index + skip < count {
        words.unsafe_get(index + skip)
      } else {
        0UL
      }
      let high = if index + skip + 1 < count {
        words.unsafe_get(index + skip + 1)
      } else {
        0UL
      }
      words.unsafe_set(
        index,
        if rest == 0 {
          low
        } else {
          (low >> rest) | (high << (64 - rest))
        },
      )
    }
    result_exponent += zeros
  }
  finite_normalized(
    negative,
    bin_coeff_from_words(words, count),
    result_exponent,
    precision,
  )
}

///|
let finish_test_modes : Array[BinaryRoundingMode] = [
  RoundTiesToEven,
  RoundTiesToAway,
  RoundTowardZero,
  RoundTowardPositive,
  RoundTowardNegative,
]

///|
/// The words of `magnitude` in a fresh array of `count + extra` words (the
/// extra top words are zero, as after a cancellation).
fn finish_test_words(
  magnitude : Coeff,
  extra : Int32,
) -> (FixedArray[UInt64], Int32) {
  let count = (magnitude.bit_length() + 63) / 64 + extra
  let words = FixedArray::make(count, 0UL)
  for index in 0..<count {
    words.unsafe_set(index, bin_coeff_word(magnitude, index))
  }
  (words, count)
}

///|
/// A magnitude that stresses the rounding position: `kept` bits, then a
/// round bit and a tail chosen to hit ties, carries (all kept bits set) and
/// exact results.
fn finish_test_magnitude(random : FastCoeffRandom, precision : Int32) -> Coeff {
  let extra = 1 + random.below(140)
  let kept = match random.below(4) {
    0 => Coeff::one().shift_left(precision).sub_checked(Coeff::one()).unwrap()
    1 => Coeff::one().shift_left(precision - 1)
    _ => fast_coeff_value(random, precision)
  }
  let round = if random.below(2) == 0 {
    Coeff::zero()
  } else {
    Coeff::one().shift_left(extra - 1)
  }
  let tail = match random.below(3) {
    0 => Coeff::zero()
    1 =>
      if extra > 1 {
        Coeff::one().shift_left(random.below(extra - 1))
      } else {
        Coeff::zero()
      }
    _ =>
      if extra > 1 {
        fast_coeff_value(random, extra - 1)
      } else {
        Coeff::zero()
      }
  }
  kept.shift_left(extra).add(round).add(tail)
}

///|
// oracle: B
// source: binary_round_dyadic on the same magnitude (Coeff shift and the rounding core), every direction, exact magnitude and magnitude plus a tiny amount (sticky): a different algorithm from the route under test. The general route is itself checked against exact arithmetic on the inputs this test draws from (precisions from 2 to 8192, all five directions, ties, carries between words, borrow, cancellation, far operands, exact quotients, perfect squares) by the tests "add, mul, div and sqrt are rounded once, exactly: rows from exact arithmetic" and "add, mul, div and sqrt without a context: the ties-to-even rows" of arith_rows_check_wbtest.mbt (rows of arith_rows_wbtest.mbt from tools/generate_arith_rows.py: Python fractions and math.isqrt, library-ran: no); the exponent-range edges of binary16, binary32 and binary64 are rows there for add, mul and div.
// shares: both routes call binary_inexact_flags for the flags of an exact result and the Binary constructors (finite_normalized, bin_repr_word) to build the value, which the differential does not check and the table does through the flags and the printed value; the rounding decision is written twice, in the word, pair or limb finish of the fast route and in binary_apply_round_bits behind binary_round_dyadic / binary_round_rational / binary_round_sqrt in the general route, so it is not shared; fast_test_same compares value, precision label, sign and exponent
// primitives: Coeff::add, Coeff::sub_checked, Coeff::mul, Coeff::shift_left, binary_round_dyadic, binary_round_rational, binary_round_sqrt: level A on the same operations and widths in arith_rows_wbtest.mbt and, up to 128 bits, in the TestFloat gate
test "bin_finish_words equals binary_round_dyadic in every mode" {
  let random = { coeff_state: 0x5EED1234UL, }
  for iteration in 0..<40000 {
    let precision = 1 + random.below(300)
    let magnitude = if iteration % 3 == 0 {
      fast_coeff_value(random, 1 + random.below(600)).shift_left(
        random.below(70),
      )
    } else {
      finish_test_magnitude(random, precision)
    }
    let exponent = random.below(2000) - 1000
    let negative = random.below(2) == 0
    let bits = magnitude.bit_length()
    for mode in finish_test_modes {
      let context = BinaryContext::new(precision~, rounding=mode)
      // exact magnitude
      let expected = binary_round_dyadic(negative, magnitude, exponent, context).0
      let (words, count) = finish_test_words(magnitude, random.below(3))
      let actual = bin_finish_words(
        negative, words, count, exponent, precision, false, mode,
      )
      assert_true(fast_test_same(actual, expected))
      // magnitude plus a tiny positive amount
      if bits > precision {
        let tiny = magnitude.shift_left(8).add(Coeff::one())
        let expected = binary_round_dyadic(
            negative,
            tiny,
            exponent - 8,
            context,
          ).0
        let (words, count) = finish_test_words(magnitude, random.below(3))
        let actual = bin_finish_words(
          negative, words, count, exponent, precision, true, mode,
        )
        assert_true(fast_test_same(actual, expected))
      }
    }
  }
}

///|
// oracle: E
// source: ref_finish, the finish of 0.11 kept verbatim in the test; no independent value of its own
// shares: finite_normalized and the Coeff word accessors
// underneath: the same finish step is the last step of every add, mul, div and sqrt row of arith_rows_wbtest.mbt (A, p 2 to 4097, five directions, ties and all-ones carries); bin_finish_words is B against binary_round_dyadic in the block above
test "binary_coeff_fast_finish equals the finish of 0.11" {
  let random = { coeff_state: 0xF1A15E11UL, }
  for iteration in 0..<40000 {
    let precision = 1 + random.below(300)
    let magnitude = if iteration % 3 == 0 {
      fast_coeff_value(random, 1 + random.below(600)).shift_left(
        random.below(70),
      )
    } else {
      finish_test_magnitude(random, precision)
    }
    let exponent = random.below(2000) - 1000
    let negative = random.below(2) == 0
    for inexact in [false, true] {
      if inexact && magnitude.bit_length() <= precision {
        continue
      }
      let expected = ref_finish(
        negative, magnitude, exponent, precision, inexact,
      )
      let actual = binary_coeff_fast_finish(
        negative, magnitude, exponent, precision, inexact,
      )
      assert_true(fast_test_same(actual, expected))
    }
  }
}
