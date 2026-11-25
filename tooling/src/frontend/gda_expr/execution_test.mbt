///|
// oracle: A
// source: rows written out: 1.20 + 2 = 3.20 (the finer exponent is kept), 3 * 4 = 12, compare 2 3 = -1, samequantum
//   1.0 2.0 = 1 (both exponents are -1); the rows were also run with CPython decimal (libmpdec 4.0.0) in this
//   review, with the same context and flags, and agree for add, multiply and compare
// shares: the decimal reader of the operands, the rounding and the scientific-notation printer of the interpreter (the
//   results are compared with the row as text), and the context it builds from the directives; all of them are
//   the code under test
test "gda interpreter executes decimal operations in process" {
  let source =
    #|precision: 9
    #|rounding: half_even
    #|a1 add 1.20 2 -> 3.20
    #|a2 multiply 3 4 -> 12
    #|a3 compare 2 3 -> -1
    #|a4 samequantum 1.0 2.0 -> 1
    #|
  let document = @gda_expr.parse_dectest("inline.decTest", source).unwrap()
  let summary = @gda_expr.execute_documents([document])
  assert_eq(summary.executable_cases(), 4)
  assert_eq(summary.passed_cases(), 4)
  assert_eq(summary.failed_cases(), 0)
}

///|
// oracle: A
// source: the four rows are sums written out (1+1=2, 2+2=4, 3+3=6, 4+4=8); the counts of two merged shards are
//   compared with those of the serial run of the same document, so the claim is about the partition and not
//   about arithmetic
// shares: the decimal reader of the operands, the rounding and the scientific-notation printer of the interpreter (the
//   results are compared with the row as text), and the context it builds from the directives; all of them are
//   the code under test
test "gda interpreter shards merge to serial totals" {
  let source =
    #|x1 add 1 1 -> 2
    #|x2 add 2 2 -> 4
    #|x3 add 3 3 -> 6
    #|x4 add 4 4 -> 8
    #|
  let document = @gda_expr.parse_dectest("shards.decTest", source).unwrap()
  let serial = @gda_expr.execute_documents([document])
  let left = @gda_expr.execute_documents(
    [document],
    options=@gda_expr.RunOptions::new(shard_count=2, shard_index=0),
  )
  let right = @gda_expr.execute_documents(
    [document],
    options=@gda_expr.RunOptions::new(shard_count=2, shard_index=1),
  )
  let merged = @gda_expr.RunSummary::merge([left, right])
  assert_eq(merged.selected_cases(), serial.selected_cases())
  assert_eq(merged.passed_cases(), serial.passed_cases())
  assert_eq(merged.failed_cases(), serial.failed_cases())
}

///|
// oracle: A
// source: decimal32 word #7C00016E is a quiet NaN whose low declet 0x16E is a non-canonical encoding of the digits
//   888: its canonical form is #7C00006E (declet 0x06E) and copy leaves the word unchanged; the declet pair was
//   decoded and re-encoded with tools/decimal_interchange_oracle.py (Python, not this library) in this review:
//   0x16E decodes to 888 and 888 encodes to 0x06E
// shares: the interchange word reader and writer of the interpreter (the code under test)
test "gda interpreter preserves raw interchange copy semantics" {
  let source =
    #|precision: 7
    #|maxExponent: 96
    #|minExponent: -95
    #|c1 canonical #7C00016E -> #7C00006E
    #|c2 copy #7C00016E -> #7C00016E
    #|
  let document = @gda_expr.parse_dectest("decimal32.decTest", source).unwrap()
  let summary = @gda_expr.execute_documents([document])
  assert_eq(summary.passed_cases(), 2)
  assert_eq(summary.failed_cases(), 0)
}

///|
// oracle: A
// source: GDA 1.70 quantize (page 36): the operation raises Invalid operation when the coefficient after quantizing
//   would be longer than precision; here 1.234 at exponent -999999000 would need 999999001 digits against
//   precision 15; the value is not checked ('?') and the flag is the row; CPython decimal gives
//   Invalid_operation for the same context
// shares: the decimal reader of the operands, the rounding and the scientific-notation printer of the interpreter (the
//   results are compared with the row as text), and the context it builds from the directives; all of them are
//   the code under test
test "gda interpreter rejects impossible extreme quantize before allocation" {
  let source =
    #|precision: 15
    #|maxExponent: 999999999
    #|minExponent: -999999999
    #|q1 quantize 1.234 1e-999999000 -> ? Invalid_operation
    #|
  let document = @gda_expr.parse_dectest("extreme.decTest", source).unwrap()
  let summary = @gda_expr.execute_documents([document])
  assert_eq(summary.passed_cases(), 1)
  assert_eq(summary.failed_cases(), 0)
}

///|
// oracle: A
// source: rows written out: 1.23 + 2.34 = 3.57 at 3 digits, 1.2345 + 2.3456 = 3.5801 at 5 digits, 1/3 = 0.33333
//   Inexact Rounded at 5 digits rounding floor; the rows were also run with CPython decimal (libmpdec 4.0.0) in
//   this review, with the same context and flags, and agree
// shares: the decimal reader of the operands, the rounding and the scientific-notation printer of the interpreter (the
//   results are compared with the row as text), and the context it builds from the directives; all of them are
//   the code under test
test "gda interpreter invalidates the context cache on directives" {
  let source =
    #|precision: 3
    #|rounding: half_even
    #|c1 add 1.23 2.34 -> 3.57
    #|precision: 5
    #|c2 add 1.2345 2.3456 -> 3.5801
    #|rounding: floor
    #|c3 divide 1 3 -> 0.33333 Inexact Rounded
    #|
  let document = @gda_expr.parse_dectest("contexts.decTest", source).unwrap()
  let summary = @gda_expr.execute_documents([document])
  assert_eq(summary.executable_cases(), 3)
  assert_eq(summary.passed_cases(), 3)
  assert_eq(summary.failed_cases(), 0)
}

///|
// oracle: A
// source: GDA 1.70 square-root (page 39, text extracted with pdftotext): an inexact result is rounded with round-half-
//   even whatever the context says; sqrt(6.25) = 2.5 needs 2 digits, so at precision 1 with rounding half_up the
//   result is 2 (not 3), Inexact Rounded
// shares: the decimal reader of the operands, the rounding and the scientific-notation printer of the interpreter (the
//   results are compared with the row as text), and the context it builds from the directives; all of them are
//   the code under test
test "gda interpreter applies the 1.70 sqrt rounding rule" {
  let source =
    #|precision: 1
    #|rounding: half_up
    #|s1 squareroot 6.25 -> 2 Inexact Rounded
    #|
  let document = @gda_expr.parse_dectest("sqrt-1.70.decTest", source).unwrap()
  let summary = @gda_expr.execute_documents([document])
  assert_eq(summary.executable_cases(), 1)
  assert_eq(summary.passed_cases(), 1)
  assert_eq(summary.failed_cases(), 0)
}

///|
// oracle: A
// source: GDA 1.70 context rules (page 9, text extracted with pdftotext): Emin and Emax have magnitudes that differ by
//   no more than one; precision 0 is not a context; the ranges 0..999999999 and -999999999..0 are the limits of
//   the decTest contexts; each invalid context of the block violates one of these and the valid one (precision
//   9, emax 999999999, emin -999999999) runs; the message texts are the interpreter's own wording written out,
//   not an external oracle
// shares: nothing (the verdicts and the texts are written out; the contexts are built by the interpreter under test)
test "gda interpreter reports an invalid context as a diagnostic row" {
  let assert_diagnostic = fn(source : String, expected : String) raise {
    let document = @gda_expr.parse_dectest("context.decTest", source).unwrap()
    let summary = @gda_expr.execute_documents([document])
    assert_eq(summary.diagnostic_cases(), 1)
    assert_eq(summary.executable_cases(), 0)
    let result = summary.results()[0]
    match result.disposition() {
      Diagnostic(message) => assert_eq(message, expected)
      _ => fail("expected an invalid-context diagnostic")
    }
  }

  let precision_zero =
    #|precision: 0
    #|z1 add 1 1 -> 2
    #|
  assert_diagnostic(precision_zero, "diagnostic invalid context: precision 0")
  let overlapping_invalid_bounds =
    #|precision: 9
    #|maxexponent: -5
    #|minexponent: 5
    #|z2 add 1 1 -> 2
    #|
  assert_diagnostic(
    overlapping_invalid_bounds, "diagnostic invalid context: minexponent outside -999999999..=0",
  )
  let max_out_of_range =
    #|precision: 9
    #|minexponent: -999999999
    #|maxexponent: 1000000000
    #|z3 add 1 1 -> 2
    #|
  assert_diagnostic(
    max_out_of_range, "diagnostic invalid context: maxexponent outside 0..=999999999",
  )
  let positive_min =
    #|precision: 9
    #|minexponent: 1
    #|maxexponent: 999999999
    #|z4 add 1 1 -> 2
    #|
  assert_diagnostic(
    positive_min, "diagnostic invalid context: minexponent outside -999999999..=0",
  )
  let negative_max =
    #|precision: 9
    #|minexponent: -999999999
    #|maxexponent: -1
    #|z5 add 1 1 -> 2
    #|
  assert_diagnostic(
    negative_max, "diagnostic invalid context: maxexponent outside 0..=999999999",
  )

  // GDA 1.70 page 10: the magnitudes of Emin and Emax differ by at most one.
  let unbalanced =
    #|precision: 9
    #|minexponent: 0
    #|maxexponent: 999999999
    #|z7 add 1 1 -> 2
    #|
  assert_diagnostic(
    unbalanced, "diagnostic invalid context: minexponent is not -maxexponent, 1 - maxexponent or -maxexponent - 1",
  )

  let valid_source =
    #|precision: 9
    #|minexponent: -999999999
    #|maxexponent: 999999999
    #|z6 add 1 1 -> 2
    #|
  let valid_document = @gda_expr.parse_dectest("context.decTest", valid_source).unwrap()
  let valid_summary = @gda_expr.execute_documents([valid_document])
  assert_eq(valid_summary.diagnostic_cases(), 0)
  assert_eq(valid_summary.executable_cases(), 1)
  assert_eq(valid_summary.passed_cases(), 1)
}

///|
// oracle: A
// source: rows written out: a 67 digit operand read exactly and rounded once to 9 digits gives 1.00000001E+66 Inexact
//   Rounded for add 0 and plus; the rows were also run with CPython decimal (libmpdec 4.0.0) in this review,
//   with the same context and flags, and agree
// shares: the decimal reader of the operands, the rounding and the scientific-notation printer of the interpreter (the
//   results are compared with the row as text), and the context it builds from the directives; all of them are
//   the code under test
test "gda interpreter reads long operands without rounding them" {
  let source =
    #|precision: 9
    #|rounding: half_even
    #|d1 add 1000000014999999999999999999999999999999999999999999999999999999995 0 -> 1.00000001E+66 Inexact Rounded
    #|d2 plus 1000000014999999999999999999999999999999999999999999999999999999995 -> 1.00000001E+66 Inexact Rounded
    #|
  let document = @gda_expr.parse_dectest("operands.decTest", source).unwrap()
  let summary = @gda_expr.execute_documents([document])
  assert_eq(summary.executable_cases(), 2)
  assert_eq(summary.passed_cases(), 2)
}
