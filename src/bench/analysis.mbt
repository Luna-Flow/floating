///|
pub struct TuneDecision {
  dataset_id : Int
  candidate_id : String
  median_us : Double
  valid_samples : Int
}

///|
fn samples_for(
  observations : Array[@model.Observation],
  case_id : String,
  dataset_id : Int,
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
pub fn tune_dataset(
  observations : Array[@model.Observation],
  case_id : String,
  dataset_id : Int,
  candidate_ids : Array[String],
  practical_delta_pct : Double,
) -> TuneDecision? {
  let scores = []
  let sample_counts : Map[String, Int] = Map([])
  for candidate_id in candidate_ids {
    let samples = samples_for(observations, case_id, dataset_id, candidate_id)
    let score = @tune.score_samples(candidate_id, samples, 0.0)
    scores.push(
      @tune.CandidateScore::new(
        score.candidate_id,
        score.primary,
        score.primary,
        score.valid,
      ),
    )
    sample_counts[candidate_id] = samples.length()
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
  dataset_id : Int,
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
    0.95,
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
    "0.7.1-candidate",
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
