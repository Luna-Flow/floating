///|
/// Tests of the C and assembly row primitives of `luna_limbs.c`, called
/// directly (so they do not depend on the `LUNA_FLOATING_PORTABLE` switch), and
/// of the wrappers. Native only. The expected value of every row is the
/// statement of the row in core `BigInt` arithmetic (`bin_limbs_check_row`,
/// `bin_limbs_check_product`, `bin_limbs_check_square`): the portable loops are
/// no longer the reference, so a contract wrong in the C row and in the portable
/// row alike is seen here.

///|
fn bin_limbs_pattern(count : Int32, seed : UInt64) -> FixedArray[UInt64] {
  let edge = [
    0UL, 1UL, 2UL, 0xffff_ffffUL, 0x1_0000_0000UL, 0x7fff_ffff_ffff_ffffUL, 0x8000_0000_0000_0000UL,
    0xffff_ffff_0000_0000UL, 0xffff_ffff_ffff_fffeUL, 0xffff_ffff_ffff_ffffUL,
  ]
  let mut state = seed
  FixedArray::makei(count, _ => {
    state = state * 6364136223846793005UL + 1442695040888963407UL
    let mixed = state ^ (state >> 29)
    if (mixed & 3UL) == 0UL {
      edge[((mixed >> 8).to_int() & 0x7fff_ffff) % edge.length()]
    } else {
      mixed
    }
  })
}

///|
fn bin_limbs_copy(source : FixedArray[UInt64]) -> FixedArray[UInt64] {
  FixedArray::makei(source.length(), index => source[index])
}

///|
fn bin_limbs_tier_name() -> String {
  match bin_limbs_mode {
    0 => "portable"
    1 => "c"
    _ => "asm"
  }
}

///|
test "the assembly tier is active on Apple arm64 unless an override is set" {
  if luna_limbs_expects_asm() == 1 && luna_limbs_override_set() == 0 {
    // a silent fallback to the C rows must fail here, not skip
    assert_eq(bin_limbs_tier_name(), "asm")
    assert_eq(luna_limbs_tier(), 1)
  }
}

///|
// oracle: S
// source: no expected value: the block prints the build facts of the limb tier (compiler, architecture, tier) for the log and asserts nothing
// shares: nothing
test "the log names the compiler and the product branch of the stub" {
  println(
    "luna_limbs: cc_id=\{luna_limbs_cc_id()} (1 clang, 2 gcc, 3 msvc, 4 tcc) arch_id=\{luna_limbs_arch_id()} (1 x86-64, 2 arm64) int128=\{luna_limbs_has_int128()} cpu_features=\{luna_limbs_cpu_features()} (bit 0 BMI2, bit 1 ADX) tier=\{bin_limbs_tier_name()} (mode \{bin_limbs_mode}) asm_compiled_in=\{luna_limbs_tier()} override=\{luna_limbs_override_set()}",
  )
}

///|
/// Which implementation a check calls: 0 the C rows, 1 the assembly rows, 2 the
/// wrappers of `coeff_limbs_native.mbt`.
fn bin_limbs_call_row(
  entry : Int32,
  kind : Int32,
  r : FixedArray[UInt64],
  ro : Int32,
  a : FixedArray[UInt64],
  ao : Int32,
  n : Int32,
  b : UInt64,
) -> UInt64 {
  match (entry, kind) {
    (0, 0) => luna_mul_1(r, ro, a, ao, n, b)
    (0, 1) => luna_addmul_1(r, ro, a, ao, n, b)
    (0, _) => luna_submul_1(r, ro, a, ao, n, b)
    (1, 0) => luna_mul_1_asm(r, ro, a, ao, n, b)
    (1, 1) => luna_addmul_1_asm(r, ro, a, ao, n, b)
    (1, _) => luna_submul_1_asm(r, ro, a, ao, n, b)
    (_, 0) => bin_limbs_mul_1(r, ro, a, ao, n, b)
    (_, 1) => bin_limbs_addmul_1(r, ro, a, ao, n, b)
    (_, _) => bin_limbs_submul_1(r, ro, a, ao, n, b)
  }
}

///|
/// The limbs of `r` outside `[lo, lo + count)` are those of `before`.
fn bin_limbs_check_outside(
  before : FixedArray[UInt64],
  r : FixedArray[UInt64],
  lo : Int32,
  count : Int32,
) -> Unit raise {
  for index in 0..<r.length() {
    if index < lo || index >= lo + count {
      assert_eq(r[index], before[index])
    }
  }
}

///|
/// One row `kind` (0 mul_1, 1 addmul_1, 2 submul_1) through `entry`: with
/// `T = a b` (mul_1), `r + a b` (addmul_1) or `r - a b` (submul_1) over the
/// integers of the row, the row left in `r` and the carry limb satisfy
/// `r_new + carry 2^(64 n) = T` for the first two and
/// `r_new = T + carry 2^(64 n)` for submul_1 (the carry limb and the borrow
/// folded together, as `bin_limbs_submul_1_portable` documents), and the limbs
/// outside the row do not change. `a` may be `r` itself (same range or not).
fn bin_limbs_check_row(
  entry : Int32,
  kind : Int32,
  r : FixedArray[UInt64],
  ro : Int32,
  a : FixedArray[UInt64],
  ao : Int32,
  n : Int32,
  b : UInt64,
) -> Unit raise {
  let before = bin_limbs_copy(r)
  let a_before = bin_limbs_copy(a)
  let modulus = BigInt::from_int(1) << (64 * n)
  let product = bin_limbs_big(a_before, ao, n) * BigInt::from_uint64(b)
  let old_row = bin_limbs_big(before, ro, n)
  let total = match kind {
    0 => product
    1 => old_row + product
    _ => old_row - product
  }
  let carry = bin_limbs_call_row(entry, kind, r, ro, a, ao, n, b)
  let new_row = bin_limbs_big(r, ro, n)
  let carry_part = BigInt::from_uint64(carry) * modulus
  if kind == 2 {
    assert_eq(new_row, total + carry_part)
  } else {
    assert_eq(new_row + carry_part, total)
  }
  bin_limbs_check_outside(before, r, ro, n)
}

///|
/// `r[ro ..< ro + an + bn] = a b` through `entry` (0 C, 1 assembly, 2 wrapper),
/// all `an + bn` limbs written, the others unchanged.
fn bin_limbs_check_product(
  entry : Int32,
  r : FixedArray[UInt64],
  ro : Int32,
  a : FixedArray[UInt64],
  ao : Int32,
  an : Int32,
  b : FixedArray[UInt64],
  bo : Int32,
  bn : Int32,
) -> Unit raise {
  let before = bin_limbs_copy(r)
  let expected = bin_limbs_big(a, ao, an) * bin_limbs_big(b, bo, bn)
  match entry {
    0 => luna_school(r, ro, a, ao, an, b, bo, bn)
    1 => luna_school_asm(r, ro, a, ao, an, b, bo, bn)
    _ => bin_limbs_school(r, ro, a, ao, an, b, bo, bn)
  }
  assert_eq(bin_limbs_big(r, ro, an + bn), expected)
  bin_limbs_check_outside(before, r, ro, an + bn)
}

///|
/// `r[ro ..< ro + 2 len] = s^2` through `entry`, the others unchanged.
fn bin_limbs_check_square(
  entry : Int32,
  r : FixedArray[UInt64],
  ro : Int32,
  s : FixedArray[UInt64],
  so : Int32,
  len : Int32,
) -> Unit raise {
  let before = bin_limbs_copy(r)
  let value = bin_limbs_big(s, so, len)
  match entry {
    0 => luna_sqr_school(r, ro, s, so, len)
    1 => luna_sqr_school_asm(r, ro, s, so, len)
    _ => bin_limbs_sqr_school(r, ro, s, so, len)
  }
  assert_eq(bin_limbs_big(r, ro, 2 * len), value * value)
  bin_limbs_check_outside(before, r, ro, 2 * len)
}

///|
fn bin_limbs_rows_scan(entry : Int32) -> Unit raise {
  let mut cases = 0
  for n in 0..<=200 {
    for round in 0..<6 {
      let seed = (n * 7 + round).to_uint64() + 1UL
      let a = bin_limbs_pattern(n + 3, seed)
      let base = bin_limbs_pattern(n + 3, seed * 31UL)
      let b = bin_limbs_pattern(1, seed * 131UL)[0]
      for factor in [b, 0UL, 1UL, 0xffff_ffff_ffff_ffffUL] {
        bin_limbs_check_row(entry, 0, bin_limbs_copy(base), 1, a, 2, n, factor)
        bin_limbs_check_row(entry, 1, bin_limbs_copy(base), 2, a, 1, n, factor)
        bin_limbs_check_row(entry, 2, bin_limbs_copy(base), 0, a, 0, n, factor)
        cases += 1
      }
    }
  }
  assert_eq(cases, 201 * 6 * 4)
}

///|
fn bin_limbs_rows_max_carry(entry : Int32) -> Unit raise {
  for n in 1..<=70 {
    let ones = FixedArray::make(n + 1, 0xffff_ffff_ffff_ffffUL)
    for position in 0..<n {
      for filler in [0UL, 0xffff_ffff_ffff_ffffUL] {
        let r = FixedArray::make(n + 1, filler)
        r[position] = 1UL - filler
        for factor in [0xffff_ffff_ffff_ffffUL, 1UL, 0x8000_0000_0000_0000UL] {
          bin_limbs_check_row(entry, 1, r, 0, ones, 0, n, factor)
          bin_limbs_check_row(entry, 2, r, 0, ones, 0, n, factor)
        }
      }
    }
  }
}

///|
fn bin_limbs_rows_aliased(entry : Int32) -> Unit raise {
  for n in 1..<=100 {
    let base = bin_limbs_pattern(n + 1, n.to_uint64() + 99UL)
    for factor in [0xffff_ffff_ffff_ffffUL, 3UL, 0UL] {
      let x = bin_limbs_copy(base)
      bin_limbs_check_row(entry, 1, x, 0, x, 0, n, factor)
      bin_limbs_check_row(entry, 2, x, 0, x, 0, n, factor)
      // the same array at different, disjoint ranges
      let y = bin_limbs_pattern(2 * n + 2, n.to_uint64() + 5UL)
      bin_limbs_check_row(entry, 1, y, n + 1, y, 0, n, factor)
    }
  }
}

///|
fn bin_limbs_rows_products(entry : Int32) -> Unit raise {
  let lengths = [1, 2, 3, 7, 8, 9, 15, 16, 17, 31, 32, 33, 64, 100]
  let mut cases = 0
  for an in lengths {
    for bn in lengths {
      for round in 0..<3 {
        let seed = (an * 1000 + bn * 10 + round).to_uint64()
        let a = bin_limbs_pattern(an + 4, seed + 1UL)
        let b = bin_limbs_pattern(bn + 4, seed + 2UL)
        let r = bin_limbs_pattern(an + bn + 5, seed + 3UL)
        bin_limbs_check_product(entry, r, 2, a, 3, an, b, 1, bn)
        cases += 1
      }
    }
  }
  for len in 1..<=130 {
    for round in 0..<3 {
      let s = bin_limbs_pattern(
        len + 2,
        len.to_uint64() * 17UL + round.to_uint64(),
      )
      let r = bin_limbs_pattern(2 * len + 3, 5UL + round.to_uint64())
      bin_limbs_check_square(entry, r, 1, s, 2, len)
      cases += 1
    }
  }
  assert_eq(cases, 14 * 14 * 3 + 130 * 3)
  // all-ones operands: every column carries
  for len in 1..<=70 {
    let ones = FixedArray::make(len, 0xffff_ffff_ffff_ffffUL)
    bin_limbs_check_product(
      entry,
      FixedArray::make(2 * len, 7UL),
      0,
      ones,
      0,
      len,
      ones,
      0,
      len,
    )
    bin_limbs_check_square(
      entry,
      FixedArray::make(2 * len, 7UL),
      0,
      ones,
      0,
      len,
    )
  }
}

///|
fn bin_limbs_rows_offsets(entry : Int32) -> Unit raise {
  for n in 0..<=70 {
    for ro in 0..<4 {
      for ao in 0..<4 {
        let a = bin_limbs_pattern(
          n + 8,
          (n * 16 + ro * 4 + ao).to_uint64() + 1UL,
        )
        let base = bin_limbs_pattern(
          n + 8,
          (n * 16 + ro * 4 + ao).to_uint64() * 7UL + 3UL,
        )
        for b in [0xffff_ffff_ffff_ffffUL, 0x8000_0000_0000_0001UL, 1UL, 0UL] {
          let r = bin_limbs_copy(base)
          bin_limbs_check_row(entry, 0, r, ro, a, ao, n, b)
          bin_limbs_check_row(entry, 1, r, ro, a, ao, n, b)
          bin_limbs_check_row(entry, 2, r, ro, a, ao, n, b)
        }
      }
    }
  }
}

///|
fn bin_limbs_rows_ripple(entry : Int32) -> Unit raise {
  for n in 1..<=200 {
    let ones = FixedArray::make(n + 1, 0xffff_ffff_ffff_ffffUL)
    for fill in [0xffff_ffff_ffff_ffffUL, 0UL, 1UL] {
      let r = FixedArray::make(n + 1, fill)
      for b in [0xffff_ffff_ffff_ffffUL, 1UL, 2UL] {
        bin_limbs_check_row(entry, 1, r, 0, ones, 0, n, b)
        bin_limbs_check_row(entry, 2, r, 0, ones, 0, n, b)
      }
    }
  }
}

///|
// oracle: B
// source: core BigInt arithmetic (a separate implementation) on the integers of the rows: a b, r + a b and r - a b over the limbs of the row, the carry limb from the equation r_new + carry 2^(64 n) = total, the limbs outside the row unchanged; replaces the comparison with the portable rows (level C: the portable rows are the contract the C rows were written from)
// shares: bin_limbs_pattern (the operands only, never the expected value) and bin_limbs_big (the results are read through it, limb by limb)
// primitives: bin_limbs_big (limbs to BigInt by shift and addition of core; level A in "bin_limbs_big reads the limbs least significant first"); the portable rows are not used
test "mul_1, addmul_1 and submul_1 in C equal the portable rows" {
  bin_limbs_rows_scan(0)
}

///|
// oracle: B
// source: core BigInt arithmetic on the integers of the rows (see "mul_1, addmul_1 and submul_1 in C equal the portable rows"), r and a every limb 2^64 - 1 or 0/1 with the carry at every position
// shares: bin_limbs_copy (the snapshot of the arrays before the call) and bin_limbs_big (the results are read through it, limb by limb)
// primitives: bin_limbs_big (level A in "bin_limbs_big reads the limbs least significant first")
test "rows with the maximum carry at every position" {
  bin_limbs_rows_max_carry(0)
}

///|
// oracle: B
// source: core BigInt arithmetic on the integers of the rows, the row read before the call from a snapshot of the array (r and a the same range, or different ranges of one array)
// shares: bin_limbs_pattern (the operands only) and bin_limbs_copy (the snapshot of the arrays before the call) and bin_limbs_big (the results are read through it, limb by limb)
// primitives: bin_limbs_big (level A in "bin_limbs_big reads the limbs least significant first")
test "rows with r and a the same range of one array" {
  bin_limbs_rows_aliased(0)
}

///|
// oracle: B
// source: core BigInt arithmetic: the product of the two integers of the operand limbs for school, the square for sqr_school, all limbs of the result row written, the others unchanged; the all-ones operands are the extreme columns
// shares: bin_limbs_pattern (the operands only) and bin_limbs_copy (the snapshot of the arrays before the call) and bin_limbs_big (the results are read through it, limb by limb)
// primitives: bin_limbs_big (level A in "bin_limbs_big reads the limbs least significant first")
test "school and square in C equal the portable products" {
  bin_limbs_rows_products(0)
}

///|
// oracle: B
// source: core BigInt arithmetic on the integers of the rows (see "mul_1, addmul_1 and submul_1 in C equal the portable rows"), assembly entry
// shares: bin_limbs_pattern (the operands only) and bin_limbs_copy (the snapshot of the arrays before the call) and bin_limbs_big (the results are read through it, limb by limb)
// primitives: bin_limbs_big (level A in "bin_limbs_big reads the limbs least significant first")
test "mul_1, addmul_1 and submul_1 in assembly equal the portable rows (assembly entry)" {
  bin_limbs_rows_scan(1)
}

///|
// oracle: B
// source: core BigInt arithmetic on the integers of the rows, carry at every position, assembly entry
// shares: bin_limbs_copy (the snapshot of the arrays before the call) and bin_limbs_big (the results are read through it, limb by limb)
// primitives: bin_limbs_big (level A in "bin_limbs_big reads the limbs least significant first")
test "rows with the maximum carry at every position (assembly entry)" {
  bin_limbs_rows_max_carry(1)
}

///|
// oracle: B
// source: core BigInt arithmetic on the integers of the rows, r and a one array, assembly entry
// shares: bin_limbs_pattern (the operands only) and bin_limbs_copy (the snapshot of the arrays before the call) and bin_limbs_big (the results are read through it, limb by limb)
// primitives: bin_limbs_big (level A in "bin_limbs_big reads the limbs least significant first")
test "rows with r and a the same range of one array (assembly entry)" {
  bin_limbs_rows_aliased(1)
}

///|
// oracle: B
// source: core BigInt arithmetic: product and square of the integers of the operand limbs, assembly entry
// shares: bin_limbs_pattern (the operands only) and bin_limbs_copy (the snapshot of the arrays before the call) and bin_limbs_big (the results are read through it, limb by limb)
// primitives: bin_limbs_big (level A in "bin_limbs_big reads the limbs least significant first")
test "school and square in assembly equal the portable products (assembly entry)" {
  bin_limbs_rows_products(1)
}

///|
// oracle: B
// source: core BigInt arithmetic on the integers of the rows at the offsets 0 to 3 of r and of a and lengths 0 to 70, assembly entry
// shares: bin_limbs_pattern (the operands only) and bin_limbs_copy (the snapshot of the arrays before the call) and bin_limbs_big (the results are read through it, limb by limb)
// primitives: bin_limbs_big (level A in "bin_limbs_big reads the limbs least significant first")
test "assembly rows equal the portable rows for every offset and length" {
  bin_limbs_rows_offsets(1)
}

///|
// oracle: B
// source: core BigInt arithmetic on the integers of the rows, all-ones operand rows of 1 to 200 limbs (the carry runs the whole row), assembly entry
// shares: bin_limbs_copy (the snapshot of the arrays before the call) and bin_limbs_big (the results are read through it, limb by limb)
// primitives: bin_limbs_big (level A in "bin_limbs_big reads the limbs least significant first")
test "assembly rows with all-ones operands and a carry rippling the whole row" {
  bin_limbs_rows_ripple(1)
}

///|
// oracle: B
// source: core BigInt arithmetic: the product of the integers of the operand limbs (lengths 1 to 120, offsets 3, 1 and 4), through the wrapper `bin_limbs_school` in the state of the limb tier the test runs in
// shares: bin_limbs_pattern (the operands only) and bin_limbs_copy (the snapshot of the arrays before the call) and bin_limbs_big (the results are read through it, limb by limb)
// primitives: bin_limbs_big (level A in "bin_limbs_big reads the limbs least significant first")
test "the wrappers equal the portable rows on random lengths and offsets" {
  for n in 1..<=120 {
    let a = bin_limbs_pattern(n + 5, n.to_uint64() * 3UL)
    let b = bin_limbs_pattern(n + 5, n.to_uint64() * 5UL)
    let r = bin_limbs_pattern(2 * n + 6, n.to_uint64())
    bin_limbs_check_product(2, r, 3, a, 1, n, b, 4, n)
  }
}
