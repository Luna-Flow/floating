///|
pub struct DecimalExponentBounds {
  valid_ : Bool
  etiny_ : Int
  etop_ : Int
}

///|
pub fn DecimalExponentBounds::new(
  precision : Int,
  e_min : Int,
  e_max : Int,
) -> DecimalExponentBounds {
  let limit = 999_999_999
  let etiny = e_min.to_int64() - precision.to_int64() + 1L
  let etop = e_max.to_int64() - precision.to_int64() + 1L
  {
    valid_: precision > 0 &&
    precision <= limit &&
    e_min >= -limit &&
    e_min <= limit &&
    e_max >= -limit &&
    e_max <= limit &&
    e_min <= e_max,
    etiny_: decimal_int_from_int64_clamped(etiny),
    etop_: decimal_int_from_int64_clamped(etop),
  }
}

///|
fn decimal_int_from_int64_clamped(value : Int64) -> Int {
  if value < -2_147_483_648L {
    -2_147_483_648
  } else if value > 2_147_483_647L {
    2_147_483_647
  } else {
    value.to_int()
  }
}

///|
pub fn DecimalExponentBounds::is_valid(self : DecimalExponentBounds) -> Bool {
  self.valid_
}

///|
pub fn DecimalExponentBounds::etiny(self : DecimalExponentBounds) -> Int {
  self.etiny_
}

///|
pub fn DecimalExponentBounds::etop(self : DecimalExponentBounds) -> Int {
  self.etop_
}
