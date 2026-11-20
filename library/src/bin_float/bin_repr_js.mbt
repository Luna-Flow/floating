///|
/// The representation of `BinFloat` on the JavaScript target: the constructors
/// and the accessors (see `bin_repr_nonjs.mbt` for the other targets). A
/// coefficient is a host bigint and every word path is absent, so a finite
/// value, zero included, is `FinBig`. Nothing else matches on
/// `@bin_kernel.BinRepr`.

///|
#inline
fn bin_repr_zero(negative : Bool, precision : Int32) -> BinFloat {
  BinFloat(
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
) -> BinFloat {
  BinFloat(
    @bin_kernel.BinRepr::FinBig(negative~, coefficient~, exponent2~, precision~),
  )
}

///|
#inline
fn bin_repr_inf(negative : Bool, precision : Int32) -> BinFloat {
  BinFloat(@bin_kernel.BinRepr::Inf(negative~, precision~))
}

///|
#inline
fn bin_repr_nan(
  negative : Bool,
  signaling : Bool,
  payload : Coeff,
  precision : Int32,
) -> BinFloat {
  BinFloat(
    @bin_kernel.BinRepr::NaN(negative~, signaling~, payload~, precision~),
  )
}

///|
#inline
fn BinFloat::class(self : BinFloat) -> FpClass {
  match self.0 {
    FinBig(..) => FpClass::Finite
    Inf(..) => FpClass::Infinity
    NaN(..) => FpClass::NaN
  }
}

///|
#inline
fn BinFloat::negative(self : BinFloat) -> Bool {
  match self.0 {
    FinBig(negative~, ..) => negative
    Inf(negative~, ..) => negative
    NaN(negative~, ..) => negative
  }
}

///|
#inline
fn BinFloat::precision_(self : BinFloat) -> Int32 {
  match self.0 {
    FinBig(precision~, ..) => precision
    Inf(precision~, ..) => precision
    NaN(precision~, ..) => precision
  }
}

///|
#inline
fn BinFloat::exponent2_(self : BinFloat) -> Int32 {
  match self.0 {
    FinBig(exponent2~, ..) => exponent2
    Inf(..) | NaN(..) => 0
  }
}

///|
#inline
fn BinFloat::coefficient_(self : BinFloat) -> Coeff {
  match self.0 {
    FinBig(coefficient~, ..) => coefficient
    Inf(..) => Coeff::one()
    NaN(..) => Coeff::zero()
  }
}

///|
/// `sign` in one match.
#inline
fn BinFloat::sign_(self : BinFloat) -> Sign {
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
fn BinFloat::coefficient_is_zero(self : BinFloat) -> Bool {
  match self.0 {
    FinBig(coefficient~, ..) => coefficient.is_zero()
    Inf(..) => false
    NaN(..) => true
  }
}

///|
#inline
fn BinFloat::coefficient_bits(self : BinFloat) -> Int32 {
  match self.0 {
    FinBig(coefficient~, ..) => coefficient.bit_length()
    Inf(..) => 1
    NaN(..) => 0
  }
}

///|
#inline
fn BinFloat::signaling(self : BinFloat) -> Bool {
  match self.0 {
    NaN(signaling~, ..) => signaling
    _ => false
  }
}

///|
#inline
fn BinFloat::payload_(self : BinFloat) -> Coeff {
  match self.0 {
    NaN(payload~, ..) => payload
    _ => Coeff::zero()
  }
}

///|
/// The same finite datum with the exponent `exponent2`; the coefficient is
/// shared. Not for infinities and NaNs.
fn BinFloat::with_exponent2_(self : BinFloat, exponent2 : Int32) -> BinFloat {
  match self.0 {
    FinBig(negative~, coefficient~, precision~, ..) =>
      bin_repr_finite(negative, coefficient, exponent2, precision)
    Inf(..) | NaN(..) => self
  }
}

///|
#inline
fn BinFloat::with_negative(self : BinFloat, negative : Bool) -> BinFloat {
  match self.0 {
    FinBig(coefficient~, exponent2~, precision~, ..) =>
      bin_repr_finite(negative, coefficient, exponent2, precision)
    Inf(precision~, ..) => bin_repr_inf(negative, precision)
    NaN(signaling~, payload~, precision~, ..) =>
      bin_repr_nan(negative, signaling, payload, precision)
  }
}
