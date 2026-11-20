///|
/// Total: the `try_atan_interval` form, or the range of the function when the kernel cannot
/// certify a bound (issue 449).
pub fn BallFloat::atan_interval(self : BallFloat) -> BallFloat {
  match self.try_atan_interval() {
    Ok(result) => result
    Err(_) => half_pi_range(self.precision_)
  }
}

///|
/// Total: the `try_asin_interval` form, or the range of the function when the kernel cannot
/// certify a bound (issue 449).
pub fn BallFloat::asin_interval(self : BallFloat) -> BallFloat {
  match self.try_asin_interval() {
    Ok(result) => result
    Err(_) => half_pi_range(self.precision_)
  }
}

///|
/// Total: the `try_acos_interval` form, or the range of the function when the kernel cannot
/// certify a bound (issue 449).
pub fn BallFloat::acos_interval(self : BallFloat) -> BallFloat {
  match self.try_acos_interval() {
    Ok(result) => result
    Err(_) => pi_range(self.precision_)
  }
}

///|
fn include_angle_hull(current : BallFloat, candidate : BallFloat) -> BallFloat {
  if candidate.is_empty() {
    current
  } else if current.is_empty() {
    candidate
  } else {
    current.convex_hull(candidate)
  }
}

///|
pub fn BallFloat::atan2_interval(
  self : BallFloat,
  abscissa : BallFloat,
) -> BallFloat {
  let precision = Int32::max(self.precision_, abscissa.precision_)
  match self.try_atan2_interval(abscissa) {
    Ok(result) => result
    Err(_) => {
      let pi = certified_pi_interval(precision)
      store_interval(pi.hi_.neg(), pi.hi_, precision)
    }
  }
}
