///|
test "exact rational constructor owns normalization invariant" {
  let rational = ExactRat::new(-6N, -8N)
  assert_eq(rational.numerator, 3N)
  assert_eq(rational.denominator, 4N)
  let zero = ExactRat::new(0N, -9N)
  assert_eq(zero.numerator, 0N)
  assert_eq(zero.denominator, 1N)
  assert_true(ExactRat::new(6N, 8N) == ExactRat::new(3N, 4N))
}
