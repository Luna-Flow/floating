///|
pub struct TuneDecision {
  dataset_id : Int32
  candidate_id : String
  median_us : Double
  valid_samples : Int32
}

///|
fn samples_for(
  observations : Array[@model.Observation],
  case_id : String,
  dataset_id : Int32,
  candidate_id : String,
) -> Array[Double] {
  let selected = observations.filter(observation => {
    observation.case_id == case_id &&
    observation.dataset_id == dataset_id &&
    observation.implementation_id == candidate_id &&
    observation.phase is @model.ObservationPhase::Confirmatory &&
    observation.valid
  })
  selected.sort_by((left, right) => left.block_id.compare(right.block_id))
  selected.map(observation => observation.raw_elapsed_us)
}

///|
fn median_of_sorted(sorted : ArrayView[Double]) -> Double {
  let middle = sorted.length() / 2
  if sorted.length() % 2 == 0 {
    (sorted[middle - 1] + sorted[middle]) / 2.0
  } else {
    sorted[middle]
  }
}

///|
/// Interquartile range of the samples `score_samples` keeps (finite and
/// non-negative): the median of the upper half minus the median of the lower
/// half, the middle sample belonging to neither for an odd count. Fewer than
/// two samples have no spread, so the range is 0.
fn interquartile_range(samples : Array[Double]) -> Double {
  let sorted = samples.filter(sample => {
    !sample.is_nan() && !sample.is_inf() && sample >= 0.0
  })
  sorted.sort()
  let count = sorted.length()
  if count < 2 {
    return 0.0
  }
  let half = count / 2
  let upper_start = if count % 2 == 0 { half } else { half + 1 }
  median_of_sorted(sorted[upper_start:]) - median_of_sorted(sorted[0:half])
}

///|
/// Picks the candidate with the lowest median; candidates within
/// `practical_delta_pct` percent of it are practically tied and the one with
/// the smaller interquartile range wins (then the smaller candidate id).
pub fn tune_dataset(
  observations : Array[@model.Observation],
  case_id : String,
  dataset_id : Int32,
  candidate_ids : Array[String],
  practical_delta_pct : Double,
) -> TuneDecision? {
  let scores = []
  let sample_counts : Map[String, Int32] = Map([])
  for candidate_id in candidate_ids {
    let samples = samples_for(observations, case_id, dataset_id, candidate_id)
    scores.push(
      @tune.score_samples(candidate_id, samples, interquartile_range(samples)),
    )
    // Count only the samples `score_samples` keeps for the median.
    sample_counts[candidate_id] = samples
      .filter(sample => !sample.is_nan() && !sample.is_inf() && sample >= 0.0)
      .length()
  }
  match @tune.select_best(scores, practical_delta_pct, true) {
    Some(best) =>
      Some({
        dataset_id,
        candidate_id: best.candidate_id,
        median_us: best.primary,
        valid_samples: sample_counts[best.candidate_id],
      })
    None => None
  }
}

///|
pub fn paired_hotspot(
  observations : Array[@model.Observation],
  case_id : String,
  dataset_id : Int32,
  baseline_id : String,
  candidate_id : String,
  practical_delta_pct : Double,
  seed : UInt64,
) -> Result[@stats.Comparison, @stats.BootstrapError] {
  let baseline = samples_for(observations, case_id, dataset_id, baseline_id)
  let candidate = samples_for(observations, case_id, dataset_id, candidate_id)
  @stats.compare_paired_with_bootstrap(
    baseline_id,
    candidate_id,
    baseline,
    candidate,
    practical_delta_pct,
    @model.confirmatory_interval(),
    seed,
    2000,
    95.0,
  )
}

///|
pub fn confirmatory_regression(
  baseline : Array[Double],
  candidate : Array[Double],
  seed : UInt64,
) -> Result[@stats.Comparison, @stats.BootstrapError] {
  @stats.compare_paired_with_bootstrap(
    "0.6.1-baseline",
    "0.8.0-candidate",
    baseline,
    candidate,
    3.0,
    @model.confirmatory_interval(),
    seed,
    10_000,
    95.0,
  )
}

///|
pub fn is_significant_regression(comparison : @stats.Comparison) -> Bool {
  comparison.decision is @stats.Decision::Slower &&
  comparison.interval.low > 0.0
}
