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
  precision : Int32,
) -> Result[BallFloat, @def.ArithmeticError] {
  let ordinate = canonical_interval_endpoint(ordinate, precision)
  let abscissa = canonical_interval_endpoint(abscissa, precision)
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
/// Corner of the box `[ordinate] x [abscissa]` at which `atan2(y, x)` attains
/// its minimum (`upper = false`) or maximum (`upper = true`), as `(y, x)`.
/// Returns `None` when that corner is the origin (degenerate boxes), where the
/// caller falls back to the general corner hull.
///
/// Monotonicity argument. Away from the origin and the branch cut,
/// `d atan2 / dy = x / r^2` and `d atan2 / dx = -y / r^2`, so for fixed `x`
/// the angle is nondecreasing in `y` iff `x >= 0` (constant when `x = 0`), and
/// for fixed `y` it is nonincreasing in `x` iff `y >= 0`. The caller has
/// excluded the cut crossing (`x.lo < 0` with `y.lo < 0 <= y.hi`), so a `y`
/// endpoint equal to zero belongs to the side of the other endpoint: the value
/// `atan2(+0, x < 0) = pi` is the limit from `y > 0`, and `atan2(0, x > 0) = 0`
/// is the limit from `y < 0`. Hence every edge of the box is monotone and the
/// extrema over the whole box are attained at corners, one per bound:
/// - `y >= 0` (Pos): the angle is nonincreasing in `x`, so the minimum has
///   `x = x.hi` and the maximum `x = x.lo`; at that `x` the `y` direction is
///   fixed by its sign (`x = 0`: constant, take the nonzero `y.hi`).
/// - `y <= 0`, `y.lo < 0` (Neg): the angle is nondecreasing in `x`, minimum at
///   `x.lo`, maximum at `x.hi`; the `y` direction is as above (`x = 0`: take
///   `y.lo`).
/// - `y.lo < 0 < y.hi` (Mixed): the early return leaves `x.lo >= 0`, so the
///   angle is nondecreasing in `y` (minimum `y.lo`, maximum `y.hi`) and, at
///   `y.lo < 0` nondecreasing in `x`, at `y.hi > 0` nonincreasing: both bounds
///   sit at `x.lo`.
/// Axis points of the general algorithm lie between these extremes.
fn atan2_extreme_corner(
  ordinate : BallFloat,
  abscissa : BallFloat,
  upper : Bool,
) -> (@bin_float.BinFloat, @bin_float.BinFloat)? {
  let zero = @bin_float.BinFloat::zero(precision=ordinate.precision_)
  let yl = ordinate.lo_
  let yh = ordinate.hi_
  let xl = abscissa.lo_
  let xh = abscissa.hi_
  let (y, x) = if yl.compare(zero) >= 0 {
    let x = if upper { xl } else { xh }
    let c = x.compare(zero)
    let y = if c == 0 { yh } else if (c > 0) == upper { yh } else { yl }
    (y, x)
  } else if yh.compare(zero) <= 0 {
    let x = if upper { xh } else { xl }
    let c = x.compare(zero)
    let y = if c == 0 { yl } else if (c > 0) == upper { yh } else { yl }
    (y, x)
  } else if upper {
    (yh, xl)
  } else {
    (yl, xl)
  }
  if y.is_zero() && x.is_zero() {
    None
  } else {
    Some((y, x))
  }
}

///|
pub fn BallFloat::try_atan2_interval(
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
  let abscissa_box = store_interval(
    canonical_interval_endpoint(abscissa.lo_, precision),
    canonical_interval_endpoint(abscissa.hi_, precision),
    precision,
  )
  let zero = @bin_float.BinFloat::zero(precision~)
  let crossing = abscissa_box.lo_.compare(zero) < 0 &&
    ordinate.lo_.compare(zero) < 0 &&
    ordinate.hi_.compare(zero) >= 0
  if !crossing {
    match
      (
        atan2_extreme_corner(ordinate, abscissa_box, false),
        atan2_extreme_corner(ordinate, abscissa_box, true),
      ) {
      (Some((ly, lx)), Some((uy, ux))) => {
        let downward = @bin_float.BinaryContext::unbounded(
          precision,
          rounding=@bin_float.BinaryRoundingMode::RoundTowardNegative,
        )
        let upward = @bin_float.BinaryContext::unbounded(
          precision,
          rounding=@bin_float.BinaryRoundingMode::RoundTowardPositive,
        )
        return ly
          .try_atan2_ctx(lx, downward)
          .bind(fn(lower) {
            uy
            .try_atan2_ctx(ux, upward)
            .map(fn(upper) { store_interval(lower.0, upper.0, precision) })
          })
      }
      _ => ()
    }
  }
  self.try_atan2_interval_corners(abscissa)
}

///|
/// General corner-and-axis hull; the fallback for degenerate boxes.
fn BallFloat::try_atan2_interval_corners(
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

///|
/// Direction of a sine-like function on an interval that contains no extremum.
/// `lo_index` and `hi_index` are `ceil(q(lo))` and `floor(q(hi))` for the
/// quotient `q` in quarter turns; `shift` is 0 for sine and 1 for cosine
/// (`cos x = sin(x + pi/2)` moves every index by one). The caller guarantees
/// that no index with sine residue 1 or 3 lies in the range, so the interval
/// stays inside one arc between two consecutive extrema. If an integer index
/// is in the range it is a zero crossing: sine increases through residue 0 and
/// decreases through residue 2. Otherwise the interval lies strictly inside
/// the arc `[k, k + 1)` with `k = lo_index - 1`, and sine increases on arcs of
/// residue 0 and 3, decreases on 1 and 2.
fn trig_arc_increasing(
  lo_index : SignedBinCoeff,
  hi_index : SignedBinCoeff,
  shift : Int32,
) -> Bool {
  if signed_coeff_compare(lo_index, hi_index) <= 0 {
    (signed_coeff_mod4(lo_index) + shift) % 4 == 0
  } else {
    let arc = (
        signed_coeff_mod4(signed_coeff_sub(lo_index, signed_coeff_from_int(1))) +
        shift
      ) %
      4
    arc == 0 || arc == 3
  }
}

///|
/// Hull of a sine-like function over `self` from correctly rounded endpoint
/// values, given the critical index range `indices` (see
/// `trig_arc_increasing`). A bound is `-1` / `1` when an extremum lies inside;
/// otherwise it is a directed endpoint value. With no extremum inside the
/// function is monotone, so each bound needs one evaluation (lower from the
/// lower end of the arc direction, upper from the other). With one extremum of
/// the opposite kind inside, the other bound is the best of both endpoints.
/// Directed rounding is monotone, so these equal the min/max over all four
/// directed endpoint values that the previous code evaluated.
fn BallFloat::try_sine_like_hull(
  self : BallFloat,
  indices : (SignedBinCoeff, SignedBinCoeff),
  shift : Int32,
  evaluate : (@bin_float.BinFloat, @bin_float.BinaryContext) -> Result[
    (@bin_float.BinFloat, @bin_float.BinaryFlags),
    @def.ArithmeticError,
  ],
) -> Result[BallFloat, @def.ArithmeticError] {
  let precision = self.precision_
  let has_min = index_range_contains_residue(indices.0, indices.1, 3 - shift)
  let has_max = index_range_contains_residue(indices.0, indices.1, 1 - shift)
  let downward = @bin_float.BinaryContext::unbounded(
    precision,
    rounding=@bin_float.BinaryRoundingMode::RoundTowardNegative,
  )
  let upward = @bin_float.BinaryContext::unbounded(
    precision,
    rounding=@bin_float.BinaryRoundingMode::RoundTowardPositive,
  )
  let increasing = has_min ||
    has_max ||
    trig_arc_increasing(indices.0, indices.1, shift)
  let lower = if has_min {
    @bin_float.BinFloat::from_int(-1, precision~)
  } else if has_max {
    match evaluate(self.lo_, downward) {
      Ok(a) =>
        match evaluate(self.hi_, downward) {
          Ok(b) => bin_min(a.0, b.0)
          Err(e) => return Err(e)
        }
      Err(e) => return Err(e)
    }
  } else {
    match evaluate(if increasing { self.lo_ } else { self.hi_ }, downward) {
      Ok(a) => a.0
      Err(e) => return Err(e)
    }
  }
  let upper = if has_max {
    @bin_float.BinFloat::one(precision~)
  } else if has_min {
    match evaluate(self.lo_, upward) {
      Ok(a) =>
        match evaluate(self.hi_, upward) {
          Ok(b) => bin_max(a.0, b.0)
          Err(e) => return Err(e)
        }
      Err(e) => return Err(e)
    }
  } else {
    match evaluate(if increasing { self.hi_ } else { self.lo_ }, upward) {
      Ok(a) => a.0
      Err(e) => return Err(e)
    }
  }
  Ok(store_interval(lower, upper, precision))
}
