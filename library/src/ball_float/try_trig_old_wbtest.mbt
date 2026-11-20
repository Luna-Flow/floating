// Test-only copies of the pre-#378 rational-series try_sin/cos/tan (oracle).

///|
fn BallFloat::old_try_sin_interval(
  self : BallFloat,
) -> Result[BallFloat, @def.ArithmeticError] {
  if self.is_empty() {
    return Ok(self)
  }
  if !self.is_bounded() {
    return Ok(unit_interval(self.precision_))
  }
  let initial_work = Int32::max(
    trig_initial_work(self.lo_, self.precision_),
    trig_initial_work(self.hi_, self.precision_),
  )
  guard !trig_cutoff_exceeded(self) else {
    return Err(
      ball_range_resource_failure("sin", self.precision_, initial_work),
    )
  }
  match certified_sin_cos_interval_bounds(self) {
    Some(bounds) => {
      let lower = if index_range_contains_residue(bounds.8, bounds.9, 3) {
        @bin_float.BinFloat::from_int(-1, precision=self.precision_)
      } else {
        bin_min(bounds.0, bounds.4)
      }
      let upper = if index_range_contains_residue(bounds.8, bounds.9, 1) {
        @bin_float.BinFloat::one(precision=self.precision_)
      } else {
        bin_max(bounds.1, bounds.5)
      }
      Ok(store_interval(lower, upper, self.precision_))
    }
    None =>
      Err(ball_certification_failure("sin", self.precision_, initial_work))
  }
}

///|
fn BallFloat::old_try_cos_interval(
  self : BallFloat,
) -> Result[BallFloat, @def.ArithmeticError] {
  if self.is_empty() {
    return Ok(self)
  }
  if !self.is_bounded() {
    return Ok(unit_interval(self.precision_))
  }
  let initial_work = Int32::max(
    trig_initial_work(self.lo_, self.precision_),
    trig_initial_work(self.hi_, self.precision_),
  )
  guard !trig_cutoff_exceeded(self) else {
    return Err(
      ball_range_resource_failure("cos", self.precision_, initial_work),
    )
  }
  match certified_sin_cos_interval_bounds(self) {
    Some(bounds) => {
      let lower = if index_range_contains_residue(bounds.8, bounds.9, 2) {
        @bin_float.BinFloat::from_int(-1, precision=self.precision_)
      } else {
        bin_min(bounds.2, bounds.6)
      }
      let upper = if index_range_contains_residue(bounds.8, bounds.9, 0) {
        @bin_float.BinFloat::one(precision=self.precision_)
      } else {
        bin_max(bounds.3, bounds.7)
      }
      Ok(store_interval(lower, upper, self.precision_))
    }
    None =>
      Err(ball_certification_failure("cos", self.precision_, initial_work))
  }
}

///|
fn BallFloat::old_try_tan_interval(
  self : BallFloat,
) -> Result[BallFloat, @def.ArithmeticError] {
  if self.is_empty() {
    return Ok(self)
  }
  if !self.is_bounded() {
    return Ok(whole_real(self.precision_))
  }
  let initial_work = Int32::max(
    trig_initial_work(self.lo_, self.precision_),
    trig_initial_work(self.hi_, self.precision_),
  )
  guard !trig_cutoff_exceeded(self) else {
    return Err(
      ball_range_resource_failure("tan", self.precision_, initial_work),
    )
  }
  match certified_tan_interval_bounds(self) {
    Bounds(lower, upper) => Ok(store_interval(lower, upper, self.precision_))
    Pole => Ok(whole_real(self.precision_))
    Failure =>
      Err(ball_certification_failure("tan", self.precision_, initial_work))
  }
}

///|
fn ball_certification_failure(
  operation : String,
  precision : Int32,
  initial_work_precision : Int32,
) -> @def.ArithmeticError {
  let mut budget = certified_refinement_budget(initial_work_precision)
  while budget.available() {
    budget = budget.next()
  }
  @internal.certified_failure(
    operation,
    @def.CertificationStage::TargetRounding,
    @def.CertificationFailureReason::RefinementBudgetExhausted,
    precision,
    budget,
  )
}
