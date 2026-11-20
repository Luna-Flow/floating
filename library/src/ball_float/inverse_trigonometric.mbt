///|
/// Total: the `try_atan` form, or the range of the function when the kernel cannot
/// certify a bound (issue 449).
pub fn BallFloat::atan(self : BallFloat) -> BallFloat {
  match self.try_atan() {
    Ok(result) => result
    Err(_) => half_pi_range(self.precision_)
  }
}

///|
/// Total: the `try_asin` form, or the range of the function when the kernel cannot
/// certify a bound (issue 449).
pub fn BallFloat::asin(self : BallFloat) -> BallFloat {
  match self.try_asin() {
    Ok(result) => result
    Err(_) => half_pi_range(self.precision_)
  }
}

///|
/// Total: the `try_acos` form, or the range of the function when the kernel cannot
/// certify a bound (issue 449).
pub fn BallFloat::acos(self : BallFloat) -> BallFloat {
  match self.try_acos() {
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
pub fn BallFloat::atan2(self : BallFloat, abscissa : BallFloat) -> BallFloat {
  let precision = Int32::max(self.precision_, abscissa.precision_)
  match self.try_atan2(abscissa) {
    Ok(result) => result
    Err(_) => {
      let pi = certified_pi_interval(precision)
      store_interval(pi.hi_.neg(), pi.hi_, precision)
    }
  }
}
