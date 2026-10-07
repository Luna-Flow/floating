///|
/// IEEE 754 fusedMultiplyAdd: `self * multiplier + addend` computed exactly and
/// rounded once under `context`.
///
/// NaN operands propagate the first NaN among `self`, `multiplier`, and
/// `addend`, quieted. `invalid_operation` is raised for a signaling NaN
/// operand, for `inf * 0` (even when the addend is a quiet NaN, as SoftFloat
/// does), and for an infinite product added to an opposite infinity.
pub fn BinFloat::fma_ctx(
  self : BinFloat,
  multiplier : BinFloat,
  addend : BinFloat,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  let product_negative = self.negative != multiplier.negative
  let product_invalid = (
      self.class == FpClass::Infinity &&
      multiplier.class == FpClass::Finite &&
      multiplier.is_zero()
    ) ||
    (
      multiplier.class == FpClass::Infinity &&
      self.class == FpClass::Finite &&
      self.is_zero()
    )
  if self.class == FpClass::NaN ||
    multiplier.class == FpClass::NaN ||
    addend.class == FpClass::NaN {
    let source = if self.class == FpClass::NaN {
      self
    } else if multiplier.class == FpClass::NaN {
      multiplier
    } else {
      addend
    }
    let invalid = self.is_signaling_nan() ||
      multiplier.is_signaling_nan() ||
      addend.is_signaling_nan() ||
      product_invalid
    return (
      binary_quiet_nan(source, context.precision),
      if invalid {
        binary_invalid_flags()
      } else {
        BinaryFlags::new()
      },
    )
  }
  if product_invalid {
    return (BinFloat::nan(precision=context.precision), binary_invalid_flags())
  }
  if self.class == FpClass::Infinity || multiplier.class == FpClass::Infinity {
    if addend.class == FpClass::Infinity && addend.negative != product_negative {
      return (
        BinFloat::nan(precision=context.precision),
        binary_invalid_flags(),
      )
    }
    return (
      BinFloat::inf(
        if product_negative {
          Sign::Negative
        } else {
          Sign::Positive
        },
        precision=context.precision,
      ),
      BinaryFlags::new(),
    )
  }
  if addend.class == FpClass::Infinity {
    return (
      BinFloat::inf(addend.sign(), precision=context.precision),
      BinaryFlags::new(),
    )
  }
  match binary_exact_product(self, multiplier, addend, context) {
    Ok(product) => product.add_ctx(addend, context)
    Err(result) => result
  }
}

///|
/// The exact finite product as a `BinFloat`, or the final result when the
/// product's exponent leaves `Int`: such a product lies far outside the
/// implementation range, so it either overflows or acts as a sticky bit next
/// to a nonzero addend.
fn binary_exact_product(
  left : BinFloat,
  right : BinFloat,
  addend : BinFloat,
  context : BinaryContext,
) -> Result[BinFloat, (BinFloat, BinaryFlags)] {
  let negative = left.negative != right.negative
  let coefficient = left.coefficient_.mul(right.coefficient_)
  if coefficient.is_zero() {
    return Ok(finite_zero(negative, context.precision))
  }
  let exponent = left.exponent2.to_int64() + right.exponent2.to_int64()
  if exponent > 2147483647L - coefficient.bit_length().to_int64() {
    return Err(binary_overflow_result(negative, context))
  }
  if exponent >= -2147483648L {
    return Ok(
      finite_normalized(
        negative,
        coefficient,
        exponent.to_int(),
        Int::max(1, coefficient.bit_length()),
      ),
    )
  }
  if addend.is_zero() {
    return Err(binary_tiny_nonzero_result(negative, context))
  }
  // Every representable addend has its leading bit above -2^31 + 2^29, so a
  // single bit far below its last significant position rounds identically.
  let addend_top = binary_exact_top(addend.coefficient_, addend.exponent2)
  Ok(
    finite_normalized(
      negative,
      BinCoeff::one(),
      addend_top - addend.coefficient_.bit_length() - context.precision - 8,
      1,
    ),
  )
}

///|
/// `fma_ctx` in an unbounded round-to-nearest-even context at the largest
/// operand precision.
pub fn BinFloat::fma(
  self : BinFloat,
  multiplier : BinFloat,
  addend : BinFloat,
) -> BinFloat {
  let precision = Int::max(
    self.precision_,
    Int::max(multiplier.precision_, addend.precision_),
  )
  self.fma_ctx(multiplier, addend, BinaryContext::unbounded(precision)).0
}
