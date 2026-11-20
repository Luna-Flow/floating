///|
/// Reverse multiplication and two-output division of IEEE 1788-2015 10.5.4 and
/// 10.5.5. For intervals `b` and `c` the set
/// `c /set b = { x in R | exists y in b with x * y in c }` has zero, one or two
/// connected components. `mul_rev_to_pair` returns their closures, ordered;
/// `mul_rev` is the hull of the part of that set that lies in the prior `x`.

///|
/// A connected component of `c /set b`, with the information whether each
/// finite endpoint belongs to it. An endpoint is open exactly when it is the
/// limit 0 of a quotient by an unbounded `b`, which is never attained; this
/// matters only when the prior `x` touches the component at that point.
priv struct RevPiece {
  lo : @bin_float.BinFloat
  lo_open : Bool
  hi : @bin_float.BinFloat
  hi_open : Bool
}

///|
fn rev_piece(
  lo : @bin_float.BinFloat,
  lo_open : Bool,
  hi : @bin_float.BinFloat,
  hi_open : Bool,
) -> RevPiece {
  { lo, lo_open, hi, hi_open, }
}

///|
/// Lower or upper bound of the quotient `num / den` of finite `num` by a
/// nonzero `den` that may be infinite (then the quotient is 0).
fn rev_quotient_bound(
  num : @bin_float.BinFloat,
  den : @bin_float.BinFloat,
  precision : Int32,
  upper~ : Bool,
) -> @bin_float.BinFloat {
  if den.classify() == FpClass::Infinity {
    return @bin_float.BinFloat::zero(precision~)
  }
  let q = BallFloat::exact(num, precision=num.precision()) /
    BallFloat::exact(den, precision=den.precision())
  let bound = if upper { q.upper_bound() } else { q.lower_bound() }
  // a zero bound is stored as +0
  if bound.is_zero() {
    @bin_float.BinFloat::zero(precision~)
  } else {
    bound
  }
}

///|
fn rev_is_zero_bound(x : @bin_float.BinFloat) -> Bool {
  x.is_zero()
}

///|
/// The components of `c /set b` in increasing order (none when empty).
fn mul_rev_pieces(b : BallFloat, c : BallFloat) -> Array[RevPiece] {
  let precision = Int32::max(b.precision_, c.precision_)
  let pieces : Array[RevPiece] = []
  if b.is_empty() || c.is_empty() {
    return pieces
  }
  let neg_inf_bound = neg_inf(precision)
  let pos_inf_bound = pos_inf(precision)
  let zero_in_c = c.contains_zero()
  let zero_in_b = b.contains_zero()
  if zero_in_c && zero_in_b {
    pieces.push(rev_piece(neg_inf_bound, false, pos_inf_bound, false))
    return pieces
  }
  if !zero_in_b {
    // y never vanishes: the set is the interval quotient c / b
    let q = c / b
    let lo = q.lower_bound()
    let hi = q.upper_bound()
    // 0 not in c: a bound 0 is the unattained limit of a quotient by an
    // unbounded b (when 0 is in c, x = 0 is attained)
    let lo_open = !zero_in_c && rev_is_zero_bound(lo)
    let hi_open = !zero_in_c && rev_is_zero_bound(hi)
    pieces.push(rev_piece(lo, lo_open, hi, hi_open))
    return pieces
  }
  // 0 in b, 0 not in c: only the values y != 0 of b contribute
  if b.lo_.is_zero() && b.hi_.is_zero() {
    return pieces
  }
  let c_positive = c.lo_.sign() == Sign::Positive
  // the end of c nearest to zero
  let near = if c_positive { c.lo_ } else { c.hi_ }
  let has_negative_y = b.lo_.sign() == Sign::Negative
  let has_positive_y = b.hi_.sign() == Sign::Positive
  // y < 0 side, y > 0 side of the divisor
  let from_negative = fn() {
    // x * y in c with y in [b.lo, 0): x <= near / b.lo when c > 0,
    // x >= near / b.lo when c < 0
    let q_up = rev_quotient_bound(near, b.lo_, precision, upper=true)
    let q_dn = rev_quotient_bound(near, b.lo_, precision, upper=false)
    if c_positive {
      rev_piece(neg_inf_bound, false, q_up, rev_is_zero_bound(q_up))
    } else {
      rev_piece(q_dn, rev_is_zero_bound(q_dn), pos_inf_bound, false)
    }
  }
  let from_positive = fn() {
    // y in (0, b.hi]: x >= near / b.hi when c > 0, x <= near / b.hi when c < 0
    let q_up = rev_quotient_bound(near, b.hi_, precision, upper=true)
    let q_dn = rev_quotient_bound(near, b.hi_, precision, upper=false)
    if c_positive {
      rev_piece(q_dn, rev_is_zero_bound(q_dn), pos_inf_bound, false)
    } else {
      rev_piece(neg_inf_bound, false, q_up, rev_is_zero_bound(q_up))
    }
  }
  if has_negative_y && has_positive_y {
    // two components, the one for the negative y is the left one when c > 0
    if c_positive {
      pieces.push(from_negative())
      pieces.push(from_positive())
    } else {
      pieces.push(from_positive())
      pieces.push(from_negative())
    }
  } else if has_negative_y {
    pieces.push(from_negative())
  } else {
    pieces.push(from_positive())
  }
  pieces
}

///|
fn rev_piece_interval(piece : RevPiece, precision : Int32) -> BallFloat {
  BallFloat::from_bounds(piece.lo, piece.hi, precision~)
}

///|
/// `mulRevToPair(b, c)` of IEEE 1788-2015 10.5.5: the closures of the
/// connected components of `c /set b`, in increasing order, as the pair
/// `(u, v)`: `(Empty, Empty)` for no component, `(u, Empty)` for one. When
/// there are two, they can share an endpoint (`[1, 1] /set Entire` gives
/// `([-inf, 0], [0, +inf])`).
pub fn BallFloat::mul_rev_to_pair(
  self : BallFloat,
  c : BallFloat,
) -> (BallFloat, BallFloat) {
  let precision = Int32::max(self.precision_, c.precision_)
  let pieces = mul_rev_pieces(self, c)
  match pieces.length() {
    0 => (empty_interval(precision), empty_interval(precision))
    1 => (rev_piece_interval(pieces[0], precision), empty_interval(precision))
    _ =>
      (
        rev_piece_interval(pieces[0], precision),
        rev_piece_interval(pieces[1], precision),
      )
  }
}

///|
/// `mulRev(b, c, x)` of IEEE 1788-2015 Table 10.1: the hull of
/// `{ x in x | exists y in b with x * y in c }`, the natural reverse
/// extension. The prior `x` defaults to Entire. The hull is taken of the set
/// itself and not of its closure: `[-1, 0]` meets the unattained component
/// `(0, 1]` in nothing, so the result is Empty.
pub fn BallFloat::mul_rev(
  self : BallFloat,
  c : BallFloat,
  x? : BallFloat,
) -> BallFloat {
  let precision = match x {
    Some(prior) =>
      Int32::max(Int32::max(self.precision_, c.precision_), prior.precision_)
    None => Int32::max(self.precision_, c.precision_)
  }
  let prior = match x {
    Some(prior) => prior
    None => BallFloat::entire(precision~)
  }
  if prior.is_empty() {
    return empty_interval(precision)
  }
  let mut lo : @bin_float.BinFloat? = None
  let mut hi : @bin_float.BinFloat? = None
  for piece in mul_rev_pieces(self, c) {
    // intersection of the piece with the closed prior interval
    let cmp_lo = piece.lo.compare(prior.lo_)
    let (low, low_open) = if cmp_lo > 0 {
      (piece.lo, piece.lo_open)
    } else if cmp_lo < 0 {
      (prior.lo_, false)
    } else {
      (piece.lo, piece.lo_open)
    }
    let cmp_hi = piece.hi.compare(prior.hi_)
    let (high, high_open) = if cmp_hi < 0 {
      (piece.hi, piece.hi_open)
    } else if cmp_hi > 0 {
      (prior.hi_, false)
    } else {
      (piece.hi, piece.hi_open)
    }
    let order = low.compare(high)
    let nonempty = order < 0 || (order == 0 && !low_open && !high_open)
    if !nonempty {
      continue
    }
    match lo {
      Some(current) if current.compare(low) <= 0 => ()
      _ => lo = Some(low)
    }
    match hi {
      Some(current) if current.compare(high) >= 0 => ()
      _ => hi = Some(high)
    }
  }
  match (lo, hi) {
    (Some(l), Some(h)) => BallFloat::from_bounds(l, h, precision~)
    _ => empty_interval(precision)
  }
}

///|
/// `mulRevToPair` on decorated intervals (IEEE 1788-2015 12.12.3): NaI in
/// gives NaI twice; when `b` and `c` are nonempty and `0` is not in `b`, `u` is
/// the decorated quotient `c / b` and `v` is Empty (`Trv`); every other output
/// is decorated `Trv`.
pub fn BallFloatDecorated::mul_rev_to_pair(
  self : BallFloatDecorated,
  c : BallFloatDecorated,
) -> (BallFloatDecorated, BallFloatDecorated) {
  let precision = Int32::max(self.interval_.precision_, c.interval_.precision_)
  if self.is_nai() || c.is_nai() {
    return (
      BallFloatDecorated::nai(precision~),
      BallFloatDecorated::nai(precision~),
    )
  }
  if !self.interval_.is_empty() &&
    !c.interval_.is_empty() &&
    !self.interval_.contains_zero() {
    return (
      c / self,
      BallFloatDecorated::new(empty_interval(precision), decoration=Trv),
    )
  }
  let (u, v) = self.interval_.mul_rev_to_pair(c.interval_)
  (
    BallFloatDecorated::new(u, decoration=Trv),
    BallFloatDecorated::new(v, decoration=Trv),
  )
}

///|
/// `mulRev` on decorated intervals: the trivial decorated version of
/// IEEE 1788-2015 11.7.1 (NaI if any input is NaI, else the bare result
/// decorated `Trv`).
pub fn BallFloatDecorated::mul_rev(
  self : BallFloatDecorated,
  c : BallFloatDecorated,
  x? : BallFloatDecorated,
) -> BallFloatDecorated {
  let precision = Int32::max(self.interval_.precision_, c.interval_.precision_)
  if self.is_nai() || c.is_nai() || (x is Some(prior) && prior.is_nai()) {
    return BallFloatDecorated::nai(precision~)
  }
  let result = match x {
    Some(prior) => self.interval_.mul_rev(c.interval_, x=prior.interval_)
    None => self.interval_.mul_rev(c.interval_)
  }
  BallFloatDecorated::new(result, decoration=Trv)
}
