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
test "immutable baseline comparison rejects a significant regression" {
  let comparison = @bench.confirmatory_regression(
    [100.0, 101.0, 99.0, 100.5, 99.5, 100.0, 101.0, 99.0, 100.0, 100.5],
    [110.0, 111.0, 109.0, 110.5, 109.5, 110.0, 111.0, 109.0, 110.0, 110.5],
    0x070UL,
  ).unwrap()
  assert_true(@bench.is_significant_regression(comparison))
}

///|
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
  let expected = @stats.compare_paired_with_bootstrap(
    "base",
    "cand",
    baseline,
    candidate,
    3.0,
    @model.confirmatory_interval(),
    1UL,
    2000,
    95.0,
  ).unwrap()
  assert_eq(hotspot.interval.low, expected.interval.low)
  assert_eq(hotspot.interval.high, expected.interval.high)
  assert_true(hotspot.interval.low < hotspot.interval.high)
}

///|
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
