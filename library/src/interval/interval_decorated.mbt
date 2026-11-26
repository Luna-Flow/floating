///|
/// The decoration of a decorated interval (IEEE 1788-2015), ordered
/// `Ill < Trv < Def < Dac < Com`: `Com` is a bounded non-empty result of a
/// function defined and continuous on the input, `Dac` the same without the
/// bound, `Def` a non-empty result of a function defined on the input, `Trv`
/// nothing is known, and `Ill` is the decoration of NaI only.
#derive(Eq, Compare, Debug)
pub(all) enum Decoration {
  Ill
  Trv
  Def
  Dac
  Com
}

///|
fn decoration_rank(decoration : Decoration) -> Int32 {
  match decoration {
    Ill => 0
    Trv => 1
    Def => 2
    Dac => 3
    Com => 4
  }
}

///|
fn min_decoration(left : Decoration, right : Decoration) -> Decoration {
  if decoration_rank(left) <= decoration_rank(right) {
    left
  } else {
    right
  }
}

///|
fn canonical_decoration(
  interval : Interval,
  decoration : Decoration,
) -> Decoration {
  if interval.is_empty() {
    Trv
  } else if !interval.is_common_interval() && decoration == Com {
    Dac
  } else {
    decoration
  }
}

///|
/// An `Interval` paired with a `Decoration`, or NaI (not an interval). The decoration is canonical: an empty interval carries
/// `Trv`, an unbounded one never `Com`, and only NaI carries `Ill`. An
/// operation takes the lowest of the decorations of its operands and of its own,
/// and NaI in gives NaI out.
pub struct DecoratedInterval {
  priv interval_ : Interval
  priv decoration_ : Decoration
  priv nai_ : Bool
}

///|
/// IEEE 1788-2015 11.5.2 `setDec`: the decoration `Ill` gives NaI for any
/// interval, empty or not (at the precision of `interval`); an empty interval
/// is decorated `Trv` and an unbounded one with `Com` is decorated `Dac`.
pub fn DecoratedInterval::new(
  interval : Interval,
  decoration~ : Decoration = Com,
) -> DecoratedInterval {
  if decoration == Ill {
    return DecoratedInterval::nai(precision=interval.precision())
  }
  {
    interval_: interval,
    decoration_: canonical_decoration(interval, decoration),
    nai_: false,
  }
}

///|
/// NaI, "not an interval", in a format of `precision` bits (default 53): its
/// interval part is empty, its decoration `Ill`. NaI is not equal to itself
/// under `==`; `identical` is true for two NaI.
pub fn DecoratedInterval::nai(precision~ : Int32 = 53) -> DecoratedInterval {
  { interval_: Interval::empty(precision~), decoration_: Ill, nai_: true, }
}

///|
/// Whether the value is NaI.
pub fn DecoratedInterval::is_nai(self : DecoratedInterval) -> Bool {
  self.nai_
}

///|
/// The interval part; the empty interval for NaI.
pub fn DecoratedInterval::interval(self : DecoratedInterval) -> Interval {
  self.interval_
}

///|
/// The decoration: `Ill` for NaI, `Trv` for an empty interval.
pub fn DecoratedInterval::decoration(self : DecoratedInterval) -> Decoration {
  self.decoration_
}

///|
pub fn DecoratedInterval::is_empty(self : DecoratedInterval) -> Bool {
  !self.is_nai() && self.interval_.is_empty()
}

///|
pub fn DecoratedInterval::is_entire(self : DecoratedInterval) -> Bool {
  !self.is_nai() && self.interval_.is_entire()
}

///|
pub fn DecoratedInterval::is_common_interval(self : DecoratedInterval) -> Bool {
  !self.is_nai() && self.interval_.is_common_interval()
}

///|
pub fn DecoratedInterval::is_singleton(self : DecoratedInterval) -> Bool {
  !self.is_nai() && self.interval_.is_singleton()
}

///|
pub fn DecoratedInterval::is_member(
  self : DecoratedInterval,
  value : @binary.Binary,
) -> Bool {
  !self.is_nai() && self.interval_.is_member(value)
}

///|
/// `equal` of IEEE 1788-2015 12.12.9 on decorated intervals: false when either
/// is NaI (so NaI is not equal to itself under `==`, as NaN is not), and
/// otherwise the equality of the interval parts; decorations are ignored.
pub impl Eq for DecoratedInterval with fn equal(self, other) {
  !self.is_nai() && !other.is_nai() && self.interval_ == other.interval_
}

///|
/// Identical datums (12.3): NaI is identical to NaI; otherwise the same
/// interval part (set and precision) and the same decoration.
pub fn DecoratedInterval::identical(
  self : DecoratedInterval,
  other : DecoratedInterval,
) -> Bool {
  if self.is_nai() || other.is_nai() {
    self.is_nai() && other.is_nai()
  } else {
    self.interval_.identical(other.interval_) &&
    self.decoration_ == other.decoration_
  }
}

///|
pub fn DecoratedInterval::subset(
  self : DecoratedInterval,
  other : DecoratedInterval,
) -> Bool {
  !self.is_nai() && !other.is_nai() && self.interval_.subset(other.interval_)
}

///|
pub fn DecoratedInterval::interior(
  self : DecoratedInterval,
  other : DecoratedInterval,
) -> Bool {
  !self.is_nai() && !other.is_nai() && self.interval_.interior(other.interval_)
}

///|
pub fn DecoratedInterval::disjoint(
  self : DecoratedInterval,
  other : DecoratedInterval,
) -> Bool {
  !self.is_nai() && !other.is_nai() && self.interval_.disjoint(other.interval_)
}

///|
pub fn DecoratedInterval::less(
  self : DecoratedInterval,
  other : DecoratedInterval,
) -> Bool {
  !self.is_nai() && !other.is_nai() && self.interval_.less(other.interval_)
}

///|
pub fn DecoratedInterval::strict_less(
  self : DecoratedInterval,
  other : DecoratedInterval,
) -> Bool {
  !self.is_nai() &&
  !other.is_nai() &&
  self.interval_.strict_less(other.interval_)
}

///|
pub fn DecoratedInterval::precedes(
  self : DecoratedInterval,
  other : DecoratedInterval,
) -> Bool {
  !self.is_nai() && !other.is_nai() && self.interval_.precedes(other.interval_)
}

///|
pub fn DecoratedInterval::strict_precedes(
  self : DecoratedInterval,
  other : DecoratedInterval,
) -> Bool {
  !self.is_nai() &&
  !other.is_nai() &&
  self.interval_.strict_precedes(other.interval_)
}

///|
pub fn DecoratedInterval::overlap(
  self : DecoratedInterval,
  other : DecoratedInterval,
) -> OverlapState? {
  if self.is_nai() || other.is_nai() {
    None
  } else {
    Some(self.interval_.overlap(other.interval_))
  }
}

///|
fn binary_result(
  left : DecoratedInterval,
  right : DecoratedInterval,
  interval : Interval,
  operation_decoration : Decoration,
) -> DecoratedInterval {
  if left.is_nai() || right.is_nai() {
    return DecoratedInterval::nai(
      precision=Int32::max(
        left.interval_.precision(),
        right.interval_.precision(),
      ),
    )
  }
  DecoratedInterval::new(
    interval,
    decoration=min_decoration(
      min_decoration(left.decoration_, right.decoration_),
      operation_decoration,
    ),
  )
}

///|
pub fn DecoratedInterval::intersection(
  self : DecoratedInterval,
  other : DecoratedInterval,
) -> DecoratedInterval {
  binary_result(self, other, self.interval_.intersection(other.interval_), Trv)
}

///|
pub fn DecoratedInterval::convex_hull(
  self : DecoratedInterval,
  other : DecoratedInterval,
) -> DecoratedInterval {
  binary_result(self, other, self.interval_.convex_hull(other.interval_), Trv)
}

///|
pub fn DecoratedInterval::cancel_plus(
  self : DecoratedInterval,
  other : DecoratedInterval,
) -> DecoratedInterval {
  binary_result(self, other, self.interval_.cancel_plus(other.interval_), Trv)
}

///|
pub fn DecoratedInterval::cancel_minus(
  self : DecoratedInterval,
  other : DecoratedInterval,
) -> DecoratedInterval {
  binary_result(self, other, self.interval_.cancel_minus(other.interval_), Trv)
}

///|
/// The sum of the interval parts (`Interval::add`) with the decoration the
/// operation propagates: the lowest of the operand decorations. NaI in gives
/// NaI out. This is the `+` operator.
pub fn DecoratedInterval::add(
  self : DecoratedInterval,
  other : DecoratedInterval,
) -> DecoratedInterval {
  binary_result(self, other, self.interval_ + other.interval_, Com)
}

///|
/// The difference of the interval parts (`Interval::sub`) decorated as `add`
/// is. This is the `-` operator.
pub fn DecoratedInterval::sub(
  self : DecoratedInterval,
  other : DecoratedInterval,
) -> DecoratedInterval {
  binary_result(self, other, self.interval_ - other.interval_, Com)
}

///|
/// The product of the interval parts (`Interval::mul`) decorated as `add` is.
/// This is the `*` operator.
pub fn DecoratedInterval::mul(
  self : DecoratedInterval,
  other : DecoratedInterval,
) -> DecoratedInterval {
  binary_result(self, other, self.interval_ * other.interval_, Com)
}

///|
/// The quotient of the interval parts (`Interval::div`). The decoration is
/// the lowest of the operand decorations, further lowered to `Trv` when the
/// divisor contains zero. This is the `/` operator.
pub fn DecoratedInterval::div(
  self : DecoratedInterval,
  other : DecoratedInterval,
) -> DecoratedInterval {
  let operation_decoration = if other.interval_.contains_zero() {
    Trv
  } else {
    Com
  }
  binary_result(
    self,
    other,
    self.interval_ / other.interval_,
    operation_decoration,
  )
}

///|
fn unary_result(
  source : DecoratedInterval,
  interval : Interval,
  operation_decoration : Decoration,
) -> DecoratedInterval {
  if source.is_nai() {
    return DecoratedInterval::nai(precision=source.interval_.precision())
  }
  DecoratedInterval::new(
    interval,
    decoration=min_decoration(source.decoration_, operation_decoration),
  )
}

///|
pub fn DecoratedInterval::pos(self : DecoratedInterval) -> DecoratedInterval {
  unary_result(self, self.interval_, Com)
}

///|
pub fn DecoratedInterval::neg(self : DecoratedInterval) -> DecoratedInterval {
  unary_result(self, self.interval_.neg(), Com)
}

///|
pub fn DecoratedInterval::abs(self : DecoratedInterval) -> DecoratedInterval {
  unary_result(self, self.interval_.abs(), Com)
}

///|
pub fn DecoratedInterval::recip(self : DecoratedInterval) -> DecoratedInterval {
  unary_result(
    self,
    self.interval_.recip(),
    if self.interval_.contains_zero() {
      Trv
    } else {
      Com
    },
  )
}

///|
pub fn DecoratedInterval::sqr(self : DecoratedInterval) -> DecoratedInterval {
  unary_result(self, self.interval_.sqr(), Com)
}

///|
pub fn DecoratedInterval::sqrt(self : DecoratedInterval) -> DecoratedInterval {
  unary_result(
    self,
    self.interval_.sqrt(),
    if self.interval_.is_empty() ||
      self.interval_.lo_.signum() == @def.Sign::Negative {
      Trv
    } else {
      Com
    },
  )
}

///|
pub fn DecoratedInterval::exp(self : DecoratedInterval) -> DecoratedInterval {
  unary_result(self, self.interval_.exp(), Com)
}

///|
pub fn DecoratedInterval::exp2(self : DecoratedInterval) -> DecoratedInterval {
  unary_result(self, self.interval_.exp2(), Com)
}

///|
pub fn DecoratedInterval::exp10(self : DecoratedInterval) -> DecoratedInterval {
  unary_result(self, self.interval_.exp10(), Com)
}

///|
pub fn DecoratedInterval::expm1(self : DecoratedInterval) -> DecoratedInterval {
  unary_result(self, self.interval_.expm1(), Com)
}

///|
fn DecoratedInterval::logarithm_result(
  self : DecoratedInterval,
  interval : Interval,
) -> DecoratedInterval {
  let partial_domain = !self.interval_.is_empty() &&
    (
      self.interval_.lo_.signum() == @def.Sign::Negative ||
      self.interval_.lo_.is_zero()
    )
  unary_result(self, interval, if partial_domain { Trv } else { Com })
}

///|
pub fn DecoratedInterval::ln(self : DecoratedInterval) -> DecoratedInterval {
  self.logarithm_result(self.interval_.ln())
}

///|
pub fn DecoratedInterval::log2(self : DecoratedInterval) -> DecoratedInterval {
  self.logarithm_result(self.interval_.log2())
}

///|
pub fn DecoratedInterval::log10(self : DecoratedInterval) -> DecoratedInterval {
  self.logarithm_result(self.interval_.log10())
}

///|
pub fn DecoratedInterval::log1p(self : DecoratedInterval) -> DecoratedInterval {
  let minus_one = @binary.Binary::from_int(
    -1,
    precision=self.interval_.precision(),
  )
  let partial_domain = !self.interval_.is_empty() &&
    self.interval_.lo_.compare(minus_one) <= 0
  unary_result(
    self,
    self.interval_.log1p(),
    if partial_domain {
      Trv
    } else {
      Com
    },
  )
}

///|
pub fn DecoratedInterval::rootn(
  self : DecoratedInterval,
  degree : Int32,
) -> DecoratedInterval {
  // rootn(x, n) is undefined for n = 0, for x < 0 when n is even and at
  // x = 0 when n is negative (x^(-1/n) has a pole there).
  let partial_domain = degree == 0 ||
    (degree % 2 == 0 && self.interval_.lo_.signum() == @def.Sign::Negative) ||
    (degree < 0 && self.interval_.contains_zero())
  unary_result(
    self,
    self.interval_.rootn(degree),
    if partial_domain {
      Trv
    } else {
      Com
    },
  )
}

///|
pub fn DecoratedInterval::hypot(
  self : DecoratedInterval,
  other : DecoratedInterval,
) -> DecoratedInterval {
  binary_result(self, other, self.interval_.hypot(other.interval_), Com)
}

///|
pub fn DecoratedInterval::sinpi(self : DecoratedInterval) -> DecoratedInterval {
  unary_result(self, self.interval_.sinpi(), Com)
}

///|
pub fn DecoratedInterval::cospi(self : DecoratedInterval) -> DecoratedInterval {
  unary_result(self, self.interval_.cospi(), Com)
}

///|
pub fn DecoratedInterval::tanpi(self : DecoratedInterval) -> DecoratedInterval {
  let result = self.interval_.tanpi()
  // tanpi is continuous wherever it is defined, so a bounded argument has a
  // bounded image unless it contains a pole k + 1/2, possibly at an endpoint
  // (tanpi([1/2, 1]) = [-inf, 0]); any unbounded result marks a pole.
  unary_result(
    self,
    result,
    if !result.is_common_interval() && !self.interval_.is_empty() {
      Trv
    } else {
      Com
    },
  )
}

///|
pub fn DecoratedInterval::sinh(self : DecoratedInterval) -> DecoratedInterval {
  unary_result(self, self.interval_.sinh(), Com)
}

///|
pub fn DecoratedInterval::cosh(self : DecoratedInterval) -> DecoratedInterval {
  unary_result(self, self.interval_.cosh(), Com)
}

///|
pub fn DecoratedInterval::tanh(self : DecoratedInterval) -> DecoratedInterval {
  unary_result(self, self.interval_.tanh(), Com)
}

///|
pub fn DecoratedInterval::asinh(self : DecoratedInterval) -> DecoratedInterval {
  unary_result(self, self.interval_.asinh(), Com)
}

///|
pub fn DecoratedInterval::acosh(self : DecoratedInterval) -> DecoratedInterval {
  let one = @binary.Binary::one(precision=self.interval_.precision())
  let partial_domain = !self.interval_.is_empty() &&
    self.interval_.lo_.compare(one) < 0
  unary_result(
    self,
    self.interval_.acosh(),
    if partial_domain {
      Trv
    } else {
      Com
    },
  )
}

///|
pub fn DecoratedInterval::atanh(self : DecoratedInterval) -> DecoratedInterval {
  let one = @binary.Binary::one(precision=self.interval_.precision())
  let minus_one = one.neg()
  let partial_domain = !self.interval_.is_empty() &&
    (
      self.interval_.lo_.compare(minus_one) <= 0 ||
      self.interval_.hi_.compare(one) >= 0
    )
  unary_result(
    self,
    self.interval_.atanh(),
    if partial_domain {
      Trv
    } else {
      Com
    },
  )
}

///|
pub fn DecoratedInterval::atan(self : DecoratedInterval) -> DecoratedInterval {
  unary_result(self, self.interval_.atan(), Com)
}

///|
fn DecoratedInterval::inverse_unit_result(
  self : DecoratedInterval,
  interval : Interval,
) -> DecoratedInterval {
  let one = @binary.Binary::one(precision=self.interval_.precision())
  let partial_domain = !self.interval_.is_empty() &&
    (
      self.interval_.lo_.compare(one.neg()) < 0 ||
      self.interval_.hi_.compare(one) > 0
    )
  unary_result(self, interval, if partial_domain { Trv } else { Com })
}

///|
pub fn DecoratedInterval::asin(self : DecoratedInterval) -> DecoratedInterval {
  self.inverse_unit_result(self.interval_.asin())
}

///|
pub fn DecoratedInterval::acos(self : DecoratedInterval) -> DecoratedInterval {
  self.inverse_unit_result(self.interval_.acos())
}

///|
pub fn DecoratedInterval::atan2(
  self : DecoratedInterval,
  abscissa : DecoratedInterval,
) -> DecoratedInterval {
  let interval = self.interval_.atan2(abscissa.interval_)
  let contains_origin = self.interval_.contains_zero() &&
    abscissa.interval_.contains_zero()
  let crosses_cut = abscissa.interval_.lo_.signum() == @def.Sign::Negative &&
    self.interval_.lo_.signum() == @def.Sign::Negative &&
    self.interval_.contains_zero()
  let touches_cut_from_above = abscissa.interval_.hi_.compare(
      @binary.Binary::zero(precision=interval.precision()),
    ) <
    0 &&
    self.interval_.lo_.is_zero()
  binary_result(
    self,
    abscissa,
    interval,
    if contains_origin {
      Trv
    } else if crosses_cut {
      Def
    } else if touches_cut_from_above {
      Dac
    } else {
      Com
    },
  )
}

///|
pub fn DecoratedInterval::pow(
  self : DecoratedInterval,
  exponent : DecoratedInterval,
) -> DecoratedInterval {
  let interval = self.interval_.pow(exponent.interval_)
  let partial_domain = self.interval_.is_empty() ||
    self.interval_.lo_.signum() == @def.Sign::Negative ||
    (
      self.interval_.contains_zero() &&
      (
        exponent.interval_.lo_.signum() == @def.Sign::Negative ||
        exponent.interval_.lo_.is_zero()
      )
    ) ||
    interval.is_empty()
  binary_result(
    self,
    exponent,
    interval,
    if partial_domain {
      Trv
    } else {
      Com
    },
  )
}

///|
pub fn DecoratedInterval::sin(self : DecoratedInterval) -> DecoratedInterval {
  unary_result(self, self.interval_.sin(), Com)
}

///|
pub fn DecoratedInterval::cos(self : DecoratedInterval) -> DecoratedInterval {
  unary_result(self, self.interval_.cos(), Com)
}

///|
pub fn DecoratedInterval::tan(self : DecoratedInterval) -> DecoratedInterval {
  let interval = self.interval_.tan()
  unary_result(self, interval, if interval.is_entire() { Trv } else { Com })
}

///|
pub fn DecoratedInterval::fma(
  self : DecoratedInterval,
  multiplier : DecoratedInterval,
  addend : DecoratedInterval,
) -> DecoratedInterval {
  if self.is_nai() || multiplier.is_nai() || addend.is_nai() {
    return DecoratedInterval::nai(
      precision=Int32::max(
        self.interval_.precision(),
        Int32::max(
          multiplier.interval_.precision(),
          addend.interval_.precision(),
        ),
      ),
    )
  }
  DecoratedInterval::new(
    self.interval_.fma(multiplier.interval_, addend.interval_),
    decoration=min_decoration(
      min_decoration(self.decoration_, multiplier.decoration_),
      addend.decoration_,
    ),
  )
}

///|
pub fn DecoratedInterval::pown(
  self : DecoratedInterval,
  exponent : Int32,
) -> DecoratedInterval {
  unary_result(
    self,
    self.interval_.pown(exponent),
    if exponent < 0 && self.interval_.contains_zero() {
      Trv
    } else {
      Com
    },
  )
}

///|
pub fn DecoratedInterval::min(
  self : DecoratedInterval,
  other : DecoratedInterval,
) -> DecoratedInterval {
  binary_result(self, other, self.interval_.min(other.interval_), Com)
}

///|
pub fn DecoratedInterval::max(
  self : DecoratedInterval,
  other : DecoratedInterval,
) -> DecoratedInterval {
  binary_result(self, other, self.interval_.max(other.interval_), Com)
}

///|
pub fn DecoratedInterval::apply_ctx(
  self : DecoratedInterval,
  ctx : IntervalContext,
) -> (DecoratedInterval, IntervalFlags) {
  let (interval, flags) = self.interval_.apply_ctx(ctx)
  if self.is_nai() {
    (DecoratedInterval::nai(precision=ctx.precision()), flags)
  } else {
    (DecoratedInterval::new(interval, decoration=self.decoration_), flags)
  }
}

///|
pub impl Add for DecoratedInterval with fn add(self, other) {
  self.add(other)
}

///|
pub impl Sub for DecoratedInterval with fn sub(self, other) {
  self.sub(other)
}

///|
pub impl Mul for DecoratedInterval with fn mul(self, other) {
  self.mul(other)
}

///|
pub impl Div for DecoratedInterval with fn div(self, other) {
  self.div(other)
}

///|
pub impl Show for Decoration with fn to_string(self) {
  match self {
    Ill => "ill"
    Trv => "trv"
    Def => "def"
    Dac => "dac"
    Com => "com"
  }
}

///|
pub impl Show for DecoratedInterval with fn to_string(self) {
  if self.is_nai() {
    "[nai]"
  } else {
    self.interval_.to_string() + "_" + self.decoration_.to_string()
  }
}

///|
/// The midpoint-radius view of the interval followed by `_` and the decoration; see
/// `Interval::to_midpoint_radius_string` (not a literal).
pub fn DecoratedInterval::to_midpoint_radius_string(
  self : DecoratedInterval,
) -> String {
  if self.is_nai() {
    "[nai]"
  } else {
    self.interval_.to_midpoint_radius_string() +
    "_" +
    self.decoration_.to_string()
  }
}

///|
pub extend Decoration with Show::{to_string}

///|
pub extend DecoratedInterval with Show::{to_string}

///|
pub extend Decoration with Eq::{not_equal, equal}

///|
pub extend Decoration with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend DecoratedInterval with Eq::{not_equal, equal}

///|
pub extend Decoration with Show::{output}

///|
pub extend DecoratedInterval with Show::{output}
