///|
/// General Decimal Arithmetic value boundary.
pub struct Decimal {
  priv inner : @decimal.Decimal
} derive(Eq)

///|
fn decimal_from_kernel(inner : @decimal.Decimal) -> Decimal {
  { inner, }
}

///|
fn complete_decimal_gda(
  value : @decimal.Decimal,
  context : GdaContext,
  flags : @decimal.DecimalFlags,
) -> GdaOutcome[Decimal] {
  complete_gda(decimal_from_kernel(value), context, flags)
}

///|
pub fn Decimal::from_string(source : String, precision? : Int = 34) -> Decimal? {
  match @decimal.Decimal::from_string(source, precision~) {
    Some(value) => Some(decimal_from_kernel(value))
    None => None
  }
}

///|
pub fn Decimal::zero(precision? : Int = 34) -> Decimal {
  decimal_from_kernel(@decimal.Decimal::zero(precision~))
}

///|
pub fn Decimal::one(precision? : Int = 34) -> Decimal {
  decimal_from_kernel(@decimal.Decimal::one(precision~))
}

///|
pub fn Decimal::quiet_nan(
  payload? : @bigint.BigInt = 0N,
  negative? : Bool = false,
  precision? : Int = 34,
) -> Decimal {
  decimal_from_kernel(
    @decimal.Decimal::quiet_nan(payload~, negative~, precision~),
  )
}

///|
pub fn Decimal::signaling_nan(
  payload? : @bigint.BigInt = 0N,
  negative? : Bool = false,
  precision? : Int = 34,
) -> Decimal {
  decimal_from_kernel(
    @decimal.Decimal::signaling_nan(payload~, negative~, precision~),
  )
}

///|
pub fn Decimal::is_finite(self : Decimal) -> Bool {
  self.inner.is_finite()
}

///|
pub fn Decimal::is_infinite(self : Decimal) -> Bool {
  self.inner.is_infinite()
}

///|
pub fn Decimal::is_nan(self : Decimal) -> Bool {
  self.inner.is_nan()
}

///|
pub fn Decimal::is_qnan(self : Decimal) -> Bool {
  self.inner.is_qnan()
}

///|
pub fn Decimal::is_snan(self : Decimal) -> Bool {
  self.inner.is_snan()
}

///|
pub fn Decimal::is_zero(self : Decimal) -> Bool {
  self.inner.is_zero()
}

///|
pub fn Decimal::is_negative(self : Decimal) -> Bool {
  self.inner.is_negative()
}

///|
pub fn Decimal::nan_payload(self : Decimal) -> @bigint.BigInt {
  self.inner.nan_payload()
}

///|
pub impl Show for Decimal with fn to_string(self) {
  self.inner.to_string()
}

///|
pub fn context(
  precision? : Int = 34,
  rounding? : GdaRoundingMode = GdaRoundingMode::HalfEven,
  e_min? : Int = -999_999_999,
  e_max? : Int = 999_999_999,
  clamp? : Bool = false,
  extended? : Bool = true,
) -> GdaContext {
  GdaContext::new(precision~, rounding~, e_min~, e_max~, clamp~, extended~)
}

///|
pub fn decimal32_context() -> GdaContext {
  GdaContext::decimal32()
}

///|
pub fn decimal64_context() -> GdaContext {
  GdaContext::decimal64()
}

///|
pub fn decimal128_context() -> GdaContext {
  GdaContext::decimal128()
}

///|
pub fn parse(source : String, ctx : GdaContext) -> GdaOutcome[Decimal] {
  let (value, flags) = @decimal.Decimal::from_string_ctx(source, ctx.inner)
  complete_decimal_gda(value, ctx, flags)
}

///|
pub fn add(
  lhs : Decimal,
  rhs : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  let (value, flags) = lhs.inner.add_ctx(rhs.inner, ctx.inner)
  complete_decimal_gda(value, ctx, flags)
}

///|
pub fn subtract(
  lhs : Decimal,
  rhs : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  let (value, flags) = lhs.inner.sub_ctx(rhs.inner, ctx.inner)
  complete_decimal_gda(value, ctx, flags)
}

///|
pub fn multiply(
  lhs : Decimal,
  rhs : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  let (value, flags) = lhs.inner.mul_ctx(rhs.inner, ctx.inner)
  complete_decimal_gda(value, ctx, flags)
}

///|
pub fn divide(
  lhs : Decimal,
  rhs : Decimal,
  ctx : GdaContext,
) -> GdaOutcome[Decimal] {
  let (value, flags) = lhs.inner.div_ctx(rhs.inner, ctx.inner)
  complete_decimal_gda(value, ctx, flags)
}
