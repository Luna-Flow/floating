///|
fn ar_box(lo : Double, hi : Double) -> Interval {
  Interval::from_bounds(
    @bin_float.BinFloat::from_double(lo),
    @bin_float.BinFloat::from_double(hi),
  )
}

///|
let ar_inf : Double = 1.0 / 0.0

///|
let ar_ninf : Double = -1.0 / 0.0

///|
test "sqr_rev: the examples of IEEE 1788-2015 10.5.4" {
  // sqrRev([1, 4]) = hull([-2, -1] U [1, 2]) = [-2, 2]
  assert_true(ar_box(1.0, 4.0).sqr_rev() == ar_box(-2.0, 2.0))
  // with the prior [0, 1.2]: [1, 1.2], tighter than intersecting afterwards
  assert_true(ar_box(1.0, 4.0).sqr_rev(x=ar_box(0.0, 1.2)) == ar_box(1.0, 1.2))
  assert_true(
    ar_box(1.0, 4.0).sqr_rev().intersection(ar_box(0.0, 1.2)) ==
    ar_box(0.0, 1.2),
  )
  // part of c below 0 is ignored, c below 0 gives Empty
  assert_true(ar_box(-1.0, 25.0).sqr_rev() == ar_box(-5.0, 5.0))
  assert_true(ar_box(-10.0, -1.0).sqr_rev().is_empty())
  assert_true(Interval::empty().sqr_rev().is_empty())
  assert_true(ar_box(0.0, ar_inf).sqr_rev() == Interval::entire())
  // the pieces are [-2, -1] and [1, 2]: a prior inside the gap gives Empty
  assert_true(ar_box(1.0, 4.0).sqr_rev(x=ar_box(-0.5, 0.5)).is_empty())
  // a prior that picks one side
  assert_true(
    ar_box(1.0, 4.0).sqr_rev(x=ar_box(-3.0, -1.5)) == ar_box(-2.0, -1.5),
  )
}

///|
test "sqr_rev rounds the root outward" {
  // sqrt(2) is not representable at 8 bits
  let c = Interval::from_int(2, precision=8)
  let r = c.sqr_rev()
  let hi = r.upper_bound()
  assert_true(
    hi.compare(@bin_float.BinFloat::from_double(1.4142135623730951)) >= 0,
  )
  assert_true(hi.mul(hi).compare(@bin_float.BinFloat::from_int(2)) >= 0)
  assert_true(r.lower_bound().neg().compare(hi) == 0)
}

///|
test "abs_rev and cosh_rev" {
  assert_true(ar_box(1.0, 3.0).abs_rev() == ar_box(-3.0, 3.0))
  assert_true(
    ar_box(1.0, 3.0).abs_rev(x=ar_box(-2.0, 0.5)) == ar_box(-2.0, -1.0),
  )
  assert_true(ar_box(-5.0, -1.0).abs_rev().is_empty())
  assert_true(ar_box(-5.0, 2.0).abs_rev() == ar_box(-2.0, 2.0))
  assert_true(ar_box(2.0, ar_inf).abs_rev(x=ar_box(-1.0, 1.0)).is_empty())
  // cosh(x) = 1 only at 0; cosh is at least 1
  assert_true(ar_box(1.0, 1.0).cosh_rev() == ar_box(0.0, 0.0))
  assert_true(ar_box(0.0, 0.5).cosh_rev().is_empty())
  assert_true(ar_box(0.0, ar_inf).cosh_rev() == Interval::entire())
  let r = ar_box(1.0, 2.0).cosh_rev()
  // acosh(2) = 1.3169578969248166
  assert_true(
    r
    .upper_bound()
    .compare(@bin_float.BinFloat::from_double(1.3169578969248166)) >=
    0,
  )
  assert_true(
    r
    .upper_bound()
    .compare(@bin_float.BinFloat::from_double(1.3169578969248169)) <=
    0,
  )
  assert_true(r.lower_bound().neg().compare(r.upper_bound()) == 0)
}

///|
test "pown_rev: p = 0, 1, even and odd positive powers" {
  // x^0 = 1 for every x
  assert_true(ar_box(-1.0, 5.0).pown_rev(0) == Interval::entire())
  assert_true(
    ar_box(1.0, 1.0).pown_rev(0, x=ar_box(2.0, 3.0)) == ar_box(2.0, 3.0),
  )
  assert_true(ar_box(-1.0, 0.0).pown_rev(0).is_empty())
  assert_true(ar_box(1.1, 10.0).pown_rev(0).is_empty())
  // p = 1: the identity
  assert_true(ar_box(2.0, 5.0).pown_rev(1) == ar_box(2.0, 5.0))
  assert_true(
    ar_box(2.0, 5.0).pown_rev(1, x=ar_box(3.0, 9.0)) == ar_box(3.0, 5.0),
  )
  // even: x^4 in [16, 81] gives [-3, -2] U [2, 3]
  assert_true(ar_box(16.0, 81.0).pown_rev(4) == ar_box(-3.0, 3.0))
  assert_true(
    ar_box(16.0, 81.0).pown_rev(4, x=ar_box(-1.0, 2.5)) == ar_box(2.0, 2.5),
  )
  assert_true(ar_box(-9.0, -1.0).pown_rev(4).is_empty())
  // odd: x^3 in [-8, 27] gives [-2, 3]
  assert_true(ar_box(-8.0, 27.0).pown_rev(3) == ar_box(-2.0, 3.0))
  assert_true(
    ar_box(-8.0, 27.0).pown_rev(3, x=ar_box(0.0, 5.0)) == ar_box(0.0, 3.0),
  )
  assert_true(ar_box(ar_ninf, 8.0).pown_rev(3) == ar_box(ar_ninf, 2.0))
}

///|
test "pown_rev: negative powers exclude 0 and the unattained limit is open" {
  // x^-2 in [1/4, 1] gives [-2, -1] U [1, 2]
  assert_true(ar_box(0.25, 1.0).pown_rev(-2) == ar_box(-2.0, 2.0))
  assert_true(
    ar_box(0.25, 1.0).pown_rev(-2, x=ar_box(-0.5, 1.5)) == ar_box(1.0, 1.5),
  )
  // c = [0, inf]: x^-2 > 0 for every x != 0
  assert_true(ar_box(0.0, ar_inf).pown_rev(-2) == Interval::entire())
  // c = [1, inf]: 0 < |x| <= 1, and x = 0 is not in the set
  assert_true(ar_box(1.0, ar_inf).pown_rev(-2) == ar_box(-1.0, 1.0))
  assert_true(ar_box(1.0, ar_inf).pown_rev(-2, x=ar_box(0.0, 0.0)).is_empty())
  assert_true(
    ar_box(1.0, ar_inf).pown_rev(-2, x=ar_box(-1.0, 0.0)) == ar_box(-1.0, 0.0),
  )
  // x^-2 is never 0 or negative
  assert_true(ar_box(0.0, 0.0).pown_rev(-2).is_empty())
  assert_true(ar_box(-3.0, -1.0).pown_rev(-2).is_empty())
  // odd: x^-1 in [2, 4] gives [1/4, 1/2]; in [-4, -2] gives [-1/2, -1/4]
  assert_true(ar_box(2.0, 4.0).pown_rev(-1) == ar_box(0.25, 0.5))
  assert_true(ar_box(-4.0, -2.0).pown_rev(-1) == ar_box(-0.5, -0.25))
  // c straddling 0: both signs, with the pole excluded
  assert_true(ar_box(-1.0, 1.0).pown_rev(-1) == Interval::entire())
  assert_true(ar_box(-1.0, 1.0).pown_rev(-1, x=ar_box(-0.5, 0.5)).is_empty())
  assert_true(ar_box(1.0, ar_inf).pown_rev(-1, x=ar_box(-1.0, 0.0)).is_empty())
  assert_true(ar_box(1.0, ar_inf).pown_rev(-1) == ar_box(0.0, 1.0))
  assert_true(ar_box(0.0, ar_inf).pown_rev(-3, x=ar_box(-1.0, 0.0)).is_empty())
}

///|
test "decorated reverse functions are trivially decorated (11.7.1)" {
  let d = fn(lo, hi, dec) {
    DecoratedInterval::new(ar_box(lo, hi), decoration=dec)
  }
  let r = d(1.0, 4.0, Com).sqr_rev()
  assert_true(r.interval() == ar_box(-2.0, 2.0))
  assert_eq(r.decoration(), Trv)
  let r = d(1.0, 4.0, Com).sqr_rev(x=d(0.0, 1.2, Dac))
  assert_true(r.interval() == ar_box(1.0, 1.2))
  assert_eq(r.decoration(), Trv)
  assert_eq(d(1.0, 3.0, Com).abs_rev().decoration(), Trv)
  assert_eq(d(1.0, 1.0, Com).cosh_rev().decoration(), Trv)
  assert_eq(d(16.0, 81.0, Com).pown_rev(4).decoration(), Trv)
  // an empty result is Empty with Trv
  let empty = d(-5.0, -1.0, Com).sqr_rev()
  assert_true(empty.is_empty())
  assert_eq(empty.decoration(), Trv)
  let nai = DecoratedInterval::nai()
  assert_true(nai.sqr_rev().is_nai())
  assert_true(nai.abs_rev().is_nai())
  assert_true(nai.cosh_rev().is_nai())
  assert_true(nai.pown_rev(2).is_nai())
  assert_true(d(1.0, 4.0, Com).sqr_rev(x=nai).is_nai())
  assert_true(d(1.0, 4.0, Com).pown_rev(2, x=nai).is_nai())
}
