///|
/// The reverse-mode functions of IEEE 1788-2015 Table 10.1 that invert an even
/// or monotone algebraic function: `sqr_rev`, `abs_rev`, `pown_rev` and
/// `cosh_rev`. Each is the hull of `{ x in x | f(x) in c }` (10.5.4, equation 5),
/// the natural reverse extension, where `x` is an optional prior interval
/// (default Entire). The preimage of `c` is one or two intervals, found from
/// the inverse function at the ends of `c`; the pieces are then met with `x`.

///|
fn rev_neg_bound(x : @bin_float.BinFloat) -> @bin_float.BinFloat {
  if x.is_zero() {
    x.abs()
  } else {
    x.neg()
  }
}

///|
/// The bound of `value^(1/degree)` for a possibly infinite or zero `value` and
/// a nonzero `degree` (negative for a negative power): the limit at an infinite
/// `value`, the pole at zero for a negative degree, otherwise the directed
/// `rootn` of the exact point.
fn rev_root_bound(
  value : @bin_float.BinFloat,
  degree : Int32,
  precision : Int32,
  upper~ : Bool,
) -> @bin_float.BinFloat {
  if degree == 1 {
    return value
  }
  if value.classify() == FpClass::Infinity {
    return if degree < 0 {
      @bin_float.BinFloat::zero(precision~)
    } else {
      value
    }
  }
  if value.is_zero() {
    return if degree < 0 {
      pos_inf(precision)
    } else {
      @bin_float.BinFloat::zero(precision~)
    }
  }
  let point = BallFloat::exact(value, precision=value.precision())
  let root = if degree == 2 { point.sqrt() } else { point.rootn(degree) }
  let bound = if upper { root.hi_ } else { root.lo_ }
  if bound.is_zero() {
    @bin_float.BinFloat::zero(precision~)
  } else {
    bound
  }
}

///|
/// The two symmetric pieces `[-r_hi, -r_lo]` and `[r_lo, r_hi]` of the preimage
/// of `c` cut at `floor` under an even function whose inverse on the positive
/// side is `root`; none when `c` lies below `floor`.
fn rev_symmetric_pieces(
  c : BallFloat,
  floor : @bin_float.BinFloat,
  root : (@bin_float.BinFloat, Bool) -> @bin_float.BinFloat,
) -> Array[RevPiece] {
  let pieces : Array[RevPiece] = []
  if c.is_empty() || c.hi_.compare(floor) < 0 {
    return pieces
  }
  let lo = if c.lo_.compare(floor) < 0 { floor } else { c.lo_ }
  let r_lo = root(lo, false)
  let r_hi = root(c.hi_, true)
  pieces.push(rev_piece(rev_neg_bound(r_hi), false, rev_neg_bound(r_lo), false))
  pieces.push(rev_piece(r_lo, false, r_hi, false))
  pieces
}

///|
fn rev_prior_precision(c : BallFloat, x : BallFloat?) -> (Int32, BallFloat) {
  match x {
    Some(prior) => (Int32::max(c.precision_, prior.precision_), prior)
    None => (c.precision_, BallFloat::entire(precision=c.precision_))
  }
}

///|
/// `sqrRev(c, x)`: the hull of `{ x in x | x^2 in c }`. For `c = [1, 4]` and
/// the default prior it is `[-2, 2]`; with the prior `[0, 1.2]` it is `[1, 1.2]`.
pub fn BallFloat::sqr_rev(self : BallFloat, x? : BallFloat) -> BallFloat {
  let (precision, prior) = rev_prior_precision(self, x)
  let pieces = rev_symmetric_pieces(
    self,
    @bin_float.BinFloat::zero(precision~),
    fn(value, upper) { rev_root_bound(value, 2, precision, upper~) },
  )
  rev_hull_in_prior(pieces, prior, precision)
}

///|
/// `absRev(c, x)`: the hull of `{ x in x | |x| in c }`.
pub fn BallFloat::abs_rev(self : BallFloat, x? : BallFloat) -> BallFloat {
  let (precision, prior) = rev_prior_precision(self, x)
  let pieces = rev_symmetric_pieces(
    self,
    @bin_float.BinFloat::zero(precision~),
    fn(value, _upper) { value },
  )
  rev_hull_in_prior(pieces, prior, precision)
}

///|
/// `coshRev(c, x)`: the hull of `{ x in x | cosh(x) in c }`; `cosh` is at least
/// 1, so the part of `c` below 1 contributes nothing.
pub fn BallFloat::cosh_rev(self : BallFloat, x? : BallFloat) -> BallFloat {
  let (precision, prior) = rev_prior_precision(self, x)
  let one = @bin_float.BinFloat::from_int(1, precision~)
  let pieces = rev_symmetric_pieces(self, one, fn(value, upper) {
    if value.classify() == FpClass::Infinity {
      return value
    }
    let r = BallFloat::exact(value, precision=value.precision()).acosh()
    let bound = if upper { r.hi_ } else { r.lo_ }
    if bound.is_zero() {
      @bin_float.BinFloat::zero(precision~)
    } else {
      bound
    }
  })
  rev_hull_in_prior(pieces, prior, precision)
}

///|
/// `pownRev(c, x, p)`: the hull of `{ x in x | x^p in c }`, with `x^p` the
/// integer power of `pown`: `x^0 = 1` for every `x`, and for `p < 0` only
/// `x != 0` is in the domain. The prior `x` is the optional last argument here.
pub fn BallFloat::pown_rev(
  self : BallFloat,
  p : Int32,
  x? : BallFloat,
) -> BallFloat {
  let (precision, prior) = rev_prior_precision(self, x)
  let zero = @bin_float.BinFloat::zero(precision~)
  let neg_inf_bound = neg_inf(precision)
  let pos_inf_bound = pos_inf(precision)
  let pieces : Array[RevPiece] = []
  if self.is_empty() {
    return empty_interval(precision)
  }
  let even = p % 2 == 0
  if p == 0 {
    // x^0 = 1 for every real x
    let one = @bin_float.BinFloat::from_int(1, precision~)
    if self.lo_.compare(one) <= 0 && self.hi_.compare(one) >= 0 {
      pieces.push(rev_piece(neg_inf_bound, false, pos_inf_bound, false))
    }
  } else if p > 0 && even {
    for
      piece in rev_symmetric_pieces(self, zero, fn(value, upper) {
        rev_root_bound(value, p, precision, upper~)
      }) {
      pieces.push(piece)
    }
  } else if p > 0 {
    // odd positive power: increasing, one piece
    pieces.push(
      rev_piece(
        rev_root_bound(self.lo_, p, precision, upper=false),
        false,
        rev_root_bound(self.hi_, p, precision, upper=true),
        false,
      ),
    )
  } else if even {
    // negative even power: x^p > 0, decreasing in |x|, x != 0
    if self.hi_.sign() == Sign::Positive {
      let lo = if self.lo_.sign() == Sign::Negative || self.lo_.is_zero() {
        zero
      } else {
        self.lo_
      }
      let r_hi = rev_root_bound(lo, p, precision, upper=true)
      let r_lo = rev_root_bound(self.hi_, p, precision, upper=false)
      let open_zero = r_lo.is_zero()
      pieces.push(
        rev_piece(rev_neg_bound(r_hi), false, rev_neg_bound(r_lo), open_zero),
      )
      pieces.push(rev_piece(r_lo, open_zero, r_hi, false))
    }
  } else {
    // negative odd power: x^p has the sign of x and is decreasing on each side
    if self.lo_.sign() == Sign::Negative {
      let upper_c = if self.hi_.sign() == Sign::Positive {
        zero
      } else {
        self.hi_
      }
      let x_lo = rev_root_bound(upper_c, p, precision, upper=false)
      let x_lo = if upper_c.is_zero() { neg_inf_bound } else { x_lo }
      let x_hi = rev_root_bound(self.lo_, p, precision, upper=true)
      let x_hi = rev_neg_bound_if_zero(x_hi)
      pieces.push(rev_piece(x_lo, false, x_hi, x_hi.is_zero()))
    }
    if self.hi_.sign() == Sign::Positive {
      let lower_c = if self.lo_.sign() == Sign::Negative || self.lo_.is_zero() {
        zero
      } else {
        self.lo_
      }
      let x_hi = rev_root_bound(lower_c, p, precision, upper=true)
      let x_lo = rev_root_bound(self.hi_, p, precision, upper=false)
      pieces.push(rev_piece(x_lo, x_lo.is_zero(), x_hi, false))
    }
  }
  rev_hull_in_prior(pieces, prior, precision)
}

///|
fn rev_neg_bound_if_zero(x : @bin_float.BinFloat) -> @bin_float.BinFloat {
  if x.is_zero() {
    x.abs()
  } else {
    x
  }
}

///|
/// The reverse-mode functions on decorated intervals have the trivial
/// decorated version of IEEE 1788-2015 11.7.1: NaI if any input is NaI, else
/// the bare result decorated `Trv`.
fn BallFloatDecorated::rev_decorated_unary(
  self : BallFloatDecorated,
  x : BallFloatDecorated?,
  bare : (BallFloat, BallFloat?) -> BallFloat,
) -> BallFloatDecorated {
  let precision = self.interval_.precision_
  if self.is_nai() || (x is Some(prior) && prior.is_nai()) {
    return BallFloatDecorated::nai(precision~)
  }
  let prior = match x {
    Some(p) => Some(p.interval_)
    None => None
  }
  BallFloatDecorated::new(bare(self.interval_, prior), decoration=Trv)
}

///|
pub fn BallFloatDecorated::sqr_rev(
  self : BallFloatDecorated,
  x? : BallFloatDecorated,
) -> BallFloatDecorated {
  self.rev_decorated_unary(x, fn(c, prior) { c.sqr_rev(x?=prior) })
}

///|
pub fn BallFloatDecorated::abs_rev(
  self : BallFloatDecorated,
  x? : BallFloatDecorated,
) -> BallFloatDecorated {
  self.rev_decorated_unary(x, fn(c, prior) { c.abs_rev(x?=prior) })
}

///|
pub fn BallFloatDecorated::cosh_rev(
  self : BallFloatDecorated,
  x? : BallFloatDecorated,
) -> BallFloatDecorated {
  self.rev_decorated_unary(x, fn(c, prior) { c.cosh_rev(x?=prior) })
}

///|
pub fn BallFloatDecorated::pown_rev(
  self : BallFloatDecorated,
  p : Int32,
  x? : BallFloatDecorated,
) -> BallFloatDecorated {
  self.rev_decorated_unary(x, fn(c, prior) { c.pown_rev(p, x?=prior) })
}
