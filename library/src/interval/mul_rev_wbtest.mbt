///|
fn rev_box(lo : Double, hi : Double) -> Interval {
  Interval::from_bounds(
    @binary.Binary::from_double(lo),
    @binary.Binary::from_double(hi),
  )
}

///|
let rev_inf : Double = 1.0 / 0.0

///|
let rev_ninf : Double = -1.0 / 0.0

///|
fn rev_dec(lo : Double, hi : Double, d : Decoration) -> DecoratedInterval {
  DecoratedInterval::new(rev_box(lo, hi), decoration=d)
}

///|
/// The six examples of IEEE 1788-2015 10.5.5, with the components closed as
/// `mulRevToPair` returns them.
test "mul_rev_to_pair: the examples of 10.5.5" {
  let empty = Interval::empty()
  // [1, 2] /set [0, 0] = empty
  let (u, v) = rev_box(0.0, 0.0).mul_rev_to_pair(rev_box(1.0, 2.0))
  assert_true(u.is_empty() && v.is_empty())
  // [0, 2] /set [0, 0] = Entire
  let (u, v) = rev_box(0.0, 0.0).mul_rev_to_pair(rev_box(0.0, 2.0))
  assert_true(u.is_entire() && v.is_empty())
  // [1, 2] /set [1, 1] = [1, 2]
  let (u, v) = rev_box(1.0, 1.0).mul_rev_to_pair(rev_box(1.0, 2.0))
  assert_true(u == rev_box(1.0, 2.0) && v == empty)
  // [1, 1] /set [1, +inf) = (0, 1]: the closure [0, 1]
  let (u, v) = rev_box(1.0, rev_inf).mul_rev_to_pair(rev_box(1.0, 1.0))
  assert_true(u == rev_box(0.0, 1.0) && v == empty)
  // [1, 2] /set [-1, 1] = (-inf, -1] U [1, +inf)
  let (u, v) = rev_box(-1.0, 1.0).mul_rev_to_pair(rev_box(1.0, 2.0))
  assert_true(u == rev_box(rev_ninf, -1.0) && v == rev_box(1.0, rev_inf))
  // [1, 1] /set Entire = (-inf, 0) U (0, +inf): the closures share 0
  let (u, v) = Interval::entire().mul_rev_to_pair(rev_box(1.0, 1.0))
  assert_true(u == rev_box(rev_ninf, 0.0) && v == rev_box(0.0, rev_inf))
  // empty operands
  let (u, v) = empty.mul_rev_to_pair(rev_box(1.0, 2.0))
  assert_true(u.is_empty() && v.is_empty())
  let (u, v) = rev_box(1.0, 2.0).mul_rev_to_pair(empty)
  assert_true(u.is_empty() && v.is_empty())
}

///|
test "mul_rev_to_pair: the two components are ordered, whichever side of zero c lies" {
  // c > 0, b = [-2, 4]: x <= 3 / -2 = -1.5 or x >= 3 / 4
  let (u, v) = rev_box(-2.0, 4.0).mul_rev_to_pair(rev_box(3.0, 5.0))
  assert_true(u == rev_box(rev_ninf, -1.5))
  assert_true(v == rev_box(0.75, rev_inf))
  // c < 0: x <= -3 / 4 = -0.75 or x >= -3 / -2 = 1.5
  let (u, v) = rev_box(-2.0, 4.0).mul_rev_to_pair(rev_box(-5.0, -3.0))
  assert_true(u == rev_box(rev_ninf, -0.75))
  assert_true(v == rev_box(1.5, rev_inf))
  // 0 is a bound of b: one component
  let (u, v) = rev_box(0.0, 4.0).mul_rev_to_pair(rev_box(3.0, 5.0))
  assert_true(u == rev_box(0.75, rev_inf) && v.is_empty())
  let (u, v) = rev_box(-2.0, 0.0).mul_rev_to_pair(rev_box(3.0, 5.0))
  assert_true(u == rev_box(rev_ninf, -1.5) && v.is_empty())
}

///|
test "mul_rev: the hull is taken of the set, which is not the intersection of the hull" {
  // [-1, 1] /set [1, 1] = (-inf, -1] U [1, +inf); the prior [0, 0.5] meets it
  // in nothing, although hull(c /set b) = Entire contains the prior
  let b = rev_box(-1.0, 1.0)
  let c = rev_box(1.0, 1.0)
  assert_true(b.mul_rev(c) == Interval::entire())
  assert_true(b.mul_rev(c, x=rev_box(0.0, 0.5)).is_empty())
  // the prior picks one component
  assert_true(b.mul_rev(c, x=rev_box(0.5, 3.0)) == rev_box(1.0, 3.0))
  // both components: the hull of the two intersections
  assert_true(b.mul_rev(c, x=rev_box(-3.0, 3.0)) == rev_box(-3.0, 3.0))
  assert_true(b.mul_rev(c, x=rev_box(-3.0, -2.0)) == rev_box(-3.0, -2.0))
}

///|
test "mul_rev: a component open at 0 is not met by a prior that only touches 0" {
  // [1, 1] /set [1, +inf) = (0, 1]: 0 is never attained
  let b = rev_box(1.0, rev_inf)
  let c = rev_box(1.0, 1.0)
  assert_true(b.mul_rev(c) == rev_box(0.0, 1.0))
  assert_true(b.mul_rev(c, x=rev_box(-1.0, 0.0)).is_empty())
  assert_true(b.mul_rev(c, x=rev_box(0.0, 0.0)).is_empty())
  assert_true(b.mul_rev(c, x=rev_box(0.0, 0.5)) == rev_box(0.0, 0.5))
  // when 0 is in c, x = 0 is attained and the bound is closed
  let c0 = rev_box(0.0, 1.0)
  assert_true(
    rev_box(1.0, rev_inf).mul_rev(c0, x=rev_box(-1.0, 0.0)) == rev_box(0.0, 0.0),
  )
  // an unbounded divisor on the negative side
  let neg_b = rev_box(rev_ninf, -1.0)
  assert_true(neg_b.mul_rev(rev_box(1.0, 1.0), x=rev_box(0.0, 1.0)).is_empty())
  assert_true(
    neg_b.mul_rev(rev_box(1.0, 1.0), x=rev_box(-2.0, 0.0)) == rev_box(-1.0, 0.0),
  )
}

///|
test "decorated mul_rev_to_pair follows 12.12.3 and mul_rev is trivially decorated (11.7.1)" {
  // 0 not in b: u is the decorated quotient c / b, v is Empty and trv
  let (u, v) = rev_dec(1.0, 2.0, Com).mul_rev_to_pair(rev_dec(2.0, 4.0, Com))
  assert_true(u.interval() == rev_box(1.0, 4.0))
  assert_eq(u.decoration(), Com)
  assert_true(v.is_empty())
  assert_eq(v.decoration(), Trv)
  // the quotient keeps the min-rule with the input decorations
  let (u, _) = rev_dec(1.0, 2.0, Def).mul_rev_to_pair(rev_dec(2.0, 4.0, Com))
  assert_eq(u.decoration(), Def)
  // 0 in b: every output is trv
  let (u, v) = rev_dec(-1.0, 1.0, Com).mul_rev_to_pair(rev_dec(1.0, 2.0, Com))
  assert_eq(u.decoration(), Trv)
  assert_eq(v.decoration(), Trv)
  assert_false(v.is_empty())
  // an empty input: trv outputs
  let (u, v) = DecoratedInterval::new(Interval::empty()).mul_rev_to_pair(
    rev_dec(1.0, 2.0, Com),
  )
  assert_true(u.is_empty() && v.is_empty())
  assert_eq(u.decoration(), Trv)
  // NaI gives NaI twice
  let nai = DecoratedInterval::nai()
  let (u, v) = nai.mul_rev_to_pair(rev_dec(1.0, 2.0, Com))
  assert_true(u.is_nai() && v.is_nai())
  let (u, v) = rev_dec(1.0, 2.0, Com).mul_rev_to_pair(nai)
  assert_true(u.is_nai() && v.is_nai())
  // mul_rev: the interval part is the bare result, decorated trv
  let r = rev_dec(1.0, 2.0, Com).mul_rev(rev_dec(2.0, 4.0, Com))
  assert_true(r.interval() == rev_box(1.0, 4.0))
  assert_eq(r.decoration(), Trv)
  let with_prior = rev_dec(-1.0, 1.0, Com).mul_rev(
    rev_dec(1.0, 1.0, Com),
    x=rev_dec(0.5, 3.0, Com),
  )
  assert_true(with_prior.interval() == rev_box(1.0, 3.0))
  assert_true(nai.mul_rev(rev_dec(1.0, 2.0, Com)).is_nai())
  assert_true(
    rev_dec(1.0, 2.0, Com).mul_rev(rev_dec(1.0, 2.0, Com), x=nai).is_nai(),
  )
}

///|
test "mul_rev: results enclose c /set b at a small precision" {
  // 1 / 3 is not representable: the lower bound rounds down
  let b = Interval::from_bounds(
    @binary.Binary::from_int(-3, precision=8),
    @binary.Binary::from_int(3, precision=8),
    precision=8,
  )
  let c = Interval::from_int(1, precision=8)
  let (u, v) = b.mul_rev_to_pair(c)
  let third = @binary.Binary::from_int(1, precision=64) /
    @binary.Binary::from_int(3, precision=64)
  assert_true(v.lower_bound().compare(third) <= 0)
  assert_true(u.upper_bound().compare(third.neg()) >= 0)
  assert_true(v.lower_bound().compare(@binary.Binary::zero()) > 0)
  assert_eq(v.precision(), 8)
}
