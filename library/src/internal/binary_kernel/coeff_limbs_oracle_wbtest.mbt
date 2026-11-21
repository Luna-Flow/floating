///|
/// Oracle of the limb rows (`bin_limbs_mul_1`, `bin_limbs_addmul_1`,
/// `bin_limbs_submul_1`, `bin_limbs_product`, `bin_limbs_sqr_school`) and of the
/// window row (`bin_limbs_window_combine`): level A. The expected arrays are
/// computed by `tools/kernel_oracle.py` (CPython integers: the mathematical
/// statement of each row, restated in the header of its rows file, not the
/// loop of a portable row) and folded into digests; the whole array is hashed,
/// so a limb written outside the row, or a carry in the wrong place, changes
/// it. The rows are in `coeff_limbs_oracle_rows_wbtest.mbt` and
/// `coeff_window_oracle_rows_wbtest.mbt`; the operands are regenerated from the
/// seed of the row with `regression_value`.
///
/// The test calls the wrappers, which select the row implementation by
/// `bin_limbs_mode`: it covers the portable loops, the C rows and the assembly
/// rows when run in each state (`LUNA_FLOATING_PORTABLE=1`, `LUNA_FLOATING_LIMBS=c`,
/// the default on Apple arm64), as the binary gate does. Before this oracle the
/// C rows were compared with the portable rows (level C: a contract wrong in
/// both was invisible).

///|
fn limbs_oracle_array(
  random : RegressionRandom,
  count : Int32,
  shape : Int32,
) -> FixedArray[UInt64] {
  let number = regression_value(random, 64 * count, shape)
  let words = FixedArray::make(count, 0UL)
  for index in 0..<count {
    words[index] = bin_coeff_word(number, index)
  }
  words
}

///|
fn limbs_oracle_word(random : RegressionRandom, bkind : Int32) -> UInt64 {
  match bkind {
    0 => bin_coeff_word(regression_value(random, 64, 0), 0)
    1 => 0xffff_ffff_ffff_ffffUL
    2 => 1UL
    3 => 0x8000_0000_0000_0000UL
    4 => 0UL
    5 => bin_coeff_word(regression_value(random, 64, 5), 0)
    _ => 0x1_0000_0001UL
  }
}

///|
fn limbs_oracle_digest(
  words : FixedArray[UInt64],
  extra : UInt64,
  with_extra : Bool,
) -> UInt64 {
  let copy = FixedArray::makei(words.length(), fn(index) { words[index] })
  let mut state = regression_mix(
    0xcbf29ce484222325UL,
    bin_coeff_from_words(copy, copy.length()),
  )
  if with_extra {
    state = regression_mix(state, Coeff::from_uint64(extra))
  }
  state
}

///|
fn limbs_oracle_run(row : Array[String]) -> Unit raise {
  let name = row[0]
  let kind = row[1]
  let seed = oracle_u64(row[9])
  let expected = oracle_u64(row[10])
  let random : RegressionRandom = { regression_state: seed, }
  let a1 = oracle_int(row[2])
  let a2 = oracle_int(row[3])
  let a3 = oracle_int(row[4])
  let a4 = oracle_int(row[5])
  let a5 = oracle_int(row[6])
  let a6 = oracle_int(row[7])
  let actual = if kind == "mul1" || kind == "addmul1" || kind == "submul1" {
    // n ro ao shape_r shape_a bkind
    let r = limbs_oracle_array(random, a2 + a1 + 2, a4)
    let a = limbs_oracle_array(random, a3 + a1 + 2, a5)
    let b = limbs_oracle_word(random, a6)
    let carry = if kind == "mul1" {
      bin_limbs_mul_1(r, a2, a, a3, a1, b)
    } else if kind == "addmul1" {
      bin_limbs_addmul_1(r, a2, a, a3, a1, b)
    } else {
      bin_limbs_submul_1(r, a2, a, a3, a1, b)
    }
    limbs_oracle_digest(r, carry, true)
  } else if kind == "product" {
    // an bn ro ao bo shape_a shape_b
    let an = a1
    let bn = a2
    let ro = a3
    let ao = a4
    let bo = a5
    let r = limbs_oracle_array(random, ro + an + bn + 2, 0)
    let a = limbs_oracle_array(random, ao + an + 2, a6)
    let b = limbs_oracle_array(random, bo + bn + 2, oracle_int(row[8]))
    bin_limbs_product(r, ro, a, ao, an, b, bo, bn)
    limbs_oracle_digest(r, 0UL, false)
  } else {
    // square: n ro so shape_s
    let n = a1
    let r = limbs_oracle_array(random, a2 + 2 * n + 2, 0)
    let s = limbs_oracle_array(random, a3 + n + 2, a4)
    bin_limbs_sqr_school(r, a2, s, a3, n)
    limbs_oracle_digest(r, 0UL, false)
  }
  if actual != expected {
    fail("\{name}: the limb row differs from the oracle")
  }
}

///|
test "oracle: limb rows equal the mathematical statement of each row" {
  let rows = oracle_rows(limbs_oracle_table)
  for row in rows {
    limbs_oracle_run(row)
  }
  assert_true(rows.length() > 700)
}

///|
fn window_oracle_run(row : Array[String]) -> Unit raise {
  let name = row[0]
  let count = oracle_int(row[1])
  let x_len = oracle_int(row[2])
  let y_len = oracle_int(row[5])
  let seed = oracle_u64(row[12])
  let random : RegressionRandom = { regression_state: seed, }
  let x = limbs_oracle_array(random, x_len, oracle_int(row[10]))
  let y = if y_len == 0 {
    FixedArray::make(1, 0UL)
  } else {
    limbs_oracle_array(random, y_len, oracle_int(row[11]))
  }
  let words = FixedArray::make(count, 0UL)
  let carry = bin_limbs_window_combine(
    words,
    count,
    x,
    x_len,
    oracle_signed(row[3]),
    oracle_int(row[4]),
    y,
    y_len,
    oracle_signed(row[6]),
    oracle_int(row[7]),
    row[8] == "1",
    oracle_u64(row[9]),
  )
  if limbs_oracle_digest(words, carry, true) != oracle_u64(row[13]) {
    fail("\{name}: the window row differs from the oracle")
  }
}

///|
test "oracle: window rows equal x + (y xor mask) + carry on the shifted windows" {
  let rows = oracle_rows(window_oracle_table)
  for row in rows {
    window_oracle_run(row)
  }
  assert_true(rows.length() > 500)
}
