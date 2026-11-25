///|
// oracle: A
// source: exit status 2 (usage error) written out for the two argument lists that carry an empty --backend= value, the
//   second one before otherwise valid options and --help
// shares: nothing
test "dispatcher rejects an empty backend value" {
  assert_eq(dispatch(["cli", "--backend="]), 2)
  assert_eq(dispatch(["cli", "--backend=", "--backend", "gda", "--help"]), 2)
}
