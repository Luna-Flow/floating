///|
fn exact_rat_gcd(left : BigInt, right : BigInt) -> BigInt {
  let mut left = abs_bigint(left)
  let mut right = abs_bigint(right)
  while !right.is_zero() {
    let remainder = left % right
    left = right
    right = remainder
  }
  if left.is_zero() {
    1N
  } else {
    left
  }
}

///|
pub struct ExactRat {
  priv numerator : BigInt
  priv denominator : BigInt
} derive(Eq)

///|
pub fn ExactRat::new(numerator : BigInt, denominator : BigInt) -> ExactRat {
  guard !denominator.is_zero() else {
    abort("exact rational denominator must be non-zero")
  }
  let (numerator, denominator) = if denominator < 0N {
    (-numerator, -denominator)
  } else {
    (numerator, denominator)
  }
  if numerator.is_zero() {
    return { numerator: 0N, denominator: 1N }
  }
  let divisor = exact_rat_gcd(numerator, denominator)
  { numerator: numerator / divisor, denominator: denominator / divisor }
}

///|
pub fn ExactRat::numerator(self : ExactRat) -> BigInt {
  self.numerator
}

///|
pub fn ExactRat::denominator(self : ExactRat) -> BigInt {
  self.denominator
}
