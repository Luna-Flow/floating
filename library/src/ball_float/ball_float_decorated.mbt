///|
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
  interval : BallFloat,
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
pub struct BallFloatDecorated {
  priv interval_ : BallFloat
  priv decoration_ : Decoration
  priv nai_ : Bool
}

///|
/// IEEE 1788-2015 11.5.2 `setDec`: the decoration `Ill` gives NaI for any
/// interval, empty or not (at the precision of `interval`); an empty interval
/// is decorated `Trv` and an unbounded one with `Com` is decorated `Dac`.
pub fn BallFloatDecorated::new(
  interval : BallFloat,
  decoration~ : Decoration = Com,
) -> BallFloatDecorated {
  if decoration == Ill {
    return BallFloatDecorated::nai(precision=interval.precision())
  }
  {
    interval_: interval,
    decoration_: canonical_decoration(interval, decoration),
    nai_: false,
  }
}

///|
pub fn BallFloatDecorated::nai(precision~ : Int32 = 53) -> BallFloatDecorated {
  { interval_: BallFloat::empty(precision~), decoration_: Ill, nai_: true, }
}

///|
pub fn BallFloatDecorated::is_nai(self : BallFloatDecorated) -> Bool {
  self.nai_
}

///|
pub fn BallFloatDecorated::interval(self : BallFloatDecorated) -> BallFloat {
  self.interval_
}

///|
pub fn BallFloatDecorated::decoration(self : BallFloatDecorated) -> Decoration {
  self.decoration_
}

///|
pub fn BallFloatDecorated::is_empty(self : BallFloatDecorated) -> Bool {
  !self.is_nai() && self.interval_.is_empty()
}

///|
pub fn BallFloatDecorated::is_entire(self : BallFloatDecorated) -> Bool {
  !self.is_nai() && self.interval_.is_entire()
}

///|
pub fn BallFloatDecorated::is_common_interval(
  self : BallFloatDecorated,
) -> Bool {
  !self.is_nai() && self.interval_.is_common_interval()
}

///|
pub fn BallFloatDecorated::is_singleton(self : BallFloatDecorated) -> Bool {
  !self.is_nai() && self.interval_.is_singleton()
}

///|
pub fn BallFloatDecorated::is_member(
  self : BallFloatDecorated,
  value : @bin_float.BinFloat,
) -> Bool {
  !self.is_nai() && self.interval_.is_member(value)
}

///|
/// `equal` of IEEE 1788-2015 12.12.9 on decorated intervals: false when either
/// is NaI (so NaI is not equal to itself under `==`, as NaN is not), and
/// otherwise the equality of the interval parts; decorations are ignored.
pub impl Eq for BallFloatDecorated with fn equal(self, other) {
  !self.is_nai() && !other.is_nai() && self.interval_ == other.interval_
}

///|
/// Identical datums (12.3): NaI is identical to NaI; otherwise the same
/// interval part (set and precision) and the same decoration.
pub fn BallFloatDecorated::identical(
  self : BallFloatDecorated,
  other : BallFloatDecorated,
) -> Bool {
  if self.is_nai() || other.is_nai() {
    self.is_nai() && other.is_nai()
  } else {
    self.interval_.identical(other.interval_) &&
    self.decoration_ == other.decoration_
  }
}

///|
pub fn BallFloatDecorated::subset(
  self : BallFloatDecorated,
  other : BallFloatDecorated,
) -> Bool {
  !self.is_nai() && !other.is_nai() && self.interval_.subset(other.interval_)
}

///|
pub fn BallFloatDecorated::interior(
  self : BallFloatDecorated,
  other : BallFloatDecorated,
) -> Bool {
  !self.is_nai() && !other.is_nai() && self.interval_.interior(other.interval_)
}

///|
pub fn BallFloatDecorated::disjoint(
  self : BallFloatDecorated,
  other : BallFloatDecorated,
) -> Bool {
  !self.is_nai() && !other.is_nai() && self.interval_.disjoint(other.interval_)
}

///|
pub fn BallFloatDecorated::less(
  self : BallFloatDecorated,
  other : BallFloatDecorated,
) -> Bool {
  !self.is_nai() && !other.is_nai() && self.interval_.less(other.interval_)
}

///|
pub fn BallFloatDecorated::strict_less(
  self : BallFloatDecorated,
  other : BallFloatDecorated,
) -> Bool {
  !self.is_nai() &&
  !other.is_nai() &&
  self.interval_.strict_less(other.interval_)
}

///|
pub fn BallFloatDecorated::precedes(
  self : BallFloatDecorated,
  other : BallFloatDecorated,
) -> Bool {
  !self.is_nai() && !other.is_nai() && self.interval_.precedes(other.interval_)
}

///|
pub fn BallFloatDecorated::strict_precedes(
  self : BallFloatDecorated,
  other : BallFloatDecorated,
) -> Bool {
  !self.is_nai() &&
  !other.is_nai() &&
  self.interval_.strict_precedes(other.interval_)
}

///|
pub fn BallFloatDecorated::overlap(
  self : BallFloatDecorated,
  other : BallFloatDecorated,
) -> OverlapState? {
  if self.is_nai() || other.is_nai() {
    None
  } else {
    Some(self.interval_.overlap(other.interval_))
  }
}

///|
fn binary_result(
  left : BallFloatDecorated,
  right : BallFloatDecorated,
  interval : BallFloat,
  operation_decoration : Decoration,
) -> BallFloatDecorated {
  if left.is_nai() || right.is_nai() {
    return BallFloatDecorated::nai(
      precision=Int32::max(
        left.interval_.precision(),
        right.interval_.precision(),
      ),
    )
  }
  BallFloatDecorated::new(
    interval,
    decoration=min_decoration(
      min_decoration(left.decoration_, right.decoration_),
      operation_decoration,
    ),
  )
}

///|
pub fn BallFloatDecorated::intersection(
  self : BallFloatDecorated,
  other : BallFloatDecorated,
) -> BallFloatDecorated {
  binary_result(self, other, self.interval_.intersection(other.interval_), Trv)
}

///|
pub fn BallFloatDecorated::convex_hull(
  self : BallFloatDecorated,
  other : BallFloatDecorated,
) -> BallFloatDecorated {
  binary_result(self, other, self.interval_.convex_hull(other.interval_), Trv)
}

///|
pub fn BallFloatDecorated::cancel_plus(
  self : BallFloatDecorated,
  other : BallFloatDecorated,
) -> BallFloatDecorated {
  binary_result(self, other, self.interval_.cancel_plus(other.interval_), Trv)
}

///|
pub fn BallFloatDecorated::cancel_minus(
  self : BallFloatDecorated,
  other : BallFloatDecorated,
) -> BallFloatDecorated {
  binary_result(self, other, self.interval_.cancel_minus(other.interval_), Trv)
}

///|
pub fn BallFloatDecorated::add(
  self : BallFloatDecorated,
  other : BallFloatDecorated,
) -> BallFloatDecorated {
  binary_result(self, other, self.interval_ + other.interval_, Com)
}

///|
pub fn BallFloatDecorated::sub(
  self : BallFloatDecorated,
  other : BallFloatDecorated,
) -> BallFloatDecorated {
  binary_result(self, other, self.interval_ - other.interval_, Com)
}

///|
pub fn BallFloatDecorated::mul(
  self : BallFloatDecorated,
  other : BallFloatDecorated,
) -> BallFloatDecorated {
  binary_result(self, other, self.interval_ * other.interval_, Com)
}

///|
pub fn BallFloatDecorated::div(
  self : BallFloatDecorated,
  other : BallFloatDecorated,
) -> BallFloatDecorated {
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
  source : BallFloatDecorated,
  interval : BallFloat,
  operation_decoration : Decoration,
) -> BallFloatDecorated {
  if source.is_nai() {
    return BallFloatDecorated::nai(precision=source.interval_.precision())
  }
  BallFloatDecorated::new(
    interval,
    decoration=min_decoration(source.decoration_, operation_decoration),
  )
}

///|
pub fn BallFloatDecorated::pos(self : BallFloatDecorated) -> BallFloatDecorated {
  unary_result(self, self.interval_, Com)
}

///|
pub fn BallFloatDecorated::neg(self : BallFloatDecorated) -> BallFloatDecorated {
  unary_result(self, self.interval_.neg(), Com)
}

///|
pub fn BallFloatDecorated::abs(self : BallFloatDecorated) -> BallFloatDecorated {
  unary_result(self, self.interval_.abs(), Com)
}

///|
pub fn BallFloatDecorated::recip(
  self : BallFloatDecorated,
) -> BallFloatDecorated {
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
pub fn BallFloatDecorated::sqr(self : BallFloatDecorated) -> BallFloatDecorated {
  unary_result(self, self.interval_.sqr(), Com)
}

///|
pub fn BallFloatDecorated::sqrt(
  self : BallFloatDecorated,
) -> BallFloatDecorated {
  unary_result(
    self,
    self.interval_.sqrt(),
    if self.interval_.is_empty() ||
      self.interval_.lo_.sign() == @def.Sign::Negative {
      Trv
    } else {
      Com
    },
  )
}

///|
pub fn BallFloatDecorated::exp(self : BallFloatDecorated) -> BallFloatDecorated {
  unary_result(self, self.interval_.exp(), Com)
}

///|
pub fn BallFloatDecorated::exp2(
  self : BallFloatDecorated,
) -> BallFloatDecorated {
  unary_result(self, self.interval_.exp2(), Com)
}

///|
pub fn BallFloatDecorated::exp10(
  self : BallFloatDecorated,
) -> BallFloatDecorated {
  unary_result(self, self.interval_.exp10(), Com)
}

///|
pub fn BallFloatDecorated::expm1(
  self : BallFloatDecorated,
) -> BallFloatDecorated {
  unary_result(self, self.interval_.expm1(), Com)
}

///|
fn BallFloatDecorated::logarithm_result(
  self : BallFloatDecorated,
  interval : BallFloat,
) -> BallFloatDecorated {
  let partial_domain = !self.interval_.is_empty() &&
    (
      self.interval_.lo_.sign() == @def.Sign::Negative ||
      self.interval_.lo_.is_zero()
    )
  unary_result(self, interval, if partial_domain { Trv } else { Com })
}

///|
pub fn BallFloatDecorated::ln(self : BallFloatDecorated) -> BallFloatDecorated {
  self.logarithm_result(self.interval_.ln())
}

///|
pub fn BallFloatDecorated::log2(
  self : BallFloatDecorated,
) -> BallFloatDecorated {
  self.logarithm_result(self.interval_.log2())
}

///|
pub fn BallFloatDecorated::log10(
  self : BallFloatDecorated,
) -> BallFloatDecorated {
  self.logarithm_result(self.interval_.log10())
}

///|
pub fn BallFloatDecorated::log1p(
  self : BallFloatDecorated,
) -> BallFloatDecorated {
  let minus_one = @bin_float.BinFloat::from_int(
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
pub fn BallFloatDecorated::rootn(
  self : BallFloatDecorated,
  degree : Int32,
) -> BallFloatDecorated {
  // rootn(x, n) is undefined for n = 0, for x < 0 when n is even and at
  // x = 0 when n is negative (x^(-1/n) has a pole there).
  let partial_domain = degree == 0 ||
    (degree % 2 == 0 && self.interval_.lo_.sign() == @def.Sign::Negative) ||
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
pub fn BallFloatDecorated::hypot(
  self : BallFloatDecorated,
  other : BallFloatDecorated,
) -> BallFloatDecorated {
  binary_result(self, other, self.interval_.hypot(other.interval_), Com)
}

///|
pub fn BallFloatDecorated::sinpi(
  self : BallFloatDecorated,
) -> BallFloatDecorated {
  unary_result(self, self.interval_.sinpi(), Com)
}

///|
pub fn BallFloatDecorated::cospi(
  self : BallFloatDecorated,
) -> BallFloatDecorated {
  unary_result(self, self.interval_.cospi(), Com)
}

///|
pub fn BallFloatDecorated::tanpi(
  self : BallFloatDecorated,
) -> BallFloatDecorated {
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
pub fn BallFloatDecorated::sinh(
  self : BallFloatDecorated,
) -> BallFloatDecorated {
  unary_result(self, self.interval_.sinh(), Com)
}

///|
pub fn BallFloatDecorated::cosh(
  self : BallFloatDecorated,
) -> BallFloatDecorated {
  unary_result(self, self.interval_.cosh(), Com)
}

///|
pub fn BallFloatDecorated::tanh(
  self : BallFloatDecorated,
) -> BallFloatDecorated {
  unary_result(self, self.interval_.tanh(), Com)
}

///|
pub fn BallFloatDecorated::asinh(
  self : BallFloatDecorated,
) -> BallFloatDecorated {
  unary_result(self, self.interval_.asinh(), Com)
}

///|
pub fn BallFloatDecorated::acosh(
  self : BallFloatDecorated,
) -> BallFloatDecorated {
  let one = @bin_float.BinFloat::one(precision=self.interval_.precision())
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
pub fn BallFloatDecorated::atanh(
  self : BallFloatDecorated,
) -> BallFloatDecorated {
  let one = @bin_float.BinFloat::one(precision=self.interval_.precision())
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
pub fn BallFloatDecorated::atan(
  self : BallFloatDecorated,
) -> BallFloatDecorated {
  unary_result(self, self.interval_.atan(), Com)
}

///|
fn BallFloatDecorated::inverse_unit_result(
  self : BallFloatDecorated,
  interval : BallFloat,
) -> BallFloatDecorated {
  let one = @bin_float.BinFloat::one(precision=self.interval_.precision())
  let partial_domain = !self.interval_.is_empty() &&
    (
      self.interval_.lo_.compare(one.neg()) < 0 ||
      self.interval_.hi_.compare(one) > 0
    )
  unary_result(self, interval, if partial_domain { Trv } else { Com })
}

///|
pub fn BallFloatDecorated::asin(
  self : BallFloatDecorated,
) -> BallFloatDecorated {
  self.inverse_unit_result(self.interval_.asin())
}

///|
pub fn BallFloatDecorated::acos(
  self : BallFloatDecorated,
) -> BallFloatDecorated {
  self.inverse_unit_result(self.interval_.acos())
}

///|
pub fn BallFloatDecorated::atan2(
  self : BallFloatDecorated,
  abscissa : BallFloatDecorated,
) -> BallFloatDecorated {
  let interval = self.interval_.atan2(abscissa.interval_)
  let contains_origin = self.interval_.contains_zero() &&
    abscissa.interval_.contains_zero()
  let crosses_cut = abscissa.interval_.lo_.sign() == @def.Sign::Negative &&
    self.interval_.lo_.sign() == @def.Sign::Negative &&
    self.interval_.contains_zero()
  let touches_cut_from_above = abscissa.interval_.hi_.compare(
      @bin_float.BinFloat::zero(precision=interval.precision()),
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
pub fn BallFloatDecorated::pow(
  self : BallFloatDecorated,
  exponent : BallFloatDecorated,
) -> BallFloatDecorated {
  let interval = self.interval_.pow(exponent.interval_)
  let partial_domain = self.interval_.is_empty() ||
    self.interval_.lo_.sign() == @def.Sign::Negative ||
    (
      self.interval_.contains_zero() &&
      (
        exponent.interval_.lo_.sign() == @def.Sign::Negative ||
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
pub fn BallFloatDecorated::sin(self : BallFloatDecorated) -> BallFloatDecorated {
  unary_result(self, self.interval_.sin(), Com)
}

///|
pub fn BallFloatDecorated::cos(self : BallFloatDecorated) -> BallFloatDecorated {
  unary_result(self, self.interval_.cos(), Com)
}

///|
pub fn BallFloatDecorated::tan(self : BallFloatDecorated) -> BallFloatDecorated {
  let interval = self.interval_.tan()
  unary_result(self, interval, if interval.is_entire() { Trv } else { Com })
}

///|
pub fn BallFloatDecorated::fma(
  self : BallFloatDecorated,
  multiplier : BallFloatDecorated,
  addend : BallFloatDecorated,
) -> BallFloatDecorated {
  if self.is_nai() || multiplier.is_nai() || addend.is_nai() {
    return BallFloatDecorated::nai(
      precision=Int32::max(
        self.interval_.precision(),
        Int32::max(
          multiplier.interval_.precision(),
          addend.interval_.precision(),
        ),
      ),
    )
  }
  BallFloatDecorated::new(
    self.interval_.fma(multiplier.interval_, addend.interval_),
    decoration=min_decoration(
      min_decoration(self.decoration_, multiplier.decoration_),
      addend.decoration_,
    ),
  )
}

///|
pub fn BallFloatDecorated::pown(
  self : BallFloatDecorated,
  exponent : Int32,
) -> BallFloatDecorated {
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
pub fn BallFloatDecorated::min(
  self : BallFloatDecorated,
  other : BallFloatDecorated,
) -> BallFloatDecorated {
  binary_result(self, other, self.interval_.min(other.interval_), Com)
}

///|
pub fn BallFloatDecorated::max(
  self : BallFloatDecorated,
  other : BallFloatDecorated,
) -> BallFloatDecorated {
  binary_result(self, other, self.interval_.max(other.interval_), Com)
}

///|
pub fn BallFloatDecorated::apply_ctx(
  self : BallFloatDecorated,
  ctx : BallContext,
) -> (BallFloatDecorated, BallFlags) {
  let (interval, flags) = self.interval_.apply_ctx(ctx)
  if self.is_nai() {
    (BallFloatDecorated::nai(precision=ctx.precision()), flags)
  } else {
    (BallFloatDecorated::new(interval, decoration=self.decoration_), flags)
  }
}

///|
pub impl Add for BallFloatDecorated with fn add(self, other) {
  self.add(other)
}

///|
pub impl Sub for BallFloatDecorated with fn sub(self, other) {
  self.sub(other)
}

///|
pub impl Mul for BallFloatDecorated with fn mul(self, other) {
  self.mul(other)
}

///|
pub impl Div for BallFloatDecorated with fn div(self, other) {
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
pub impl Show for BallFloatDecorated with fn to_string(self) {
  if self.is_nai() {
    "[nai]"
  } else {
    self.interval_.to_string() + "_" + self.decoration_.to_string()
  }
}

///|
/// The midpoint-radius view of the interval followed by `_` and the decoration; see
/// `BallFloat::to_ball_string` (not a literal).
pub fn BallFloatDecorated::to_ball_string(self : BallFloatDecorated) -> String {
  if self.is_nai() {
    "[nai]"
  } else {
    self.interval_.to_ball_string() + "_" + self.decoration_.to_string()
  }
}

///|
pub extend Decoration with Show::{to_string}

///|
pub extend BallFloatDecorated with Show::{to_string}

///|
pub extend Decoration with Eq::{not_equal, equal}

///|
pub extend Decoration with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend BallFloatDecorated with Eq::{not_equal, equal}

///|
pub extend Decoration with Show::{output}

///|
pub extend BallFloatDecorated with Show::{output}
