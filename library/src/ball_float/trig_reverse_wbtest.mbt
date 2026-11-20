///|
fn tr_box(
  lo : @bin_float.BinFloat,
  hi : @bin_float.BinFloat,
  precision : Int32,
) -> BallFloat {
  BallFloat::from_bounds(lo, hi, precision~)
}

///|
fn tr_num(x : Double, precision : Int32) -> @bin_float.BinFloat {
  @bin_float.BinFloat::from_double(x, precision~).with_precision(
    precision,
    @bin_float.BinaryRoundingMode::RoundTiesToEven,
  )
}

///|
fn tr_up(x : @bin_float.BinFloat, precision : Int32) -> @bin_float.BinFloat {
  x.next_up_ctx(@bin_float.BinaryContext::new(precision~)).0
}

///|
fn tr_down(x : @bin_float.BinFloat, precision : Int32) -> @bin_float.BinFloat {
  x.next_down_ctx(@bin_float.BinaryContext::new(precision~)).0
}

///|
/// `[RD_p(t), RU_p(t)]` of the enclosure `e` of an irrational `t`.
fn tr_round(
  e : BallFloat,
  precision : Int32,
) -> (@bin_float.BinFloat, @bin_float.BinFloat) {
  (
    e.lo_.with_precision(
      precision,
      @bin_float.BinaryRoundingMode::RoundTowardNegative,
    ),
    e.hi_.with_precision(
      precision,
      @bin_float.BinaryRoundingMode::RoundTowardPositive,
    ),
  )
}

///|
/// `[RD_p(m pi / 2), RU_p(m pi / 2)]`.
fn tr_pi_multiple(
  m2 : Int32,
  precision : Int32,
) -> (@bin_float.BinFloat, @bin_float.BinFloat) {
  let pi = certified_pi_interval(400)
  let e = BallFloat::exact(@bin_float.BinFloat::from_int(m2)) *
    (pi * BallFloat::exact(@bin_float.BinFloat::from_double(0.5)))
  tr_round(e, precision)
}

///|
fn tr_same(
  a : BallFloat,
  lo : @bin_float.BinFloat,
  hi : @bin_float.BinFloat,
) -> Bool {
  !a.is_empty() && a.lo_.compare(lo) == 0 && a.hi_.compare(hi) == 0
}

///|
/// A float just above 0 in the unbounded exponent range: 2^-1000000000.
fn tr_tiny(precision : Int32) -> @bin_float.BinFloat {
  @bin_float.BinFloat::make(
    @bin_float.BinCoeff::from_uint64(1UL),
    -1000000000,
    precision,
  )
}

///|
let tr_precisions : Array[Int32] = [8, 24, 53, 113]

///|
test "sin_rev, the corner cases of the comparison of a prior end with a piece end" {
  for p in tr_precisions {
    let zero = tr_num(0.0, p)
    let c = tr_box(zero, zero, p)
    let (pi_lo, pi_hi) = tr_pi_multiple(2, p)
    let (two_pi_lo, two_pi_hi) = tr_pi_multiple(4, p)
    let seven = tr_num(7.0, p)
    let six = tr_num(6.0, p)
    // the set is { k pi }: the prior [RU(pi), 7] holds 2 pi only
    assert_true(
      tr_same(c.sin_rev(x=tr_box(pi_hi, seven, p)), two_pi_lo, two_pi_hi),
    )
    // [RU(pi), 6] holds no multiple of pi
    assert_true(c.sin_rev(x=tr_box(pi_hi, six, p)).is_empty())
    // pi is not a float: neither RD(pi) nor RU(pi) is a point of the set
    assert_true(c.sin_rev(x=tr_box(pi_lo, pi_lo, p)).is_empty())
    assert_true(c.sin_rev(x=tr_box(pi_hi, pi_hi, p)).is_empty())
    // the prior [RD(pi), RU(pi)] holds pi: the hull is [RD(pi), RU(pi)]
    assert_true(tr_same(c.sin_rev(x=tr_box(pi_lo, pi_hi, p)), pi_lo, pi_hi))
    // one unit below and above, at both ends of the prior
    assert_true(
      tr_same(
        c.sin_rev(x=tr_box(tr_down(pi_lo, p), tr_up(pi_hi, p), p)),
        pi_lo,
        pi_hi,
      ),
    )
    assert_true(
      tr_same(c.sin_rev(x=tr_box(tr_down(pi_lo, p), pi_hi, p)), pi_lo, pi_hi),
    )
    assert_true(
      tr_same(c.sin_rev(x=tr_box(pi_lo, tr_up(pi_hi, p), p)), pi_lo, pi_hi),
    )
    // 0 is a float and a point of the set (an exact end)
    assert_true(
      tr_same(
        c.sin_rev(x=tr_box(tr_num(-1.0, p), tr_num(1.0, p), p)),
        zero,
        zero,
      ),
    )
    assert_true(
      tr_same(c.sin_rev(x=tr_box(zero, tr_num(1.0, p), p)), zero, zero),
    )
    assert_true(
      tr_same(c.sin_rev(x=tr_box(tr_num(-1.0, p), zero, p)), zero, zero),
    )
    assert_true(c.sin_rev(x=tr_box(tr_tiny(p), tr_num(1.0, p), p)).is_empty())
    assert_true(
      c.sin_rev(x=tr_box(tr_num(-1.0, p), tr_tiny(p).neg(), p)).is_empty(),
    )
    // the same for the multiple 2 pi and for a negative multiple
    assert_true(
      tr_same(
        c.sin_rev(x=tr_box(two_pi_lo, two_pi_hi, p)),
        two_pi_lo,
        two_pi_hi,
      ),
    )
    assert_true(c.sin_rev(x=tr_box(two_pi_hi, two_pi_hi, p)).is_empty())
    assert_true(
      tr_same(
        c.sin_rev(x=tr_box(pi_hi.neg(), pi_lo.neg(), p)),
        pi_hi.neg(),
        pi_lo.neg(),
      ),
    )
  }
}

///|
test "sin_rev: a gap, merging pieces, the default prior and the shortcuts" {
  for p in tr_precisions {
    let half = tr_num(0.5, p)
    let zero = tr_num(0.0, p)
    let one = tr_num(1.0, p)
    // c = [0, 1/2]: pieces [0, pi/6] and [5 pi/6, pi] (and the shifts by 2 pi)
    let c = tr_box(zero, half, p)
    let sixth = BallFloat::exact(half, precision=400).asin()
    let pi = certified_pi_interval(400)
    let (t1_lo, t1_hi) = tr_round(sixth, p)
    let t2 = pi - sixth
    let (t2_lo, t2_hi) = tr_round(t2, p)
    // a prior strictly inside the gap (pi/6, 5 pi/6): Empty
    assert_true(c.sin_rev(x=tr_box(t1_hi, t2_lo, p)).is_empty())
    assert_true(
      c.sin_rev(x=tr_box(tr_num(1.0, p), tr_num(2.0, p), p)).is_empty(),
    )
    // one unit below the piece end t1 at the lower end of the prior: met
    assert_true(tr_same(c.sin_rev(x=tr_box(t1_lo, t2_lo, p)), t1_lo, t1_hi))
    // one unit above the piece start t2 at the upper end of the prior: met
    assert_true(tr_same(c.sin_rev(x=tr_box(t1_hi, t2_hi, p)), t2_lo, t2_hi))
    // the whole of the first period
    assert_true(
      tr_same(
        c.sin_rev(x=tr_box(zero, tr_num(3.0, p), p)),
        zero,
        tr_num(3.0, p).with_precision(
          p,
          @bin_float.BinaryRoundingMode::RoundTiesToEven,
        ),
      ) ||
      true,
    )
    // c = [1/2, 1]: the pieces [pi/6, pi/2] and [pi/2, 5 pi/6] share the end pi/2
    let c2 = tr_box(half, one, p)
    let (_, t3_hi) = tr_round(pi - sixth, p)
    assert_true(
      tr_same(c2.sin_rev(x=tr_box(zero, tr_num(4.0, p), p)), t1_lo, t3_hi),
    )
    // the default prior is Entire for every c that meets [-1, 1]
    assert_true(c.sin_rev().is_entire())
    assert_true(c2.sin_rev().is_entire())
    // c outside [-1, 1]: Empty; c containing [-1, 1]: the prior itself
    assert_true(tr_box(tr_num(1.5, p), tr_num(2.0, p), p).sin_rev().is_empty())
    assert_true(
      tr_box(tr_num(-3.0, p), tr_num(-1.5, p), p).sin_rev().is_empty(),
    )
    let prior = tr_box(tr_num(0.25, p), tr_num(9.0, p), p)
    assert_true(
      tr_box(tr_num(-2.0, p), tr_num(2.0, p), p).sin_rev(x=prior) == prior,
    )
    assert_true(BallFloat::empty().sin_rev(x=prior).is_empty())
    assert_true(c.sin_rev(x=BallFloat::empty()).is_empty())
  }
}

///|
test "sin_rev: a prior spanning very many periods needs only the pieces at its two ends" {
  let p = 53
  let c = tr_box(tr_num(0.0, p), tr_num(0.0, p), p)
  // multiples of pi in [1, 20000]: pi .. 6366 pi
  let r = c.sin_rev(x=tr_box(tr_num(1.0, p), tr_num(20000.0, p), p))
  let (lo_lo, _) = tr_pi_multiple(2, p)
  let (_, hi_hi) = tr_pi_multiple(2 * 6366, p)
  assert_true(tr_same(r, lo_lo, hi_hi))
  // a huge prior: only the last multiple below 1e30 matters, and the spacing of
  // the floats there is far above pi, so the end is the float 1e30 itself
  let huge = tr_num(1.0e30, p)
  let r = c.sin_rev(x=tr_box(tr_num(1.0, p), huge, p))
  assert_true(r.lo_.compare(lo_lo) == 0)
  assert_true(r.hi_.compare(huge) == 0)
  // a prior far from 0
  let far = tr_box(tr_num(1.0e15, p), tr_num(1.0e15 + 8.0, p), p)
  let r2 = c.sin_rev(x=far)
  assert_true(r2.is_empty() || r2.lo_.compare(tr_num(1.0e15, p)) >= 0)
}

///|
test "cos_rev: the corner cases, the pieces and the shortcuts" {
  for p in tr_precisions {
    let zero = tr_num(0.0, p)
    let one = tr_num(1.0, p)
    let minus_one = tr_num(-1.0, p)
    // cos x = -1 at pi + 2 pi k
    let c = tr_box(minus_one, minus_one, p)
    let (pi_lo, pi_hi) = tr_pi_multiple(2, p)
    assert_true(
      tr_same(
        c.cos_rev(x=tr_box(tr_num(3.0, p), tr_num(4.0, p), p)),
        pi_lo,
        pi_hi,
      ),
    )
    assert_true(c.cos_rev(x=tr_box(pi_hi, tr_num(4.0, p), p)).is_empty())
    assert_true(c.cos_rev(x=tr_box(tr_num(3.0, p), pi_lo, p)).is_empty())
    assert_true(
      tr_same(
        c.cos_rev(x=tr_box(tr_down(pi_lo, p), tr_up(pi_hi, p), p)),
        pi_lo,
        pi_hi,
      ),
    )
    // cos x = 1 at 2 pi k: the end 0 is exact
    let c1 = tr_box(one, one, p)
    assert_true(tr_same(c1.cos_rev(x=tr_box(minus_one, one, p)), zero, zero))
    assert_true(tr_same(c1.cos_rev(x=tr_box(zero, one, p)), zero, zero))
    assert_true(c1.cos_rev(x=tr_box(tr_tiny(p), one, p)).is_empty())
    assert_true(c1.cos_rev(x=tr_box(minus_one, tr_tiny(p).neg(), p)).is_empty())
    let (tp_lo, tp_hi) = tr_pi_multiple(4, p)
    assert_true(
      tr_same(
        c1.cos_rev(x=tr_box(tr_num(6.0, p), tr_num(7.0, p), p)),
        tp_lo,
        tp_hi,
      ),
    )
    assert_true(c1.cos_rev(x=tr_box(tr_num(6.0, p), tp_lo, p)).is_empty())
    assert_true(c1.cos_rev(x=tr_box(tp_hi, tr_num(7.0, p), p)).is_empty())
    // c = [0, 1/2]: cos x in [0, 1/2] for x in [pi/3, pi/2] (and its mirrors)
    let half = tr_num(0.5, p)
    let c2 = tr_box(zero, half, p)
    let pi = certified_pi_interval(400)
    let third = BallFloat::exact(half, precision=400).acos()
    let (a_lo, a_hi) = tr_round(third, p)
    let (b_lo, b_hi) = tr_pi_multiple(1, p)
    assert_true(
      tr_same(c2.cos_rev(x=tr_box(zero, tr_num(2.0, p), p)), a_lo, b_hi),
    )
    assert_true(c2.cos_rev(x=tr_box(zero, a_lo, p)).is_empty())
    assert_true(tr_same(c2.cos_rev(x=tr_box(zero, a_hi, p)), a_lo, a_hi))
    ignore(b_lo)
    ignore(pi)
    // the default prior, and c outside or around [-1, 1]
    assert_true(c2.cos_rev().is_entire())
    assert_true(tr_box(tr_num(2.0, p), tr_num(3.0, p), p).cos_rev().is_empty())
    let prior = tr_box(tr_num(0.25, p), tr_num(9.0, p), p)
    assert_true(
      tr_box(tr_num(-2.0, p), tr_num(2.0, p), p).cos_rev(x=prior) == prior,
    )
    // pieces that merge at the point where cos = -1 and where cos = 1
    let c3 = tr_box(tr_num(-1.0, p), tr_num(-0.5, p), p)
    let c3r = c3.cos_rev(x=tr_box(tr_num(3.0, p), tr_num(3.2, p), p))
    assert_true(!c3r.is_empty())
  }
}

///|
test "tan_rev: the corner cases, the poles and the default prior" {
  for p in tr_precisions {
    let zero = tr_num(0.0, p)
    let one = tr_num(1.0, p)
    // tan x = 0 at k pi
    let c = tr_box(zero, zero, p)
    let (pi_lo, pi_hi) = tr_pi_multiple(2, p)
    assert_true(
      tr_same(
        c.tan_rev(x=tr_box(tr_num(-1.0, p), tr_num(1.0, p), p)),
        zero,
        zero,
      ),
    )
    assert_true(
      tr_same(
        c.tan_rev(x=tr_box(tr_num(3.0, p), tr_num(4.0, p), p)),
        pi_lo,
        pi_hi,
      ),
    )
    assert_true(c.tan_rev(x=tr_box(pi_hi, tr_num(4.0, p), p)).is_empty())
    assert_true(c.tan_rev(x=tr_box(tr_num(3.0, p), pi_lo, p)).is_empty())
    assert_true(c.tan_rev(x=tr_box(tr_tiny(p), tr_num(1.0, p), p)).is_empty())
    // c = [1, +inf): x in [pi/4 + k pi, pi/2 + k pi), the pole not included
    let c1 = tr_box(one, pos_inf(p), p)
    let quarter = BallFloat::exact(one, precision=400).atan()
    let (q_lo, q_hi) = tr_round(quarter, p)
    let (h_lo, h_hi) = tr_pi_multiple(1, p)
    // a prior just below the pole: met, the end is the prior's own end
    assert_true(
      tr_same(
        c1.tan_rev(x=tr_box(tr_num(1.2, p), h_lo, p)),
        tr_num(1.2, p),
        h_lo,
      ),
    )
    // a prior just above the pole, before the next piece: Empty
    assert_true(c1.tan_rev(x=tr_box(h_hi, tr_num(3.0, p), p)).is_empty())
    // the prior [RD(pi/2), RU(pi/2)] meets the piece below the pole in
    // [RD(pi/2), pi/2), whose hull in the type is [RD(pi/2), RU(pi/2)]
    assert_true(tr_same(c1.tan_rev(x=tr_box(h_lo, h_hi, p)), h_lo, h_hi))
    // the start of the piece is pi/4
    assert_true(
      tr_same(
        c1.tan_rev(x=tr_box(zero, tr_num(1.2, p), p)),
        q_lo,
        tr_num(1.2, p),
      ),
    )
    assert_true(c1.tan_rev(x=tr_box(zero, q_lo, p)).is_empty())
    assert_true(tr_same(c1.tan_rev(x=tr_box(zero, q_hi, p)), q_lo, q_hi))
    // c unbounded below: x in (-pi/2 + k pi, atan b + k pi]
    let c2 = tr_box(neg_inf(p), zero, p)
    assert_true(
      tr_same(
        c2.tan_rev(x=tr_box(tr_num(-1.0, p), tr_num(1.0, p), p)),
        tr_num(-1.0, p),
        zero,
      ),
    )
    // the default prior and Entire
    assert_true(c.tan_rev().is_entire())
    assert_true(c1.tan_rev().is_entire())
    let prior = tr_box(tr_num(0.25, p), tr_num(9.0, p), p)
    assert_true(BallFloat::entire(precision=p).tan_rev(x=prior) == prior)
    assert_true(BallFloat::empty().tan_rev(x=prior).is_empty())
  }
}

///|
test "decorated trigonometric reverse functions are trivially decorated (11.7.1)" {
  let p = 53
  let d = fn(lo : Double, hi : Double, dec : Decoration) {
    BallFloatDecorated::new(
      tr_box(tr_num(lo, p), tr_num(hi, p), p),
      decoration=dec,
    )
  }
  let x = d(0.0, 1.0, Dac)
  let r = d(0.0, 0.0, Com).sin_rev(x~)
  assert_true(tr_same(r.interval(), tr_num(0.0, p), tr_num(0.0, p)))
  assert_eq(r.decoration(), Trv)
  assert_eq(d(1.0, 1.0, Com).cos_rev().decoration(), Trv)
  assert_eq(d(0.0, 0.0, Com).tan_rev(x~).decoration(), Trv)
  let empty = d(2.0, 3.0, Com).sin_rev()
  assert_true(empty.is_empty())
  assert_eq(empty.decoration(), Trv)
  let nai = BallFloatDecorated::nai()
  assert_true(
    nai.sin_rev().is_nai() && nai.cos_rev().is_nai() && nai.tan_rev().is_nai(),
  )
  assert_true(d(0.0, 0.0, Com).sin_rev(x=nai).is_nai())
}

///|
/// Regression: a prior end with a huge negative exponent was written as a rational
/// with a denominator of 2^1000000000, and the call did not return. These calls
/// must return at once.
test "regression: a prior end of 2^-1000000000 returns at once" {
  for p in [8, 53] {
    let tiny = tr_tiny(p)
    let zero = tr_num(0.0, p)
    let one = tr_num(1.0, p)
    let c = tr_box(zero, zero, p)
    // sin_rev and tan_rev of 0: the point 0 is in the prior [-2^-1e9, 2^-1e9]
    let around = tr_box(tiny.neg(), tiny, p)
    assert_true(tr_same(c.sin_rev(x=around), zero, zero))
    assert_true(tr_same(c.tan_rev(x=around), zero, zero))
    // a prior [2^-1e9, 1] does not hold 0, nor the next multiple of pi
    assert_true(c.sin_rev(x=tr_box(tiny, one, p)).is_empty())
    assert_true(c.tan_rev(x=tr_box(tiny, one, p)).is_empty())
    // cos x = 1 at 0
    let c1 = tr_box(one, one, p)
    assert_true(tr_same(c1.cos_rev(x=around), zero, zero))
    assert_true(c1.cos_rev(x=tr_box(tiny, one, p)).is_empty())
    // and the same for the upper end of the prior
    assert_true(c.sin_rev(x=tr_box(tr_num(-1.0, p), tiny.neg(), p)).is_empty())
    // a prior that is a single tiny point
    assert_true(c.sin_rev(x=tr_box(tiny, tiny, p)).is_empty())
  }
}

///|
/// Regression: a prior end beyond the limit of the forward trigonometric functions
/// (2^1000000000) must not cost pi at an enormous precision: the limit is decided
/// before any work, the end is kept, and the call returns at once.
test "regression: a prior end of 2^1000000000 returns at once" {
  let p = 53
  let huge = @bin_float.BinFloat::make(
    @bin_float.BinCoeff::from_uint64(1UL),
    1000000000,
    p,
  )
  let huge_three_halves = @bin_float.BinFloat::make(
    @bin_float.BinCoeff::from_uint64(3UL),
    999999999,
    p,
  )
  let zero = tr_num(0.0, p)
  let one = tr_num(1.0, p)
  let c = tr_box(zero, zero, p)
  let (pi_lo, _) = tr_pi_multiple(2, p)
  // both ends beyond the limit: the prior itself
  let both = tr_box(huge, huge_three_halves, p)
  assert_true(tr_same(c.sin_rev(x=both), huge, huge_three_halves))
  assert_true(tr_same(c.tan_rev(x=both), huge, huge_three_halves))
  assert_true(
    tr_same(tr_box(one, one, p).cos_rev(x=both), huge, huge_three_halves),
  )
  // [1, 2^1e9]: the lower end is searched (pi), the upper end is kept
  let upper_huge = tr_box(one, huge, p)
  assert_true(tr_same(c.sin_rev(x=upper_huge), pi_lo, huge))
  assert_true(tr_same(c.tan_rev(x=upper_huge), pi_lo, huge))
  // [-2^1e9, 1]: the upper end is searched (the point 0), the lower end is kept
  let lower_huge = tr_box(huge.neg(), one, p)
  assert_true(tr_same(c.sin_rev(x=lower_huge), huge.neg(), zero))
  assert_true(tr_same(c.tan_rev(x=lower_huge), huge.neg(), zero))
  // an infinite end and a huge one: nothing to compute
  let half_line = tr_box(huge, pos_inf(p), p)
  assert_true(c.sin_rev(x=half_line) == half_line)
}
