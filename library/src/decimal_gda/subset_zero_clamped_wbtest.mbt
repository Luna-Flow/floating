///|
/// Add and subtract of operands far below the range whose result is an exact zero
/// (`x - x`, `x + (-x)`) and of operands in and above the subnormal range. Oracle
/// (level A): decNumber 3.68 (https://speleotrove.com/decimal/decNumber-icu-368.zip,
/// sha256 14ec2cf30b58758493a7661b78b80abfb281652b61a425b85cda83173518fe25) built
/// with DECSUBSET=1 and run on each row (half-even); written out. In the subset an
/// exact zero is `0` with no flag (its exponent is 0, nothing is altered to fit the
/// range); the extended arithmetic keeps the clamped zero `0E-Etiny` with Clamped
/// when the operands are below Etiny, as decNumber does.
test "subset add and subtract of a pair whose result is an exact zero raise no Clamped" {
  let rows = [
    ("add", 9, -999, 999, false, "1E-1010", "1E-1010", "0", "xrsu."),
    ("add", 9, -999, 999, false, "1E-1010", "-1E-1010", "0", "....."),
    ("add", 9, -999, 999, false, "1E-1000", "1E-1000", "0", "xrsu."),
    ("add", 9, -999, 999, false, "5E-995", "5E-995", "1.0E-994", "....."),
    ("add", 9, -999, 999, false, "1E-120", "1E-120", "2E-120", "....."),
    ("add", 9, -999, 999, false, "1E-100", "-1E-100", "0", "....."),
    ("subtract", 9, -999, 999, false, "1E-1010", "1E-1010", "0", "....."),
    ("subtract", 9, -999, 999, false, "1E-1010", "-1E-1010", "0", "xrsu."),
    ("subtract", 9, -999, 999, false, "1E-1000", "1E-1000", "0", "....."),
    ("subtract", 9, -999, 999, false, "5E-995", "5E-995", "0", "....."),
    ("subtract", 9, -999, 999, false, "1E-120", "1E-120", "0", "....."),
    ("subtract", 9, -999, 999, false, "1E-100", "-1E-100", "2E-100", "....."),
    ("add", 5, -99, 99, false, "1E-1000", "1E-1000", "0", "xrsu."),
    ("add", 5, -99, 99, false, "5E-995", "5E-995", "0", "xrsu."),
    ("add", 5, -99, 99, false, "1E-120", "1E-120", "0", "xrsu."),
    ("add", 5, -99, 99, false, "1E-100", "-1E-100", "0", "....."),
    ("subtract", 5, -99, 99, false, "1E-1000", "1E-1000", "0", "....."),
    ("subtract", 5, -99, 99, false, "5E-995", "5E-995", "0", "....."),
    ("subtract", 5, -99, 99, false, "1E-120", "1E-120", "0", "....."),
    ("subtract", 5, -99, 99, false, "1E-100", "-1E-100", "0", "xrsu."),
    ("add", 9, -999, 999, true, "1E-1010", "1E-1010", "0E-1007", "xrsuc"),
    ("add", 9, -999, 999, true, "1E-1010", "-1E-1010", "0E-1007", "....c"),
    ("add", 9, -999, 999, true, "1E-1000", "1E-1000", "2E-1000", "..s.."),
    ("add", 9, -999, 999, true, "5E-995", "5E-995", "1.0E-994", "....."),
    ("add", 9, -999, 999, true, "1E-120", "1E-120", "2E-120", "....."),
    ("add", 9, -999, 999, true, "1E-100", "-1E-100", "0E-100", "....."),
    ("subtract", 9, -999, 999, true, "1E-1010", "1E-1010", "0E-1007", "....c"),
    ("subtract", 9, -999, 999, true, "1E-1010", "-1E-1010", "0E-1007", "xrsuc"),
    ("subtract", 9, -999, 999, true, "1E-1000", "1E-1000", "0E-1000", "....."),
    ("subtract", 9, -999, 999, true, "5E-995", "5E-995", "0E-995", "....."),
    ("subtract", 9, -999, 999, true, "1E-120", "1E-120", "0E-120", "....."),
    ("subtract", 9, -999, 999, true, "1E-100", "-1E-100", "2E-100", "....."),
    ("add", 5, -99, 99, true, "1E-1000", "1E-1000", "0E-103", "xrsuc"),
    ("add", 5, -99, 99, true, "5E-995", "5E-995", "0E-103", "xrsuc"),
    ("add", 5, -99, 99, true, "1E-120", "1E-120", "0E-103", "xrsuc"),
    ("add", 5, -99, 99, true, "1E-100", "-1E-100", "0E-100", "....."),
    ("subtract", 5, -99, 99, true, "1E-1000", "1E-1000", "0E-103", "....c"),
    ("subtract", 5, -99, 99, true, "5E-995", "5E-995", "0E-103", "....c"),
    ("subtract", 5, -99, 99, true, "1E-120", "1E-120", "0E-103", "....c"),
    ("subtract", 5, -99, 99, true, "1E-100", "-1E-100", "2E-100", "..s.."),
  ]
  for row in rows {
    let (
      op,
      precision,
      e_min,
      e_max,
      extended,
      a_text,
      b_text,
      expected,
      expected_flags,
    ) = row
    let context = GdaContext::new(precision~, e_min~, e_max~, extended~)
    let wide = GdaContext::new(
      precision=10,
      e_min=-999_999_999,
      e_max=999_999_999,
      extended~,
    )
    let a = to_number(a_text, wide).value()
    let b = to_number(b_text, wide).value()
    let outcome = if op == "add" {
      add(a, b, context)
    } else {
      subtract(a, b, context)
    }
    let raised = outcome.raised()
    let flags = (if raised.inexact() { "x" } else { "." }) +
      (if raised.rounded() { "r" } else { "." }) +
      (if raised.subnormal() { "s" } else { "." }) +
      (if raised.underflow() { "u" } else { "." }) +
      (if raised.clamped() { "c" } else { "." })
    let label = "\{op} p=\{precision} extended=\{extended} \{a_text} \{b_text}"
    assert_eq(
      (label, outcome.value().to_string(), flags),
      (label, expected, expected_flags),
    )
  }
}
