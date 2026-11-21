///|
/// The integer functions of IEEE 1788-2015 Table 9.1: `sign`, `ceil`, `floor`,
/// `trunc`, `roundTiesToEven` and `roundTiesToAway`. Each is nondecreasing, so
/// the interval result is `[f(lower), f(upper)]`; every endpoint is an integer
/// (or -1, 0, 1 for `sign`), so the result is exact and no rounding happens.
/// The decorated versions follow the local decoration of 11.2 and 11.6.

///|
priv enum IntegerFunction {
  Sign
  Ceil
  Floor
  Trunc
  RoundTiesToEven
  RoundTiesToAway
}

///|
fn integer_zero_positive(
  x : @binary.Binary,
  precision : Int32,
) -> @binary.Binary {
  // an interval endpoint 0 is stored as +0, whatever the sign the rounding gave
  if x.is_zero() {
    @binary.Binary::zero(precision~)
  } else {
    x
  }
}

///|
fn integer_apply(
  kind : IntegerFunction,
  x : @binary.Binary,
  precision : Int32,
) -> @binary.Binary {
  let value = match kind {
    Sign =>
      if x.is_zero() {
        @binary.Binary::zero(precision~)
      } else if x.sign() == Sign::Negative {
        @binary.Binary::from_int(-1, precision~)
      } else {
        @binary.Binary::from_int(1, precision~)
      }
    Ceil => x.ceil()
    Floor => x.floor()
    Trunc => x.trunc()
    RoundTiesToEven => x.round_ties_even()
    RoundTiesToAway => x.round()
  }
  integer_zero_positive(value, precision)
}

///|
fn Interval::integer_function(
  self : Interval,
  kind : IntegerFunction,
) -> Interval {
  if self.is_empty() {
    return self
  }
  store_interval(
    integer_apply(kind, self.lo_, self.precision_),
    integer_apply(kind, self.hi_, self.precision_),
    self.precision_,
  )
}

///|
/// `sign` of IEEE 1788-2015 Table 9.1: the hull of the signs of the points,
/// a subset of `[-1, 1]`; empty for Empty.
pub fn Interval::sign(self : Interval) -> Interval {
  self.integer_function(Sign)
}

///|
/// `ceil`: the smallest integer not less than each point.
pub fn Interval::ceil(self : Interval) -> Interval {
  self.integer_function(Ceil)
}

///|
/// `floor`: the largest integer not greater than each point.
pub fn Interval::floor(self : Interval) -> Interval {
  self.integer_function(Floor)
}

///|
/// `trunc`: the integer nearest to each point in the direction of zero.
pub fn Interval::trunc(self : Interval) -> Interval {
  self.integer_function(Trunc)
}

///|
/// `roundTiesToEven`: the nearest integer, a tie going to the even integer.
pub fn Interval::round_ties_to_even(self : Interval) -> Interval {
  self.integer_function(RoundTiesToEven)
}

///|
/// `roundTiesToAway`: the nearest integer, a tie going away from zero.
pub fn Interval::round_ties_to_away(self : Interval) -> Interval {
  self.integer_function(RoundTiesToAway)
}

///|
fn integer_equal(a : @binary.Binary, b : @binary.Binary) -> Bool {
  a.compare(b) == 0
}

///|
/// The strongest decoration of 11.2 (equation 14) for the function over the
/// interval `x` whose result is `y`:
/// - the function is nondecreasing with integer values, so its restriction to
///   `x` is continuous exactly when it is constant on `x` (`y` is a single
///   point); otherwise the decoration is `def`;
/// - when it is constant, `com` also needs `x` bounded and no point of
///   discontinuity of the function on the real line inside `x`; otherwise
///   `dac`. With the constant value `k`, a point of discontinuity lies in `x`
///   only at an endpoint equal to `k` (ceil, floor, trunc), to `k - 1/2` or
///   `k + 1/2` (the two roundings), and for `sign` when `k` is 0.
fn integer_local_decoration(
  kind : IntegerFunction,
  x : Interval,
  y : Interval,
) -> Decoration {
  if x.is_empty() {
    return Trv
  }
  if !integer_equal(y.lo_, y.hi_) {
    return Def
  }
  if !x.is_common_interval() {
    return Dac
  }
  let k = y.lo_
  let a = x.lo_
  let b = x.hi_
  let half = @binary.Binary::from_double(0.5, precision=x.precision_)
  let jump_inside = match kind {
    Sign => k.is_zero()
    Ceil => integer_equal(b, k)
    Floor => integer_equal(a, k)
    Trunc =>
      if k.is_zero() {
        false
      } else if k.sign() == Sign::Positive {
        integer_equal(a, k)
      } else {
        integer_equal(b, k)
      }
    RoundTiesToEven | RoundTiesToAway =>
      integer_equal(k - a, half) || integer_equal(b - k, half)
  }
  if jump_inside {
    Dac
  } else {
    Com
  }
}

///|
fn DecoratedInterval::integer_function(
  self : DecoratedInterval,
  kind : IntegerFunction,
) -> DecoratedInterval {
  let result = self.interval_.integer_function(kind)
  unary_result(
    self,
    result,
    integer_local_decoration(kind, self.interval_, result),
  )
}

///|
pub fn DecoratedInterval::sign(self : DecoratedInterval) -> DecoratedInterval {
  self.integer_function(Sign)
}

///|
pub fn DecoratedInterval::ceil(self : DecoratedInterval) -> DecoratedInterval {
  self.integer_function(Ceil)
}

///|
pub fn DecoratedInterval::floor(self : DecoratedInterval) -> DecoratedInterval {
  self.integer_function(Floor)
}

///|
pub fn DecoratedInterval::trunc(self : DecoratedInterval) -> DecoratedInterval {
  self.integer_function(Trunc)
}

///|
pub fn DecoratedInterval::round_ties_to_even(
  self : DecoratedInterval,
) -> DecoratedInterval {
  self.integer_function(RoundTiesToEven)
}

///|
pub fn DecoratedInterval::round_ties_to_away(
  self : DecoratedInterval,
) -> DecoratedInterval {
  self.integer_function(RoundTiesToAway)
}
