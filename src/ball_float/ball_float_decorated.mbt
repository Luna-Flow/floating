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
pub fn BallFloatDecorated::expm1_interval(
  self : BallFloatDecorated,
) -> BallFloatDecorated {
  unary_result(self, self.interval_.expm1_interval(), Com)
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
pub fn BallFloatDecorated::log1p_interval(
  self : BallFloatDecorated,
) -> BallFloatDecorated {
  let minus_one = @bin_float.BinFloat::from_int(
    -1,
    precision=self.interval_.precision(),
  )
  let partial_domain = !self.interval_.is_empty() &&
    self.interval_.lower_bound().compare(minus_one) <= 0
  unary_result(
    self,
    self.interval_.log1p_interval(),
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
  degree : Int,
) -> BallFloatDecorated {
  let partial_domain = degree == 0 ||
    (
      degree % 2 == 0 &&
      self.interval_.lower_bound().sign() == @def.Sign::Negative
    )
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
pub fn BallFloatDecorated::sinpi_interval(
  self : BallFloatDecorated,
) -> BallFloatDecorated {
  unary_result(self, self.interval_.sinpi_interval(), Com)
}

///|
pub fn BallFloatDecorated::cospi_interval(
  self : BallFloatDecorated,
) -> BallFloatDecorated {
  unary_result(self, self.interval_.cospi_interval(), Com)
}

///|
pub fn BallFloatDecorated::tanpi_interval(
  self : BallFloatDecorated,
) -> BallFloatDecorated {
  let result = self.interval_.tanpi_interval()
  unary_result(
    self,
    result,
    if result.is_entire() && !self.interval_.is_empty() {
      Trv
    } else {
      Com
    },
  )
}

///|
pub fn BallFloatDecorated::sinh_interval(
  self : BallFloatDecorated,
) -> BallFloatDecorated {
  unary_result(self, self.interval_.sinh_interval(), Com)
}

///|
pub fn BallFloatDecorated::cosh_interval(
  self : BallFloatDecorated,
) -> BallFloatDecorated {
  unary_result(self, self.interval_.cosh_interval(), Com)
}

///|
pub fn BallFloatDecorated::tanh_interval(
  self : BallFloatDecorated,
) -> BallFloatDecorated {
  unary_result(self, self.interval_.tanh_interval(), Com)
}

///|
pub fn BallFloatDecorated::asinh_interval(
  self : BallFloatDecorated,
) -> BallFloatDecorated {
  unary_result(self, self.interval_.asinh_interval(), Com)
}

///|
pub fn BallFloatDecorated::acosh_interval(
  self : BallFloatDecorated,
) -> BallFloatDecorated {
  let one = @bin_float.BinFloat::one(precision=self.interval_.precision())
  let partial_domain = !self.interval_.is_empty() &&
    self.interval_.lower_bound().compare(one) < 0
  unary_result(
    self,
    self.interval_.acosh_interval(),
    if partial_domain {
      Trv
    } else {
      Com
    },
  )
}

///|
pub fn BallFloatDecorated::atanh_interval(
  self : BallFloatDecorated,
) -> BallFloatDecorated {
  let one = @bin_float.BinFloat::one(precision=self.interval_.precision())
  let minus_one = one.neg()
  let partial_domain = !self.interval_.is_empty() &&
    (
      self.interval_.lower_bound().compare(minus_one) <= 0 ||
      self.interval_.upper_bound().compare(one) >= 0
    )
  unary_result(
    self,
    self.interval_.atanh_interval(),
    if partial_domain {
      Trv
    } else {
      Com
    },
  )
}

///|
pub fn BallFloatDecorated::atan_interval(
  self : BallFloatDecorated,
) -> BallFloatDecorated {
  unary_result(self, self.interval_.atan_interval(), Com)
}

///|
fn BallFloatDecorated::inverse_unit_result(
  self : BallFloatDecorated,
  interval : BallFloat,
) -> BallFloatDecorated {
  let one = @bin_float.BinFloat::one(precision=self.interval_.precision())
  let partial_domain = !self.interval_.is_empty() &&
    (
      self.interval_.lower_bound().compare(one.neg()) < 0 ||
      self.interval_.upper_bound().compare(one) > 0
    )
  unary_result(self, interval, if partial_domain { Trv } else { Com })
}

///|
pub fn BallFloatDecorated::asin_interval(
  self : BallFloatDecorated,
) -> BallFloatDecorated {
  self.inverse_unit_result(self.interval_.asin_interval())
}

///|
pub fn BallFloatDecorated::acos_interval(
  self : BallFloatDecorated,
) -> BallFloatDecorated {
  self.inverse_unit_result(self.interval_.acos_interval())
}

///|
pub fn BallFloatDecorated::atan2_interval(
  self : BallFloatDecorated,
  abscissa : BallFloatDecorated,
) -> BallFloatDecorated {
  let interval = self.interval_.atan2_interval(abscissa.interval_)
  let contains_origin = self.interval_.contains_zero() &&
    abscissa.interval_.contains_zero()
  let crosses_cut = abscissa.interval_.lower_bound().sign() ==
    @def.Sign::Negative &&
    self.interval_.lower_bound().sign() == @def.Sign::Negative &&
    self.interval_.contains_zero()
  let touches_cut_from_above = abscissa.interval_
    .upper_bound()
    .compare(@bin_float.BinFloat::zero(precision=interval.precision())) <
    0 &&
    self.interval_.lower_bound().is_zero()
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
