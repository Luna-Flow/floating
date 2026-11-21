///|
/// A reference for `atan2_rev1` and `atan2_rev2` that does not use the pieces of the
/// implementation: membership of a float is decided by the forward definition, with the
/// forward `Interval::atan2` of points at 200 bits. For a fixed ordinate `y`,
/// `atan2(y, b0)` is monotone and continuous in `b0` on each side of the abscissa 0
/// (decreasing for `y > 0`, increasing for `y < 0`), so the angles over `b` form an interval
/// decided from the ends of `b`; for `y = 0` they are the points 0 (a positive `b0`) and
/// `pi` (a negative `b0`). Rev2 is the same with the roles exchanged. The result is checked
/// against it: every float certainly in the set is in the result, a point a quarter of a
/// float beyond an end that comes from a piece is not in the set, and the float one step
/// inside is not certainly outside while the next one is certainly inside. The helpers
/// `PowRng`, `pwr_w`, `pwr_between`, `pwr_pick` and `pwr_ordered` are shared with the
/// reference tests of `pow_rev1`.

///|
fn at2_pi() -> Interval {
  certified_pi_interval(pwr_w)
}

///|
fn at2_half_pi() -> Interval {
  at2_pi() * Interval::exact(@binary.Binary::from_double(0.5))
}

///|
fn at2_neg(x : Interval) -> Interval {
  Interval::from_bounds(x.hi_.neg(), x.lo_.neg(), precision=pwr_w)
}

///|
fn at2_angle(y : @binary.Binary, x : @binary.Binary) -> Interval {
  Interval::exact(y, precision=pwr_w).atan2(Interval::exact(x, precision=pwr_w))
}

///|
let at2_tol : @binary.Binary = @binary.Binary::make(
  @binary.BinCoeff::from_uint64(1UL),
  -100,
  1,
)

///|
/// 1 if the angle interval `[lo, hi]` (two enclosures) certainly meets `c`, 0 if it certainly
/// does not, 2 if it is not decided at this precision. An end of the image that is not
/// attained is passed with its limit, and the margin `2^-100` makes the decision strict.
fn at2_meets(lo : Interval, hi : Interval, c : Interval) -> Int32 {
  if hi.hi_.compare(c.lo_) < 0 || lo.lo_.compare(c.hi_) > 0 {
    return 0
  }
  let above = fn(x : @binary.Binary, y : @binary.Binary) {
    // x - y > tol, with infinities
    if x.classify() == FpClass::Infinity || y.classify() == FpClass::Infinity {
      true
    } else {
      let diff = Interval::exact(x, precision=pwr_w * 2) -
        Interval::exact(y, precision=pwr_w * 2)
      diff.lo_.compare(at2_tol) > 0
    }
  }
  if above(hi.lo_, c.lo_) && above(c.hi_, lo.hi_) {
    1
  } else {
    2
  }
}

///|
/// Combines the decisions of the pieces of an image: 1 if one is certainly in, 0 if all are
/// certainly out, else 2.
fn at2_combine(decisions : Array[Int32]) -> Int32 {
  let mut any_in = false
  let mut all_out = true
  for d in decisions {
    if d == 1 {
      any_in = true
    }
    if d != 0 {
      all_out = false
    }
  }
  if any_in {
    1
  } else if all_out {
    0
  } else {
    2
  }
}

///|
/// Membership of the ordinate `y` in the set of `atan2_rev1(b, c)`.
fn at2_sat1(y : @binary.Binary, b : Interval, c : Interval) -> Int32 {
  let zero = @binary.Binary::zero(precision=pwr_w)
  let pi = at2_pi()
  let decisions : Array[Int32] = []
  if y.is_zero() {
    if b.hi_.compare(zero) > 0 {
      let exact_zero = Interval::exact(zero, precision=pwr_w)
      decisions.push(at2_meets(exact_zero, exact_zero, c))
    }
    if b.lo_.compare(zero) < 0 {
      decisions.push(at2_meets(pi, pi, c))
    }
    return at2_combine(decisions)
  }
  let exact_zero = Interval::exact(zero, precision=pwr_w)
  if y.signum() == Sign::Positive {
    // decreasing in b0: from pi (b0 -> -inf, open) to 0 (b0 -> +inf, open)
    let low = if is_pos_inf(b.hi_) { exact_zero } else { at2_angle(y, b.hi_) }
    let high = if is_neg_inf(b.lo_) { pi } else { at2_angle(y, b.lo_) }
    decisions.push(at2_meets(low, high, c))
  } else {
    // increasing in b0: from -pi (open) to 0 (open)
    let low = if is_neg_inf(b.lo_) { at2_neg(pi) } else { at2_angle(y, b.lo_) }
    let high = if is_pos_inf(b.hi_) { exact_zero } else { at2_angle(y, b.hi_) }
    decisions.push(at2_meets(low, high, c))
  }
  at2_combine(decisions)
}

///|
/// Membership of the abscissa `x0` in the set of `atan2_rev2(a, c)`.
fn at2_sat2(x0 : @binary.Binary, a : Interval, c : Interval) -> Int32 {
  let zero = @binary.Binary::zero(precision=pwr_w)
  let pi = at2_pi()
  let half = at2_half_pi()
  let decisions : Array[Int32] = []
  if x0.is_zero() {
    if a.hi_.compare(zero) > 0 {
      decisions.push(at2_meets(half, half, c))
    }
    if a.lo_.compare(zero) < 0 {
      let neg_half = at2_neg(half)
      decisions.push(at2_meets(neg_half, neg_half, c))
    }
    return at2_combine(decisions)
  }
  if x0.signum() == Sign::Positive {
    // increasing in a0 over the whole line, from -pi/2 to pi/2 (both open)
    let low = if is_neg_inf(a.lo_) {
      at2_neg(half)
    } else {
      at2_angle(a.lo_, x0)
    }
    let high = if is_pos_inf(a.hi_) { half } else { at2_angle(a.hi_, x0) }
    decisions.push(at2_meets(low, high, c))
    return at2_combine(decisions)
  }
  // x0 < 0
  if a.hi_.compare(zero) > 0 {
    // a0 > 0: the angle decreases from pi (a0 -> 0+) to pi/2 (a0 -> +inf)
    let low = if is_pos_inf(a.hi_) { half } else { at2_angle(a.hi_, x0) }
    let high = if a.lo_.compare(zero) > 0 { at2_angle(a.lo_, x0) } else { pi }
    decisions.push(at2_meets(low, high, c))
  }
  if a.lo_.compare(zero) < 0 {
    // a0 < 0: the angle lies in (-pi, -pi/2), from -pi/2 (a0 -> -inf) down to -pi (a0 -> 0-)
    let high = if is_neg_inf(a.lo_) {
      at2_neg(half)
    } else {
      at2_angle(a.lo_, x0)
    }
    let low = if a.hi_.compare(zero) < 0 {
      at2_angle(a.hi_, x0)
    } else {
      at2_neg(pi)
    }
    decisions.push(at2_meets(low, high, c))
  }
  if a.lo_.compare(zero) <= 0 && a.hi_.compare(zero) >= 0 {
    decisions.push(at2_meets(pi, pi, c))
  }
  at2_combine(decisions)
}

///|
fn at2_sat(
  rev : Int32,
  point : @binary.Binary,
  factor : Interval,
  c : Interval,
) -> Int32 {
  if rev == 1 {
    at2_sat1(point, factor, c)
  } else {
    at2_sat2(point, factor, c)
  }
}

///|
fn at2_run(
  rev : Int32,
  factor : Interval,
  c : Interval,
  prior : Interval?,
  cap : Int32?,
) -> Interval {
  match cap {
    None =>
      match prior {
        Some(p) =>
          if rev == 1 {
            factor.atan2_rev1(c, x=p)
          } else {
            factor.atan2_rev2(c, x=p)
          }
        None =>
          if rev == 1 {
            factor.atan2_rev1(c)
          } else {
            factor.atan2_rev2(c)
          }
      }
    Some(limit) =>
      if rev == 1 {
        factor.atan2_rev1_capped(c, prior, limit)
      } else {
        factor.atan2_rev2_capped(c, prior, limit)
      }
  }
}

///|
fn at2_check(
  rev : Int32,
  precision : Int32,
  cases : Int32,
  seed : UInt64,
  cap? : Int32,
) -> Unit raise {
  let rng : PowRng = { state: seed, }
  let f_values = [
    -8.0,
    -2.0,
    -1.0,
    -0.5,
    0.0,
    0.0,
    0.5,
    1.0,
    2.0,
    8.0,
    1.0 / 0.0,
    -1.0 / 0.0,
  ]
  let c_values = [
    -4.0,
    -3.2,
    -3.1,
    -2.0,
    -1.6,
    -1.5,
    -1.0,
    -0.5,
    0.0,
    0.0,
    0.5,
    1.0,
    1.5,
    1.6,
    2.0,
    3.0,
    3.1,
    3.2,
    4.0,
    1.0 / 0.0,
    -1.0 / 0.0,
  ]
  let x_values = [
    -8.0,
    -4.0,
    -2.0,
    -1.0,
    -0.5,
    0.0,
    0.5,
    1.0,
    2.0,
    4.0,
    8.0,
    1.0 / 0.0,
    -1.0 / 0.0,
  ]
  let ctx = @binary.BinaryContext::new(precision~)
  let mut nonempty = 0
  for _ in 0..<cases {
    let factor = pwr_ordered(
      pwr_pick(rng, f_values, precision),
      pwr_pick(rng, f_values, precision),
      precision,
    )
    let c = pwr_ordered(
      pwr_pick(rng, c_values, precision),
      pwr_pick(rng, c_values, precision),
      precision,
    )
    let whole = at2_run(rev, factor, c, None, None)
    let mut xl = pwr_pick(rng, x_values, precision)
    let mut xh = pwr_pick(rng, x_values, precision)
    if !whole.is_empty() && rng.below(2) == 0 {
      let near = fn(e : @binary.Binary) {
        if e.classify() != FpClass::Finite {
          return e
        }
        match rng.below(3) {
          0 => e.next_up_ctx(ctx).0
          1 => e.next_down_ctx(ctx).0
          _ => e
        }
      }
      if rng.below(2) == 0 {
        xl = near(whole.lo_)
      } else {
        xh = near(whole.hi_)
      }
    }
    let prior = pwr_ordered(xl, xh, precision)
    println(
      "CASE rev=\{rev} f=\{factor.to_string()} c=\{c.to_string()} prior=\{prior.to_string()}",
    )
    let got = at2_run(rev, factor, c, Some(prior), cap)
    let candidates : Array[@binary.Binary] = []
    candidates.push(prior.lo_)
    candidates.push(prior.hi_)
    for value in x_values {
      if value.is_inf() {
        continue
      }
      candidates.push(pw_num(value, precision))
    }
    if !got.is_empty() {
      candidates.push(got.lo_.next_down_ctx(ctx).0)
      candidates.push(got.lo_.next_up_ctx(ctx).0)
      if got.hi_.classify() == FpClass::Finite {
        candidates.push(got.hi_.next_down_ctx(ctx).0)
        candidates.push(got.hi_.next_up_ctx(ctx).0)
      }
    }
    for x in candidates {
      if x.classify() != FpClass::Finite {
        continue
      }
      if x.compare(prior.lo_) < 0 || x.compare(prior.hi_) > 0 {
        continue
      }
      let status = at2_sat(rev, x, factor, c)
      let inside = !got.is_empty() &&
        x.compare(got.lo_) >= 0 &&
        x.compare(got.hi_) <= 0
      // (A) a float certainly in the set is in the result
      if status == 1 && !inside {
        fail(
          "missed: rev=\{rev} f=\{factor.to_string()} c=\{c.to_string()} prior=\{prior.to_string()} got=\{got.to_string()} x=\{x.to_string()}",
        )
      }
    }
    // tightness of an end that comes from a piece (not from the prior, not infinite)
    if cap is None && !got.is_empty() {
      let sat_of = fn(x : @binary.Binary) {
        if x.classify() != FpClass::Finite {
          2
        } else {
          at2_sat(rev, x, factor, c)
        }
      }
      let lo = got.lo_
      if lo.classify() == FpClass::Finite && lo.compare(prior.lo_) > 0 {
        let below = lo.next_down_ctx(ctx).0
        let above = lo.next_up_ctx(ctx).0
        let above2 = above.next_up_ctx(ctx).0
        if sat_of(pwr_between(below, lo, 3)) == 1 {
          fail(
            "lower end too high: rev=\{rev} f=\{factor.to_string()} c=\{c.to_string()} prior=\{prior.to_string()} got=\{got.to_string()}",
          )
        }
        if sat_of(above) == 0 && sat_of(above2) == 1 {
          fail(
            "lower end too low: rev=\{rev} f=\{factor.to_string()} c=\{c.to_string()} prior=\{prior.to_string()} got=\{got.to_string()}",
          )
        }
      }
      let hi = got.hi_
      if hi.classify() == FpClass::Finite && hi.compare(prior.hi_) < 0 {
        let above = hi.next_up_ctx(ctx).0
        let below = hi.next_down_ctx(ctx).0
        let below2 = below.next_down_ctx(ctx).0
        if sat_of(pwr_between(hi, above, 1)) == 1 {
          fail(
            "upper end too low: rev=\{rev} f=\{factor.to_string()} c=\{c.to_string()} prior=\{prior.to_string()} got=\{got.to_string()}",
          )
        }
        if sat_of(below) == 0 && sat_of(below2) == 1 {
          fail(
            "upper end too high: rev=\{rev} f=\{factor.to_string()} c=\{c.to_string()} prior=\{prior.to_string()} got=\{got.to_string()}",
          )
        }
      }
    }
    if !got.is_empty() {
      nonempty += 1
      if cap is Some(_) {
        // the fallback stays inside the prior
        assert_true(
          got.lo_.compare(prior.lo_) >= 0 && got.hi_.compare(prior.hi_) <= 0,
        )
      }
    }
  }
  if cases >= 20 {
    assert_true(nonempty > cases / 10)
  }
}

///|
/// The sample that runs with every test run (fixed seeds, three precisions: 24, 53 and
/// 113, both operations).
test "atan2 reverse reference sample: against the forward atan2 at 200 bits" {
  at2_check(1, 24, 6, 301UL)
  at2_check(1, 53, 6, 302UL)
  at2_check(1, 113, 6, 303UL)
  at2_check(2, 24, 6, 311UL)
  at2_check(2, 53, 6, 312UL)
  at2_check(2, 113, 6, 313UL)
}

///|
/// The fallback: with no refinement (cap 0) and one (cap 1) every float certainly in the
/// set is still in the result, which stays inside the prior.
test "atan2 reverse reference fallback: the cap at 0 and at 1 never misses a point" {
  at2_check(1, 24, 5, 321UL, cap=0)
  at2_check(1, 53, 5, 322UL, cap=1)
  at2_check(2, 24, 5, 331UL, cap=0)
  at2_check(2, 113, 5, 332UL, cap=1)
}

///|
/// The long run: 500 cases per operation at each of three precisions, run by the interval
/// gate with `--include-skipped`.
#skip("long run: the interval gate runs it with --include-skipped")
test "atan2 reverse reference long: against the forward atan2 at 200 bits" {
  for rev in [1, 2] {
    at2_check(rev, 24, 500, 41UL + rev.to_uint64())
    at2_check(rev, 53, 500, 51UL + rev.to_uint64())
    at2_check(rev, 113, 500, 61UL + rev.to_uint64())
  }
}
