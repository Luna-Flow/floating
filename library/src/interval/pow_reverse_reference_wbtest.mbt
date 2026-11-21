///|
/// A reference for `pow_rev1` that does not use the pieces of the implementation: the
/// condition `exists beta in b : x^beta in c` is evaluated for a float `x` with the
/// forward `Interval::pow` at 200 bits (the range of `x^beta` over `b` is the
/// interval `pow(x, b)`, since `beta -> x^beta` is monotone), and the result is
/// checked against it: every float certainly in the set is in the result (a wrong
/// Empty has no end to check), and the float one step outside either end of the
/// result, where the end comes from a piece and not from the prior, is certainly not
/// in the set.

///|
priv struct PowRng {
  mut state : UInt64
}

///|
fn PowRng::next(self : PowRng) -> UInt64 {
  self.state = self.state * 6364136223846793005UL + 1442695040888963407UL
  self.state >> 33
}

///|
fn PowRng::below(self : PowRng, n : Int32) -> Int32 {
  (self.next() % n.to_uint64()).to_int()
}

///|
let pwr_w : Int32 = 200

///|
/// 0: certainly not in the set, 1: certainly in, 2: not decided at this precision.
fn pwr_sat(x : @binary.Binary, b : Interval, c : Interval) -> Int32 {
  let e = Interval::exact(x, precision=pwr_w).pow(b.with_precision(pwr_w))
  if e.is_empty() {
    return 0
  }
  if e.hi_.compare(c.lo_) < 0 || e.lo_.compare(c.hi_) > 0 {
    return 0
  }
  // E contains the range R of x^beta over b within delta << tol: if c reaches more
  // than tol beyond both ends of E, then c meets R
  let tol = @binary.Binary::make(
    @binary.BinCoeff::from_uint64(1UL),
    -(pwr_w / 2),
    1,
  )
  let one_side = fn(hi : @binary.Binary, lo : @binary.Binary) {
    // hi - lo > tol, with infinities
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
/// `e + (f - e) * num / 4` computed exactly (all operands have far fewer than 200 bits).
fn pwr_between(
  e : @binary.Binary,
  f : @binary.Binary,
  num : Int32,
) -> @binary.Binary {
  let diff = Interval::exact(f, precision=pwr_w) -
    Interval::exact(e, precision=pwr_w)
  let scaled = diff *
    Interval::exact(@binary.Binary::from_double(num.to_double() * 0.25))
  (Interval::exact(e, precision=pwr_w) + scaled).lo_
}

///|
fn pwr_pick(
  rng : PowRng,
  values : Array[Double],
  precision : Int32,
) -> @binary.Binary {
  let x = values[rng.below(values.length())]
  if x == 1.0 / 0.0 {
    pos_inf(precision)
  } else if x == -1.0 / 0.0 {
    neg_inf(precision)
  } else {
    pw_num(x, precision)
  }
}

///|
fn pwr_ordered(
  a : @binary.Binary,
  b : @binary.Binary,
  precision : Int32,
) -> Interval {
  let (lo, hi) = if a.compare(b) <= 0 { (a, b) } else { (b, a) }
  // an interval cannot start at +infinity or end at -infinity
  let lo = if is_pos_inf(lo) { pw_num(8.0, precision) } else { lo }
  let hi = if is_neg_inf(hi) { pw_num(-8.0, precision) } else { hi }
  Interval::from_bounds(lo, hi, precision~)
}

///|
fn pwr_check(
  precision : Int32,
  cases : Int32,
  seed : UInt64,
  cap? : Int32,
) -> Unit raise {
  let rng : PowRng = { state: seed, }
  let b_values = [
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
    1.0 / 0.0,
  ]
  let x_values = [
    0.0, 0.1, 0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0, 4.0, 10.0, 30.0,
  ]
  let ctx = @binary.BinaryContext::new(precision~)
  let mut nonempty = 0
  for _ in 0..<cases {
    let b = pwr_ordered(
      pwr_pick(rng, b_values, precision),
      pwr_pick(rng, b_values, precision),
      precision,
    )
    let c = pwr_ordered(
      pwr_pick(rng, c_values, precision),
      pwr_pick(rng, c_values, precision),
      precision,
    )
    // the unrestricted set, to put prior ends next to its ends
    let whole = b.pow_rev1(c)
    let mut xl = pw_num(x_values[rng.below(x_values.length())], precision)
    let mut xh = pw_num(x_values[rng.below(x_values.length())], precision)
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
    if xl.signum() == Sign::Negative {
      xl = pw_num(0.0, precision)
    }
    if xh.signum() == Sign::Negative || xh.is_zero() {
      xh = xl
    }
    let prior = pwr_ordered(xl, xh, precision)
    println(
      "CASE b=\{b.to_string()} c=\{c.to_string()} prior=\{prior.to_string()}",
    )
    let got = match cap {
      None => b.pow_rev1(c, x=prior)
      Some(limit) => b.pow_rev1_capped(c, Some(prior), limit)
    }
    let candidates : Array[@binary.Binary] = []
    candidates.push(prior.lo_)
    candidates.push(prior.hi_)
    // fixed interior points
    for value in x_values {
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
      if x.classify() != FpClass::Finite || x.signum() != Sign::Positive {
        continue
      }
      if x.compare(prior.lo_) < 0 || x.compare(prior.hi_) > 0 {
        continue
      }
      let status = pwr_sat(x, b, c)
      let inside = !got.is_empty() &&
        x.compare(got.lo_) >= 0 &&
        x.compare(got.hi_) <= 0
      // (A) a float certainly in the set is in the result
      if status == 1 && !inside {
        fail(
          "missed: b=\{b.to_string()} c=\{c.to_string()} prior=\{prior.to_string()} got=\{got.to_string()} x=\{x.to_string()}",
        )
      }
      if cap is None {
        // (B) the float one step outside an end that comes from a piece is not in the set
        if status == 1 && !got.is_empty() {
          let outside_lo = x.compare(got.lo_) < 0
          let outside_hi = x.compare(got.hi_) > 0
          if outside_lo || outside_hi {
            fail(
              "not tight: b=\{b.to_string()} c=\{c.to_string()} prior=\{prior.to_string()} got=\{got.to_string()} x=\{x.to_string()}",
            )
          }
        }
      }
    }
    // tightness of an end that comes from a piece (not from the prior, not infinite, not 0):
    // the real set starts at t with RD(t) = the lower end, so a point a quarter of a
    // float below the lower end is not in the set, and the float one step above the lower
    // end is not certainly outside while the next one is certainly inside
    if cap is None && !got.is_empty() {
      let sat_of = fn(x : @binary.Binary) {
        if x.signum() != Sign::Positive || x.classify() != FpClass::Finite {
          2
        } else {
          pwr_sat(x, b, c)
        }
      }
      let lo = got.lo_
      if lo.classify() == FpClass::Finite &&
        lo.signum() == Sign::Positive &&
        lo.compare(prior.lo_) > 0 {
        let below = lo.next_down_ctx(ctx).0
        let above = lo.next_up_ctx(ctx).0
        let above2 = above.next_up_ctx(ctx).0
        if sat_of(pwr_between(below, lo, 3)) == 1 {
          fail(
            "lower end too high: b=\{b.to_string()} c=\{c.to_string()} prior=\{prior.to_string()} got=\{got.to_string()}",
          )
        }
        if sat_of(above) == 0 && sat_of(above2) == 1 {
          fail(
            "lower end too low: b=\{b.to_string()} c=\{c.to_string()} prior=\{prior.to_string()} got=\{got.to_string()}",
          )
        }
      }
      let hi = got.hi_
      if hi.classify() == FpClass::Finite &&
        hi.signum() == Sign::Positive &&
        hi.compare(prior.hi_) < 0 {
        let above = hi.next_up_ctx(ctx).0
        let below = hi.next_down_ctx(ctx).0
        let below2 = below.next_down_ctx(ctx).0
        if sat_of(pwr_between(hi, above, 1)) == 1 {
          fail(
            "upper end too low: b=\{b.to_string()} c=\{c.to_string()} prior=\{prior.to_string()} got=\{got.to_string()}",
          )
        }
        if sat_of(below) == 0 && sat_of(below2) == 1 {
          fail(
            "upper end too high: b=\{b.to_string()} c=\{c.to_string()} prior=\{prior.to_string()} got=\{got.to_string()}",
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
// source: the exponent-side reference: the forward pow at 200 bits and a bisection over the prior; no code of pow_reverse.mbt; the case is checked for the exact hull (tightness) where the test says so, and for enclosure and containment in the prior in the capped fallback
// shares: forward Interval::pow at 200 bits, Interval add/sub at 200 bits
// primitives: forward pow: forward_reference_wbtest.mbt (MPFR rows, level A, tightness, 80 rows with a point exponent, while pow_rev1 uses an interval exponent); add, sub: ITF1788 and the MPFR differential stage
test "pow_rev1 reference sample: against the forward pow at 200 bits" {
  pwr_check(24, 8, 101UL)
  pwr_check(53, 8, 102UL)
  pwr_check(113, 8, 103UL)
}

///|
/// The fallback: with no refinement (cap 0) and one (cap 1) every float certainly in the
/// set is still in the result, which stays inside the prior.
// oracle: B
// source: the exponent-side reference: the forward pow at 200 bits and a bisection over the prior; no code of pow_reverse.mbt; the case is checked for the exact hull (tightness) where the test says so, and for enclosure and containment in the prior in the capped fallback
// shares: forward Interval::pow at 200 bits, Interval add/sub at 200 bits
// primitives: forward pow: forward_reference_wbtest.mbt (MPFR rows, level A, tightness, 80 rows with a point exponent, while pow_rev1 uses an interval exponent); add, sub: ITF1788 and the MPFR differential stage
test "pow_rev1 reference fallback: the cap at 0 and at 1 never misses a point" {
  pwr_check(24, 6, 111UL, cap=0)
  pwr_check(53, 6, 112UL, cap=1)
  pwr_check(113, 6, 113UL, cap=0)
}

///|
/// The long run: 700 cases at each of three precisions, run by the interval gate with
/// `--include-skipped`.
// oracle: B
// source: the exponent-side reference: the forward pow at 200 bits and a bisection over the prior; no code of pow_reverse.mbt; the case is checked for the exact hull (tightness) where the test says so, and for enclosure and containment in the prior in the capped fallback
// shares: forward Interval::pow at 200 bits, Interval add/sub at 200 bits
// primitives: forward pow: forward_reference_wbtest.mbt (MPFR rows, level A, tightness, 80 rows with a point exponent, while pow_rev1 uses an interval exponent); add, sub: ITF1788 and the MPFR differential stage
#skip("long run: the interval gate runs it with --include-skipped")
test "pow_rev1 reference long: against the forward pow at 200 bits" {
  pwr_check(24, 700, 1UL)
  pwr_check(53, 700, 2UL)
  pwr_check(113, 700, 3UL)
}
