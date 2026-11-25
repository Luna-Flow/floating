///|
// oracle: A,S
// source: atan(0) = 0 is written out (the point 0); atan(1) = pi / 4 is compared with the interval [RD(pi / 4), RU(pi / 4)] at 53 bits of ref_pi_ratio(1, 4, 53) (tools/interval_pi_oracle.py, Machin's formula in Python integers); the oddness atan(-x) = -atan(x) is a self-consistency check (level S)
// shares: Interval::from_double builds the inputs; Interval::neg and equal compare; ref_pi_ratio reads the generated table of pi
test "certified atan contains exact origin and odd symmetry" {
  let zero = Interval::from_double(0.0, precision=53).atan()
  assert_true(zero.is_member(@binary.Binary::zero()))
  // atan(0) = 0 exactly: the tightest interval is the point 0
  assert_true(zero.lower_bound().is_zero() && zero.upper_bound().is_zero())
  let positive = Interval::from_double(1.0, precision=53).atan()
  let negative = Interval::from_double(-1.0, precision=53).atan()
  assert_true(positive.neg().equal(negative))
  // atan(1) = pi / 4: the tightest interval at 53 bits is [RD(pi / 4), RU(pi / 4)]
  let quarter = ref_pi_ratio(1, 4, 53)
  assert_true(positive.equal(quarter))
}
