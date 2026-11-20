// Accessors of the private engine context that only the white-box tests use.

///|
fn DecimalContext::precision(self : DecimalContext) -> Int32 {
  self.precision
}

///|
fn DecimalContext::rounding(self : DecimalContext) -> RoundingMode {
  self.rounding
}

///|
fn DecimalContext::e_max(self : DecimalContext) -> Int32 {
  self.e_max
}

///|
fn DecimalContext::clamp(self : DecimalContext) -> Bool {
  self.clamp
}

///|
fn DecimalContext::exact() -> DecimalContext {
  decimal_exact_work_context()
}

///|
impl Eq for DecimalContext with fn equal(a, b) {
  a.precision == b.precision &&
  a.rounding == b.rounding &&
  a.decimal_rounding == b.decimal_rounding &&
  a.e_min == b.e_min &&
  a.e_max == b.e_max &&
  a.clamp == b.clamp &&
  a.extended == b.extended &&
  a.refinement_limit == b.refinement_limit
}

///|
/// A `GdaContext` whose exponent range is not checked against GDA 1.70 page 10.
/// The regression tests of #264 to #405 keep the oracle rows (libmpdec) that
/// were found under such ranges and compare the engine with the public
/// functions on them; `GdaContext::new` rejects these ranges. They are to move
/// to legal ranges with recomputed oracle rows (issue 438, item 6).
fn gda_context_unchecked(
  precision~ : Int32 = 34,
  rounding~ : GdaRoundingMode = GdaRoundingMode::HalfEven,
  e_min~ : Int32 = -999_999_999,
  e_max~ : Int32 = 999_999_999,
  clamp~ : Bool = false,
  extended~ : Bool = true,
) -> GdaContext {
  let decimal_ = gda_build_decimal_context(
    precision, rounding, e_min, e_max, clamp, extended,
  )
  {
    precision_: precision,
    rounding_: rounding,
    e_min_: e_min,
    e_max_: e_max,
    clamp_: clamp,
    extended_: extended,
    status_: GdaFlags::new(),
    traps_: GdaTrapSet::new(),
    decimal_,
    mathematical_: {
      ..decimal_,
      rounding: @lf_arith.RoundingMode::ToNearestEven,
      decimal_rounding: DecimalRoundingMode::HalfEven,
    },
  }
}

///|
fn normalize_decimal_parts_gda(
  negative : Bool,
  magnitude : BigInt,
  exponent10 : Int32,
  precision : Int32,
  mode : DecimalRoundingMode,
) -> Decimal {
  normalize_decimal_parts_gda_repr(
    negative,
    coeff_from_bigint(abs_bigint(magnitude)),
    exponent10,
    precision,
    mode,
  )
}

///|
/// (tests only) The IEEE 754-2019 attribute of an `@arithmetic` mode for a value of the
/// given sign (`AwayFromZero` is the direction of the sign).
fn bin_mode(
  mode : @def.RoundingMode,
  negative : Bool,
) -> @bin_float.BinaryRoundingMode {
  match mode {
    @def.RoundingMode::ToNearestEven =>
      @bin_float.BinaryRoundingMode::RoundTiesToEven
    @def.RoundingMode::TowardZero =>
      @bin_float.BinaryRoundingMode::RoundTowardZero
    @def.RoundingMode::TowardPositive =>
      @bin_float.BinaryRoundingMode::RoundTowardPositive
    @def.RoundingMode::TowardNegative =>
      @bin_float.BinaryRoundingMode::RoundTowardNegative
    @def.RoundingMode::AwayFromZero =>
      if negative {
        @bin_float.BinaryRoundingMode::RoundTowardNegative
      } else {
        @bin_float.BinaryRoundingMode::RoundTowardPositive
      }
  }
}

///|
/// A finite value beyond the stored range (`gda_implementation_e_tiny`,
/// `gda_implementation_e_max`), which no public constructor can make. The
/// engine tests that pin the exponent arithmetic against `Int` overflow still
/// need such operands, so the value is built from its parts.
fn decimal_unchecked(
  negative : Bool,
  coefficient : BigInt,
  exponent10 : Int32,
  precision : Int32,
) -> Decimal {
  finite_with_exponent_repr(
    negative,
    coeff_from_bigint(coefficient),
    exponent10,
    precision,
  )
}

///|
/// `decimal_unchecked` of a finite numeral of at most `precision` digits.
fn decimal_text_unchecked(text : String, precision~ : Int32 = 34) -> Decimal {
  match split_decimal_string_wide(text) {
    Some((negative, digits, exponent10)) => {
      let significant = strip_leading_zero_digits(digits)
      let coefficient = if significant.length() == 0 {
        dec_coeff_zero()
      } else {
        dec_coeff_from_decimal_digits_repr(significant).unwrap()
      }
      finite_with_exponent_repr(
        negative,
        coefficient,
        exponent10.to_int(),
        precision,
      )
    }
    None => abort("decimal_text_unchecked: not a numeral: " + text)
  }
}
