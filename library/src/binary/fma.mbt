///|
/// IEEE 754 fusedMultiplyAdd: `self * multiplier + addend` computed exactly and
/// rounded once under `context`.
///
/// NaN operands propagate the first NaN among `self`, `multiplier`, and
/// `addend`, quieted. `invalid_operation` is raised for a signaling NaN
/// operand, for `inf * 0` (even when the addend is a quiet NaN, as SoftFloat
/// does), and for an infinite product added to an opposite infinity.
pub fn Binary::fma_ctx(
  self : Binary,
  multiplier : Binary,
  addend : Binary,
  context : BinaryContext,
) -> (Binary, BinaryFlags) {
  let product_negative = self.negative() != multiplier.negative()
  let product_invalid = (
      self.class() == FpClass::Infinity &&
      multiplier.class() == FpClass::Finite &&
      multiplier.is_zero()
    ) ||
    (
      multiplier.class() == FpClass::Infinity &&
      self.class() == FpClass::Finite &&
      self.is_zero()
    )
  if self.class() == FpClass::NaN ||
    multiplier.class() == FpClass::NaN ||
    addend.class() == FpClass::NaN {
    let source = if self.class() == FpClass::NaN {
      self
    } else if multiplier.class() == FpClass::NaN {
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
    return (
      Binary::nan_raw(precision=context.precision),
      binary_invalid_flags(),
    )
  }
  if self.class() == FpClass::Infinity ||
    multiplier.class() == FpClass::Infinity {
    if addend.class() == FpClass::Infinity &&
      addend.negative() != product_negative {
      return (
        Binary::nan_raw(precision=context.precision),
        binary_invalid_flags(),
      )
    }
    return (
      Binary::inf_raw(
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
  if addend.class() == FpClass::Infinity {
    return (
      Binary::inf_raw(addend.sign(), precision=context.precision),
      BinaryFlags::new(),
    )
  }
  match binary_exact_product(self, multiplier, addend, context) {
    Ok(product) => product.add_ctx(addend, context)
    Err(result) => result
  }
}

///|
/// The exact finite product as a `Binary`, or the final result when the
/// product's exponent leaves `Int`: such a product lies far outside the
/// implementation range, so it either overflows or acts as a sticky bit next
/// to a nonzero addend.
fn binary_exact_product(
  left : Binary,
  right : Binary,
  addend : Binary,
  context : BinaryContext,
) -> Result[Binary, (Binary, BinaryFlags)] {
  let negative = left.negative() != right.negative()
  let coefficient = left.coefficient_().mul(right.coefficient_())
  if coefficient.is_zero() {
    return Ok(finite_zero(negative, context.precision))
  }
  let exponent = left.exponent2_().to_int64() + right.exponent2_().to_int64()
  if exponent > 2147483647L - coefficient.bit_length().to_int64() {
    return Err(binary_overflow_result(negative, context))
  }
  if exponent >= -2147483648L {
    return Ok(
      finite_normalized(
        negative,
        coefficient,
        exponent.to_int(),
        Int32::max(1, coefficient.bit_length()),
      ),
    )
  }
  if addend.is_zero() {
    return Err(binary_tiny_nonzero_result(negative, context))
  }
  // Every representable addend has its leading bit above -2^31 + 2^29, so a
  // single bit far below its last significant position rounds identically.
  let addend_top = addend.exact_top()
  Ok(
    finite_normalized(
      negative,
      Coeff::one(),
      addend_top - addend.coefficient_bits() - context.precision - 8,
      1,
    ),
  )
}

///|
/// `fma_ctx` in an unbounded round-to-nearest-even context at the largest
/// operand precision.
pub fn Binary::fma(
  self : Binary,
  multiplier : Binary,
  addend : Binary,
) -> Binary {
  let precision = Int32::max(
    self.precision_(),
    Int32::max(multiplier.precision_(), addend.precision_()),
  )
  self.fma_ctx(multiplier, addend, binary_working_context(precision)).0
}
