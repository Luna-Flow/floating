// #441: `BinFloat::make` rounds to the precision and to the implementation
// range in one step. Below 2^binary_implementation_e_min the grid is the
// smallest quantum q = 2^(binary_implementation_e_min - (p - 1)) whatever the
// leading bit, so a value whose leading bit is in range but whose lowest bit is
// below q has to be rounded to a multiple of q, like every other path does.

///|
fn q441_quantum_exponent(precision : Int32) -> Int32 {
  binary_implementation_e_min - (precision - 1)
}

///|
fn q441_modes() -> Array[RoundingMode] {
  [
    RoundingMode::ToNearestEven,
    RoundingMode::AwayFromZero,
    RoundingMode::TowardZero,
    RoundingMode::TowardPositive,
    RoundingMode::TowardNegative,
  ]
}

///|
/// The independent oracle: c * 2^(-k) quanta rounded to an integer number of
/// quanta in `mode`, by integer arithmetic on a UInt64.
fn q441_oracle(
  c : UInt64,
  k : Int32,
  negative : Bool,
  mode : RoundingMode,
) -> UInt64 {
  let floor = c >> k
  let rem = c & ((1UL << k) - 1UL)
  let half = 1UL << (k - 1)
  let up = if rem == 0UL {
    false
  } else {
    match mode {
      RoundingMode::ToNearestEven =>
        rem > half || (rem == half && (floor & 1UL) == 1UL)
      RoundingMode::AwayFromZero => true
      RoundingMode::TowardZero => false
      RoundingMode::TowardPositive => !negative
      RoundingMode::TowardNegative => negative
    }
  }
  if up {
    floor + 1UL
  } else {
    floor
  }
}

///|
/// Odd coefficient c with exponent q - k and a leading bit at or above q
/// (so the underflow shortcut of `normalize_finite` is not taken):
/// c * 2^(q-k) with 2^k <= c.
fn q441_rows() -> Array[(UInt64, Int32)] {
  [
    (3UL, 1), // 1.5 quanta, leading bit at q
    (5UL, 2), // 1.25
    (7UL, 2), // 1.75
    (5UL, 1), // 2.5, leading bit above q
    (11UL, 2), // 2.75
    (13UL, 2), // 3.25
    (9UL, 3), // 1.125
    (15UL, 3), // 1.875
    (17UL, 3), // 2.125
    (29UL, 3), // 3.625
    (31UL, 4), // 1.9375
    (255UL, 5), // 7.96875
  ]
}

///|
test "make rounds a value whose lowest bit is below the smallest quantum (#441)" {
  for precision in [4, 5, 24, 53, 113] {
    let q = q441_quantum_exponent(precision)
    for mode_index, mode in q441_modes() {
      for negative in [false, true] {
        for row in q441_rows() {
          let (c, k) = row
          let actual = BinFloat::make(
            BinCoeff::from_uint64(c),
            q - k,
            precision,
            negative~,
            mode~,
          )
          let expected_units = q441_oracle(c, k, negative, mode)
          let expected = BinFloat::make(
            BinCoeff::from_uint64(expected_units),
            q,
            precision,
            negative~,
          )
          let label = "p=\{precision} mode=\{mode_index} neg=\{negative} c=\{c} k=\{k}"
          assert_eq(actual.exponent2(), expected.exponent2(), msg=label)
          assert_true(actual.coefficient() == expected.coefficient(), msg=label)
          assert_eq(actual.is_negative(), expected.is_negative(), msg=label)
          // The stored value is on the grid: no bit below the quantum.
          if !actual.is_zero() {
            assert_true(actual.exponent2() >= q, msg=label)
          }
        }
      }
    }
  }
}

///|
test "the example of #441" {
  let x = BinFloat::make(
    BinCoeff::from_uint64(3UL),
    binary_implementation_e_min - 53,
    53,
  )
  let y = x.add(BinFloat::zero())
  assert_true(x.coefficient() == y.coefficient())
  assert_eq(x.exponent2(), y.exponent2())
  assert_eq(x.exponent2(), binary_implementation_e_min - 52 + 1)
}

///|
test "from_coefficient, from_hex and with_precision round at the smallest quantum (#441)" {
  let q = q441_quantum_exponent(53)
  // from_hex: 0x3p(q-1) is 1.5 quanta, to nearest even 2 quanta.
  let hex = "0x3p\{q - 1}"
  let parsed = BinFloat::from_hex(hex, 53).unwrap()
  assert_eq(parsed.exponent2(), q + 1)
  assert_true(parsed.coefficient() == BinCoeff::from_uint64(1UL))
  // with_precision: a precision-113 value on the 113-bit grid moved to 53 bits
  // lands on the 53-bit quantum, which is coarser, and rounds there.
  let q113 = q441_quantum_exponent(113)
  let fine = BinFloat::make(BinCoeff::from_uint64(3UL), q113, 113)
  let coarse = fine.with_precision(53, RoundingMode::ToNearestEven)
  assert_true(coarse.exponent2() >= q)
  // from_coefficient has exponent 0 and is not near the range limit; it must
  // still be unchanged by the fix.
  let ordinary = BinFloat::from_coefficient(
    BinCoeff::from_uint64(12345UL),
    precision=53,
  )
  assert_true(ordinary.coefficient() == BinCoeff::from_uint64(12345UL))
  assert_eq(ordinary.exponent2(), 0)
}
