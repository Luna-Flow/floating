///|
/// A reference for the reverse trigonometric functions that shares nothing with
/// the implementation's index arithmetic or comparison loops: it lists every
/// piece for every period index in a window that covers the prior, with
/// enclosures at 400 bits, and decides each comparison by the enclosure (every
/// end but 0 is irrational, and 0 has a zero-width enclosure).

///|
priv struct RefRng {
  mut state : UInt64
}

///|
fn RefRng::next(self : RefRng) -> UInt64 {
  self.state = self.state * 6364136223846793005UL + 1442695040888963407UL
  self.state >> 33
}

///|
/// A uniform integer in `[0, n)`.
fn RefRng::below(self : RefRng, n : Int32) -> Int32 {
  (self.next() % n.to_uint64()).to_int()
}

///|
let ref_w : Int32 = 200

///|
fn ref_cmp(e : Interval, d : @binary.Binary) -> Int32 {
  if e.lo_.compare(d) > 0 {
    1
  } else if e.hi_.compare(d) < 0 {
    -1
  } else {
    0
  }
}

///|
/// The pieces `[lo, hi]` (as enclosures) of `f^-1(c)` for the period indices
/// `kmin ..= kmax`; `kind` is 0 for sin, 1 for cos and 2 for tan.
fn ref_pieces(
  kind : Int32,
  c : Interval,
  kmin : Int32,
  kmax : Int32,
) -> Array[(Interval, Interval)] {
  let pi = certified_pi_interval(ref_w)
  let two_pi = pi * Interval::exact(@binary.Binary::from_int(2))
  let at = fn(s : @binary.Binary) { Interval::exact(s, precision=ref_w) }
  let out : Array[(Interval, Interval)] = []
  for k in kmin..<=kmax {
    let kf = Interval::exact(@binary.Binary::from_int(k))
    if kind == 2 {
      // (atan lo + pi k, atan hi + pi k), poles open and not floats
      let shift = kf * pi
      let half_pi = pi * Interval::exact(@binary.Binary::from_double(0.5))
      let lo = if c.lo_.classify() == FpClass::Infinity {
        shift - half_pi
      } else {
        at(c.lo_).atan() + shift
      }
      let hi = if c.hi_.classify() == FpClass::Infinity {
        shift + half_pi
      } else {
        at(c.hi_).atan() + shift
      }
      out.push((lo, hi))
    } else {
      let one = @binary.Binary::from_int(1)
      let minus_one = @binary.Binary::from_int(-1)
      let s_lo = if c.lo_.compare(minus_one) < 0 { minus_one } else { c.lo_ }
      let s_hi = if c.hi_.compare(one) > 0 { one } else { c.hi_ }
      let shift = kf * two_pi
      if kind == 0 {
        let a = at(s_lo).asin()
        let b = at(s_hi).asin()
        out.push((a + shift, b + shift))
        out.push((shift + pi - b, shift + pi - a))
      } else {
        let a = at(s_hi).acos()
        let b = at(s_lo).acos()
        out.push((a + shift, b + shift))
        out.push((shift - b, shift - a))
      }
    }
  }
  out
}

///|
fn ref_hull(
  kind : Int32,
  c : Interval,
  prior : Interval,
  prior_lo : Double,
  prior_hi : Double,
  precision : Int32,
) -> Interval {
  let xl = prior.lo_
  let xh = prior.hi_
  // sin and cos reach only [-1, 1]
  if kind != 2 &&
    (
      c.hi_.compare(@binary.Binary::from_int(-1)) < 0 ||
      c.lo_.compare(@binary.Binary::from_int(1)) > 0
    ) {
    return empty_interval(precision)
  }
  // the window of period indices from plain floating point, generously wide
  let period = if kind == 2 { 3.141592653589793 } else { 6.283185307179586 }
  let kmin = (prior_lo / period).floor().to_int() - 3
  let kmax = (prior_hi / period).floor().to_int() + 3
  let down = @binary.BinaryRoundingMode::RoundTowardNegative
  let up = @binary.BinaryRoundingMode::RoundTowardPositive
  let mut lower : @binary.Binary? = None
  let mut upper : @binary.Binary? = None
  for piece in ref_pieces(kind, c, kmin, kmax) {
    let (lo, hi) = piece
    // the piece meets the prior iff hi >= xl and lo <= xh
    if ref_cmp(hi, xl) < 0 || ref_cmp(lo, xh) > 0 {
      continue
    }
    let v = if ref_cmp(lo, xl) <= 0 {
      xl
    } else {
      lo.lo_.with_precision(precision, down)
    }
    let w = if ref_cmp(hi, xh) >= 0 {
      xh
    } else {
      hi.hi_.with_precision(precision, up)
    }
    lower = match lower {
      Some(current) if current.compare(v) <= 0 => Some(current)
      _ => Some(v)
    }
    upper = match upper {
      Some(current) if current.compare(w) >= 0 => Some(current)
      _ => Some(w)
    }
  }
  match (lower, upper) {
    (Some(l), Some(u)) => Interval::from_bounds(l, u, precision~)
    _ => empty_interval(precision)
  }
}

///|
fn ref_double(rng : RefRng, lo : Double, hi : Double) -> Double {
  let u = rng.below(1000000).to_double() / 1000000.0
  lo + (hi - lo) * u
}

///|
fn ref_float(
  rng : RefRng,
  lo : Double,
  hi : Double,
  precision : Int32,
) -> @binary.Binary {
  tr_num(ref_double(rng, lo, hi), precision)
}

///|
/// A random `c` that is often at 0 or at +-1 and, for tan, sometimes unbounded.
fn ref_c(rng : RefRng, kind : Int32, precision : Int32) -> Interval {
  let special = [0.0, 0.0, 1.0, -1.0, 0.5, -0.5]
  let pick = fn() {
    if rng.below(3) == 0 {
      tr_num(special[rng.below(6)], precision)
    } else if kind == 2 {
      ref_float(rng, -6.0, 6.0, precision)
    } else {
      ref_float(rng, -1.2, 1.2, precision)
    }
  }
  let a = pick()
  let b = pick()
  let (lo, hi) = if a.compare(b) <= 0 { (a, b) } else { (b, a) }
  let lo = if kind == 2 && rng.below(8) == 0 { neg_inf(precision) } else { lo }
  let hi = if kind == 2 && rng.below(8) == 0 { pos_inf(precision) } else { hi }
  if lo.classify() == FpClass::Infinity && hi.classify() == FpClass::Infinity {
    return Interval::from_bounds(lo, hi, precision~)
  }
  Interval::from_bounds(lo, hi, precision~)
}

///|
fn ref_check(
  kind : Int32,
  precision : Int32,
  cases : Int32,
  seed : UInt64,
  cap? : Int32,
) -> Unit raise {
  let rng : RefRng = { state: seed, }
  let mut checked = 0
  let mut nonempty = 0
  for _ in 0..<cases {
    let c = ref_c(rng, kind, precision)
    // offsets from 0 to several thousand periods, widths from one gap to a few periods
    let periods = if rng.below(4) == 0 { rng.below(3000) } else { rng.below(8) }
    let centre = periods.to_double() * 6.283185307179586 +
      ref_double(rng, -4.0, 4.0)
    let width = match rng.below(4) {
      0 => 0.0
      1 => ref_double(rng, 0.0, 0.5)
      2 => ref_double(rng, 0.0, 3.0)
      _ => ref_double(rng, 0.0, 14.0)
    }
    let sign = if rng.below(2) == 0 { 1.0 } else { -1.0 }
    let a = centre * sign
    let b = (centre + width) * sign
    let (xl, xh) = if a <= b { (a, b) } else { (b, a) }
    let mut pl = tr_num(xl, precision)
    let mut ph = tr_num(xh, precision)
    if rng.below(3) == 0 {
      // put one end of the prior next to a piece end: RD, RU, or a neighbour
      let period = if kind == 2 { 3.141592653589793 } else { 6.283185307179586 }
      let k0 = (xl / period).floor().to_int()
      let pieces = ref_pieces(kind, c, k0, k0 + 1)
      let (lo, hi) = pieces[rng.below(pieces.length())]
      let e = if rng.below(2) == 0 { lo } else { hi }
      let down = @binary.BinaryRoundingMode::RoundTowardNegative
      let up = @binary.BinaryRoundingMode::RoundTowardPositive
      let near = match rng.below(4) {
        0 => e.lo_.with_precision(precision, down)
        1 => e.hi_.with_precision(precision, up)
        2 => tr_up(e.hi_.with_precision(precision, up), precision)
        _ => tr_down(e.lo_.with_precision(precision, down), precision)
      }
      if rng.below(2) == 0 {
        if near.compare(ph) <= 0 {
          pl = near
        }
      } else if near.compare(pl) >= 0 {
        ph = near
      }
    }
    let prior = tr_box(pl, ph, precision)
    let want = ref_hull(kind, c, prior, xl, xh, precision)
    let got = match cap {
      None =>
        match kind {
          0 => c.sin_rev(x=prior)
          1 => c.cos_rev(x=prior)
          _ => c.tan_rev(x=prior)
        }
      Some(limit) =>
        match kind {
          0 => c.sin_rev_capped(Some(prior), limit)
          1 => c.cos_rev_capped(Some(prior), limit)
          _ => c.tan_rev_capped(Some(prior), limit)
        }
    }
    let ok = match cap {
      None =>
        // the result is the exact hull
        if want.is_empty() {
          got.is_empty()
        } else {
          !got.is_empty() &&
          got.lo_.compare(want.lo_) == 0 &&
          got.hi_.compare(want.hi_) == 0
        }
      Some(_) =>
        // the fallback promises an enclosure: it contains the hull, and stays inside
        // the prior
        want.is_empty() ||
        (
          !got.is_empty() &&
          got.lo_.compare(want.lo_) <= 0 &&
          got.hi_.compare(want.hi_) >= 0 &&
          got.lo_.compare(prior.lo_) >= 0 &&
          got.hi_.compare(prior.hi_) <= 0
        )
    }
    if !ok {
      fail(
        "kind \{kind} p=\{precision} c=\{c.to_string()} prior=\{prior.to_string()} want=\{want.to_string()} got=\{got.to_string()}",
      )
    }
    checked += 1
    if !want.is_empty() {
      nonempty += 1
    }
  }
  assert_eq(checked, cases)
  assert_true(nonempty > cases / 10)
}

///|
/// The sample that runs with every test run: the same classes of case as the
/// long run (random c and priors, priors with an end next to a piece end, offsets
/// up to thousands of periods), fewer cases per class, fixed seeds.
test "reference sample: sin_rev, cos_rev and tan_rev against the enumeration of every piece" {
  for kind in 0..<3 {
    ref_check(kind, 24, 10, 11UL + kind.to_uint64())
    ref_check(kind, 53, 10, 21UL + kind.to_uint64())
  }
}

///|
/// The fallback of the comparison: with no refinement allowed (cap 0) every
/// comparison of a non-zero end is undecided, with one refinement most are
/// decided at the second precision; the result must still contain the exact hull
/// (and stay inside the prior), never miss a point of the set.
test "reference fallback: with the cap at 0 and at 1 the result contains the hull" {
  for kind in 0..<3 {
    ref_check(kind, 24, 6, 31UL + kind.to_uint64(), cap=0)
    ref_check(kind, 53, 6, 41UL + kind.to_uint64(), cap=0)
    ref_check(kind, 24, 6, 51UL + kind.to_uint64(), cap=1)
    ref_check(kind, 53, 6, 61UL + kind.to_uint64(), cap=1)
  }
}

///|
/// The long run: 700 cases per function at precisions 24 and 53 (4,200 in all, about
/// 40 s). Skipped in a plain `moon test`; the interval gate runs it with
/// `--include-skipped` (`INTERVAL: reverse trigonometric reference`).
#skip("long run: the interval gate runs it with --include-skipped")
test "reference long: sin_rev against the enumeration of every piece" {
  ref_check(0, 24, 700, 1UL)
  ref_check(0, 53, 700, 2UL)
}

///|
#skip("long run: the interval gate runs it with --include-skipped")
test "reference long: cos_rev against the enumeration of every piece" {
  ref_check(1, 24, 700, 3UL)
  ref_check(1, 53, 700, 4UL)
}

///|
#skip("long run: the interval gate runs it with --include-skipped")
test "reference long: tan_rev against the enumeration of every piece" {
  ref_check(2, 24, 700, 5UL)
  ref_check(2, 53, 700, 6UL)
}
