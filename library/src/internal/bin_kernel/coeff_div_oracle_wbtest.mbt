///|
/// Oracle of the division routes of `Coeff`: level A. The expected value of a row
/// is computed by `tools/kernel_oracle.py` (CPython integers: `divmod`, `<<`; no
/// library of this repository) and folded into the FNV-1a digest of the quotient
/// and the remainder (the packed `2 q + s` for the scaled quotient; the three
/// roundings of the exact quotient for the short quotient). The operands are
/// built from the row: `regression_value` bases and limb terms `+-HEX@k` and
/// `+-D@k` (the divisor times `2^(64 k)`), the grammar is in the header of
/// `coeff_div_oracle_rows_wbtest.mbt`. The rows put the quotient and the remainder
/// on the edges of the correction steps of Knuth's algorithm D (a remainder of
/// zero and of divisor minus one, quotients `B^k`, `B^k - 1`, `B^k - 2`, divisors
/// with a top limb of all ones and of `2^63`, a window whose top limb equals the
/// divisor's, and dividends `Q (d1, d0) B^(n-2)` for which the estimate is one
/// too large and the add-back runs: the generator checks with a port of the
/// algorithm that each of the latter reaches the add-back; that the kernel's
/// own correction code is reached is shown by the mutations of the pull
/// request, not checked here).
///
/// Routes, and how it is known that a row takes one:
///
/// - `div`: `Coeff::div_rem_checked`. A divisor of one limb below 2^32 takes the
///   half-limb loop, otherwise below `bin_coeff_bz_division_min_words` (752, 352,
///   208 limbs on the assembly rows, the C rows, the portable loops:
///   `coeff_thresholds_native.mbt`) Knuth's division, from there Burnikel-Ziegler
///   (`coeff_nonjs.mbt`, `Coeff::div_rem_checked`); Newton starts at 2^29 limbs
///   and no row reaches it. The rows run in every state of the limb tier, whose
///   threshold differs, so each state has rows on both sides of its own; the
///   gate test counts them with the active threshold.
/// - `knuth`, `bz`: `bin_coeff_div_rem_knuth_words` and
///   `bin_coeff_div_rem_burnikel_ziegler` called directly on the same operands,
///   at every size, so that both are checked against CPython also where the
///   dispatch does not select them (the leaf of the recursion is 64 limbs,
///   `bin_coeff_bz_leaf_words`; the sizes include one limb either side of
///   it and of the padding boundaries `j 2^k`).
/// - `short`: `bin_coeff_short_div_rem`: a quotient of up to 17 bits over a
///   divisor of more than 96 bits is found by bisection on the high product
///   (`bin_coeff_short_div_high_product`), the rest by the long division.
/// - `scaled`: `bin_coeff_div_scaled_quotient`, a divisor of 2 to 95 limbs.
/// - `shortq`: `bin_coeff_div_short_quotient`, a divisor of 2 to 256 limbs: it
///   returns an approximation that must round as the exact quotient does in
///   the three ways (nearest even, down, up; the rounding of the returned
///   value is written out here with `Coeff` shifts and bit tests), or declines;
///   it must not decline when the exact quotient is farther than
///   `2 (2 n + 8)` units of the last limb from every rounding boundary
///   (`must`, the oracle's own bound).

///|
fn oracle_hex_u64(text : String) -> UInt64 {
  let mut result = 0UL
  for char in text {
    let digit = if char >= '0' && char <= '9' {
      char.to_int() - 48
    } else {
      char.to_int() - 55
    }
    result = result * 16UL + digit.to_uint64()
  }
  result
}

///|
fn oracle_split(text : String, separator : Char) -> Array[String] {
  let parts : Array[String] = []
  let mut start = 0
  let mut index = 0
  let length = text.length()
  while index < length {
    if text[index].to_int() == separator.to_int() {
      parts.push(text[start:index].to_owned())
      start = index + 1
    }
    index += 1
  }
  parts.push(text[start:length].to_owned())
  parts
}

///|
/// An operand of a division row: `BASE` or `BASE:TERM,TERM`.
fn div_oracle_operand(
  spec : String,
  divisor : Coeff,
  random : RegressionRandom,
) -> Coeff raise {
  let halves = oracle_split(spec, ':')
  let base = halves[0]
  let mut total = Coeff::zero()
  if base != "0" {
    let parts = oracle_split(base, '.')
    total = regression_value(random, oracle_int(parts[0]), oracle_int(parts[1]))
  }
  if halves.length() > 1 {
    for term in oracle_split(halves[1], ',') {
      let negative = term[0] == '-'
      let pair = oracle_split(term[1:].to_owned(), '@')
      let factor = if pair[0] == "D" {
        divisor
      } else {
        Coeff::from_uint64(oracle_hex_u64(pair[0]))
      }
      let shifted = factor.shift_left(64 * oracle_int(pair[1]))
      if negative {
        match total.sub_checked(shifted) {
          Ok(smaller) => total = smaller
          Err(_) => fail("a negative partial sum in \{spec}")
        }
      } else {
        total = total.add(shifted)
      }
    }
  }
  total
}

///|
fn div_oracle_strip(value : Coeff, exponent : Int32) -> (Coeff, Int32) {
  let zeros = value.ctz()
  (value.shift_right(zeros), exponent + zeros)
}

///|
fn div_oracle_pair_digest(quotient : Coeff, remainder : Coeff) -> UInt64 {
  regression_mix(regression_mix(0xcbf29ce484222325UL, quotient), remainder)
}

///|
/// Runs one row; the result says whether the route returned a value (only
/// `shortq` may decline).
fn div_oracle_run(row : Array[String]) -> Bool raise {
  let name = row[0]
  let route = row[1]
  let random : RegressionRandom = { regression_state: oracle_u64(row[4]), }
  let divisor = div_oracle_operand(row[2], Coeff::zero(), random)
  let dividend = div_oracle_operand(row[3], divisor, random)
  let scale = oracle_int(row[6])
  let precision = oracle_int(row[7])
  let expected = oracle_u64(row[9])
  match route {
    "scaled" => {
      assert_true(bin_coeff_div_scaled_ok(dividend, scale, divisor))
      let packed = bin_coeff_div_scaled_quotient(dividend, scale, divisor)
      if regression_mix(0xcbf29ce484222325UL, packed) != expected {
        fail("\{name}: the packed scaled quotient differs from CPython")
      }
      true
    }
    "shortq" => {
      assert_true(bin_coeff_div_short_ok(dividend, scale, divisor))
      let approximate = bin_coeff_div_short_quotient(
        dividend, scale, divisor, precision,
      )
      if approximate.is_zero() {
        if row[8] == "1" {
          fail(
            "\{name}: the short quotient declined far from every rounding boundary",
          )
        }
        return false
      }
      let shift = approximate.bit_length() - precision
      let kept = approximate.shift_right(shift)
      let nearest = if approximate.test_bit(shift - 1) {
        kept.add(Coeff::one())
      } else {
        kept
      }
      let up = kept.add(Coeff::one())
      let mut state = 0xcbf29ce484222325UL
      for rounded in [nearest, kept, up] {
        let (stripped, exponent) = div_oracle_strip(rounded, shift)
        state = regression_mix_int(regression_mix(state, stripped), exponent)
      }
      if state != expected {
        fail(
          "\{name}: the short quotient rounds differently from the exact quotient",
        )
      }
      true
    }
    _ => {
      let (quotient, remainder) = match route {
        "div" => dividend.div_rem_checked(divisor).unwrap()
        "knuth" => bin_coeff_div_rem_knuth_words(dividend, divisor)
        "bz" => bin_coeff_div_rem_burnikel_ziegler(dividend, divisor)
        "short" => bin_coeff_short_div_rem(dividend, divisor)
        _ => fail("\{name}: unknown route \{route}")
      }
      if div_oracle_pair_digest(quotient, remainder) != expected {
        fail(
          "\{name}: quotient and remainder differ from CPython (route \{route})",
        )
      }
      true
    }
  }
}

///|
/// Runs the rows of one `where`; returns the row counts by route, and for `div`
/// the rows whose divisor is below and at or above the active threshold of the
/// recursive division.
fn div_oracle_run_where(where_ : String) -> Array[Int32] raise {
  // total, returned, div rows below the threshold, div rows at or above it,
  // knuth rows, bz rows, short rows, scaled rows, shortq rows
  let counts = [0, 0, 0, 0, 0, 0, 0, 0, 0]
  for row in oracle_rows(div_oracle_table) {
    if row[5] != where_ {
      continue
    }
    counts[0] += 1
    if div_oracle_run(row) {
      counts[1] += 1
    }
    match row[1] {
      "div" => {
        let random : RegressionRandom = {
          regression_state: oracle_u64(row[4]),
        }
        let divisor = div_oracle_operand(row[2], Coeff::zero(), random)
        if bin_coeff_word_len(divisor) >= bin_coeff_bz_division_min_words {
          counts[3] += 1
        } else {
          counts[2] += 1
        }
      }
      "knuth" => counts[4] += 1
      "bz" => counts[5] += 1
      "short" => counts[6] += 1
      "scaled" => counts[7] += 1
      _ => counts[8] += 1
    }
  }
  counts
}

///|
// oracle: A
// source: quotient, remainder, packed quotient and roundings computed by tools/kernel_oracle.py with CPython integers (divmod), rows in coeff_div_oracle_rows_wbtest.mbt
// shares: nothing (the kernel's own multiplication is not used to build the operands: shifts, additions and subtractions of regression_value operands, which have the level A digests of coeff_regression_wbtest.mbt)
test "oracle: division routes against CPython, divisors up to 130 limbs" {
  let counts = div_oracle_run_where("pr")
  assert_true(counts[0] > 1000)
  assert_true(counts[4] > 100 && counts[5] > 100)
  assert_true(counts[6] > 100 && counts[7] > 100 && counts[8] > 100)
  // the short quotient must return on most rows far from a boundary
  assert_true(counts[1] > counts[0] * 9 / 10)
}

///|
// oracle: A
// source: quotient, remainder and roundings computed by tools/kernel_oracle.py with CPython integers (divmod), rows in coeff_div_oracle_rows_wbtest.mbt
// shares: nothing (operands are shifts, additions and subtractions of regression_value operands)
#skip("binary gate stage: divisors of 192 to 1,025 limbs, both sides of the Burnikel-Ziegler threshold of each state of the limb tier")
test "oracle: division routes against CPython, divisors from 192 to 1,025 limbs" {
  let counts = div_oracle_run_where("gate")
  // rows on both sides of the active threshold of the recursive division
  assert_true(counts[2] > 20 && counts[3] > 20)
  assert_true(counts[4] > 20 && counts[5] > 20)
}
