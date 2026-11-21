///|
/// `outer` contains `inner`.
fn split_test_contains(
  outer : (Binary, Binary),
  inner : (Binary, Binary),
) -> Bool {
  outer.0.compare(inner.0) <= 0 && inner.1.compare(outer.1) <= 0
}

///|
fn split_test_width(bounds : (Binary, Binary)) -> Binary {
  bounds.1.sub(bounds.0)
}

///|
test "split constants enclose the series enclosures at higher precision" {
  for work in [64, 65, 100, 128, 200, 256, 500, 1024] {
    let wide = work + 256
    assert_true(
      split_test_contains(
        binary_ln2_split_bounds(work),
        binary_ln2_series_compute(wide).unwrap(),
      ),
    )
    assert_true(
      split_test_contains(
        binary_ln10_split_bounds(work).unwrap(),
        binary_ln10_series_compute(wide).unwrap(),
      ),
    )
    assert_true(
      split_test_contains(
        binary_pi_split_bounds(work).unwrap(),
        binary_pi_series_compute(wide).unwrap(),
      ),
    )
  }
}

///|
test "split constants are no wider than the series enclosures" {
  for work in [64, 65, 100, 128, 200, 256, 500, 1024, 2048] {
    assert_true(
      split_test_width(binary_ln2_split_bounds(work)).compare(
        split_test_width(binary_ln2_series_compute(work).unwrap()),
      ) <=
      0,
    )
    assert_true(
      split_test_width(binary_ln10_split_bounds(work).unwrap()).compare(
        split_test_width(binary_ln10_series_compute(work).unwrap()),
      ) <=
      0,
    )
    assert_true(
      split_test_width(binary_pi_split_bounds(work).unwrap()).compare(
        split_test_width(binary_pi_series_compute(work).unwrap()),
      ) <=
      0,
    )
  }
}

///|
test "split constants nest across precisions" {
  // The enclosure at a higher precision lies inside the one at a lower
  // precision (both enclose the same number).
  for work in [64, 130, 777, 2048, 5000, 20000] {
    assert_true(
      split_test_contains(
        binary_ln2_split_bounds(work),
        binary_ln2_split_bounds(work + 300),
      ),
    )
    assert_true(
      split_test_contains(
        binary_ln10_split_bounds(work).unwrap(),
        binary_ln10_split_bounds(work + 300).unwrap(),
      ),
    )
    assert_true(
      split_test_contains(
        binary_pi_split_bounds(work).unwrap(),
        binary_pi_split_bounds(work + 300).unwrap(),
      ),
    )
  }
}

///|
test "dropping terms from the splitting breaks containment" {
  // A deliberately short series must be caught: the omitted terms exceed the
  // claimed tail, so the enclosure no longer contains the true value.
  let work = 512
  let wide = work + 256
  let reference_ln2 = binary_ln2_series_compute(wide).unwrap()
  let reference_ln10 = binary_ln10_series_compute(wide).unwrap()
  let reference_pi = binary_pi_series_compute(wide).unwrap()
  assert_false(
    split_test_contains(
      binary_ln2_split_bounds(work, reduce_terms=20),
      reference_ln2,
    ),
  )
  assert_false(
    split_test_contains(
      binary_ln10_split_bounds(work, reduce_terms=20).unwrap(),
      reference_ln10,
    ),
  )
  assert_false(
    split_test_contains(
      binary_pi_split_bounds(work, reduce_terms=8).unwrap(),
      reference_pi,
    ),
  )
}

///|
test "constants dispatch to the splitting from the threshold" {
  let below = binary_constants_split_min_precision - 1
  let at = binary_constants_split_min_precision
  assert_true(
    binary_constant_test_same(
      binary_pi_bounds_compute(below),
      binary_pi_series_compute(below),
    ),
  )
  assert_true(
    binary_constant_test_same(
      binary_pi_bounds_compute(at),
      binary_pi_split_bounds(at),
    ),
  )
  assert_true(
    binary_constant_test_same(
      binary_ln2_compute(at),
      Some(binary_ln2_split_bounds(at)),
    ),
  )
}
