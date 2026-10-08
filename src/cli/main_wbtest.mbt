///|
test "dispatcher rejects an empty backend value" {
  assert_eq(dispatch(["cli", "--backend="]), 2)
  assert_eq(dispatch(["cli", "--backend=", "--backend", "gda", "--help"]), 2)
}
