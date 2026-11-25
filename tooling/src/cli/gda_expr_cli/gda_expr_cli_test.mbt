///|
// oracle: A
// source: exit status 2 (usage error) written out: moon.mod is a file of the module directory and does not end in
//   .decTest
// shares: nothing
test "gda runner rejects a named file without the .decTest suffix" {
  assert_eq(@gda_expr_cli.run(["gda", "moon.mod"]), 2)
}
