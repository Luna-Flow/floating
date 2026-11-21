///|
/// The representation of `Binary` on the native, wasm and llvm targets: the
/// constructors and the accessors. Nothing else matches on `@bin_kernel.BinRepr`
/// except the `_nonjs` fast paths, which read words through `is_word`,
/// `word_`, `is_pair`, `pair_high` and `pair_low` (scalars, no option and no
/// tuple: either would allocate).
///
/// A finite value has one form: `Fin64` for a coefficient of at most 64 bits
/// (zero is `word = 0`, `exponent2 = 0`), `Fin128` for 65 to 128 bits, `FinBig`
/// for more. The `exponent2` of an infinity and of a NaN reads as 0 and the
/// coefficient of an infinity as 1, as before the representation changed.

///|
#inline
fn bin_repr_zero(negative : Bool, precision : Int32) -> Binary {
  Binary(
    @bin_kernel.BinRepr::Fin64(negative~, word=0UL, exponent2=0, precision~),
  )
}

///|
/// A finite value from its coefficient (odd, or zero with `exponent2 = 0`).
#inline
fn bin_repr_finite(
  negative : Bool,
  coefficient : Coeff,
  exponent2 : Int32,
  precision : Int32,
) -> Binary {
  match coefficient.0 {
    Inline64(word) =>
      Binary(
        @bin_kernel.BinRepr::Fin64(negative~, word~, exponent2~, precision~),
      )
    Inline128(high, low) =>
      if high == 0UL {
        Binary(
          @bin_kernel.BinRepr::Fin64(
            negative~,
            word=low,
            exponent2~,
            precision~,
          ),
        )
      } else {
        Binary(
          @bin_kernel.BinRepr::Fin128(
            negative~,
            high~,
            low~,
            exponent2~,
            precision~,
          ),
        )
      }
    Heap(_, _) =>
      Binary(
        @bin_kernel.BinRepr::FinBig(
          negative~,
          coefficient~,
          exponent2~,
          precision~,
        ),
      )
  }
}

///|
/// A finite value of a non-zero one-word odd coefficient.
#inline
fn bin_repr_word(
  negative : Bool,
  word : UInt64,
  exponent2 : Int32,
  precision : Int32,
) -> Binary {
  Binary(@bin_kernel.BinRepr::Fin64(negative~, word~, exponent2~, precision~))
}

///|
/// A finite value of a non-zero odd coefficient `high * 2^64 + low`.
#inline
fn bin_repr_pair(
  negative : Bool,
  high : UInt64,
  low : UInt64,
  exponent2 : Int32,
  precision : Int32,
) -> Binary {
  if high == 0UL {
    Binary(
      @bin_kernel.BinRepr::Fin64(negative~, word=low, exponent2~, precision~),
    )
  } else {
    Binary(
      @bin_kernel.BinRepr::Fin128(
        negative~,
        high~,
        low~,
        exponent2~,
        precision~,
      ),
    )
  }
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
    Fin64(..) | Fin128(..) | FinBig(..) => FpClass::Finite
    Inf(..) => FpClass::Infinity
    NaN(..) => FpClass::NaN
  }
}

///|
#inline
fn Binary::negative(self : Binary) -> Bool {
  match self.0 {
    Fin64(negative~, ..) => negative
    Fin128(negative~, ..) => negative
    FinBig(negative~, ..) => negative
    Inf(negative~, ..) => negative
    NaN(negative~, ..) => negative
  }
}

///|
#inline
fn Binary::precision_(self : Binary) -> Int32 {
  match self.0 {
    Fin64(precision~, ..) => precision
    Fin128(precision~, ..) => precision
    FinBig(precision~, ..) => precision
    Inf(precision~, ..) => precision
    NaN(precision~, ..) => precision
  }
}

///|
#inline
fn Binary::exponent2_(self : Binary) -> Int32 {
  match self.0 {
    Fin64(exponent2~, ..) => exponent2
    Fin128(exponent2~, ..) => exponent2
    FinBig(exponent2~, ..) => exponent2
    Inf(..) | NaN(..) => 0
  }
}

///|
/// The coefficient as a `Coeff`: for a value of at most 128 bits this builds
/// the object, so a reader that only needs a test or a length uses
/// `coefficient_is_zero` and `coefficient_bits`.
#inline
fn Binary::coefficient_(self : Binary) -> Coeff {
  match self.0 {
    Fin64(word~, ..) => Coeff::from_uint64(word)
    Fin128(high~, low~, ..) => bin_coeff_inline(high, low)
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
    Fin64(negative~, word~, ..) =>
      if word == 0UL {
        Sign::Zero
      } else if negative {
        Sign::Negative
      } else {
        Sign::Positive
      }
    Fin128(negative~, ..) | FinBig(negative~, ..) | Inf(negative~, ..) =>
      if negative {
        Sign::Negative
      } else {
        Sign::Positive
      }
    NaN(..) => Sign::Zero
  }
}

///|
/// `self.coefficient_().is_zero()` without building the coefficient.
#inline
fn Binary::coefficient_is_zero(self : Binary) -> Bool {
  match self.0 {
    Fin64(word~, ..) => word == 0UL
    Fin128(..) | FinBig(..) | Inf(..) => false
    NaN(..) => true
  }
}

///|
/// `self.coefficient_().bit_length()` without building the coefficient.
#inline
fn Binary::coefficient_bits(self : Binary) -> Int32 {
  match self.0 {
    Fin64(word~, ..) => binary_fast_bits(word)
    Fin128(high~, ..) => 64 + binary_fast_bits(high)
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
/// The same finite datum with the exponent `exponent2`: the words are copied
/// and a wide coefficient is shared, not copied. Not for infinities and NaNs.
fn Binary::with_exponent2_(self : Binary, exponent2 : Int32) -> Binary {
  match self.0 {
    Fin64(negative~, word~, precision~, ..) =>
      Binary(
        @bin_kernel.BinRepr::Fin64(negative~, word~, exponent2~, precision~),
      )
    Fin128(negative~, high~, low~, precision~, ..) =>
      Binary(
        @bin_kernel.BinRepr::Fin128(
          negative~,
          high~,
          low~,
          exponent2~,
          precision~,
        ),
      )
    FinBig(negative~, coefficient~, precision~, ..) =>
      Binary(
        @bin_kernel.BinRepr::FinBig(
          negative~,
          coefficient~,
          exponent2~,
          precision~,
        ),
      )
    Inf(..) | NaN(..) => self
  }
}

///|
/// The same datum with the sign bit set to `negative`.
#inline
fn Binary::with_negative(self : Binary, negative : Bool) -> Binary {
  match self.0 {
    Fin64(word~, exponent2~, precision~, ..) =>
      Binary(
        @bin_kernel.BinRepr::Fin64(negative~, word~, exponent2~, precision~),
      )
    Fin128(high~, low~, exponent2~, precision~, ..) =>
      Binary(
        @bin_kernel.BinRepr::Fin128(
          negative~,
          high~,
          low~,
          exponent2~,
          precision~,
        ),
      )
    FinBig(coefficient~, exponent2~, precision~, ..) =>
      Binary(
        @bin_kernel.BinRepr::FinBig(
          negative~,
          coefficient~,
          exponent2~,
          precision~,
        ),
      )
    Inf(precision~, ..) => bin_repr_inf(negative, precision)
    NaN(signaling~, payload~, precision~, ..) =>
      bin_repr_nan(negative, signaling, payload, precision)
  }
}

///|
/// Whether `self` is finite with a non-zero coefficient of one word.
#inline
fn Binary::is_word(self : Binary) -> Bool {
  match self.0 {
    Fin64(word~, ..) => word != 0UL
    _ => false
  }
}

///|
/// The word of a value for which `is_word` holds (0 for another value).
#inline
fn Binary::word_(self : Binary) -> UInt64 {
  match self.0 {
    Fin64(word~, ..) => word
    _ => 0UL
  }
}

///|
/// Whether `self` is finite with a non-zero coefficient of one or two words.
#inline
fn Binary::is_pair(self : Binary) -> Bool {
  match self.0 {
    Fin64(word~, ..) => word != 0UL
    Fin128(..) => true
    _ => false
  }
}

///|
#inline
fn Binary::pair_high(self : Binary) -> UInt64 {
  match self.0 {
    Fin128(high~, ..) => high
    _ => 0UL
  }
}

///|
#inline
fn Binary::pair_low(self : Binary) -> UInt64 {
  match self.0 {
    Fin64(word~, ..) => word
    Fin128(low~, ..) => low
    _ => 0UL
  }
}
