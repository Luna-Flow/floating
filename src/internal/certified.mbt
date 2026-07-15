///|
pub struct CertifiedRefinementBudget {
  work_precision : Int
  refinements_ : Int
  limit_ : Int
}

///|
pub struct CertifiedInterval[T] {
  lower_ : T
  upper_ : T
}

///|
pub fn[T] CertifiedInterval::new(
  lower : T,
  upper : T,
  compare : (T, T) -> Int,
) -> Result[CertifiedInterval[T], @def.ArithmeticError] {
  guard compare(lower, upper) <= 0 else {
    return Err(
      @def.ArithmeticError::certification_failure(
        @def.CertificationFailureDetail::new(
          "interval",
          @def.CertificationStage::EnclosurePropagation,
          @def.CertificationFailureReason::InvalidEnclosure,
          1,
          1,
          0,
        ),
      ),
    )
  }
  Ok({ lower_: lower, upper_: upper })
}

///|
pub fn[T] CertifiedInterval::lower(self : CertifiedInterval[T]) -> T {
  self.lower_
}

///|
pub fn[T] CertifiedInterval::upper(self : CertifiedInterval[T]) -> T {
  self.upper_
}

///|
pub fn CertifiedRefinementBudget::new(
  initial_precision : Int,
  limit? : Int = 12,
) -> CertifiedRefinementBudget {
  {
    work_precision: Int::max(1, initial_precision),
    refinements_: 0,
    limit_: Int::max(1, limit),
  }
}

///|
pub fn CertifiedRefinementBudget::available(
  self : CertifiedRefinementBudget,
) -> Bool {
  self.refinements_ < self.limit_
}

///|
pub fn CertifiedRefinementBudget::precision(
  self : CertifiedRefinementBudget,
) -> Int {
  self.work_precision
}

///|
pub fn CertifiedRefinementBudget::refinements(
  self : CertifiedRefinementBudget,
) -> Int {
  self.refinements_
}

///|
pub fn CertifiedRefinementBudget::next(
  self : CertifiedRefinementBudget,
) -> CertifiedRefinementBudget {
  {
    work_precision: self.work_precision + Int::max(32, self.work_precision / 2),
    refinements_: self.refinements_ + 1,
    limit_: self.limit_,
  }
}

///|
pub fn certified_failure(
  operation : String,
  stage : @def.CertificationStage,
  reason : @def.CertificationFailureReason,
  target_precision : Int,
  budget : CertifiedRefinementBudget,
) -> @def.ArithmeticError {
  @def.ArithmeticError::certification_failure(
    @def.CertificationFailureDetail::new(
      operation,
      stage,
      reason,
      target_precision,
      budget.precision(),
      budget.refinements(),
    ),
  )
}
