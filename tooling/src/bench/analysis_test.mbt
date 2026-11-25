///|
fn observation(
  implementation_id : String,
  dataset_id : Int32,
  block_id : Int32,
  elapsed_us : Double,
) -> @model.Observation {
  @model.Observation::new(
    "mul",
    implementation_id,
    "1",
    dataset_id,
    block_id,
    block_id,
    @model.ObservationPhase::Confirmatory,
    elapsed_us,
    1,
    @model.BatchSinkStatus::Kept,
    @model.SetupTiming::ExcludedFromMeasurement,
    true,
  )
}

///|
// oracle: A
// source: winners and sample counts read off the written times by hand: dataset 0 has kernel 10 and 11 against full 20
//   and 21 (kernel faster, two valid samples), dataset 1 has kernel 30 against full 15 (full faster)
// shares: observation() (builds the observation records from the written times); the analysis functions under test are
//   not used to build any expected value
test "auto tune selects the fastest valid candidate" {
  let observations = [
    observation("kernel", 0, 0, 10.0),
    observation("full", 0, 0, 20.0),
    observation("full", 0, 1, 21.0),
    observation("kernel", 0, 1, 11.0),
    observation("kernel", 1, 0, 30.0),
    observation("full", 1, 0, 15.0),
  ]
  let first = @bench.tune_dataset(
    observations,
    "mul",
    0,
    ["kernel", "full"],
    3.0,
  )
  let second = @bench.tune_dataset(
    observations,
    "mul",
    1,
    ["kernel", "full"],
    3.0,
  )
  assert_eq(first.unwrap().candidate_id, "kernel")
  assert_eq(first.unwrap().valid_samples, 2)
  assert_eq(second.unwrap().candidate_id, "full")
}

///|
// oracle: A
// source: pairs written out: full is twice kernel in blocks 0 and 1 (10 to 20, 11 to 22) and 19/9 in block 2, so every
//   paired relative delta is 100 percent or more and the bound 90 percent holds; hand arithmetic, the bootstrap
//   is not recomputed
// shares: observation() (builds the observation records from the written times); the analysis functions under test are
//   not used to build any expected value
test "paired hotspot analysis preserves balanced block pairing" {
  let observations = [
    observation("kernel", 0, 0, 10.0),
    observation("full", 0, 0, 20.0),
    observation("full", 0, 1, 22.0),
    observation("kernel", 0, 1, 11.0),
    observation("kernel", 0, 2, 9.0),
    observation("full", 0, 2, 19.0),
  ]
  let comparison = @bench.paired_hotspot(
    observations, "mul", 0, "kernel", "full", 3.0, 42UL,
  ).unwrap()
  assert_true(comparison.relative_delta_pct > 90.0)
}

///|
// oracle: A
// source: the verdict is read off the written samples: every candidate time (109 to 111) lies above every baseline
//   time (99 to 101), a slowdown of about 10 percent against a spread of about 1 percent, which any sound test
//   reports as a significant regression; the bootstrap itself is not recomputed
// shares: nothing
test "immutable baseline comparison rejects a significant regression" {
  let comparison = @bench.confirmatory_regression(
    [100.0, 101.0, 99.0, 100.5, 99.5, 100.0, 101.0, 99.0, 100.0, 100.5],
    [110.0, 111.0, 109.0, 110.5, 109.5, 110.0, 111.0, 109.0, 110.0, 110.5],
    0x070UL,
  ).unwrap()
  assert_true(@bench.is_significant_regression(comparison))
}

///|
// oracle: A
// source: bounds from hand arithmetic on the ten paired differences (-18 to -3, median -8); the bootstrap itself is
//   not recomputed
// shares: nothing
test "paired hotspot reports a 95 percent interval" {
  let baseline = [
    100.0, 104.0, 98.0, 110.0, 101.0, 97.0, 105.0, 99.0, 103.0, 100.0,
  ]
  let candidate = [90.0, 99.0, 91.0, 92.0, 98.0, 88.0, 95.0, 93.0, 90.0, 96.0]
  let observations = []
  for block in 0..<baseline.length() {
    observations.push(observation("base", 0, block, baseline[block]))
    observations.push(observation("cand", 0, block, candidate[block]))
  }
  let hotspot = @bench.paired_hotspot(
    observations, "mul", 0, "base", "cand", 3.0, 1UL,
  ).unwrap()
  // The paired differences candidate - baseline are -10, -5, -7, -18, -3, -9, -10,
  // -6, -13, -4: their median is -8 and they lie in [-18, -3]. A bootstrap interval
  // of the median is inside the range of the data and, for these ten values, holds
  // the sample median (hand arithmetic; the bootstrap itself is not recomputed).
  assert_true(hotspot.interval.low >= -18.0)
  assert_true(hotspot.interval.high <= -3.0)
  assert_true(hotspot.interval.low <= -8.0)
  assert_true(hotspot.interval.high >= -8.0)
  assert_true(hotspot.interval.low < hotspot.interval.high)
}

///|
// oracle: A
// source: hand arithmetic on the written times: the sample -1 is invalid, the two valid ones 10 and 12 have median 11
//   and count 2
// shares: observation() (builds the observation records from the written times); the analysis functions under test are
//   not used to build any expected value
test "tune decision counts only the samples behind the median" {
  let observations = [
    observation("kernel", 0, 0, 10.0),
    observation("kernel", 0, 1, -1.0),
    observation("kernel", 0, 2, 12.0),
  ]
  let decision = @bench.tune_dataset(observations, "mul", 0, ["kernel"], 3.0).unwrap()
  assert_eq(decision.median_us, 11.0)
  assert_eq(decision.valid_samples, 2)
}

///|
/// Candidates within `practical_delta_pct` of the fastest median are tied in
/// practice; the secondary criterion is the interquartile range of their
/// samples (#60). `a` has median 102 and no spread, `b` median 100 and a wide
/// spread: outside the threshold the faster `b` wins, inside it the steadier `a`.
// oracle: A
// source: the rule written in the doc comment of the block (issue 60) applied by hand to the written samples: a is 102
//   four times (median 102, no spread), b is 90, 95, 105, 110 (median 100, wide spread); a is 2 percent above b,
//   so thresholds 0 and 1 percent pick the faster b and 2 and 50 percent pick the steadier a, whatever the order
//   of candidate_ids
// shares: observation() (builds the observation records from the written times); the analysis functions under test are
//   not used to build any expected value
test "tune_dataset breaks practical ties by interquartile range" {
  let observations = []
  let a = [102.0, 102.0, 102.0, 102.0]
  let b = [90.0, 95.0, 105.0, 110.0]
  for i in 0..<4 {
    observations.push(observation("a", 0, i, a[i]))
    observations.push(observation("b", 0, i, b[i]))
  }
  let pick = fn(delta : Double) {
    @bench.tune_dataset(observations, "mul", 0, ["a", "b"], delta).unwrap().candidate_id
  }
  inspect(pick(0.0), content="b")
  inspect(pick(1.0), content="b")
  inspect(pick(2.0), content="a")
  inspect(pick(50.0), content="a")
  inspect(
    @bench.tune_dataset(observations, "mul", 0, ["b", "a"], 50.0).unwrap().candidate_id,
    content="a",
  )
}

///|
/// With equal medians and equal spread the smaller candidate id wins, whatever
/// the order of `candidate_ids`.
// oracle: A
// source: the rule written in the doc comment of the block applied by hand: a has median 102, b median 100, both
//   without spread; within 3 percent they tie and the smaller id a wins in either argument order, within 0 or 1
//   percent b is faster and wins
// shares: observation() (builds the observation records from the written times); the analysis functions under test are
//   not used to build any expected value
test "tune_dataset ties on median and spread resolve by candidate id" {
  let observations = [
    observation("a", 0, 0, 102.0),
    observation("a", 0, 1, 102.0),
    observation("b", 0, 0, 100.0),
    observation("b", 0, 1, 100.0),
  ]
  let pick = fn(ids : Array[String], delta : Double) {
    @bench.tune_dataset(observations, "mul", 0, ids, delta).unwrap().candidate_id
  }
  inspect(pick(["a", "b"], 0.0), content="b")
  inspect(pick(["a", "b"], 3.0), content="a")
  inspect(pick(["b", "a"], 3.0), content="a")
  inspect(pick(["b", "a"], 1.0), content="b")
}
