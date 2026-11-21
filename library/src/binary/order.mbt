///|
/// IEEE 754 copySign: `self` with the sign bit of `sign_source`. Quiet for
/// every operand, including NaNs, whose payload is kept.
pub fn Binary::copy_sign(self : Binary, sign_source : Binary) -> Binary {
  self.with_negative(sign_source.negative())
}

///|
/// Rank of the non-finite and finite classes for one sign in the total order:
/// finite (including zero) < infinity < signaling NaN < quiet NaN.
fn binary_total_order_rank(value : Binary) -> Int32 {
  match value.class() {
    FpClass::Finite => 0
    FpClass::Infinity => 1
    FpClass::NaN => if value.signaling() { 2 } else { 3 }
  }
}

///|
/// Magnitude comparison in the total order for operands of the same sign.
fn binary_total_order_magnitude(left : Binary, right : Binary) -> Int32 {
  let rank = binary_total_order_rank(left) - binary_total_order_rank(right)
  if rank != 0 {
    return if rank < 0 { -1 } else { 1 }
  }
  match left.class() {
    FpClass::Finite => binary_compare_magnitude(left, right)
    FpClass::Infinity => 0
    FpClass::NaN => left.payload_().compare(right.payload_())
  }
}

///|
/// -1, 0, or 1 as `self` precedes, equals, or follows `other` in the IEEE 754
/// totalOrder: -qNaN < -sNaN < -inf < negative finites < -0 < +0 < positive
/// finites < +inf < +sNaN < +qNaN, with NaNs of one kind ordered by payload.
pub fn Binary::total_order_compare(self : Binary, other : Binary) -> Int32 {
  if self.negative() != other.negative() {
    return if self.negative() { -1 } else { 1 }
  }
  let magnitude = binary_total_order_magnitude(self, other)
  if self.negative() {
    -magnitude
  } else {
    magnitude
  }
}

///|
/// IEEE 754 totalOrder(self, other): whether `self` does not follow `other`.
pub fn Binary::total_order(self : Binary, other : Binary) -> Bool {
  self.total_order_compare(other) <= 0
}

///|
/// IEEE 754 totalOrderMag: totalOrder of the absolute values.
pub fn Binary::total_order_mag(self : Binary, other : Binary) -> Bool {
  binary_total_order_magnitude(self, other) <= 0
}

///|
fn binary_compare_relation(left : Binary, right : Binary) -> @def.PartialOrder {
  if left.class() == FpClass::NaN || right.class() == FpClass::NaN {
    return @def.PartialOrder::Unordered
  }
  let comparison = left.compare(right)
  if comparison < 0 {
    @def.PartialOrder::Less
  } else if comparison > 0 {
    @def.PartialOrder::Greater
  } else {
    @def.PartialOrder::Equal
  }
}

///|
/// IEEE 754 quiet comparison: the relation of `self` to `other`, where
/// `-0 == +0` and NaN is unordered. Only a signaling NaN raises invalid.
pub fn Binary::compare_quiet(
  self : Binary,
  other : Binary,
) -> (@def.PartialOrder, BinaryFlags) {
  (
    binary_compare_relation(self, other),
    if self.is_signaling_nan() || other.is_signaling_nan() {
      binary_invalid_flags()
    } else {
      BinaryFlags::new()
    },
  )
}

///|
/// IEEE 754 signaling comparison: as `compare_quiet`, but any NaN operand
/// raises invalid.
pub fn Binary::compare_signaling(
  self : Binary,
  other : Binary,
) -> (@def.PartialOrder, BinaryFlags) {
  let relation = binary_compare_relation(self, other)
  (
    relation,
    if relation == @def.PartialOrder::Unordered {
      binary_invalid_flags()
    } else {
      BinaryFlags::new()
    },
  )
}

///|
/// compareQuietEqual.
pub fn Binary::compare_quiet_equal(
  self : Binary,
  other : Binary,
) -> (Bool, BinaryFlags) {
  let (relation, flags) = self.compare_quiet(other)
  (relation == @def.PartialOrder::Equal, flags)
}

///|
/// compareSignalingEqual.
pub fn Binary::compare_signaling_equal(
  self : Binary,
  other : Binary,
) -> (Bool, BinaryFlags) {
  let (relation, flags) = self.compare_signaling(other)
  (relation == @def.PartialOrder::Equal, flags)
}

///|
/// compareQuietLess.
pub fn Binary::compare_quiet_less(
  self : Binary,
  other : Binary,
) -> (Bool, BinaryFlags) {
  let (relation, flags) = self.compare_quiet(other)
  (relation == @def.PartialOrder::Less, flags)
}

///|
/// compareSignalingLess.
pub fn Binary::compare_signaling_less(
  self : Binary,
  other : Binary,
) -> (Bool, BinaryFlags) {
  let (relation, flags) = self.compare_signaling(other)
  (relation == @def.PartialOrder::Less, flags)
}

///|
/// compareQuietLessEqual.
pub fn Binary::compare_quiet_less_equal(
  self : Binary,
  other : Binary,
) -> (Bool, BinaryFlags) {
  let (relation, flags) = self.compare_quiet(other)
  (
    relation == @def.PartialOrder::Less || relation == @def.PartialOrder::Equal,
    flags,
  )
}

///|
/// compareSignalingLessEqual.
pub fn Binary::compare_signaling_less_equal(
  self : Binary,
  other : Binary,
) -> (Bool, BinaryFlags) {
  let (relation, flags) = self.compare_signaling(other)
  (
    relation == @def.PartialOrder::Less || relation == @def.PartialOrder::Equal,
    flags,
  )
}

///|
/// compareQuietUnordered.
pub fn Binary::compare_quiet_unordered(
  self : Binary,
  other : Binary,
) -> (Bool, BinaryFlags) {
  let (relation, flags) = self.compare_quiet(other)
  (relation == @def.PartialOrder::Unordered, flags)
}
