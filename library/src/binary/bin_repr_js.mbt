///|
/// The representation of `Binary` on the JavaScript target: the constructors
/// and the accessors (see `bin_repr_nonjs.mbt` for the other targets). A
/// coefficient is a host bigint and every word path is absent, so a finite
/// value, zero included, is `FinBig`. Nothing else matches on
/// `@bin_kernel.BinRepr`.

///|
#inline
fn bin_repr_zero(negative : Bool, precision : Int32) -> Binary {
  Binary(
    @bin_kernel.BinRepr::FinBig(
      negative~,
      coefficient=Coeff::zero(),
      exponent2=0,
      precision~,
    ),
  )
}

///|
#inline
fn bin_repr_finite(
  negative : Bool,
  coefficient : Coeff,
  exponent2 : Int32,
  precision : Int32,
) -> Binary {
  Binary(
    @bin_kernel.BinRepr::FinBig(negative~, coefficient~, exponent2~, precision~),
  )
}

///|
#inline
fn bin_repr_inf(negative : Bool, precision : Int32) -> Binary {
  Binary(@bin_kernel.BinRepr::Inf(negative~, precision~))
}

///|
#inline
fn bin_repr_nan(
  negative : Bool,
  signaling : Bool,
  payload : Coeff,
  precision : Int32,
) -> Binary {
  Binary(@bin_kernel.BinRepr::NaN(negative~, signaling~, payload~, precision~))
}

///|
#inline
fn Binary::class(self : Binary) -> FpClass {
  match self.0 {
    FinBig(..) => FpClass::Finite
    Inf(..) => FpClass::Infinity
    NaN(..) => FpClass::NaN
  }
}

///|
#inline
fn Binary::negative(self : Binary) -> Bool {
  match self.0 {
    FinBig(negative~, ..) => negative
    Inf(negative~, ..) => negative
    NaN(negative~, ..) => negative
  }
}

///|
#inline
fn Binary::precision_(self : Binary) -> Int32 {
  match self.0 {
    FinBig(precision~, ..) => precision
    Inf(precision~, ..) => precision
    NaN(precision~, ..) => precision
  }
}

///|
#inline
fn Binary::exponent2_(self : Binary) -> Int32 {
  match self.0 {
    FinBig(exponent2~, ..) => exponent2
    Inf(..) | NaN(..) => 0
  }
}

///|
#inline
fn Binary::coefficient_(self : Binary) -> Coeff {
  match self.0 {
    FinBig(coefficient~, ..) => coefficient
    Inf(..) => Coeff::one()
    NaN(..) => Coeff::zero()
  }
}

///|
/// `sign` in one match.
#inline
fn Binary::sign_(self : Binary) -> Sign {
  match self.0 {
    FinBig(negative~, coefficient~, ..) =>
      if coefficient.is_zero() {
        Sign::Zero
      } else if negative {
        Sign::Negative
      } else {
        Sign::Positive
      }
    Inf(negative~, ..) => if negative { Sign::Negative } else { Sign::Positive }
    NaN(..) => Sign::Zero
  }
}

///|
#inline
fn Binary::coefficient_is_zero(self : Binary) -> Bool {
  match self.0 {
    FinBig(coefficient~, ..) => coefficient.is_zero()
    Inf(..) => false
    NaN(..) => true
  }
}

///|
#inline
fn Binary::coefficient_bits(self : Binary) -> Int32 {
  match self.0 {
    FinBig(coefficient~, ..) => coefficient.bit_length()
    Inf(..) => 1
    NaN(..) => 0
  }
}

///|
#inline
fn Binary::signaling(self : Binary) -> Bool {
  match self.0 {
    NaN(signaling~, ..) => signaling
    _ => false
  }
}

///|
#inline
fn Binary::payload_(self : Binary) -> Coeff {
  match self.0 {
    NaN(payload~, ..) => payload
    _ => Coeff::zero()
  }
}

///|
/// The same finite datum with the exponent `exponent2`; the coefficient is
/// shared. Not for infinities and NaNs.
fn Binary::with_exponent2_(self : Binary, exponent2 : Int32) -> Binary {
  match self.0 {
    FinBig(negative~, coefficient~, precision~, ..) =>
      bin_repr_finite(negative, coefficient, exponent2, precision)
    Inf(..) | NaN(..) => self
  }
}

///|
#inline
fn Binary::with_negative(self : Binary, negative : Bool) -> Binary {
  match self.0 {
    FinBig(coefficient~, exponent2~, precision~, ..) =>
      bin_repr_finite(negative, coefficient, exponent2, precision)
    Inf(precision~, ..) => bin_repr_inf(negative, precision)
    NaN(signaling~, payload~, precision~, ..) =>
      bin_repr_nan(negative, signaling, payload, precision)
  }
}
