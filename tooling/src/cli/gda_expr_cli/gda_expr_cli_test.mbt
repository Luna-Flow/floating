///|
test "gda runner rejects a named file without the .decTest suffix" {
  assert_eq(@gda_expr_cli.run(["gda", "moon.mod"]), 2)
}
