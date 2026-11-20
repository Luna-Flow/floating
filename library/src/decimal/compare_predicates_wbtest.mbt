///|
/// IEEE 754-2019 5.11, Tables 5.1 (10 predicates) and 5.2 (12 predicates): every
/// predicate against every relation. The operand pairs cover less, equal (cohort
/// members, the two zeros, infinities), greater, unordered with a quiet NaN and
/// unordered with a signaling NaN. The letters are the true relations a predicate
/// lists in the table: L less, E equal, G greater, U unordered.
fn compare_operand_pairs() -> Array[(String, Decimal, Decimal, String, Bool)] {
  let d = fn(s : String) { Decimal::from_string(s).unwrap() }
  [
    ("less", d("1"), d("2"), "L", false),
    ("less, negative", d("-2"), d("-1"), "L", false),
    ("equal", d("1"), d("1.00"), "E", false),
    ("equal zeros", d("-0"), d("0"), "E", false),
    ("greater", d("2"), d("1"), "G", false),
    ("less, infinities", d("-Infinity"), d("Infinity"), "L", false),
    ("equal infinities", d("Infinity"), d("Infinity"), "E", false),
    ("quiet NaN left", Decimal::quiet_nan(), d("1"), "U", false),
    ("quiet NaN right", d("1"), Decimal::quiet_nan(), "U", false),
    ("quiet NaNs", Decimal::quiet_nan(), Decimal::quiet_nan(), "U", false),
    ("signaling NaN left", Decimal::signaling_nan(), d("1"), "U", true),
    ("signaling NaN right", d("1"), Decimal::signaling_nan(), "U", true),
    (
      "signaling and quiet NaN",
      Decimal::signaling_nan(),
      Decimal::quiet_nan(),
      "U",
      true,
    ),
  ]
}

///|
/// One row per predicate: its name as the standard writes it, the function, the
/// relations that make it true, whether it is a signaling predicate, and the
/// table that lists it.
fn compare_predicate_table() -> Array[
  (String, (Decimal, Decimal) -> (Bool, DecimalFlags), String, Bool, String),
] {
  [
    (
      "compareQuietEqual",
      fn(a, b) { a.compare_quiet_equal(b) },
      "E",
      false,
      "5.1",
    ),
    (
      "compareSignalingEqual",
      fn(a, b) { a.compare_signaling_equal(b) },
      "E",
      true,
      "5.2",
    ),
    (
      "compareQuietLess",
      fn(a, b) { a.compare_quiet_less(b) },
      "L",
      false,
      "5.2",
    ),
    (
      "compareSignalingLess",
      fn(a, b) { a.compare_signaling_less(b) },
      "L",
      true,
      "5.1",
    ),
    (
      "compareQuietLessEqual",
      fn(a, b) { a.compare_quiet_less_equal(b) },
      "LE",
      false,
      "5.2",
    ),
    (
      "compareSignalingLessEqual",
      fn(a, b) { a.compare_signaling_less_equal(b) },
      "LE",
      true,
      "5.1",
    ),
    (
      "compareQuietUnordered",
      fn(a, b) { a.compare_quiet_unordered(b) },
      "U",
      false,
      "5.2",
    ),
    (
      "compareQuietNotEqual",
      fn(a, b) { a.compare_quiet_not_equal(b) },
      "LGU",
      false,
      "5.1",
    ),
    (
      "compareQuietGreater",
      fn(a, b) { a.compare_quiet_greater(b) },
      "G",
      false,
      "5.2",
    ),
    (
      "compareQuietGreaterEqual",
      fn(a, b) { a.compare_quiet_greater_equal(b) },
      "EG",
      false,
      "5.2",
    ),
    (
      "compareQuietNotGreater",
      fn(a, b) { a.compare_quiet_not_greater(b) },
      "LEU",
      false,
      "5.2",
    ),
    (
      "compareQuietLessUnordered",
      fn(a, b) { a.compare_quiet_less_unordered(b) },
      "LU",
      false,
      "5.2",
    ),
    (
      "compareQuietNotLess",
      fn(a, b) { a.compare_quiet_not_less(b) },
      "EGU",
      false,
      "5.2",
    ),
    (
      "compareQuietGreaterUnordered",
      fn(a, b) { a.compare_quiet_greater_unordered(b) },
      "GU",
      false,
      "5.2",
    ),
    (
      "compareQuietOrdered",
      fn(a, b) { a.compare_quiet_ordered(b) },
      "LEG",
      false,
      "5.2",
    ),
    (
      "compareSignalingNotEqual",
      fn(a, b) { a.compare_signaling_not_equal(b) },
      "LGU",
      true,
      "5.2",
    ),
    (
      "compareSignalingGreater",
      fn(a, b) { a.compare_signaling_greater(b) },
      "G",
      true,
      "5.1",
    ),
    (
      "compareSignalingGreaterEqual",
      fn(a, b) { a.compare_signaling_greater_equal(b) },
      "EG",
      true,
      "5.1",
    ),
    (
      "compareSignalingNotGreater",
      fn(a, b) { a.compare_signaling_not_greater(b) },
      "LEU",
      true,
      "5.1",
    ),
    (
      "compareSignalingLessUnordered",
      fn(a, b) { a.compare_signaling_less_unordered(b) },
      "LU",
      true,
      "5.1",
    ),
    (
      "compareSignalingNotLess",
      fn(a, b) { a.compare_signaling_not_less(b) },
      "EGU",
      true,
      "5.1",
    ),
    (
      "compareSignalingGreaterUnordered",
      fn(a, b) { a.compare_signaling_greater_unordered(b) },
      "GU",
      true,
      "5.1",
    ),
  ]
}

///|
/// The value is true exactly when the relation is among the true relations of
/// the table, and invalid is raised on a signaling NaN by every predicate and on a
/// quiet NaN by the signaling predicates only; no other flag is ever raised.
test "decimal comparison predicates: value and flag for every relation" {
  assert_eq(compare_predicate_table().length(), 22)
  for pair in compare_operand_pairs() {
    let (label, a, b, relation, signaling_nan) = pair
    let (quiet_relation, quiet_flags) = a.compare_quiet(b)
    let (signaling_relation, signaling_flags) = a.compare_signaling(b)
    assert_true(quiet_relation == signaling_relation, msg=label)
    assert_eq(
      quiet_flags.invalid_operation(),
      signaling_nan,
      msg=label + " quiet",
    )
    assert_eq(
      signaling_flags.invalid_operation(),
      relation == "U",
      msg=label + " signaling",
    )
    for row in compare_predicate_table() {
      let (name, predicate, true_relations, signaling, _) = row
      let (value, flags) = predicate(a, b)
      assert_eq(
        value,
        true_relations.contains(relation),
        msg=name + " " + label,
      )
      let expected_invalid = signaling_nan || (signaling && relation == "U")
      assert_eq(
        flags.invalid_operation(),
        expected_invalid,
        msg=name + " " + label + " flag",
      )
      assert_false(
        flags.inexact() ||
        flags.overflow() ||
        flags.underflow() ||
        flags.division_by_zero(),
        msg=name + " " + label + " other flags",
      )
    }
  }
}

///|
/// The negation pairs the standard states: the value is the complement and the
/// flags are the same, on every relation.
test "decimal comparison predicates: the negation pairs are complements" {
  let pairs = [
    ("compareQuietEqual", "compareQuietNotEqual"),
    ("compareSignalingGreater", "compareSignalingNotGreater"),
    ("compareSignalingGreaterEqual", "compareSignalingLessUnordered"),
    ("compareSignalingLess", "compareSignalingNotLess"),
    ("compareSignalingLessEqual", "compareSignalingGreaterUnordered"),
    ("compareSignalingEqual", "compareSignalingNotEqual"),
    ("compareQuietGreater", "compareQuietNotGreater"),
    ("compareQuietGreaterEqual", "compareQuietLessUnordered"),
    ("compareQuietLess", "compareQuietNotLess"),
    ("compareQuietLessEqual", "compareQuietGreaterUnordered"),
    ("compareQuietUnordered", "compareQuietOrdered"),
  ]
  for pair in compare_operand_pairs() {
    let (label, a, b, _, _) = pair
    for names in pairs {
      let (positive, negative) = names
      let mut found = 0
      for row in compare_predicate_table() {
        if row.0 == positive || row.0 == negative {
          found += 1
        }
      }
      assert_eq(found, 2)
      let mut p : (Bool, DecimalFlags) = (false, DecimalFlags::new())
      let mut n : (Bool, DecimalFlags) = (false, DecimalFlags::new())
      for row in compare_predicate_table() {
        if row.0 == positive {
          p = (row.1)(a, b)
        }
        if row.0 == negative {
          n = (row.1)(a, b)
        }
      }
      assert_eq(p.0, !n.0, msg=positive + " " + label)
      assert_true(p.1 == n.1, msg=positive + " flags " + label)
    }
  }
  // Table 5.1 has 10 predicates and Table 5.2 has 12.
  let mut t51 = 0
  let mut t52 = 0
  for row in compare_predicate_table() {
    if row.4 == "5.1" {
      t51 += 1
    } else {
      t52 += 1
    }
  }
  assert_eq(t51, 10)
  assert_eq(t52, 12)
}
