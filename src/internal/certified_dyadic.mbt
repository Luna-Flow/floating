///|
pub struct CertifiedDyadic {
  numerator_ : BigInt
  scale_ : Int
}

///|
pub fn CertifiedDyadic::new(numerator : BigInt, scale : Int) -> CertifiedDyadic {
  guard scale >= 0 else { abort("certified dyadic scale must be non-negative") }
  { numerator_: numerator, scale_: scale }
}

///|
pub fn CertifiedDyadic::from_int(value : Int) -> CertifiedDyadic {
  CertifiedDyadic::new(BigInt::from_int(value), 0)
}

///|
pub fn CertifiedDyadic::numerator(self : CertifiedDyadic) -> BigInt {
  self.numerator_
}

///|
pub fn CertifiedDyadic::scale(self : CertifiedDyadic) -> Int {
  self.scale_
}

///|
pub fn CertifiedDyadic::compare(
  self : CertifiedDyadic,
  other : CertifiedDyadic,
) -> Int {
  let scale = Int::max(self.scale_, other.scale_)
  let left = self.numerator_ << (scale - self.scale_)
  let right = other.numerator_ << (scale - other.scale_)
  left.compare(right)
}

///|
pub fn CertifiedDyadic::neg(self : CertifiedDyadic) -> CertifiedDyadic {
  CertifiedDyadic::new(-self.numerator_, self.scale_)
}

///|
pub fn CertifiedDyadic::add(
  self : CertifiedDyadic,
  other : CertifiedDyadic,
) -> CertifiedDyadic {
  let scale = Int::max(self.scale_, other.scale_)
  CertifiedDyadic::new(
    (self.numerator_ << (scale - self.scale_)) +
    (other.numerator_ << (scale - other.scale_)),
    scale,
  )
}

///|
pub fn CertifiedDyadic::sub(
  self : CertifiedDyadic,
  other : CertifiedDyadic,
) -> CertifiedDyadic {
  self.add(other.neg())
}

///|
pub fn CertifiedDyadic::mul(
  self : CertifiedDyadic,
  other : CertifiedDyadic,
) -> CertifiedDyadic {
  CertifiedDyadic::new(
    self.numerator_ * other.numerator_,
    self.scale_ + other.scale_,
  )
}

///|
fn certified_floor_ratio(numerator : BigInt, denominator : BigInt) -> BigInt {
  guard denominator > BigInt::from_int(0) else {
    abort("certified ratio denominator must be positive")
  }
  if numerator >= BigInt::from_int(0) {
    numerator / denominator
  } else {
    let magnitude = -numerator
    -((magnitude + denominator - BigInt::from_int(1)) / denominator)
  }
}

///|
fn certified_ceil_ratio(numerator : BigInt, denominator : BigInt) -> BigInt {
  -certified_floor_ratio(-numerator, denominator)
}

///|
pub fn CertifiedDyadic::round_down(
  self : CertifiedDyadic,
  scale : Int,
) -> CertifiedDyadic {
  guard scale >= 0 else { abort("certified dyadic scale must be non-negative") }
  if scale >= self.scale_ {
    CertifiedDyadic::new(self.numerator_ << (scale - self.scale_), scale)
  } else {
    CertifiedDyadic::new(
      certified_floor_ratio(
        self.numerator_,
        BigInt::from_int(1) << (self.scale_ - scale),
      ),
      scale,
    )
  }
}

///|
pub fn CertifiedDyadic::round_up(
  self : CertifiedDyadic,
  scale : Int,
) -> CertifiedDyadic {
  guard scale >= 0 else { abort("certified dyadic scale must be non-negative") }
  if scale >= self.scale_ {
    CertifiedDyadic::new(self.numerator_ << (scale - self.scale_), scale)
  } else {
    CertifiedDyadic::new(
      certified_ceil_ratio(
        self.numerator_,
        BigInt::from_int(1) << (self.scale_ - scale),
      ),
      scale,
    )
  }
}

///|
pub fn certified_dyadic_fraction(
  numerator : BigInt,
  denominator : BigInt,
  scale : Int,
) -> Result[CertifiedInterval[CertifiedDyadic], @def.ArithmeticError] {
  guard denominator > BigInt::from_int(0) else {
    return Err(
      @def.ArithmeticError::domain_error("dyadic denominator must be positive"),
    )
  }
  let scaled = numerator << scale
  CertifiedInterval::new(
    CertifiedDyadic::new(certified_floor_ratio(scaled, denominator), scale),
    CertifiedDyadic::new(certified_ceil_ratio(scaled, denominator), scale),
    fn(left, right) { left.compare(right) },
  )
}

///|
pub fn certified_dyadic_div(
  numerator : CertifiedDyadic,
  denominator : CertifiedDyadic,
  scale : Int,
) -> Result[CertifiedInterval[CertifiedDyadic], @def.ArithmeticError] {
  guard denominator.numerator_ != BigInt::from_int(0) else {
    return Err(
      @def.ArithmeticError::division_by_zero(
        "certified dyadic division by zero",
      ),
    )
  }
  let signed_numerator = if denominator.numerator_ < BigInt::from_int(0) {
    -numerator.numerator_
  } else {
    numerator.numerator_
  }
  let positive_denominator = if denominator.numerator_ < BigInt::from_int(0) {
    -denominator.numerator_
  } else {
    denominator.numerator_
  }
  certified_dyadic_fraction(
    signed_numerator << denominator.scale_,
    positive_denominator << numerator.scale_,
    scale,
  )
}
