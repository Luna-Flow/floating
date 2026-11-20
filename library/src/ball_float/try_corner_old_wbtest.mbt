// Test-only copies of the pre-#378 corner selection (equivalence oracle).

///|
fn BallFloat::try_pi_scaled_endpoint_bounds(
  self : BallFloat,
  evaluate : (@bin_float.BinFloat, @bin_float.BinaryContext) -> Result[
    (@bin_float.BinFloat, @bin_float.BinaryFlags),
    @def.ArithmeticError,
  ],
) -> Result[
  (
    @bin_float.BinFloat,
    @bin_float.BinFloat,
    @bin_float.BinFloat,
    @bin_float.BinFloat,
  ),
  @def.ArithmeticError,
] {
  let downward = @bin_float.BinaryContext::unbounded(
    self.precision_,
    rounding=@bin_float.BinaryRoundingMode::RoundTowardNegative,
  )
  let upward = @bin_float.BinaryContext::unbounded(
    self.precision_,
    rounding=@bin_float.BinaryRoundingMode::RoundTowardPositive,
  )
  evaluate(self.lo_, downward).bind(fn(lower_down) {
    evaluate(self.lo_, upward).bind(fn(lower_up) {
      evaluate(self.hi_, downward).bind(fn(upper_down) {
        evaluate(self.hi_, upward).map(fn(upper_up) {
          (lower_down.0, lower_up.0, upper_down.0, upper_up.0)
        })
      })
    })
  })
}

///|
fn BallFloat::old_try_sinpi_interval(
  self : BallFloat,
) -> Result[BallFloat, @def.ArithmeticError] {
  if self.is_empty() {
    return Ok(self)
  }
  if !self.is_common_interval() {
    return Ok(unit_interval(self.precision_))
  }
  self
  .try_pi_scaled_endpoint_bounds(fn(value, context) {
    value.try_sinpi_ctx(context)
  })
  .map(fn(bounds) {
    let indices = pi_scaled_index_range(self)
    let lower = if index_range_contains_residue(indices.0, indices.1, 3) {
      @bin_float.BinFloat::from_int(-1, precision=self.precision_)
    } else {
      bin_min(bounds.0, bounds.2)
    }
    let upper = if index_range_contains_residue(indices.0, indices.1, 1) {
      @bin_float.BinFloat::one(precision=self.precision_)
    } else {
      bin_max(bounds.1, bounds.3)
    }
    store_interval(lower, upper, self.precision_)
  })
}

///|
fn BallFloat::old_try_cospi_interval(
  self : BallFloat,
) -> Result[BallFloat, @def.ArithmeticError] {
  if self.is_empty() {
    return Ok(self)
  }
  if !self.is_common_interval() {
    return Ok(unit_interval(self.precision_))
  }
  self
  .try_pi_scaled_endpoint_bounds(fn(value, context) {
    value.try_cospi_ctx(context)
  })
  .map(fn(bounds) {
    let indices = pi_scaled_index_range(self)
    let lower = if index_range_contains_residue(indices.0, indices.1, 2) {
      @bin_float.BinFloat::from_int(-1, precision=self.precision_)
    } else {
      bin_min(bounds.0, bounds.2)
    }
    let upper = if index_range_contains_residue(indices.0, indices.1, 0) {
      @bin_float.BinFloat::one(precision=self.precision_)
    } else {
      bin_max(bounds.1, bounds.3)
    }
    store_interval(lower, upper, self.precision_)
  })
}

///|
fn BallFloat::old_try_atan2_interval(
  self : BallFloat,
  abscissa : BallFloat,
) -> Result[BallFloat, @def.ArithmeticError] {
  let precision = Int32::max(self.precision_, abscissa.precision_)
  if self.is_empty() || abscissa.is_empty() {
    return Ok(empty_interval(precision))
  }
  let ordinate = store_interval(
    canonical_interval_endpoint(self.lo_, precision),
    canonical_interval_endpoint(self.hi_, precision),
    precision,
  )
  let abscissa = store_interval(
    canonical_interval_endpoint(abscissa.lo_, precision),
    canonical_interval_endpoint(abscissa.hi_, precision),
    precision,
  )
  if ordinate.is_singleton() &&
    ordinate.contains_zero() &&
    abscissa.is_singleton() &&
    abscissa.contains_zero() {
    return Ok(empty_interval(precision))
  }
  let zero = @bin_float.BinFloat::zero(precision~)
  if abscissa.lo_.compare(zero) < 0 &&
    ordinate.lo_.compare(zero) < 0 &&
    ordinate.hi_.compare(zero) >= 0 {
    let pi = certified_pi_interval(precision)
    return Ok(store_interval(pi.hi_.neg(), pi.hi_, precision))
  }
  try_certified_atan2_point(ordinate.lo_, abscissa.lo_, precision).bind(fn(
    lower_lower,
  ) {
    try_certified_atan2_point(ordinate.lo_, abscissa.hi_, precision).bind(fn(
      lower_upper,
    ) {
      try_certified_atan2_point(ordinate.hi_, abscissa.lo_, precision).bind(fn(
        upper_lower,
      ) {
        try_certified_atan2_point(ordinate.hi_, abscissa.hi_, precision).bind(fn(
          upper_upper,
        ) {
          let mut result = include_angle_hull(lower_lower, lower_upper)
          result = include_angle_hull(result, upper_lower)
          result = include_angle_hull(result, upper_upper)
          let ordinate_axis = if abscissa.contains_zero() &&
            ordinate.hi_.compare(zero) > 0 {
            try_certified_atan2_point(ordinate.hi_, zero, precision)
          } else {
            Ok(empty_interval(precision))
          }
          ordinate_axis.bind(fn(positive_axis) {
            result = include_angle_hull(result, positive_axis)
            let negative_axis = if abscissa.contains_zero() &&
              ordinate.lo_.compare(zero) < 0 {
              try_certified_atan2_point(ordinate.lo_, zero, precision)
            } else {
              Ok(empty_interval(precision))
            }
            negative_axis.bind(fn(negative_axis) {
              result = include_angle_hull(result, negative_axis)
              let positive_abscissa = if ordinate.contains_zero() &&
                abscissa.hi_.compare(zero) > 0 {
                try_certified_atan2_point(zero, abscissa.hi_, precision)
              } else {
                Ok(empty_interval(precision))
              }
              positive_abscissa.bind(fn(positive_abscissa) {
                result = include_angle_hull(result, positive_abscissa)
                let negative_abscissa = if ordinate.contains_zero() &&
                  abscissa.lo_.compare(zero) < 0 {
                  try_certified_atan2_point(zero, abscissa.lo_, precision)
                } else {
                  Ok(empty_interval(precision))
                }
                negative_abscissa.map(fn(negative_abscissa) {
                  include_angle_hull(result, negative_abscissa)
                })
              })
            })
          })
        })
      })
    })
  })
}
