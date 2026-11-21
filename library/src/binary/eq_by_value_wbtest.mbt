// `Binary`'s `==` agrees with `compare` (S3 of the plan, as `Decimal`'s): `a == b`
// exactly when `a.compare(b) == 0`; `identical` is the structural equality and
// `compare_quiet_equal` the IEEE one.
//
// ORACLE (level A): the expected answers are written out: -0 == +0, the same number of
// different precisions equal, every NaN equal to every NaN (the documented total
// preorder), a NaN unequal to every number; the IEEE answer (a NaN unequal to itself) is
// the one of `compare_quiet_equal` (5.11), checked here too. The structural answers are
// the definition of `identical` in its comment.

///|
test "== agrees with compare: zeros, NaNs, precisions" {
  let zero = Binary::zero(precision=53)
  let negative_zero = Binary::negative_zero(precision=53)
  assert_true(zero == negative_zero)
  assert_false(zero != negative_zero)
  assert_false(zero.identical(negative_zero))
  let nan = Binary::nan(precision=53)
  assert_true(nan == nan)
  assert_false(nan != nan)
  assert_true(nan.identical(nan))
  assert_true(nan == Binary::nan(precision=24))
  // IEEE equality is compare_quiet_equal: a NaN is unordered, not equal to itself
  assert_false(nan.compare_quiet_equal(nan).0)
  assert_true(
    Binary::zero(precision=53).compare_quiet_equal(
      Binary::negative_zero(precision=53),
    ).0,
  )
  assert_false(nan == Binary::one(precision=53))
  let one_53 = Binary::one(precision=53)
  let one_24 = Binary::one(precision=24)
  assert_true(one_53 == one_24)
  assert_false(one_53.identical(one_24))
  assert_true(
    Binary::from_int(3, precision=53) ==
    Binary::make(BinCoeff::from_uint64(12UL), -2, 7),
  )
  let positive_infinity = Binary::inf(precision=53)
  assert_true(positive_infinity == Binary::inf(precision=24))
  assert_false(positive_infinity == Binary::inf(negative=true, precision=53))
  assert_false(positive_infinity == Binary::from_int(1, precision=53))
  assert_false(Binary::from_int(2, precision=53) == one_53)
}

///|
test "identical distinguishes the sign of zero, the precision and the NaN kind" {
  let a = Binary::from_int(5, precision=53)
  assert_true(a.identical(Binary::from_int(5, precision=53)))
  assert_false(a.identical(Binary::from_int(5, precision=24)))
  assert_false(a.identical(Binary::from_int(6, precision=53)))
  assert_true(
    Binary::inf(negative=true, precision=53).identical(
      Binary::inf(negative=true, precision=53),
    ),
  )
  assert_false(
    Binary::inf(negative=true, precision=53).identical(
      Binary::inf(precision=53),
    ),
  )
}

///|
test "== is compare == 0 for a grid of values, NaNs included" {
  let values = [
    Binary::nan(precision=53),
    Binary::nan(precision=24),
    Binary::inf(precision=53),
    Binary::inf(negative=true, precision=24),
    Binary::zero(precision=53),
    Binary::negative_zero(precision=24),
    Binary::one(precision=53),
    Binary::one(precision=24),
    Binary::from_int(-3, precision=53),
  ]
  for a in values {
    for b in values {
      assert_true((a == b) == (a.compare(b) == 0))
    }
  }
}

///|
test "Compare keeps its total preorder: every NaN compares equal to every NaN" {
  let nan = Binary::nan(precision=53)
  assert_true(nan.compare(nan) == 0)
  assert_true(nan.compare(Binary::one(precision=53)) > 0)
  assert_true(
    Binary::zero(precision=53).compare(Binary::negative_zero(precision=53)) == 0,
  )
}
