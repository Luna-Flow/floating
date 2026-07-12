///|
pub(all) enum Decoration {
  Ill
  Trv
  Def
  Dac
  Com
} derive(Eq, Debug)

///|
fn decoration_rank(decoration : Decoration) -> Int {
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
  } else if decoration == Ill {
    Trv
  } else {
    decoration
  }
}

///|
pub struct BallFloatDecorated {
  priv interval_ : BallFloat
  priv decoration_ : Decoration
  priv nai_ : Bool
} derive(Eq)

///|
pub fn BallFloatDecorated::new(
  interval : BallFloat,
  decoration? : Decoration = Com,
) -> BallFloatDecorated {
  {
    interval_: interval,
    decoration_: canonical_decoration(interval, decoration),
    nai_: false,
  }
}

///|
pub fn BallFloatDecorated::nai(precision? : Int = 53) -> BallFloatDecorated {
  { interval_: BallFloat::empty(precision~), decoration_: Ill, nai_: true }
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
pub fn BallFloatDecorated::contains(
  self : BallFloatDecorated,
  value : @bin_float.BinFloat,
) -> Bool {
  !self.is_nai() && self.interval_.contains(value)
}

///|
pub fn BallFloatDecorated::set_equal(
  self : BallFloatDecorated,
  other : BallFloatDecorated,
) -> Bool {
  !self.is_nai() && !other.is_nai() && self.interval_.set_equal(other.interval_)
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
pub fn BallFloatDecorated::strictly_less(
  self : BallFloatDecorated,
  other : BallFloatDecorated,
) -> Bool {
  !self.is_nai() &&
  !other.is_nai() &&
  self.interval_.strictly_less(other.interval_)
}

///|
pub fn BallFloatDecorated::precedes(
  self : BallFloatDecorated,
  other : BallFloatDecorated,
) -> Bool {
  !self.is_nai() && !other.is_nai() && self.interval_.precedes(other.interval_)
}

///|
pub fn BallFloatDecorated::strictly_precedes(
  self : BallFloatDecorated,
  other : BallFloatDecorated,
) -> Bool {
  !self.is_nai() &&
  !other.is_nai() &&
  self.interval_.strictly_precedes(other.interval_)
}

///|
pub fn BallFloatDecorated::overlap_state(
  self : BallFloatDecorated,
  other : BallFloatDecorated,
) -> OverlapState {
  if self.is_nai() || other.is_nai() {
    Undefined
  } else {
    self.interval_.overlap_state(other.interval_)
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
      precision=Int::max(
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
pub fn BallFloatDecorated::reciprocal(
  self : BallFloatDecorated,
) -> BallFloatDecorated {
  unary_result(
    self,
    self.interval_.reciprocal(),
    if self.interval_.contains_zero() {
      Trv
    } else {
      Com
    },
  )
}

///|
pub fn BallFloatDecorated::square(
  self : BallFloatDecorated,
) -> BallFloatDecorated {
  unary_result(self, self.interval_.square(), Com)
}

///|
pub fn BallFloatDecorated::sqrt_interval(
  self : BallFloatDecorated,
) -> BallFloatDecorated {
  unary_result(
    self,
    self.interval_.sqrt_interval(),
    if self.interval_.is_empty() ||
      self.interval_.lower_bound().sign() == @def.Sign::Negative {
      Trv
    } else {
      Com
    },
  )
}

///|
pub fn BallFloatDecorated::exp_interval(
  self : BallFloatDecorated,
) -> BallFloatDecorated {
  unary_result(self, self.interval_.exp_interval(), Com)
}

///|
pub fn BallFloatDecorated::exp2_interval(
  self : BallFloatDecorated,
) -> BallFloatDecorated {
  unary_result(self, self.interval_.exp2_interval(), Com)
}

///|
pub fn BallFloatDecorated::exp10_interval(
  self : BallFloatDecorated,
) -> BallFloatDecorated {
  unary_result(self, self.interval_.exp10_interval(), Com)
}

///|
fn BallFloatDecorated::logarithm_result(
  self : BallFloatDecorated,
  interval : BallFloat,
) -> BallFloatDecorated {
  let partial_domain = !self.interval_.is_empty() &&
    (
      self.interval_.lower_bound().sign() == @def.Sign::Negative ||
      self.interval_.lower_bound().is_zero()
    )
  unary_result(self, interval, if partial_domain { Trv } else { Com })
}

///|
pub fn BallFloatDecorated::ln_interval(
  self : BallFloatDecorated,
) -> BallFloatDecorated {
  self.logarithm_result(self.interval_.ln_interval())
}

///|
pub fn BallFloatDecorated::log2_interval(
  self : BallFloatDecorated,
) -> BallFloatDecorated {
  self.logarithm_result(self.interval_.log2_interval())
}

///|
pub fn BallFloatDecorated::log10_interval(
  self : BallFloatDecorated,
) -> BallFloatDecorated {
  self.logarithm_result(self.interval_.log10_interval())
}

///|
pub fn BallFloatDecorated::pow_interval(
  self : BallFloatDecorated,
  exponent : BallFloatDecorated,
) -> BallFloatDecorated {
  let interval = self.interval_.pow_interval(exponent.interval_)
  let partial_domain = self.interval_.is_empty() ||
    self.interval_.lower_bound().sign() == @def.Sign::Negative ||
    (
      self.interval_.contains_zero() &&
      (
        exponent.interval_.lower_bound().sign() == @def.Sign::Negative ||
        exponent.interval_.lower_bound().is_zero()
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
pub fn BallFloatDecorated::sin_interval(
  self : BallFloatDecorated,
) -> BallFloatDecorated {
  unary_result(self, self.interval_.sin_interval(), Com)
}

///|
pub fn BallFloatDecorated::cos_interval(
  self : BallFloatDecorated,
) -> BallFloatDecorated {
  unary_result(self, self.interval_.cos_interval(), Com)
}

///|
pub fn BallFloatDecorated::tan_interval(
  self : BallFloatDecorated,
) -> BallFloatDecorated {
  let interval = self.interval_.tan_interval()
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
      precision=Int::max(
        self.interval_.precision(),
        Int::max(multiplier.interval_.precision(), addend.interval_.precision()),
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
  exponent : Int,
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
pub fn BallFloatDecorated::minimum(
  self : BallFloatDecorated,
  other : BallFloatDecorated,
) -> BallFloatDecorated {
  binary_result(self, other, self.interval_.minimum(other.interval_), Com)
}

///|
pub fn BallFloatDecorated::maximum(
  self : BallFloatDecorated,
  other : BallFloatDecorated,
) -> BallFloatDecorated {
  binary_result(self, other, self.interval_.maximum(other.interval_), Com)
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
