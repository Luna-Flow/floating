///|
/// The `exp` bit-burst kernel as it was before the combination by one full
/// product (two full products per chunk, the first one with the identity),
/// kept as the reference for the new kernel: the integers must be equal.
fn binary_exp_bounds_burst_reference(
  value : Binary,
  work_precision : Int32,
  mutation~ : BurstMutation = burst_no_mutation,
  first_chunk~ : Int32 = binary_exp_burst_first_chunk,
  chunk_factor~ : Int32 = binary_exp_burst_chunk_factor,
  split_min_terms~ : Int32 = binary_exp_burst_split_min_terms,
) -> (Binary, Binary)? {
  let f = work_precision + binary_exp_burst_guard_bits
  guard fixed_exp_reduce(value, f, ln2_drop_bits=mutation.ln2_drop_bits)
    is Some(reduction) else {
    return None
  }
  let reduced = reduction.reduced
  let one_unit = Coeff::one().shift_left(f)
  // Chunks of the reduced argument.
  let mut lower = one_unit
  let mut upper = one_unit
  let chunks_ok = fixed_burst_chunks(reduced, f, first_chunk, chunk_factor, fn(
    chunk,
    boundary,
  ) {
    let terms = fixed_split_terms(chunk, boundary, f)
    let stage = if terms >= split_min_terms {
      burst_split_stage(chunk, boundary, f, mutation)
    } else {
      burst_fixed_stage(chunk, boundary, f, mutation)
    }
    guard stage is Some((stage_low, stage_high)) else { return false }
    lower = lower.mul(stage_low).shift_right(f)
    upper = upper.mul(stage_high).shift_right(f).add(Coeff::one())
    true
  })
  guard chunks_ok else { return None }
  // exp(delta) with |delta| <= 1.5 * 2^-F and exp(R_t) < 3.
  fixed_exp_finish(
    lower,
    upper,
    reduction,
    f,
    work_precision,
    drop_delta=mutation.drop_delta,
  )
}

///|
fn ball_fold_test_value(bits : Int32, seed : UInt64) -> Coeff {
  burst_test_coefficient(bits, seed)
}

///|
test "exp fold by one full product equals the two separate products" {
  let mut seed = 31UL
  for f in [64, 256, 1088, 2160, 4400] {
    for spread_bits in [1, 10, 17, 40] {
      for _ in 0..<6 {
        seed += 3UL
        let lower = ball_fold_test_value(f + 1, seed)
        let spread = ball_fold_test_value(spread_bits, seed + 1UL)
        let upper = lower.add(spread)
        let stage_low = ball_fold_test_value(f - 3, seed + 2UL)
        let stage_spread = ball_fold_test_value(
          Int32::min(spread_bits + 2, 12),
          seed + 5UL,
        )
        let stage_high = stage_low.add(stage_spread)
        let (new_lower, new_upper) = burst_exp_fold(
          lower, spread, stage_low, stage_spread, stage_high, f,
        )
        assert_eq(new_lower.compare(lower.mul(stage_low).shift_right(f)), 0)
        assert_eq(
          new_upper.compare(
            upper.mul(stage_high).shift_right(f).add(Coeff::one()),
          ),
          0,
        )
      }
    }
  }
}

///|
// oracle: S
// source: the previous kernel kept in this file (binary_exp_bounds_burst_reference) against the current one on the same inputs: both are kernels of this library with no external value on these inputs (the end-to-end enclosures of the same functions are checked against MPFR in the burst and table blocks, on other arguments), so only agreement is stated
// shares: binary_exp_bounds_burst and its reference share the splitting trees, the reduction and the Coeff arithmetic; burst_test_value and burst_test_coefficient build the arguments
test "exp burst kernel equals the kernel with two products per chunk" {
  let mut seed = 5150UL
  let mut compared = 0
  for work in [128, 256, 640, 1088, 2112, 4160] {
    for _ in 0..<5 {
      for top in [-20, -3, 0, 1, 4, 12] {
        let value = burst_test_value(
          Int32::min(work, 1200),
          top,
          seed % 2UL == 0UL,
          seed,
        )
        seed += 1UL
        let new = binary_exp_bounds_burst(
          value,
          work,
          first_chunk=binary_exp_burst_first_chunk,
          chunk_factor=binary_exp_burst_chunk_factor,
          split_min_terms=binary_exp_burst_split_min_terms,
        )
        let reference = binary_exp_bounds_burst_reference(value, work)
        match (new, reference) {
          (Some(a), Some(b)) => {
            assert_eq(a.0.compare(b.0), 0)
            assert_eq(a.1.compare(b.1), 0)
            compared += 1
          }
          (None, None) => ()
          _ => fail("kernels disagree on declining")
        }
      }
    }
  }
  assert_true(compared > 60)
}

///|
// oracle: S
// source: burst_trig_fold, the fold of both components, run on the same random balls; the claim is that the one-component forms agree with it
// shares: burst_trig_fold_one and burst_trig_fold (both are the code under test), Binary::compare
test "trig fold of one component equals the component of the full fold" {
  let mut seed = 9001UL
  for f in [128, 1100, 2200] {
    for _ in 0..<8 {
      seed += 7UL
      let ball = fn(offset : UInt64) -> BurstBall {
        {
          mid: ball_fold_test_value(f - 2, seed + offset),
          rad: ball_fold_test_value(5, seed + offset + 100UL),
        }
      }
      let running : BurstRotation = { cos: ball(1UL), sin: ball(2UL), }
      let stage : BurstRotation = { cos: ball(3UL), sin: ball(4UL), }
      match
        (
          burst_trig_fold(running, stage, f),
          burst_trig_fold_one(running, stage, f, true),
          burst_trig_fold_one(running, stage, f, false),
        ) {
        (Some(full), Some(sine), Some(cosine)) => {
          assert_eq(full.sin.mid.compare(sine.sin.mid), 0)
          assert_eq(full.sin.rad.compare(sine.sin.rad), 0)
          assert_eq(full.cos.mid.compare(cosine.cos.mid), 0)
          assert_eq(full.cos.rad.compare(cosine.cos.rad), 0)
        }
        (None, _, None) => ()
        _ => fail("fold disagrees on declining")
      }
    }
  }
}
