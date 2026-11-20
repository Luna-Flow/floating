///|
/// The binary-splitting trees as they were before the shared powers, the
/// shifted add and the two-leaf nodes: a power product and a shifted copy at
/// every node, kept here as the reference the new trees are compared with. The
/// states are exact integers, so the comparison is equality and every stage
/// enclosure derived from them is the same one.
fn split_exp_state_reference(
  from : Int32,
  to : Int32,
  numerator : Coeff,
  s : Int32,
) -> SplitState {
  if to - from == 1 {
    if from == 0 {
      return {
        p: Coeff::one(),
        q: Coeff::one(),
        q_shift: 0,
        t_negative: false,
        t: Coeff::one(),
      }
    }
    return {
      p: numerator,
      q: Coeff::from_uint64(from.to_uint64()),
      q_shift: s,
      t_negative: false,
      t: numerator,
    }
  }
  let middle = from + (to - from) / 2
  split_combine(
    split_exp_state_reference(from, middle, numerator, s),
    split_exp_state_reference(middle, to, numerator, s),
  )
}

///|
priv struct SplitComplexReference {
  p : Coeff
  leaves : Int32
  q : Coeff
  q_shift : Int32
  re : SplitInt
  im : SplitInt
}

///|
fn split_trig_state_reference(
  from : Int32,
  to : Int32,
  numerator : Coeff,
  s : Int32,
) -> SplitComplexReference {
  if to - from == 1 {
    if from == 0 {
      return {
        p: Coeff::one(),
        leaves: 0,
        q: Coeff::one(),
        q_shift: 0,
        re: SplitInt::make(false, Coeff::one()),
        im: SplitInt::make(false, Coeff::zero()),
      }
    }
    return {
      p: numerator,
      leaves: 1,
      q: Coeff::from_uint64(from.to_uint64()),
      q_shift: s,
      re: SplitInt::make(false, Coeff::zero()),
      im: SplitInt::make(false, numerator),
    }
  }
  let middle = from + (to - from) / 2
  let left = split_trig_state_reference(from, middle, numerator, s)
  let right = split_trig_state_reference(middle, to, numerator, s)
  let (rotated_re, rotated_im) = match left.leaves % 4 {
    0 => (right.re, right.im)
    1 => (burst_trig_rotate(right.im, 2), right.re)
    2 => (burst_trig_rotate(right.re, 2), burst_trig_rotate(right.im, 2))
    _ => (right.im, burst_trig_rotate(right.re, 2))
  }
  {
    p: left.p.mul(right.p),
    leaves: left.leaves + right.leaves,
    q: left.q.mul(right.q),
    q_shift: left.q_shift + right.q_shift,
    re: split_combine_t(left.re, left.p, rotated_re, right.q, right.q_shift),
    im: split_combine_t(left.im, left.p, rotated_im, right.q, right.q_shift),
  }
}

///|
fn split_tree_test_cases() -> Array[(Coeff, Int32, Int32)] {
  let cases : Array[(Coeff, Int32, Int32)] = []
  let mut seed = 71UL
  for bits in [1, 3, 16, 48, 192, 768] {
    for s in [bits, 16, 64, 256, 1024] {
      for terms in [2, 3, 4, 5, 6, 7, 8, 9, 17, 40, 64, 105, 315] {
        seed += 1UL
        cases.push((burst_test_coefficient(bits, seed), s, terms))
      }
    }
  }
  cases
}

///|
test "exp splitting tree equals the tree with a power product at every node" {
  for case in split_tree_test_cases() {
    let (numerator, s, terms) = case
    let reference = split_exp_state_reference(0, terms, numerator, s)
    let state = split_exp_state(0, terms, SplitPowers::new(numerator, terms), s)
    assert_eq(state.q.compare(reference.q), 0)
    assert_eq(state.q_shift, reference.q_shift)
    assert_eq(state.t.compare(reference.t), 0)
    assert_true(!reference.t_negative)
  }
}

///|
test "trig splitting tree equals the tree with a power product at every node" {
  for case in split_tree_test_cases() {
    let (numerator, s, terms) = case
    let reference = split_trig_state_reference(0, terms, numerator, s)
    let state = split_trig_state(
      0,
      terms,
      SplitPowers::new(numerator, terms),
      s,
    )
    assert_eq(state.q.compare(reference.q), 0)
    assert_eq(state.q_shift, reference.q_shift)
    assert_eq(state.leaves, reference.leaves)
    assert_eq(state.re.negative, reference.re.negative)
    assert_eq(state.re.magnitude.compare(reference.re.magnitude), 0)
    assert_eq(state.im.negative, reference.im.negative)
    assert_eq(state.im.magnitude.compare(reference.im.magnitude), 0)
  }
}

///|
test "exp and trig bursts contain the exact value at 256 bits more" {
  // The stage integers are equal to the reference (above), hence the same
  // enclosures; this checks the whole kernels against the series at a working
  // precision 256 bits higher, on seeded random arguments.
  let mut seed = 6001UL
  for work in [256, 1024, 2048, 4096] {
    let count = if work <= 1024 { 6 } else { 2 }
    for _ in 0..<count {
      let value = burst_test_value(Int32::min(work, 1500), 1, false, seed)
      seed += 1UL
      match binary_exp_bounds_burst(value, work) {
        Some(bounds) => {
          let reference = binary_exp_bounds_series(value, work + 256).unwrap()
          assert_true(burst_test_contains(bounds, reference))
        }
        None => ()
      }
      match binary_trig_bounds_burst(value, false, work) {
        Some(bounds) => {
          let reference = burst_trig_test_reference(value, false, work).unwrap()
          assert_true(burst_test_contains(bounds, reference))
        }
        None => ()
      }
    }
  }
}
