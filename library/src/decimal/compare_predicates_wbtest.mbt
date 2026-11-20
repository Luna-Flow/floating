///|
/// The operand pairs of the five relations of IEEE 754-2019 5.11: less, equal
/// (two cohort members, and the two zeros), greater, unordered with a quiet NaN
/// and unordered with a signaling NaN. The letters are the true relations a
/// predicate lists in Tables 5.1 and 5.2: L less, E equal, G greater, U unordered.
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
/// relations that make it true, and whether it is a signaling predicate.
fn compare_predicate_table() -> Array[
  (String, (Decimal, Decimal) -> (Bool, DecimalFlags), String, Bool),
] {
  [
    ("compareQuietEqual", fn(a, b) { a.compare_quiet_equal(b) }, "E", false),
    (
      "compareSignalingEqual",
      fn(a, b) { a.compare_signaling_equal(b) },
      "E",
      true,
    ),
    ("compareQuietLess", fn(a, b) { a.compare_quiet_less(b) }, "L", false),
    (
      "compareSignalingLess",
      fn(a, b) { a.compare_signaling_less(b) },
      "L",
      true,
    ),
    (
      "compareQuietLessEqual",
      fn(a, b) { a.compare_quiet_less_equal(b) },
      "LE",
      false,
    ),
    (
      "compareSignalingLessEqual",
      fn(a, b) { a.compare_signaling_less_equal(b) },
      "LE",
      true,
    ),
    (
      "compareQuietUnordered",
      fn(a, b) { a.compare_quiet_unordered(b) },
      "U",
      false,
    ),
  ]
}

///|
/// Every predicate against every relation: the value is true exactly when the
/// relation is among its true relations, and invalid is raised on a signaling
/// NaN by every predicate and on a quiet NaN by the signaling predicates only.
test "decimal comparison predicates: value and flag for every relation" {
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
      let (name, predicate, true_relations, signaling) = row
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
