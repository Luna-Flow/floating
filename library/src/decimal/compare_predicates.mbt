///|
// The comparison predicates of IEEE 754-2019 5.11 that Tables 5.1 and 5.2 list
// beyond the first seven (`compare_quiet_equal` and its siblings in `order`).
// Each is `compare_quiet` or `compare_signaling` seen through the relations
// that make it true; the quiet predicates raise invalid for a signaling NaN
// only, the signaling predicates for every NaN operand.

///|
/// compareQuietNotEqual (IEEE 754-2019 Table 5.1): true when the relation is less than, greater than, unordered.
pub fn Decimal::compare_quiet_not_equal(
  self : Decimal,
  other : Decimal,
) -> (Bool, DecimalFlags) {
  let (relation, flags) = self.compare_quiet(other)
  (
    match relation {
      Less | Greater | Unordered => true
      _ => false
    },
    flags,
  )
}

///|
/// compareQuietGreater (IEEE 754-2019 Table 5.2): true when the relation is greater than.
pub fn Decimal::compare_quiet_greater(
  self : Decimal,
  other : Decimal,
) -> (Bool, DecimalFlags) {
  let (relation, flags) = self.compare_quiet(other)
  (
    match relation {
      Greater => true
      _ => false
    },
    flags,
  )
}

///|
/// compareQuietGreaterEqual (IEEE 754-2019 Table 5.2): true when the relation is equal, greater than.
pub fn Decimal::compare_quiet_greater_equal(
  self : Decimal,
  other : Decimal,
) -> (Bool, DecimalFlags) {
  let (relation, flags) = self.compare_quiet(other)
  (
    match relation {
      Equal | Greater => true
      _ => false
    },
    flags,
  )
}

///|
/// compareQuietNotGreater (IEEE 754-2019 Table 5.2): true when the relation is less than, equal, unordered.
pub fn Decimal::compare_quiet_not_greater(
  self : Decimal,
  other : Decimal,
) -> (Bool, DecimalFlags) {
  let (relation, flags) = self.compare_quiet(other)
  (
    match relation {
      Less | Equal | Unordered => true
      _ => false
    },
    flags,
  )
}

///|
/// compareQuietLessUnordered (IEEE 754-2019 Table 5.2): true when the relation is less than, unordered.
pub fn Decimal::compare_quiet_less_unordered(
  self : Decimal,
  other : Decimal,
) -> (Bool, DecimalFlags) {
  let (relation, flags) = self.compare_quiet(other)
  (
    match relation {
      Less | Unordered => true
      _ => false
    },
    flags,
  )
}

///|
/// compareQuietNotLess (IEEE 754-2019 Table 5.2): true when the relation is equal, greater than, unordered.
pub fn Decimal::compare_quiet_not_less(
  self : Decimal,
  other : Decimal,
) -> (Bool, DecimalFlags) {
  let (relation, flags) = self.compare_quiet(other)
  (
    match relation {
      Equal | Greater | Unordered => true
      _ => false
    },
    flags,
  )
}

///|
/// compareQuietGreaterUnordered (IEEE 754-2019 Table 5.2): true when the relation is greater than, unordered.
pub fn Decimal::compare_quiet_greater_unordered(
  self : Decimal,
  other : Decimal,
) -> (Bool, DecimalFlags) {
  let (relation, flags) = self.compare_quiet(other)
  (
    match relation {
      Greater | Unordered => true
      _ => false
    },
    flags,
  )
}

///|
/// compareQuietOrdered (IEEE 754-2019 Table 5.2): true when the relation is less than, equal, greater than.
pub fn Decimal::compare_quiet_ordered(
  self : Decimal,
  other : Decimal,
) -> (Bool, DecimalFlags) {
  let (relation, flags) = self.compare_quiet(other)
  (
    match relation {
      Less | Equal | Greater => true
      _ => false
    },
    flags,
  )
}

///|
/// compareSignalingNotEqual (IEEE 754-2019 Table 5.2): true when the relation is less than, greater than, unordered.
pub fn Decimal::compare_signaling_not_equal(
  self : Decimal,
  other : Decimal,
) -> (Bool, DecimalFlags) {
  let (relation, flags) = self.compare_signaling(other)
  (
    match relation {
      Less | Greater | Unordered => true
      _ => false
    },
    flags,
  )
}

///|
/// compareSignalingGreater (IEEE 754-2019 Table 5.1): true when the relation is greater than.
pub fn Decimal::compare_signaling_greater(
  self : Decimal,
  other : Decimal,
) -> (Bool, DecimalFlags) {
  let (relation, flags) = self.compare_signaling(other)
  (
    match relation {
      Greater => true
      _ => false
    },
    flags,
  )
}

///|
/// compareSignalingGreaterEqual (IEEE 754-2019 Table 5.1): true when the relation is equal, greater than.
pub fn Decimal::compare_signaling_greater_equal(
  self : Decimal,
  other : Decimal,
) -> (Bool, DecimalFlags) {
  let (relation, flags) = self.compare_signaling(other)
  (
    match relation {
      Equal | Greater => true
      _ => false
    },
    flags,
  )
}

///|
/// compareSignalingNotGreater (IEEE 754-2019 Table 5.1): true when the relation is less than, equal, unordered.
pub fn Decimal::compare_signaling_not_greater(
  self : Decimal,
  other : Decimal,
) -> (Bool, DecimalFlags) {
  let (relation, flags) = self.compare_signaling(other)
  (
    match relation {
      Less | Equal | Unordered => true
      _ => false
    },
    flags,
  )
}

///|
/// compareSignalingLessUnordered (IEEE 754-2019 Table 5.1): true when the relation is less than, unordered.
pub fn Decimal::compare_signaling_less_unordered(
  self : Decimal,
  other : Decimal,
) -> (Bool, DecimalFlags) {
  let (relation, flags) = self.compare_signaling(other)
  (
    match relation {
      Less | Unordered => true
      _ => false
    },
    flags,
  )
}

///|
/// compareSignalingNotLess (IEEE 754-2019 Table 5.1): true when the relation is equal, greater than, unordered.
pub fn Decimal::compare_signaling_not_less(
  self : Decimal,
  other : Decimal,
) -> (Bool, DecimalFlags) {
  let (relation, flags) = self.compare_signaling(other)
  (
    match relation {
      Equal | Greater | Unordered => true
      _ => false
    },
    flags,
  )
}

///|
/// compareSignalingGreaterUnordered (IEEE 754-2019 Table 5.1): true when the relation is greater than, unordered.
pub fn Decimal::compare_signaling_greater_unordered(
  self : Decimal,
  other : Decimal,
) -> (Bool, DecimalFlags) {
  let (relation, flags) = self.compare_signaling(other)
  (
    match relation {
      Greater | Unordered => true
      _ => false
    },
    flags,
  )
}
