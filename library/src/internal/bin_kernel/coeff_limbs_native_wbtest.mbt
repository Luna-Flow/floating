///|
/// Differential tests of the C row primitives of `luna_limbs.c` against the
/// portable loops (`coeff_limbs_portable_nonjs.mbt`, `coeff_words_nonjs.mbt`).
/// Native only. The C functions are called directly, so the tests do not depend
/// on the `LUNA_FLOATING_PORTABLE` switch.

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
test "the log names the compiler and the product branch of the stub" {
  println(
    "luna_limbs: cc_id=\{luna_limbs_cc_id()} (1 clang, 2 gcc, 3 msvc, 4 tcc) arch_id=\{luna_limbs_arch_id()} (1 x86-64, 2 arm64) int128=\{luna_limbs_has_int128()} cpu_features=\{luna_limbs_cpu_features()} (bit 0 BMI2, bit 1 ADX) enabled=\{bin_limbs_native}",
  )
}

///|
test "mul_1, addmul_1 and submul_1 in C equal the portable rows" {
  let mut cases = 0
  for n in 0..<=200 {
    for round in 0..<6 {
      let seed = (n * 7 + round).to_uint64() + 1UL
      let a = bin_limbs_pattern(n + 3, seed)
      let base = bin_limbs_pattern(n + 3, seed * 31UL)
      let b = bin_limbs_pattern(1, seed * 131UL)[0]
      for factor in [b, 0UL, 1UL, 0xffff_ffff_ffff_ffffUL] {
        let r1 = bin_limbs_copy(base)
        let r2 = bin_limbs_copy(base)
        assert_eq(
          luna_mul_1(r1, 1, a, 2, n, factor),
          bin_limbs_mul_1_portable(r2, 1, a, 2, n, factor),
        )
        assert_eq(r1, r2)
        let r3 = bin_limbs_copy(base)
        let r4 = bin_limbs_copy(base)
        assert_eq(
          luna_addmul_1(r3, 2, a, 1, n, factor),
          bin_limbs_addmul_1_portable(r4, 2, a, 1, n, factor),
        )
        assert_eq(r3, r4)
        let r5 = bin_limbs_copy(base)
        let r6 = bin_limbs_copy(base)
        assert_eq(
          luna_submul_1(r5, 0, a, 0, n, factor),
          bin_limbs_submul_1_portable(r6, 0, a, 0, n, factor),
        )
        assert_eq(r5, r6)
        cases += 1
      }
    }
  }
  assert_eq(cases, 201 * 6 * 4)
}

///|
test "rows with the maximum carry at every position" {
  for n in 1..<=70 {
    let ones = FixedArray::make(n + 1, 0xffff_ffff_ffff_ffffUL)
    for position in 0..<n {
      for filler in [0UL, 0xffff_ffff_ffff_ffffUL] {
        let r1 = FixedArray::make(n + 1, filler)
        r1[position] = 1UL - filler
        let r2 = bin_limbs_copy(r1)
        for factor in [0xffff_ffff_ffff_ffffUL, 1UL, 0x8000_0000_0000_0000UL] {
          assert_eq(
            luna_addmul_1(r1, 0, ones, 0, n, factor),
            bin_limbs_addmul_1_portable(r2, 0, ones, 0, n, factor),
          )
          assert_eq(r1, r2)
          assert_eq(
            luna_submul_1(r1, 0, ones, 0, n, factor),
            bin_limbs_submul_1_portable(r2, 0, ones, 0, n, factor),
          )
          assert_eq(r1, r2)
        }
      }
    }
  }
}

///|
test "rows with r and a the same range of one array" {
  for n in 1..<=100 {
    let base = bin_limbs_pattern(n + 1, n.to_uint64() + 99UL)
    for factor in [0xffff_ffff_ffff_ffffUL, 3UL, 0UL] {
      let x1 = bin_limbs_copy(base)
      let x2 = bin_limbs_copy(base)
      assert_eq(
        luna_addmul_1(x1, 0, x1, 0, n, factor),
        bin_limbs_addmul_1_portable(x2, 0, x2, 0, n, factor),
      )
      assert_eq(x1, x2)
      assert_eq(
        luna_submul_1(x1, 0, x1, 0, n, factor),
        bin_limbs_submul_1_portable(x2, 0, x2, 0, n, factor),
      )
      assert_eq(x1, x2)
      // the same array at different, disjoint ranges
      let y1 = bin_limbs_pattern(2 * n + 2, n.to_uint64() + 5UL)
      let y2 = bin_limbs_copy(y1)
      assert_eq(
        luna_addmul_1(y1, n + 1, y1, 0, n, factor),
        bin_limbs_addmul_1_portable(y2, n + 1, y2, 0, n, factor),
      )
      assert_eq(y1, y2)
    }
  }
}

///|
test "school and square in C equal the portable products" {
  let lengths = [1, 2, 3, 7, 8, 9, 15, 16, 17, 31, 32, 33, 64, 100]
  let mut cases = 0
  for an in lengths {
    for bn in lengths {
      for round in 0..<3 {
        let seed = (an * 1000 + bn * 10 + round).to_uint64()
        let a = bin_limbs_pattern(an + 4, seed + 1UL)
        let b = bin_limbs_pattern(bn + 4, seed + 2UL)
        let r1 = bin_limbs_pattern(an + bn + 5, seed + 3UL)
        let r2 = bin_limbs_copy(r1)
        luna_school(r1, 2, a, 3, an, b, 1, bn)
        bin_coeff_words_school(r2, 2, a, 3, an, b, 1, bn)
        assert_eq(r1, r2)
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
      let r1 = bin_limbs_pattern(2 * len + 3, 5UL + round.to_uint64())
      let r2 = bin_limbs_copy(r1)
      luna_sqr_school(r1, 1, s, 2, len)
      bin_coeff_words_sqr_school(r2, 1, s, 2, len)
      assert_eq(r1, r2)
      cases += 1
    }
  }
  assert_eq(cases, 14 * 14 * 3 + 130 * 3)
  // all-ones operands: every column carries
  for len in 1..<=70 {
    let ones = FixedArray::make(len, 0xffff_ffff_ffff_ffffUL)
    let r1 = FixedArray::make(2 * len, 7UL)
    let r2 = FixedArray::make(2 * len, 7UL)
    luna_school(r1, 0, ones, 0, len, ones, 0, len)
    bin_coeff_words_school(r2, 0, ones, 0, len, ones, 0, len)
    assert_eq(r1, r2)
    let s1 = FixedArray::make(2 * len, 7UL)
    luna_sqr_school(s1, 0, ones, 0, len)
    assert_eq(s1, r2)
  }
}

///|
test "the wrappers equal the portable rows on random lengths and offsets" {
  for n in 1..<=120 {
    let a = bin_limbs_pattern(n + 5, n.to_uint64() * 3UL)
    let b = bin_limbs_pattern(n + 5, n.to_uint64() * 5UL)
    let r1 = bin_limbs_pattern(2 * n + 6, n.to_uint64())
    let r2 = bin_limbs_copy(r1)
    bin_limbs_school(r1, 3, a, 1, n, b, 4, n)
    bin_coeff_words_school(r2, 3, a, 1, n, b, 4, n)
    assert_eq(r1, r2)
  }
}
