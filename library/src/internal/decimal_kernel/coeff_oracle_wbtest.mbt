///|
// Oracle of the coefficient kernel: level A. The expected values are computed by
// `tools/decimal_kernel_oracle.py` with CPython integers (`*`, `divmod`, `math.isqrt`,
// `math.gcd`; no library of this repository) and written to `coeff_oracle_rows_wbtest.mbt`
// as one FNV-1a digest per class. A class here is the loop of the Python program written out
// again: the operands are drawn from the same xorshift64 generator with the same limb
// generators, the kernel is called on them, and the decimal text of every operand and every
// result is folded into the digest, in the same order. The digest of the operands is part
// of the row, so an operand built wrongly (by `dec_coeff_multiply_repr`, `dec_coeff_power10_repr`,
// `dec_coeff_magnitude_add_unit` and the like, which build the operands of some classes) cannot
// hide a wrong result.
//
// The previous tests of these functions compared the kernel with a private reference
// implementation of the same kernel (levels C and E: a copy of the logic, the same Knuth core,
// the library BigInt rounding); they are replaced by these classes, which draw the same operand
// classes (the shapes and seeds are those of the old tests).

///|
priv struct OracleDigest {
  mut state : UInt64
}

///|
fn OracleDigest::new() -> OracleDigest {
  { state: 0xcbf29ce484222325UL, }
}

///|
/// The FNV-1a bytes of `text`, then one `0xff` step.
fn OracleDigest::add(self : OracleDigest, text : String) -> Unit {
  for char in text {
    self.state = (self.state ^ char.to_int().to_uint64()) * 0x100000001b3UL
  }
  self.state = (self.state ^ 0xffUL) * 0x100000001b3UL
}

///|
fn OracleDigest::add_coeff(self : OracleDigest, value : DecCoeff) -> Unit {
  self.add(value.to_string())
}

///|
fn OracleDigest::add_int(self : OracleDigest, value : Int32) -> Unit {
  self.add(value.to_string())
}

///|
fn OracleDigest::add_flag(self : OracleDigest, flag : Bool) -> Unit {
  self.add(if flag { "1" } else { "0" })
}

///|
/// The digest of the row `id` of `decimal_kernel_oracle_table`.
fn oracle_expected(id : String) -> UInt64 raise {
  for line in decimal_kernel_oracle_table.split("\n") {
    let line = line.to_owned()
    let prefix = id + " "
    if line.has_prefix(prefix.to_string()) {
      let mut result = 0UL
      for char in line[prefix.length():line.length()] {
        result = result * 10UL + (char.to_int() - 48).to_uint64()
      }
      return result
    }
  }
  fail("no oracle row " + id)
}

///|
fn oracle_finish(id : String, digest : OracleDigest) -> Unit raise {
  let expected = oracle_expected(id)
  if digest.state != expected {
    fail(
      "oracle class \{id}: digest \{digest.state} differs from the CPython digest \{expected}",
    )
  }
}

///|
/// The limb generators of the Python program (`round_value`, `random_limbs`), the xorshift64
/// generator `sqrt_diff_next` of `coeff_sqrt_diff_wbtest.mbt`.
fn oracle_value(
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
fn oracle_all_nines(length : Int32) -> DecCoeff {
  let limbs = Array::make(length, (dec_coeff_base - 1).reinterpret_as_uint())
  dec_coeff_from_unit_accumulator(limbs, length)
}

///|
let oracle_cases : Int32 = 300

///|
let oracle_modes : Array[DecCoeffRounding] = [
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
fn oracle_same(a : DecCoeff, b : DecCoeff) -> Bool {
  match (a, b) {
    (Small(x), Small(y)) => x == y
    (Limbs(x, dx), Limbs(y, dy)) => dx == dy && x == y
    _ => false
  }
}

///|
// ---- round_div_pow10 ----

///|
/// `dec_coeff_round_div_pow10` for the eight directions and both signs, with the owned entry
/// compared with it (the persistent operand must not change either).
fn oracle_round_add(
  digest : OracleDigest,
  value : DecCoeff,
  shift : Int32,
) -> Unit raise {
  digest.add_coeff(value)
  digest.add_int(shift)
  for mode in oracle_modes {
    for negative in [false, true] {
      let (actual, inexact) = dec_coeff_round_div_pow10(
        value, shift, negative, mode,
      )
      digest.add_coeff(actual)
      digest.add_flag(inexact)
      if value is Limbs(units, digits) {
        let (owned, owned_inexact) = dec_coeff_round_div_pow10_owned(
          units.copy(),
          digits,
          shift,
          negative,
          mode,
        )
        if !oracle_same(actual, owned) || inexact != owned_inexact {
          fail(
            "round_div_pow10_owned differs from round_div_pow10 for \{value.to_string()} shift \{shift}",
          )
        }
      }
    }
  }
}

///|
fn oracle_round_shifts(state : Ref[UInt64], value : DecCoeff) -> Array[Int32] {
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
fn oracle_round_class(length : Int32, seed : UInt64) -> Unit raise {
  let state = Ref(seed)
  let digest = OracleDigest::new()
  for iteration in 0..<oracle_cases {
    let nines = (iteration % 4).to_uint64() * 3UL
    let value = oracle_value(state, length, nines)
    for shift in oracle_round_shifts(state, value) {
      oracle_round_add(digest, value, shift)
    }
  }
  oracle_finish("round-\{length}", digest)
}

///|
// oracle: A
// source: tools/decimal_kernel_oracle.py, `round` table: CPython integers, the quotient and the
//   remainder of `divmod(value, 10^shift)` and the rounding table of GDA and IEEE 754-2019 4.3
//   written out in Python (the rule of each of the eight directions for both signs)
// shares: the operand is drawn by `oracle_value` and `dec_coeff_from_unit_accumulator` (the operand
//   text is in the digest), `DecCoeff::to_string` reads the results (the digest is of the text)
test "decimal kernel oracle: round_div_pow10, 1 limb" {
  oracle_round_class(1, 0x9E3779B97F4A7C15UL)
}

///|
// oracle: A
// source: tools/decimal_kernel_oracle.py, `round` table (CPython integers, the rounding table of
//   GDA and IEEE 754-2019 4.3 written out in Python)
// shares: the operand is drawn by `oracle_value` and `dec_coeff_from_unit_accumulator` (the operand
//   text is in the digest), `DecCoeff::to_string` reads the results
test "decimal kernel oracle: round_div_pow10, 2 limbs" {
  oracle_round_class(2, 0xD1B54A32D192ED03UL)
}

///|
// oracle: A
// source: tools/decimal_kernel_oracle.py, `round` table (CPython integers, the rounding table of
//   GDA and IEEE 754-2019 4.3 written out in Python)
// shares: the operand is drawn by `oracle_value` and `dec_coeff_from_unit_accumulator` (the operand
//   text is in the digest), `DecCoeff::to_string` reads the results
test "decimal kernel oracle: round_div_pow10, 3 limbs" {
  oracle_round_class(3, 0x2545F4914F6CDD1DUL)
}

///|
// oracle: A
// source: tools/decimal_kernel_oracle.py, `round` table (CPython integers, the rounding table of
//   GDA and IEEE 754-2019 4.3 written out in Python)
// shares: the operand is drawn by `oracle_value` and `dec_coeff_from_unit_accumulator` (the operand
//   text is in the digest), `DecCoeff::to_string` reads the results
test "decimal kernel oracle: round_div_pow10, 6 limbs" {
  oracle_round_class(6, 0x94D049BB133111EBUL)
}

///|
// oracle: A
// source: tools/decimal_kernel_oracle.py, `round` table (CPython integers, the rounding table of
//   GDA and IEEE 754-2019 4.3 written out in Python)
// shares: the operand is drawn by `oracle_value` and `dec_coeff_from_unit_accumulator` (the operand
//   text is in the digest), `DecCoeff::to_string` reads the results
test "decimal kernel oracle: round_div_pow10, 12 limbs" {
  oracle_round_class(12, 0xBF58476D1CE4E5B9UL)
}

///|
// oracle: A
// source: tools/decimal_kernel_oracle.py, `round` table (CPython integers, the rounding table of
//   GDA and IEEE 754-2019 4.3 written out in Python)
// shares: the operand is drawn by `oracle_value` and `dec_coeff_from_unit_accumulator` (the operand
//   text is in the digest), `DecCoeff::to_string` reads the results
test "decimal kernel oracle: round_div_pow10, 56 limbs" {
  oracle_round_class(56, 0x6A09E667F3BCC909UL)
}

///|
// oracle: A
// source: tools/decimal_kernel_oracle.py, `round` table (CPython integers, the rounding table of
//   GDA and IEEE 754-2019 4.3 written out in Python)
// shares: the operand is drawn by `oracle_value` and `dec_coeff_from_unit_accumulator` (the operand
//   text is in the digest), `DecCoeff::to_string` reads the results
test "decimal kernel oracle: round_div_pow10, 112 limbs" {
  oracle_round_class(112, 0xBB67AE8584CAA73BUL)
}

///|
// oracle: A
// source: tools/decimal_kernel_oracle.py, `round` table, row `round-powers`: 10^d, 10^d - 1 and
//   5 10^d for d in 1..399 at every shift from 0 to d + 2 (exact ties, all-nine carries, shifts
//   at and across limb boundaries); CPython integers and the rounding table written out in Python
// shares: the operands are built with `dec_coeff_power10_repr`, `dec_coeff_magnitude_sub_unit` and
//   `dec_coeff_multiply_by_unit_repr` (their text is in the digest, so a wrong operand fails the row)
test "decimal kernel oracle: round_div_pow10, powers of ten and nines" {
  let digest = OracleDigest::new()
  for digits in 1..<400 {
    let power = dec_coeff_power10_repr(digits)
    let nines = dec_coeff_magnitude_sub_unit(power, 1)
    for value in [power, nines, dec_coeff_multiply_by_unit_repr(power, 5)] {
      for shift in 0..<(digits + 3) {
        oracle_round_add(digest, value, shift)
      }
    }
  }
  oracle_finish("round-powers", digest)
}

///|
// ---- Knuth division and the scaled quotient ----

///|
fn oracle_div_add(
  digest : OracleDigest,
  numerator : DecCoeff,
  denominator : DecCoeff,
) -> Unit {
  let (quotient, remainder) = dec_coeff_div_rem_knuth_repr(
    numerator, denominator,
  )
  digest.add_coeff(numerator)
  digest.add_coeff(denominator)
  digest.add_coeff(quotient)
  digest.add_coeff(remainder)
}

///|
fn oracle_scaled_add(
  digest : OracleDigest,
  coefficient : DecCoeff,
  shift : Int32,
  denominator : DecCoeff,
) -> Unit {
  digest.add_coeff(coefficient)
  digest.add_int(shift)
  digest.add_coeff(denominator)
  digest.add_coeff(
    dec_coeff_div_scaled_inexact(coefficient, shift, denominator),
  )
}

///|
fn oracle_div_class(
  numerator_limbs : Int32,
  denominator_limbs : Int32,
  seed : UInt64,
) -> Unit raise {
  let state = Ref(seed)
  let digest = OracleDigest::new()
  for iteration in 0..<oracle_cases {
    let nines = (iteration % 4).to_uint64() * 3UL
    let numerator = oracle_value(state, numerator_limbs, nines)
    let denominator = oracle_value(state, denominator_limbs, nines)
    oracle_div_add(digest, numerator, denominator)
    let multiple = dec_coeff_multiply_repr(denominator, numerator)
    oracle_div_add(digest, multiple, denominator)
    oracle_div_add(
      digest,
      dec_coeff_magnitude_add_unit(multiple, 1),
      denominator,
    )
    oracle_div_add(
      digest,
      dec_coeff_magnitude_sub_unit(multiple, 1),
      denominator,
    )
    let coefficient = oracle_value(state, numerator_limbs, nines)
    let shift = (sqrt_diff_next(state) % 40UL).to_int()
    oracle_scaled_add(digest, coefficient, shift, denominator)
    let twos = (sqrt_diff_next(state) % 12UL).to_int()
    let fives = (sqrt_diff_next(state) % 8UL).to_int()
    let mut composite = denominator
    for _ in 0..<twos {
      composite = dec_coeff_multiply_by_unit_repr(composite, 2)
    }
    for _ in 0..<fives {
      composite = dec_coeff_multiply_by_unit_repr(composite, 5)
    }
    oracle_scaled_add(digest, coefficient, shift, composite)
    oracle_scaled_add(
      digest,
      dec_coeff_multiply_repr(coefficient, denominator),
      shift,
      composite,
    )
    oracle_scaled_add(
      digest,
      coefficient,
      shift,
      dec_coeff_power10_repr(twos + 9),
    )
  }
  oracle_finish("div-\{numerator_limbs}x\{denominator_limbs}", digest)
}

///|
// oracle: A
// source: tools/decimal_kernel_oracle.py, `div` table: `divmod` of CPython integers for the
//   quotient and the remainder of Knuth's division (operand, an exact multiple, one above and one
//   below it); for the scaled quotient `c 10^s / d`, `divmod`, the finite expansion decided by the
//   definition (`d / gcd(n, d)` has no prime factor but 2 and 5) and the increment when the last
//   digit is 0 or 5, all in Python
// shares: the operands are drawn by `oracle_value` and built with `dec_coeff_multiply_repr`,
//   `dec_coeff_magnitude_add_unit`, `dec_coeff_magnitude_sub_unit`, `dec_coeff_multiply_by_unit_repr`
//   and `dec_coeff_power10_repr` (their text is in the digest)
test "decimal kernel oracle: Knuth division and scaled quotient, 2 by 2 limbs" {
  oracle_div_class(2, 2, 0x9E3779B97F4A7C15UL)
}

///|
// oracle: A
// source: tools/decimal_kernel_oracle.py, `div` table (CPython `divmod`; the finite expansion by
//   the definition with `math.gcd`)
// shares: the operands are drawn by `oracle_value` and built with the `dec_coeff_*_repr` operand
//   builders, whose text is in the digest
test "decimal kernel oracle: Knuth division and scaled quotient, 4 by 2 limbs" {
  oracle_div_class(4, 2, 0xD1B54A32D192ED03UL)
}

///|
// oracle: A
// source: tools/decimal_kernel_oracle.py, `div` table (CPython `divmod`; the finite expansion by
//   the definition with `math.gcd`)
// shares: the operands are drawn by `oracle_value` and built with the `dec_coeff_*_repr` operand
//   builders, whose text is in the digest
test "decimal kernel oracle: Knuth division and scaled quotient, 4 by 3 limbs" {
  oracle_div_class(4, 3, 0x2545F4914F6CDD1DUL)
}

///|
// oracle: A
// source: tools/decimal_kernel_oracle.py, `div` table (CPython `divmod`; the finite expansion by
//   the definition with `math.gcd`)
// shares: the operands are drawn by `oracle_value` and built with the `dec_coeff_*_repr` operand
//   builders, whose text is in the digest
test "decimal kernel oracle: Knuth division and scaled quotient, 8 by 4 limbs" {
  oracle_div_class(8, 4, 0x94D049BB133111EBUL)
}

///|
// oracle: A
// source: tools/decimal_kernel_oracle.py, `div` table (CPython `divmod`; the finite expansion by
//   the definition with `math.gcd`)
// shares: the operands are drawn by `oracle_value` and built with the `dec_coeff_*_repr` operand
//   builders, whose text is in the digest
test "decimal kernel oracle: Knuth division and scaled quotient, 12 by 6 limbs" {
  oracle_div_class(12, 6, 0xBF58476D1CE4E5B9UL)
}

///|
// oracle: A
// source: tools/decimal_kernel_oracle.py, `div` table (CPython `divmod`; the finite expansion by
//   the definition with `math.gcd`)
// shares: the operands are drawn by `oracle_value` and built with the `dec_coeff_*_repr` operand
//   builders, whose text is in the digest
test "decimal kernel oracle: Knuth division and scaled quotient, 24 by 12 limbs" {
  oracle_div_class(24, 12, 0x6A09E667F3BCC909UL)
}

///|
// oracle: A
// source: tools/decimal_kernel_oracle.py, `div` table (CPython `divmod`; the finite expansion by
//   the definition with `math.gcd`)
// shares: the operands are drawn by `oracle_value` and built with the `dec_coeff_*_repr` operand
//   builders, whose text is in the digest
test "decimal kernel oracle: Knuth division and scaled quotient, 112 by 56 limbs" {
  oracle_div_class(112, 56, 0xBB67AE8584CAA73BUL)
}

///|
// oracle: A
// source: tools/decimal_kernel_oracle.py, `div` table (CPython `divmod`; the finite expansion by
//   the definition with `math.gcd`)
// shares: the operands are drawn by `oracle_value` and built with the `dec_coeff_*_repr` operand
//   builders, whose text is in the digest
test "decimal kernel oracle: Knuth division and scaled quotient, 224 by 112 limbs" {
  oracle_div_class(224, 112, 0x3C6EF372FE94F82BUL)
}

///|
// oracle: A
// source: tools/decimal_kernel_oracle.py, `div` table, row `div-powers`: the numerators 10^d,
//   10^d - 1 and 7 10^d against 10^(d/2+9), 10^(d/2+9) - 1 and 10^(d/3+9) + 1 for d in 10..399
//   (quotients that are exact powers, all-nine quotient limbs, finite and infinite expansions);
//   CPython `divmod`, `math.gcd`
// shares: the operands are built with `dec_coeff_power10_repr`, `dec_coeff_magnitude_sub_unit`,
//   `dec_coeff_magnitude_add_unit` and `dec_coeff_multiply_by_unit_repr` (their text is in the digest)
test "decimal kernel oracle: Knuth division and scaled quotient, powers of ten and nines" {
  let digest = OracleDigest::new()
  for digits in 10..<400 {
    let power = dec_coeff_power10_repr(digits)
    let nines = dec_coeff_magnitude_sub_unit(power, 1)
    for
      denominator in [
        dec_coeff_power10_repr(digits / 2 + 9),
        dec_coeff_magnitude_sub_unit(dec_coeff_power10_repr(digits / 2 + 9), 1),
        dec_coeff_magnitude_add_unit(dec_coeff_power10_repr(digits / 3 + 9), 1),
      ] {
      for numerator in [power, nines, dec_coeff_multiply_by_unit_repr(power, 7)] {
        if dec_coeff_compare_repr(numerator, denominator) >= 0 &&
          dec_coeff_unit_len(denominator) > 1 {
          oracle_div_add(digest, numerator, denominator)
        }
        oracle_scaled_add(digest, numerator, digits % 25, denominator)
      }
    }
  }
  oracle_finish("div-powers", digest)
}

///|
// ---- integer square root ----

///|
fn oracle_sqrt_add(digest : OracleDigest, n : DecCoeff) -> Unit {
  let (root, remainder) = dec_coeff_integer_sqrt_rem_repr(n)
  digest.add_coeff(n)
  digest.add_coeff(root)
  digest.add_coeff(remainder)
}

///|
fn oracle_sqrt_class(length : Int32, seed : UInt64) -> Unit raise {
  let state = Ref(seed)
  let digest = OracleDigest::new()
  for _ in 0..<oracle_cases {
    oracle_sqrt_add(digest, sqrt_diff_random_limbs(state, length))
    let root = sqrt_diff_random_limbs(state, (length + 1) / 2)
    let square = dec_coeff_square_repr(root)
    oracle_sqrt_add(digest, square)
    oracle_sqrt_add(digest, dec_coeff_magnitude_add_unit(square, 1))
    oracle_sqrt_add(digest, dec_coeff_magnitude_sub_unit(square, 1))
  }
  oracle_finish("sqrt-\{length}", digest)
}

///|
// oracle: A
// source: tools/decimal_kernel_oracle.py, `sqrt` table: `math.isqrt` of CPython for the root and
//   `n - isqrt(n)^2` for the remainder, on random radicands of the class and on a perfect square,
//   one below and one above it
// shares: the radicands are drawn by `sqrt_diff_random_limbs` and the square formed with
//   `dec_coeff_square_repr`, `dec_coeff_magnitude_add_unit`, `dec_coeff_magnitude_sub_unit` (their
//   text is in the digest, so a wrong square fails the row)
test "decimal kernel oracle: integer square root, 1 limb" {
  oracle_sqrt_class(1, 0x9E3779B97F4A7C15UL)
}

///|
// oracle: A
// source: tools/decimal_kernel_oracle.py, `sqrt` table (`math.isqrt`, remainder `n - isqrt(n)^2`)
// shares: the radicands are drawn by `sqrt_diff_random_limbs` and the square is formed with
//   `dec_coeff_square_repr` (their text is in the digest)
test "decimal kernel oracle: integer square root, 2 limbs" {
  oracle_sqrt_class(2, 0xD1B54A32D192ED03UL)
}

///|
// oracle: A
// source: tools/decimal_kernel_oracle.py, `sqrt` table (`math.isqrt`, remainder `n - isqrt(n)^2`)
// shares: the radicands are drawn by `sqrt_diff_random_limbs` and the square is formed with
//   `dec_coeff_square_repr` (their text is in the digest)
test "decimal kernel oracle: integer square root, 3 limbs" {
  oracle_sqrt_class(3, 0x2545F4914F6CDD1DUL)
}

///|
// oracle: A
// source: tools/decimal_kernel_oracle.py, `sqrt` table (`math.isqrt`, remainder `n - isqrt(n)^2`)
// shares: the radicands are drawn by `sqrt_diff_random_limbs` and the square is formed with
//   `dec_coeff_square_repr` (their text is in the digest)
test "decimal kernel oracle: integer square root, 6 limbs" {
  oracle_sqrt_class(6, 0x94D049BB133111EBUL)
}

///|
// oracle: A
// source: tools/decimal_kernel_oracle.py, `sqrt` table (`math.isqrt`, remainder `n - isqrt(n)^2`)
// shares: the radicands are drawn by `sqrt_diff_random_limbs` and the square is formed with
//   `dec_coeff_square_repr` (their text is in the digest)
test "decimal kernel oracle: integer square root, 12 limbs" {
  oracle_sqrt_class(12, 0xBF58476D1CE4E5B9UL)
}

///|
// oracle: A
// source: tools/decimal_kernel_oracle.py, `sqrt` table (`math.isqrt`, remainder `n - isqrt(n)^2`)
// shares: the radicands are drawn by `sqrt_diff_random_limbs` and the square is formed with
//   `dec_coeff_square_repr` (their text is in the digest)
test "decimal kernel oracle: integer square root, 56 limbs" {
  oracle_sqrt_class(56, 0x6A09E667F3BCC909UL)
}

///|
// oracle: A
// source: tools/decimal_kernel_oracle.py, `sqrt` table (`math.isqrt`, remainder `n - isqrt(n)^2`)
// shares: the radicands are drawn by `sqrt_diff_random_limbs` and the square is formed with
//   `dec_coeff_square_repr` (their text is in the digest)
test "decimal kernel oracle: integer square root, 112 limbs" {
  oracle_sqrt_class(112, 0xBB67AE8584CAA73BUL)
}

///|
// oracle: A
// source: tools/decimal_kernel_oracle.py, `sqrt` table, row `sqrt-powers`: 10^d, 10^d + 1, 10^d - 1,
//   4 10^d, 9 10^d and 3 10^d for d in 0..1099 (both parities of the digit count around the perfect
//   squares 10^(2k) and 4 10^(2k)); `math.isqrt` of CPython
// shares: the radicands are built with `dec_coeff_power10_repr`, `dec_coeff_magnitude_add_unit`,
//   `dec_coeff_magnitude_sub_unit` and `dec_coeff_multiply_by_unit_repr` (their text is in the digest)
test "decimal kernel oracle: integer square root, powers of ten" {
  let digest = OracleDigest::new()
  for digits in 0..<1100 {
    let power = dec_coeff_power10_repr(digits)
    oracle_sqrt_add(digest, power)
    oracle_sqrt_add(digest, dec_coeff_magnitude_add_unit(power, 1))
    if digits > 0 {
      oracle_sqrt_add(digest, dec_coeff_magnitude_sub_unit(power, 1))
    }
    oracle_sqrt_add(digest, dec_coeff_multiply_by_unit_repr(power, 4))
    oracle_sqrt_add(digest, dec_coeff_multiply_by_unit_repr(power, 9))
    oracle_sqrt_add(digest, dec_coeff_multiply_by_unit_repr(power, 3))
  }
  oracle_finish("sqrt-powers", digest)
}

///|
// oracle: A
// source: tools/decimal_kernel_oracle.py, `sqrt` table, row `sqrt-small`: every n below 2000, then
//   random single-word values below 10^18, squares of random roots below 10^9, one below and one
//   above them; `math.isqrt` of CPython
// shares: nothing but `DecCoeff::to_string` (the radicands are `DecCoeff::Small` of the drawn word
//   or `dec_coeff_from_int`; the digest reads their text)
test "decimal kernel oracle: integer square root, the small range" {
  let digest = OracleDigest::new()
  for value in 0..<2000 {
    oracle_sqrt_add(digest, dec_coeff_from_int(value))
  }
  let state = Ref(0x123456789ABCDEF1UL)
  for _ in 0..<oracle_cases {
    let value = sqrt_diff_next(state) % dec_coeff_small_limit
    oracle_sqrt_add(digest, DecCoeff::Small(value))
    let root = sqrt_diff_next(state) % 1000000000UL
    oracle_sqrt_add(digest, DecCoeff::Small(root * root))
    if root > 0UL {
      oracle_sqrt_add(digest, DecCoeff::Small(root * root - 1UL))
    }
    oracle_sqrt_add(digest, DecCoeff::Small(root * root + 1UL))
  }
  oracle_finish("sqrt-small", digest)
}

///|
// ---- schoolbook product ----

///|
fn oracle_mul_add(
  digest : OracleDigest,
  left : DecCoeff,
  right : DecCoeff,
) -> Unit {
  digest.add_coeff(left)
  digest.add_coeff(right)
  digest.add_coeff(dec_coeff_mul_schoolbook(left, right))
}

///|
fn oracle_square_add(digest : OracleDigest, value : DecCoeff) -> Unit {
  digest.add_coeff(value)
  digest.add_coeff(dec_coeff_square_schoolbook(value))
}

///|
fn oracle_mul_class(
  left_limbs : Int32,
  right_limbs : Int32,
  seed : UInt64,
) -> Unit raise {
  let state = Ref(seed)
  let digest = OracleDigest::new()
  for iteration in 0..<oracle_cases {
    let nines = (iteration % 4).to_uint64() * 3UL
    let left = oracle_value(state, left_limbs, nines)
    let right = oracle_value(state, right_limbs, nines)
    oracle_mul_add(digest, left, right)
    oracle_square_add(digest, left)
  }
  oracle_finish("mul-\{left_limbs}x\{right_limbs}", digest)
}

///|
// oracle: A
// source: tools/decimal_kernel_oracle.py, `mul` table: `a * b` and `a * a` of CPython integers
// shares: the operands are drawn by `oracle_value` (their text is in the digest)
test "decimal kernel oracle: schoolbook product, 1 and 2 limbs" {
  oracle_mul_class(1, 1, 0x9E3779B97F4A7C15UL)
  oracle_mul_class(1, 2, 0xD1B54A32D192ED03UL)
  oracle_mul_class(2, 2, 0x2545F4914F6CDD1DUL)
}

///|
// oracle: A
// source: tools/decimal_kernel_oracle.py, `mul` table: `a * b` and `a * a` of CPython integers
// shares: the operands are drawn by `oracle_value` (their text is in the digest)
test "decimal kernel oracle: schoolbook product, 3 to 12 limbs" {
  oracle_mul_class(3, 3, 0x94D049BB133111EBUL)
  oracle_mul_class(4, 4, 0xBF58476D1CE4E5B9UL)
  oracle_mul_class(6, 3, 0x6A09E667F3BCC909UL)
  oracle_mul_class(12, 12, 0xBB67AE8584CAA73BUL)
}

///|
// oracle: A
// source: tools/decimal_kernel_oracle.py, `mul` table: `a * b` and `a * a` of CPython integers,
//   at 17, 18 and 19 limbs (the column limit of the schoolbook is 18 limbs) and 40 by 18
// shares: the operands are drawn by `oracle_value` (their text is in the digest)
test "decimal kernel oracle: schoolbook product around the column limit of 18 limbs" {
  oracle_mul_class(17, 17, 0x3C6EF372FE94F82BUL)
  oracle_mul_class(18, 18, 0xA54FF53A5F1D36F1UL)
  oracle_mul_class(19, 18, 0x510E527FADE682D1UL)
  oracle_mul_class(19, 19, 0x9B05688C2B3E6C1FUL)
  oracle_mul_class(40, 18, 0x1F83D9ABFB41BD6BUL)
}

///|
// oracle: A
// source: tools/decimal_kernel_oracle.py, `mul` table: `a * b` and `a * a` of CPython integers
// shares: the operands are drawn by `oracle_value` (their text is in the digest)
test "decimal kernel oracle: schoolbook product, 56 and 112 limbs" {
  oracle_mul_class(56, 56, 0x5BE0CD19137E2179UL)
  oracle_mul_class(112, 112, 0xCBBB9D5DC1059ED8UL)
  oracle_mul_class(112, 20, 0x629A292A367CD507UL)
}

///|
// oracle: A
// source: tools/decimal_kernel_oracle.py, `mul` table, row `mul-nines`: (10^(9 n) - 1)^2 and the
//   products with the all-nines values of n + 1 and n / 2 + 1 limbs for n in 1..139 (every column
//   sum is the largest possible); `a * b` of CPython integers
// shares: the operands are built by `oracle_all_nines` and `dec_coeff_from_unit_accumulator` (their
//   text is in the digest)
test "decimal kernel oracle: schoolbook product and square of all 10^9 - 1 limbs at every length" {
  let digest = OracleDigest::new()
  for length in 1..<140 {
    let nines = oracle_all_nines(length)
    oracle_mul_add(digest, nines, nines)
    digest.add_coeff(dec_coeff_square_schoolbook(nines))
    oracle_mul_add(digest, nines, oracle_all_nines(length + 1))
    oracle_mul_add(digest, oracle_all_nines(length / 2 + 1), nines)
  }
  oracle_finish("mul-nines", digest)
}

///|
// oracle: A
// source: tools/decimal_kernel_oracle.py, `mul` table, row `mul-folds`: operands of 1 to 97 limbs
//   against 1, n - 1, n, n + 1 and 2 n + 1 limbs, in both orders, and squares, around every fold
//   boundary of the column accumulator (15, 16, 17 and more products per column); `a * b` of CPython
// shares: the operands are drawn by `oracle_value` (their text is in the digest)
test "decimal kernel oracle: schoolbook product and square around each fold boundary" {
  let state = Ref(0x243F6A8885A308D3UL)
  let digest = OracleDigest::new()
  for
    length in [
      1, 2, 15, 16, 17, 18, 19, 31, 32, 33, 34, 47, 48, 49, 63, 64, 65, 80, 81, 96,
      97,
    ] {
    for other in [1, length - 1, length, length + 1, 2 * length + 1] {
      if other >= 1 {
        for iteration in 0..<20 {
          let nines = (iteration % 4).to_uint64() * 3UL
          let left = oracle_value(state, length, nines)
          let right = oracle_value(state, other, nines)
          oracle_mul_add(digest, left, right)
          oracle_mul_add(digest, right, left)
        }
      }
    }
    for iteration in 0..<20 {
      let nines = (iteration % 4).to_uint64() * 3UL
      oracle_square_add(digest, oracle_value(state, length, nines))
    }
  }
  oracle_finish("mul-folds", digest)
}

///|
// ---- unbalanced product ----

///|
fn oracle_unbalanced_add(
  digest : OracleDigest,
  short : DecCoeff,
  long : DecCoeff,
) -> Unit {
  digest.add_coeff(short)
  digest.add_coeff(long)
  digest.add_coeff(dec_coeff_mul_unbalanced(short, long))
  digest.add_coeff(dec_coeff_multiply_repr(short, long))
  digest.add_coeff(dec_coeff_multiply_repr(long, short))
}

///|
// oracle: A
// source: tools/decimal_kernel_oracle.py, `unbalanced` table, row `unbalanced-shapes`: `a * b` of
//   CPython integers for the unbalanced entry and for the public dispatch in both operand orders,
//   on shapes of 1 to 191 limbs against 2.1 to 12 times as many (1 to 3 limbs, the column limit
//   of 18, the fold boundary of 16, just below the threshold of 191)
// shares: the operands are drawn by `oracle_value` (their text is in the digest)
test "decimal kernel oracle: unbalanced product on shapes around every boundary" {
  let state = Ref(0x9E3779B97F4A7C15UL)
  let digest = OracleDigest::new()
  for short_limbs in [1, 2, 3, 5, 9, 17, 18, 19, 20, 33, 34, 50, 96, 150, 191] {
    for factor_tenths in [21, 25, 30, 50, 80, 120] {
      let long_limbs = short_limbs * factor_tenths / 10 + 1
      if long_limbs > 2 * short_limbs {
        for round in 0..<4 {
          let nines = (round * 3).to_uint64()
          let short = oracle_value(state, short_limbs, nines)
          let long = oracle_value(state, long_limbs, nines)
          oracle_unbalanced_add(digest, short, long)
        }
      }
    }
  }
  oracle_finish("unbalanced-shapes", digest)
}

///|
// oracle: A
// source: tools/decimal_kernel_oracle.py, `unbalanced` table, row `unbalanced-blocks`: `a * b` of
//   CPython integers on operands above the threshold, where the block products are used
// shares: the operands are drawn by `oracle_value` (their text is in the digest)
test "decimal kernel oracle: unbalanced product above the threshold (block products)" {
  let state = Ref(0xD1B54A32D192ED03UL)
  let digest = OracleDigest::new()
  for short_limbs in [192, 200, 250] {
    for
      long_limbs in [2 * short_limbs + 1, 3 * short_limbs, 4 * short_limbs + 7] {
      for nines in [0UL, 6UL] {
        let short = oracle_value(state, short_limbs, nines)
        let long = oracle_value(state, long_limbs, nines)
        oracle_unbalanced_add(digest, short, long)
      }
    }
  }
  oracle_finish("unbalanced-blocks", digest)
}

///|
// oracle: A
// source: tools/decimal_kernel_oracle.py, `unbalanced` table, row `unbalanced-nines`: `a * b` of
//   CPython integers for all-nines operands (the largest column sums) at every fold boundary
// shares: the operands are built by `oracle_all_nines` (their text is in the digest)
test "decimal kernel oracle: unbalanced product of all-nines operands" {
  let digest = OracleDigest::new()
  for short_limbs in [1, 2, 15, 16, 17, 18, 19, 31, 32, 33, 64, 100, 191] {
    for
      long_limbs in [
        2 * short_limbs + 1,
        3 * short_limbs + 2,
        40 + 5 * short_limbs,
      ] {
      oracle_unbalanced_add(
        digest,
        oracle_all_nines(short_limbs),
        oracle_all_nines(long_limbs),
      )
    }
  }
  oracle_finish("unbalanced-nines", digest)
}

///|
// ---- finite decimal expansion ----

///|
fn oracle_finite_power(base : Int32, exponent : Int32) -> DecCoeff {
  let mut value = dec_coeff_from_int(1)
  for _ in 0..<exponent {
    value = dec_coeff_multiply_by_unit_repr(value, base)
  }
  value
}

///|
fn oracle_finite_add(
  digest : OracleDigest,
  numerator : DecCoeff,
  denominator : DecCoeff,
) -> Unit {
  digest.add_coeff(numerator)
  digest.add_coeff(denominator)
  digest.add_flag(has_finite_decimal_expansion_repr(numerator, denominator))
}

///|
fn oracle_finite_class(limbs : Int32, seed : UInt64) -> Unit raise {
  let state = Ref(seed)
  let digest = OracleDigest::new()
  for iteration in 0..<oracle_cases {
    let nines = (iteration % 4).to_uint64() * 3UL
    let numerator = oracle_value(state, limbs, nines)
    let part = oracle_value(state, (limbs + 1) / 2, nines)
    let twos = [0, 1, 3, 8, 9, 10, 20, 37][(sqrt_diff_next(state) % 8UL).to_int()]
    let fives = [0, 1, 4, 8, 9, 11, 25][(sqrt_diff_next(state) % 7UL).to_int()]
    let denominator = dec_coeff_multiply_repr(
      dec_coeff_multiply_repr(part, oracle_finite_power(2, twos)),
      oracle_finite_power(5, fives),
    )
    oracle_finite_add(digest, numerator, denominator)
    oracle_finite_add(
      digest,
      dec_coeff_multiply_repr(numerator, part),
      denominator,
    )
    oracle_finite_add(
      digest,
      dec_coeff_multiply_repr(numerator, denominator),
      denominator,
    )
    oracle_finite_add(
      digest,
      dec_coeff_magnitude_add_unit(dec_coeff_multiply_repr(numerator, part), 1),
      denominator,
    )
    oracle_finite_add(digest, denominator, denominator)
    oracle_finite_add(digest, dec_coeff_zero(), denominator)
    oracle_finite_add(digest, dec_coeff_from_int(1), denominator)
  }
  oracle_finish("finite-\{limbs}", digest)
}

///|
// oracle: A
// source: tools/decimal_kernel_oracle.py, `finite` table: the expansion of n / d terminates iff the
//   reduced denominator d / gcd(n, d) has no prime factor but 2 and 5 (the definition, with
//   `math.gcd` of CPython; a zero numerator terminates); numerators that are and are not multiples
//   of the part of the denominator prime to 10, valuations of 2 and 5 below, at and above 9
// shares: the operands are drawn by `oracle_value` and built with `dec_coeff_multiply_repr`,
//   `dec_coeff_magnitude_add_unit` and `oracle_finite_power` (their text is in the digest)
test "decimal kernel oracle: finite expansion decision, 1 limb" {
  oracle_finite_class(1, 0x9E3779B97F4A7C15UL)
}

///|
// oracle: A
// source: tools/decimal_kernel_oracle.py, `finite` table (the definition with `math.gcd`)
// shares: the operands are drawn by `oracle_value` and built with `dec_coeff_multiply_repr`,
//   `dec_coeff_magnitude_add_unit` and `oracle_finite_power` (their text is in the digest)
test "decimal kernel oracle: finite expansion decision, 2 to 4 limbs" {
  oracle_finite_class(2, 0xD1B54A32D192ED03UL)
  oracle_finite_class(3, 0x2545F4914F6CDD1DUL)
  oracle_finite_class(4, 0x94D049BB133111EBUL)
}

///|
// oracle: A
// source: tools/decimal_kernel_oracle.py, `finite` table (the definition with `math.gcd`)
// shares: the operands are drawn by `oracle_value` and built with `dec_coeff_multiply_repr`,
//   `dec_coeff_magnitude_add_unit` and `oracle_finite_power` (their text is in the digest)
test "decimal kernel oracle: finite expansion decision, 6 to 12 limbs" {
  oracle_finite_class(6, 0xBF58476D1CE4E5B9UL)
  oracle_finite_class(12, 0x6A09E667F3BCC909UL)
}

///|
// oracle: A
// source: tools/decimal_kernel_oracle.py, `finite` table (the definition with `math.gcd`)
// shares: the operands are drawn by `oracle_value` and built with `dec_coeff_multiply_repr`,
//   `dec_coeff_magnitude_add_unit` and `oracle_finite_power` (their text is in the digest)
test "decimal kernel oracle: finite expansion decision, 24 and 56 limbs" {
  oracle_finite_class(24, 0xBB67AE8584CAA73BUL)
  oracle_finite_class(56, 0x3C6EF372FE94F82BUL)
}

///|
// oracle: A
// source: tools/decimal_kernel_oracle.py, `finite` table (the definition with `math.gcd`)
// shares: the operands are drawn by `oracle_value` and built with `dec_coeff_multiply_repr`,
//   `dec_coeff_magnitude_add_unit` and `oracle_finite_power` (their text is in the digest)
test "decimal kernel oracle: finite expansion decision, 120 limbs" {
  oracle_finite_class(120, 0xA54FF53A5F1D36F1UL)
}

///|
// oracle: A
// source: tools/decimal_kernel_oracle.py, `finite` table, row `finite-special`: the denominators
//   10^e, 2^e, 5^e, 10^e (as 2^e 5^e), 10^e + 1, 3 10^e and 7 10^e against the numerators 1, 7,
//   10^e, 21 10^e and 10^e + 1 for e in 0..79; the definition with `math.gcd` of CPython
// shares: the operands are built with `dec_coeff_power10_repr`, `oracle_finite_power`,
//   `dec_coeff_multiply_repr`, `dec_coeff_magnitude_add_unit` and `dec_coeff_multiply_by_unit_repr`
//   (their text is in the digest)
test "decimal kernel oracle: finite expansion decision, special denominators" {
  let digest = OracleDigest::new()
  for exponent in 0..<80 {
    let ten = dec_coeff_power10_repr(exponent)
    let two = oracle_finite_power(2, exponent)
    let five = oracle_finite_power(5, exponent)
    for
      denominator in [
        ten,
        two,
        five,
        dec_coeff_multiply_repr(two, five),
        dec_coeff_magnitude_add_unit(ten, 1),
        dec_coeff_multiply_by_unit_repr(ten, 3),
        dec_coeff_multiply_by_unit_repr(ten, 7),
      ] {
      for
        numerator in [
          dec_coeff_from_int(1),
          dec_coeff_from_int(7),
          ten,
          dec_coeff_multiply_by_unit_repr(ten, 21),
          dec_coeff_magnitude_add_unit(ten, 1),
        ] {
        oracle_finite_add(digest, numerator, denominator)
      }
    }
  }
  oracle_finish("finite-special", digest)
}
