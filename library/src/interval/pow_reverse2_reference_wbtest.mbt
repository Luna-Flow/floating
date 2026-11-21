///|
/// A reference for `pow_rev2` that does not use the pieces of the implementation: the
/// condition `exists a0 in a : a0^beta in c` is evaluated for a float `beta` with the
/// forward `Interval::pow` at 200 bits (the range of `a0^beta` over `a0 in a` is the
/// interval `pow(a, beta)`, since `a0 -> a0^beta` is monotone), and the result is
/// checked against it: every float certainly in the set is in the result, the float one
/// step outside either end of the result, where the end comes from a piece and not
/// from the prior, is certainly not in the set, and a point a quarter of a float beyond
/// such an end is not in the set. The helpers `PowRng`, `pwr_w`, `pwr_between`,
/// `pwr_pick` and `pwr_ordered` are shared with the reference test of `pow_rev1`.

///|
/// 0: certainly not in the set, 1: certainly in, 2: not decided at this precision.
fn pw2_sat(beta : @binary.Binary, a : Interval, c : Interval) -> Int32 {
  let e = a.with_precision(pwr_w).pow(Interval::exact(beta, precision=pwr_w))
  if e.is_empty() {
    return 0
  }
  if e.hi_.compare(c.lo_) < 0 || e.lo_.compare(c.hi_) > 0 {
    return 0
  }
  let tol = @binary.Binary::make(
    @binary.BinCoeff::from_uint64(1UL),
    -(pwr_w / 2),
    1,
  )
  let one_side = fn(hi : @binary.Binary, lo : @binary.Binary) {
    if hi.classify() == FpClass::Infinity || lo.classify() == FpClass::Infinity {
      true
    } else {
      let diff = Interval::exact(hi, precision=pwr_w * 2) -
        Interval::exact(lo, precision=pwr_w * 2)
      diff.lo_.compare(tol) > 0
    }
  }
  if one_side(c.hi_, e.lo_) && one_side(e.hi_, c.lo_) {
    1
  } else {
    2
  }
}

///|
fn pw2_check(
  precision : Int32,
  cases : Int32,
  seed : UInt64,
  cap? : Int32,
) -> Unit raise {
  let rng : PowRng = { state: seed, }
  let a_values = [
    -1.0,
    0.0,
    0.0,
    0.1,
    0.25,
    0.5,
    0.75,
    1.0,
    1.0,
    1.5,
    2.0,
    3.0,
    4.0,
    10.0,
    8.0,
    0.125,
    9.0,
    27.0,
    1.0 / 0.0,
  ]
  let c_values = [
    -1.0,
    0.0,
    0.0,
    0.25,
    0.5,
    1.0,
    1.0,
    2.0,
    3.0,
    4.0,
    9.0,
    100.0,
    8.0,
    0.125,
    27.0,
    81.0,
    1.0 / 0.0,
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
    3.0,
    4.0,
    8.0,
    1.0 / 0.0,
    -1.0 / 0.0,
  ]
  let ctx = @binary.BinaryContext::new(precision~)
  let mut nonempty = 0
  for _ in 0..<cases {
    let a = pwr_ordered(
      pwr_pick(rng, a_values, precision),
      pwr_pick(rng, a_values, precision),
      precision,
    )
    let c = pwr_ordered(
      pwr_pick(rng, c_values, precision),
      pwr_pick(rng, c_values, precision),
      precision,
    )
    // the unrestricted set, to put prior ends next to its ends
    let whole = a.pow_rev2(c)
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
      "CASE a=\{a.to_string()} c=\{c.to_string()} prior=\{prior.to_string()}",
    )
    let got = match cap {
      None => a.pow_rev2(c, x=prior)
      Some(limit) => a.pow_rev2_capped(c, Some(prior), limit)
    }
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
      let status = pw2_sat(x, a, c)
      let inside = !got.is_empty() &&
        x.compare(got.lo_) >= 0 &&
        x.compare(got.hi_) <= 0
      // (A) a float certainly in the set is in the result
      if status == 1 && !inside {
        fail(
          "missed: a=\{a.to_string()} c=\{c.to_string()} prior=\{prior.to_string()} got=\{got.to_string()} x=\{x.to_string()}",
        )
      }
    }
    // tightness of an end that comes from a piece (not from the prior, not infinite):
    // the real set starts at t with RD(t) = the lower end, so a point a quarter of a
    // float below the lower end is not in the set, and the float one step above the
    // lower end is not certainly outside while the next one is certainly inside
    if cap is None && !got.is_empty() {
      let sat_of = fn(x : @binary.Binary) {
        if x.classify() != FpClass::Finite {
          2
        } else {
          pw2_sat(x, a, c)
        }
      }
      let lo = got.lo_
      if lo.classify() == FpClass::Finite && lo.compare(prior.lo_) > 0 {
        let below = lo.next_down_ctx(ctx).0
        let above = lo.next_up_ctx(ctx).0
        let above2 = above.next_up_ctx(ctx).0
        if sat_of(pwr_between(below, lo, 3)) == 1 {
          fail(
            "lower end too high: a=\{a.to_string()} c=\{c.to_string()} prior=\{prior.to_string()} got=\{got.to_string()}",
          )
        }
        if sat_of(above) == 0 && sat_of(above2) == 1 {
          fail(
            "lower end too low: a=\{a.to_string()} c=\{c.to_string()} prior=\{prior.to_string()} got=\{got.to_string()}",
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
            "upper end too low: a=\{a.to_string()} c=\{c.to_string()} prior=\{prior.to_string()} got=\{got.to_string()}",
          )
        }
        if sat_of(below) == 0 && sat_of(below2) == 1 {
          fail(
            "upper end too high: a=\{a.to_string()} c=\{c.to_string()} prior=\{prior.to_string()} got=\{got.to_string()}",
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
/// 113).
// oracle: B
// source: the base-side reference: the forward pow at 200 bits and a bisection over the prior; no code of pow_reverse2.mbt; the case is checked for the exact hull (tightness) where the test says so, and for enclosure and containment in the prior in the capped fallback
// shares: forward Interval::pow at 200 bits, Interval add/sub at 200 bits
// primitives: forward pow: forward_reference_wbtest.mbt (MPFR rows, level A, tightness, 80 rows with a point exponent); add, sub: ITF1788 and the MPFR differential stage
test "pow_rev2 reference sample: against the forward pow at 200 bits" {
  pw2_check(24, 8, 201UL)
  pw2_check(53, 8, 202UL)
  pw2_check(113, 8, 203UL)
}

///|
/// The fallback: with no refinement (cap 0) and one (cap 1) every float certainly in the
/// set is still in the result, which stays inside the prior.
// oracle: B
// source: the base-side reference: the forward pow at 200 bits and a bisection over the prior; no code of pow_reverse2.mbt; the case is checked for the exact hull (tightness) where the test says so, and for enclosure and containment in the prior in the capped fallback
// shares: forward Interval::pow at 200 bits, Interval add/sub at 200 bits
// primitives: forward pow: forward_reference_wbtest.mbt (MPFR rows, level A, tightness, 80 rows with a point exponent); add, sub: ITF1788 and the MPFR differential stage
test "pow_rev2 reference fallback: the cap at 0 and at 1 never misses a point" {
  pw2_check(24, 6, 211UL, cap=0)
  pw2_check(53, 6, 212UL, cap=1)
  pw2_check(113, 6, 213UL, cap=0)
}

#skip("long run: the interval gate runs it with --include-skipped")

///|
/// The long run: 700 cases at each of three precisions, run by the interval gate with
/// `--include-skipped`.
// oracle: B
// source: the base-side reference: the forward pow at 200 bits and a bisection over the prior; no code of pow_reverse2.mbt; the case is checked for the exact hull (tightness) where the test says so, and for enclosure and containment in the prior in the capped fallback
// shares: forward Interval::pow at 200 bits, Interval add/sub at 200 bits
// primitives: forward pow: forward_reference_wbtest.mbt (MPFR rows, level A, tightness, 80 rows with a point exponent); add, sub: ITF1788 and the MPFR differential stage
test "pow_rev2 reference long: against the forward pow at 200 bits" {
  pw2_check(24, 700, 21UL)
  pw2_check(53, 700, 22UL)
  pw2_check(113, 700, 23UL)
}
