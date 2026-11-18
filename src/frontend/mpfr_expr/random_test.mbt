///|
test "MPFR random rows compare value and flags under a bounded context" {
  let source =
    #|# mpfr-random-v1
    #|t.1 add n 24 -126 127 a 0x1p0 0x1p-30 - 0 0x1p0 x
    #|t.2 add z 24 -126 127 a 0x1p0 0x1p-30 - 0 0x1p0 x
    #|t.3 add u 24 -126 127 a 0x1p0 0x1p-30 - 0 0x800001p-23 x
    #|t.4 mul n 24 -126 127 a 0x1p-100 0x1p-100 - 0 0x0p0 xu
    #|t.5 mul z 24 -126 127 a 0x1p100 0x1p100 - 0 0xffffffp104 xo
    #|t.6 div n 53 - - - 0x1p0 0x0p0 - 0 inf z
    #|t.7 sqrt n 53 - - - -0x1p0 - - 0 nan v
    #|t.8 fma n 53 - - - 0x3p0 0x5p0 0x7p0 0 0x16p0 -
    #|t.9 strtofr na 11 - - - 2049 - - 0 0x401p1 x
    #|t.10 getstr n 53 - - - 0x5p-1 - - 1 2e0 x
    #|t.11 shortest n 53 - - - 0x1999999999999ap-56 - - 0 1 -
    #|t.12 sin n 24 - - - 0x0p0 - - 0 0x0p0 -
  let document = @mpfr_expr.parse_random_data("inline.random", source).unwrap()
  assert_eq(document.case_count(), 12)
  assert_eq(document.case_ids()[0], "t.1")
  let summary = @mpfr_expr.execute_random_data(document)
  for result in summary.results() {
    assert_true(result.passed(), msg=result.id() + ": " + result.message())
  }
  assert_eq(summary.passed_cases(), 12)
}

///|
test "MPFR random executor reports a flag or value difference" {
  let source =
    #|t.1 add n 24 -126 127 a 0x1p0 0x1p-30 - 0 0x1p0 -
    #|t.2 add n 24 -126 127 a 0x1p0 0x1p-30 - 0 0x2p0 x
    #|t.3 mul n 24 -126 127 b 0x1p-100 0x1p-100 - 0 0x0p0 x
  let summary = @mpfr_expr.execute_random_data(
    @mpfr_expr.parse_random_data("diff", source).unwrap(),
  )
  assert_eq(summary.results().map(result => result.passed()), [
    false, false, false,
  ])
}

///|
test "MPFR random parser rejects malformed rows" {
  for
    row in [
      "t add n 24 - - - 0x1p0 0x1p0 - 0 0x2p0", "t nope n 24 - - - 0x1p0 - - 0 0x1p0 -",
      "t add q 24 - - - 0x1p0 0x1p0 - 0 0x2p0 -", "t add n 24 -126 127 x 0x1p0 0x1p0 - 0 0x2p0 -",
      "t add n 24 - - - 0x1p0 0x1p0 - 0 0x2p0 q", "t add n 24 - - - 0xzp0 0x1p0 - 0 0x2p0 -",
    ] {
    match @mpfr_expr.parse_random_data("bad", row) {
      Err([_]) => ()
      _ => fail("expected one diagnostic for " + row)
    }
  }
}
