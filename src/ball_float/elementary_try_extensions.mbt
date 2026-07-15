///|
fn BallFloat::try_certified_monotone(
  self : BallFloat,
  increasing : Bool,
  evaluate : (@bin_float.BinFloat, @bin_float.BinaryContext) -> Result[
    (@bin_float.BinFloat, @bin_float.BinaryFlags),
    @def.ArithmeticError,
  ],
) -> Result[BallFloat, @def.ArithmeticError] {
  if self.is_empty() {
    return Ok(self)
  }
  let downward = @bin_float.BinaryContext::unbounded(
    self.precision_,
    rounding=@bin_float.BinaryRoundingMode::RoundTowardNegative,
  )
  let upward = @bin_float.BinaryContext::unbounded(
    self.precision_,
    rounding=@bin_float.BinaryRoundingMode::RoundTowardPositive,
  )
  let lower_source = if increasing { self.lo_ } else { self.hi_ }
  let upper_source = if increasing { self.hi_ } else { self.lo_ }
  evaluate(lower_source, downward).bind(fn(lower) {
    evaluate(upper_source, upward).map(fn(upper) {
      store_interval(lower.0, upper.0, self.precision_)
    })
  })
}

///|
fn BallFloat::unit_domain(self : BallFloat) -> BallFloat {
  let one = @bin_float.BinFloat::one(precision=self.precision_)
  self.intersection(store_interval(one.neg(), one, self.precision_))
}

///|
pub fn BallFloat::try_asin_interval(
  self : BallFloat,
) -> Result[BallFloat, @def.ArithmeticError] {
  self
  .unit_domain()
  .try_certified_monotone(true, fn(value, context) {
    value.try_asin_ctx(context)
  })
}

///|
pub fn BallFloat::try_acos_interval(
  self : BallFloat,
) -> Result[BallFloat, @def.ArithmeticError] {
  self
  .unit_domain()
  .try_certified_monotone(false, fn(value, context) {
    value.try_acos_ctx(context)
  })
}

///|
pub fn BallFloat::try_atan_interval(
  self : BallFloat,
) -> Result[BallFloat, @def.ArithmeticError] {
  self.try_certified_monotone(true, fn(value, context) {
    value.try_atan_ctx(context)
  })
}

///|
fn try_certified_atan2_point(
  ordinate : @bin_float.BinFloat,
  abscissa : @bin_float.BinFloat,
  precision : Int,
) -> Result[BallFloat, @def.ArithmeticError] {
  if ordinate.is_zero() && abscissa.is_zero() {
    return Ok(empty_interval(precision))
  }
  let downward = @bin_float.BinaryContext::unbounded(
    precision,
    rounding=@bin_float.BinaryRoundingMode::RoundTowardNegative,
  )
  let upward = @bin_float.BinaryContext::unbounded(
    precision,
    rounding=@bin_float.BinaryRoundingMode::RoundTowardPositive,
  )
  ordinate
  .try_atan2_ctx(abscissa, downward)
  .bind(fn(lower) {
    ordinate
    .try_atan2_ctx(abscissa, upward)
    .map(fn(upper) { store_interval(lower.0, upper.0, precision) })
  })
}

///|
pub fn BallFloat::try_atan2_interval(
  self : BallFloat,
  abscissa : BallFloat,
) -> Result[BallFloat, @def.ArithmeticError] {
  let precision = Int::max(self.precision_, abscissa.precision_)
  if self.is_empty() || abscissa.is_empty() {
    return Ok(empty_interval(precision))
  }
  if self.is_singleton() &&
    self.contains_zero() &&
    abscissa.is_singleton() &&
    abscissa.contains_zero() {
    return Ok(empty_interval(precision))
  }
  let zero = @bin_float.BinFloat::zero(precision~)
  if abscissa.lo_.compare(zero) < 0 &&
    self.lo_.compare(zero) < 0 &&
    self.hi_.compare(zero) >= 0 {
    let pi = certified_pi_interval(precision)
    return Ok(store_interval(pi.hi_.neg(), pi.hi_, precision))
  }
  try_certified_atan2_point(self.lo_, abscissa.lo_, precision).bind(fn(
    lower_lower,
  ) {
    try_certified_atan2_point(self.lo_, abscissa.hi_, precision).bind(fn(
      lower_upper,
    ) {
      try_certified_atan2_point(self.hi_, abscissa.lo_, precision).bind(fn(
        upper_lower,
      ) {
        try_certified_atan2_point(self.hi_, abscissa.hi_, precision).bind(fn(
          upper_upper,
        ) {
          let mut result = include_angle_hull(lower_lower, lower_upper)
          result = include_angle_hull(result, upper_lower)
          result = include_angle_hull(result, upper_upper)
          let ordinate_axis = if abscissa.contains_zero() &&
            self.hi_.compare(zero) > 0 {
            try_certified_atan2_point(self.hi_, zero, precision)
          } else {
            Ok(empty_interval(precision))
          }
          ordinate_axis.bind(fn(positive_axis) {
            result = include_angle_hull(result, positive_axis)
            let negative_axis = if abscissa.contains_zero() &&
              self.lo_.compare(zero) < 0 {
              try_certified_atan2_point(self.lo_, zero, precision)
            } else {
              Ok(empty_interval(precision))
            }
            negative_axis.bind(fn(negative_axis) {
              result = include_angle_hull(result, negative_axis)
              let positive_abscissa = if self.contains_zero() &&
                abscissa.hi_.compare(zero) > 0 {
                try_certified_atan2_point(zero, abscissa.hi_, precision)
              } else {
                Ok(empty_interval(precision))
              }
              positive_abscissa.bind(fn(positive_abscissa) {
                result = include_angle_hull(result, positive_abscissa)
                let negative_abscissa = if self.contains_zero() &&
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

///|
pub fn BallFloat::try_sinh_interval(
  self : BallFloat,
) -> Result[BallFloat, @def.ArithmeticError] {
  self.try_certified_monotone(true, fn(value, context) {
    value.try_sinh_ctx(context)
  })
}

///|
pub fn BallFloat::try_cosh_interval(
  self : BallFloat,
) -> Result[BallFloat, @def.ArithmeticError] {
  self
  .abs()
  .try_certified_monotone(true, fn(value, context) {
    value.try_cosh_ctx(context)
  })
}

///|
pub fn BallFloat::try_tanh_interval(
  self : BallFloat,
) -> Result[BallFloat, @def.ArithmeticError] {
  self.try_certified_monotone(true, fn(value, context) {
    value.try_tanh_ctx(context)
  })
}

///|
pub fn BallFloat::try_asinh_interval(
  self : BallFloat,
) -> Result[BallFloat, @def.ArithmeticError] {
  self.try_certified_monotone(true, fn(value, context) {
    value.try_asinh_ctx(context)
  })
}

///|
pub fn BallFloat::try_acosh_interval(
  self : BallFloat,
) -> Result[BallFloat, @def.ArithmeticError] {
  if self.is_empty() {
    return Ok(self)
  }
  let one = @bin_float.BinFloat::one(precision=self.precision_)
  if self.hi_.compare(one) < 0 {
    return Ok(empty_interval(self.precision_))
  }
  let restricted = self.intersection(
    store_interval(one, pos_inf(self.precision_), self.precision_),
  )
  restricted.try_certified_monotone(true, fn(value, context) {
    value.try_acosh_ctx(context)
  })
}

///|
pub fn BallFloat::try_atanh_interval(
  self : BallFloat,
) -> Result[BallFloat, @def.ArithmeticError] {
  if self.is_empty() {
    return Ok(self)
  }
  let one = @bin_float.BinFloat::one(precision=self.precision_)
  let minus_one = one.neg()
  if self.hi_.compare(minus_one) < 0 || self.lo_.compare(one) > 0 {
    return Ok(empty_interval(self.precision_))
  }
  let restricted = self.intersection(
    store_interval(minus_one, one, self.precision_),
  )
  restricted.try_certified_monotone(true, fn(value, context) {
    value.try_atanh_ctx(context)
  })
}
