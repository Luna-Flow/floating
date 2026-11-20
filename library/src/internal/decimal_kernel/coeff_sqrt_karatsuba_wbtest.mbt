///|
// Tests of the Karatsuba square root (`coeff_sqrt_karatsuba.mbt`) against the
// reference implementation of `coeff_sqrt_diff_wbtest.mbt` (Newton from a
// power of ten, one full division per step): the recursion depths, the
// capped quotient, the correction step and the rounding state of the scalar
// entry. Counters of the module are read before and after each call.

///|
fn karatsuba_random(state : Ref[UInt64], length : Int32) -> DecCoeff {
  sqrt_diff_random_limbs(state, length)
}

///|
fn karatsuba_compare(n : DecCoeff, stats? : DecSqrtStats) -> Unit raise {
  let (root, remainder) = dec_coeff_sqrt_rem_karatsuba(n, stats?)
  let (reference_root, reference_remainder) = reference_integer_sqrt_rem_repr(n)
  if !sqrt_diff_same(root, reference_root) ||
    !sqrt_diff_same(remainder, reference_remainder) {
    fail("Karatsuba root differs from the reference for \{n.to_string()}")
  }
  // the scalar entry: the root and the state of the remainder against it
  let (scalar_root, state) = dec_coeff_sqrt_rounding(n)
  let expected = if reference_remainder.is_zero() {
    DecSqrtRemainder::Zero
  } else if dec_coeff_compare_repr(reference_remainder, reference_root) > 0 {
    DecSqrtRemainder::AboveRoot
  } else {
    DecSqrtRemainder::UpToRoot
  }
  if !sqrt_diff_same(scalar_root, reference_root) || state != expected {
    fail("rounding state differs from the reference for \{n.to_string()}")
  }
}

///|
test "Karatsuba root equals the reference for every length from 3 to 70 limbs" {
  let state = Ref(0x9E3779B97F4A7C15UL)
  for length in 3..<71 {
    for _ in 0..<12 {
      let n = karatsuba_random(state, length)
      karatsuba_compare(n)
      let root = karatsuba_random(state, (length + 1) / 2)
      let square = dec_coeff_square_repr(root)
      karatsuba_compare(square)
      karatsuba_compare(dec_coeff_magnitude_add_unit(square, 1))
      karatsuba_compare(dec_coeff_magnitude_sub_unit(square, 1))
      // remainders r = s, r = s + 1 and r = 2 s around the midpoint
      karatsuba_compare(dec_coeff_magnitude_add_repr(square, root))
      karatsuba_compare(
        dec_coeff_magnitude_add_unit(
          dec_coeff_magnitude_add_repr(square, root),
          1,
        ),
      )
      karatsuba_compare(
        dec_coeff_magnitude_add_repr(
          square,
          dec_coeff_multiply_by_unit_repr(root, 2),
        ),
      )
    }
  }
}

///|
test "Karatsuba root on 10^k, 10^k - 1, 10^k + 1 and 4, 9 and 3 times them" {
  for digits in 18..<1200 {
    let power = dec_coeff_power10_repr(digits)
    karatsuba_compare(power)
    karatsuba_compare(dec_coeff_magnitude_add_unit(power, 1))
    karatsuba_compare(dec_coeff_magnitude_sub_unit(power, 1))
    karatsuba_compare(dec_coeff_multiply_by_unit_repr(power, 4))
    karatsuba_compare(dec_coeff_multiply_by_unit_repr(power, 9))
    karatsuba_compare(dec_coeff_multiply_by_unit_repr(power, 3))
  }
}

///|
/// A radicand of `length` limbs whose recursion has the given depth: each level
/// keeps `n - 2 floor((n - 1) / 4)` limbs of the radicand, down to four or
/// fewer.
fn karatsuba_depth_of(length : Int32) -> Int32 {
  let mut n = length
  let mut depth = 0
  while n > 4 {
    n = n - 2 * ((n - 1) / 4)
    depth += 1
  }
  depth
}

///|
test "Karatsuba recursion reaches every depth from 0 to 6" {
  let state = Ref(0xD1B54A32D192ED03UL)
  // (limbs, depth): 4 -> leaf, 5 -> 3 -> leaf, 8 -> 6 -> 4, ...
  let classes = [
    (3, 0),
    (4, 0),
    (5, 1),
    (8, 2),
    (12, 3),
    (24, 4),
    (50, 5),
    (100, 6),
  ]
  for entry in classes {
    let (length, depth) = entry
    assert_eq(karatsuba_depth_of(length), depth)
    for _ in 0..<20 {
      let n = karatsuba_random(state, length)
      // exactly one leaf per root, at the depth the formula gives
      let stats : DecSqrtStats = { leaf_depths: [], caps: 0, corrections: 0, }
      karatsuba_compare(n, stats~)
      assert_eq(stats.leaf_depths, [depth])
    }
  }
}

///|
test "Karatsuba caps a quotient of X and takes the correction step" {
  let state = Ref(0x2545F4914F6CDD1DUL)
  let stats : DecSqrtStats = { leaf_depths: [], caps: 0, corrections: 0, }
  // the top part a perfect square plus its largest remainder `2 s'`, the next
  // block all nines: the quotient estimate is exactly `X` (capped), and with a
  // random lower block the capped root and the remainder are right
  let mut cases = 0
  for length in [5, 6, 7, 8, 9, 10, 12, 16, 24, 30, 50] {
    let block = (length - 1) / 4
    let high_len = length - 2 * block
    for _ in 0..<40 {
      let high_root = karatsuba_random(state, (high_len + 1) / 2)
      let high = dec_coeff_magnitude_add_repr(
        dec_coeff_square_repr(high_root),
        dec_coeff_multiply_by_unit_repr(high_root, 2),
      )
      // radicand = high * X^2 + (X - 1) * X + a0
      let x = dec_coeff_power10_repr(9 * block)
      let shifted = dec_coeff_multiply_repr(high, dec_coeff_square_repr(x))
      let middle = dec_coeff_multiply_repr(
        dec_coeff_magnitude_sub_unit(x, 1),
        x,
      )
      let low = karatsuba_random(state, block)
      let n = dec_coeff_magnitude_add_repr(
        dec_coeff_magnitude_add_repr(shifted, middle),
        low,
      )
      karatsuba_compare(n, stats~)
      cases += 1
    }
  }
  assert_true(cases > 0)
  assert_true(stats.caps > 0)
  // random radicands: count the corrections (the proof says at most one step,
  // and it is taken for a fraction of the levels)
  stats.corrections = 0
  for length in [5, 6, 8, 12, 20, 40] {
    for _ in 0..<2000 {
      karatsuba_compare(karatsuba_random(state, length), stats~)
    }
  }
  assert_true(stats.corrections > 0)
}

///|
/// A radicand constructed to take the correction step: with `s'` the root of
/// the top part (top limb at least 5 * 10^8), a quotient `q` below `X` and
/// `D = 2 s' q` split as `r' X + a1`, the top part `H = s'^2 + r'` and the
/// lower blocks `a1`, `a0 = 0` give `(q, u) = (q, 0)` and `r = 0 + 0 - q^2 < 0`.
test "Karatsuba takes the correction step on a constructed class" {
  let state = Ref(0xBF58476D1CE4E5B9UL)
  for length in [6, 8, 10, 12, 20, 40, 80] {
    let block = (length - 1) / 4
    let high_len = length - 2 * block
    guard high_len % 2 == 0 else { fail("class needs an even top part") }
    let g = high_len / 2
    for _ in 0..<30 {
      let units : Array[UInt32] = Array::make(g, 0U)
      for index in 0..<g {
        units[index] = (sqrt_diff_next(state) % 1000000000UL).to_uint()
      }
      units[g - 1] = (500000000UL + sqrt_diff_next(state) % 500000000UL).to_uint()
      let s1 = dec_coeff_from_unit_accumulator(units, g)
      let x = dec_coeff_power10_repr(9 * block)
      // q in [10^(9 block - 1), X): at least 10^(9 block) / 10 so that q^2 > a0 = 0
      let q = dec_coeff_magnitude_add_unit(
        dec_coeff_div_rem_repr(
          karatsuba_random(state, block),
          dec_coeff_from_int(2),
        ).0,
        1,
      )
      let d = dec_coeff_multiply_repr(dec_coeff_multiply_by_unit_repr(s1, 2), q)
      let (r1, a1) = dec_coeff_div_rem_repr(d, x)
      let high = dec_coeff_magnitude_add_repr(dec_coeff_square_repr(s1), r1)
      let n = dec_coeff_magnitude_add_repr(
        dec_coeff_multiply_repr(high, dec_coeff_square_repr(x)),
        dec_coeff_multiply_repr(a1, x),
      )
      let stats : DecSqrtStats = { leaf_depths: [], caps: 0, corrections: 0, }
      let (root, remainder) = dec_coeff_sqrt_rem_karatsuba(n, stats~)
      let (reference_root, reference_remainder) = reference_integer_sqrt_rem_repr(
        n,
      )
      assert_true(sqrt_diff_same(root, reference_root))
      assert_true(sqrt_diff_same(remainder, reference_remainder))
      // the top level takes the step (the levels below may too)
      assert_true(stats.corrections >= 1)
    }
  }
}

///|
/// Above the old limit of a fixed counter array: a radicand whose recursion has
/// a leaf at depth 16 or more (`n >= 65,539` limbs, 589,851 digits) is rooted
/// and checked by the identity `N = s^2 + r`, `r <= 2 s`. The radicand
/// `10^(9 (n - 1)) + 12345` is sparse (cheap to build and to compare) but runs
/// the whole recursion; the leaf depths are recorded in a growable store.
test "Karatsuba root above 65,538 limbs (the recursion is deeper than 15)" {
  let length = 65540
  assert_true(karatsuba_depth_of(length) >= 16)
  let n = dec_coeff_magnitude_add_unit(
    dec_coeff_power10_repr(9 * (length - 1)),
    12345,
  )
  assert_eq(dec_coeff_unit_len(n), length)
  let stats : DecSqrtStats = { leaf_depths: [], caps: 0, corrections: 0, }
  let (root, remainder) = dec_coeff_sqrt_rem_karatsuba(n, stats~)
  assert_eq(stats.leaf_depths.length(), 1)
  assert_true(stats.leaf_depths[0] >= 16)
  let reconstructed = dec_coeff_magnitude_add_repr(
    dec_coeff_square_repr(root),
    remainder,
  )
  assert_eq(dec_coeff_compare_repr(reconstructed, n), 0)
  assert_true(
    dec_coeff_compare_repr(remainder, dec_coeff_multiply_by_unit_repr(root, 2)) <=
    0,
  )
  // the root of 10^(9 (n - 1)) + 12345 is 10^(9 (n - 1) / 2) when n - 1 is even
  // and slightly above 10^(...) otherwise; either way it has ceil(n / 2) limbs
  assert_eq(dec_coeff_unit_len(root), (length + 1) / 2)
}
