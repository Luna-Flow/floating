///|
pub struct CertifiedRefinementBudget {
  work_precision : Int32
  refinements_ : Int32
  limit_ : Int32?
  cap_ : Int32
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
  compare : (T, T) -> Int32,
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
  Ok({ lower_: lower, upper_: upper, })
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
/// The work precision (bits) that stops a certified refinement loop whose count
/// limit is `None`: at least 8,000,000 bits, and 256 times the initial work
/// precision for a larger precision (twelve refinement steps grow the work by
/// about 130 times, so the unbounded mode always reaches past the default).
/// The cap stays below 1,000,000,000 so the next work precision fits `Int32`.
pub fn certified_unbounded_work_cap(initial_precision : Int32) -> Int32 {
  let wide = Int64::max(8000000L, 256L * initial_precision.to_int64())
  Int64::min(wide, 1000000000L).to_int()
}

///|
/// Whether a hand-written refinement loop may run another step. `limit` is the
/// refinement limit of the context: `Some(n)` allows `n` steps (at least one);
/// `None` has no count limit and stops at `certified_unbounded_work_cap` of the
/// context precision.
pub fn certified_refinement_continues(
  limit : Int32?,
  attempt : Int32,
  work : Int32,
  precision : Int32,
) -> Bool {
  match limit {
    Some(count) => attempt < Int32::max(1, count)
    None => work <= certified_unbounded_work_cap(precision)
  }
}

///|
pub fn CertifiedRefinementBudget::new(
  initial_precision : Int32,
  limit~ : Int32? = Some(12),
) -> CertifiedRefinementBudget {
  let work = Int32::max(1, initial_precision)
  {
    work_precision: work,
    refinements_: 0,
    limit_: match limit {
      Some(count) => Some(Int32::max(1, count))
      None => None
    },
    cap_: certified_unbounded_work_cap(work),
  }
}

///|
pub fn CertifiedRefinementBudget::available(
  self : CertifiedRefinementBudget,
) -> Bool {
  match self.limit_ {
    Some(count) => self.refinements_ < count
    None => self.work_precision <= self.cap_
  }
}

///|
pub fn CertifiedRefinementBudget::precision(
  self : CertifiedRefinementBudget,
) -> Int32 {
  self.work_precision
}

///|
pub fn CertifiedRefinementBudget::refinements(
  self : CertifiedRefinementBudget,
) -> Int32 {
  self.refinements_
}

///|
pub fn CertifiedRefinementBudget::next(
  self : CertifiedRefinementBudget,
) -> CertifiedRefinementBudget {
  {
    work_precision: self.work_precision +
    Int32::max(32, self.work_precision / 2),
    refinements_: self.refinements_ + 1,
    limit_: self.limit_,
    cap_: self.cap_,
  }
}

///|
pub fn certified_failure(
  operation : String,
  stage : @def.CertificationStage,
  reason : @def.CertificationFailureReason,
  target_precision : Int32,
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
