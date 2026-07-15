///|
fn observation(
  implementation_id : String,
  dataset_id : Int,
  block_id : Int,
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
  let first = tune_dataset(observations, "mul", 0, ["kernel", "full"], 3.0)
  let second = tune_dataset(observations, "mul", 1, ["kernel", "full"], 3.0)
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
  let comparison = paired_hotspot(
    observations, "mul", 0, "kernel", "full", 3.0, 42UL,
  ).unwrap()
  assert_true(comparison.relative_delta_pct > 90.0)
}

///|
test "immutable baseline comparison rejects a significant regression" {
  let comparison = confirmatory_regression(
    [100.0, 101.0, 99.0, 100.5, 99.5, 100.0, 101.0, 99.0, 100.0, 100.5],
    [110.0, 111.0, 109.0, 110.5, 109.5, 110.0, 111.0, 109.0, 110.0, 110.5],
    0x070UL,
  ).unwrap()
  assert_true(is_significant_regression(comparison))
}
