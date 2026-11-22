///|
/// A literal that underflows far below the range of the context. Oracle (level A):
/// decNumber 3.68 (https://speleotrove.com/decimal/decNumber-icu-368.zip, sha256
/// 14ec2cf30b58758493a7661b78b80abfb281652b61a425b85cda83173518fe25) built with
/// DECSUBSET=1 and run on each row (`tosci`, precision 13, Emax 999999999, Emin
/// -999999999, no clamp); written out: in the subset the result is `0` (sign and
/// exponent 0, GDA 1.70 Appendix A, page 55) in every rounding mode with
/// Inexact, Rounded, Subnormal and Underflow and no Clamped; with the extended
/// arithmetic it is the subnormal member at Etiny (-1000000011), `0E-1000000011`
/// with Clamped or `1E-1000000011` for the modes that round away.
// oracle: A
// source: decNumber 3.68 built with DECSUBSET=1 for the 20 subset rows (sha256 in docstring); 20 extended rows
//   re-run in CPython, 0 disagree
// shares: Decimal::to_string (printing the result)
test "to_number of a literal far below the range: the subset gives 0, the extended arithmetic Etiny" {
  let rows = [
    (true, "half_even", "1e-1000000014", "0", "xrsu."),
    (true, "half_even", "-1e-12345678903", "0", "xrsu."),
    (true, "half_even", "5e-1000000020", "0", "xrsu."),
    (true, "half_even", "123456789e-1000000030", "0", "xrsu."),
    (true, "up", "1e-1000000014", "0", "xrsu."),
    (true, "up", "-1e-12345678903", "0", "xrsu."),
    (true, "up", "5e-1000000020", "0", "xrsu."),
    (true, "up", "123456789e-1000000030", "0", "xrsu."),
    (true, "floor", "1e-1000000014", "0", "xrsu."),
    (true, "floor", "-1e-12345678903", "0", "xrsu."),
    (true, "floor", "5e-1000000020", "0", "xrsu."),
    (true, "floor", "123456789e-1000000030", "0", "xrsu."),
    (true, "ceiling", "1e-1000000014", "0", "xrsu."),
    (true, "ceiling", "-1e-12345678903", "0", "xrsu."),
    (true, "ceiling", "5e-1000000020", "0", "xrsu."),
    (true, "ceiling", "123456789e-1000000030", "0", "xrsu."),
    (true, "down", "1e-1000000014", "0", "xrsu."),
    (true, "down", "-1e-12345678903", "0", "xrsu."),
    (true, "down", "5e-1000000020", "0", "xrsu."),
    (true, "down", "123456789e-1000000030", "0", "xrsu."),
    (false, "half_even", "1e-1000000014", "0E-1000000011", "xrsuc"),
    (false, "half_even", "-1e-12345678903", "-0E-1000000011", "xrsuc"),
    (false, "half_even", "5e-1000000020", "0E-1000000011", "xrsuc"),
    (false, "half_even", "123456789e-1000000030", "0E-1000000011", "xrsuc"),
    (false, "up", "1e-1000000014", "1E-1000000011", "xrsu."),
    (false, "up", "-1e-12345678903", "-1E-1000000011", "xrsu."),
    (false, "up", "5e-1000000020", "1E-1000000011", "xrsu."),
    (false, "up", "123456789e-1000000030", "1E-1000000011", "xrsu."),
    (false, "floor", "1e-1000000014", "0E-1000000011", "xrsuc"),
    (false, "floor", "-1e-12345678903", "-1E-1000000011", "xrsu."),
    (false, "floor", "5e-1000000020", "0E-1000000011", "xrsuc"),
    (false, "floor", "123456789e-1000000030", "0E-1000000011", "xrsuc"),
    (false, "ceiling", "1e-1000000014", "1E-1000000011", "xrsu."),
    (false, "ceiling", "-1e-12345678903", "-0E-1000000011", "xrsuc"),
    (false, "ceiling", "5e-1000000020", "1E-1000000011", "xrsu."),
    (false, "ceiling", "123456789e-1000000030", "1E-1000000011", "xrsu."),
    (false, "down", "1e-1000000014", "0E-1000000011", "xrsuc"),
    (false, "down", "-1e-12345678903", "-0E-1000000011", "xrsuc"),
    (false, "down", "5e-1000000020", "0E-1000000011", "xrsuc"),
    (false, "down", "123456789e-1000000030", "0E-1000000011", "xrsuc"),
  ]
  for row in rows {
    let (subset, mode_name, text, expected, expected_flags) = row
    let mode = match mode_name {
      "half_even" => GdaRoundingMode::HalfEven
      "up" => GdaRoundingMode::Up
      "floor" => GdaRoundingMode::Floor
      "ceiling" => GdaRoundingMode::Ceiling
      _ => GdaRoundingMode::Down
    }
    let context = GdaContext::new(
      precision=13,
      rounding=mode,
      e_min=-999_999_999,
      e_max=999_999_999,
      extended=!subset,
    )
    let outcome = to_number(text, context)
    let raised = outcome.raised()
    let flags = (if raised.inexact() { "x" } else { "." }) +
      (if raised.rounded() { "r" } else { "." }) +
      (if raised.subnormal() { "s" } else { "." }) +
      (if raised.underflow() { "u" } else { "." }) +
      (if raised.clamped() { "c" } else { "." })
    let label = "subset=\{subset} \{mode_name} \{text}"
    assert_eq(
      (label, outcome.value().to_string(), flags),
      (label, expected, expected_flags),
    )
  }
}

///|
/// The rows of `official0/quantize0.decTest` that depend on it (decTest 2.62,
/// extended 0, precision 9, half_up, Emax 999, Emin -999): the quantum is a
/// literal far below the range, read as `0`, so the quantization is to the
/// units. The frontend used to rewrite the exponent before the library read it.
// oracle: A
// source: decTest quantize0 rows qua530 and qua531 (extended 0)
// shares: Decimal::from_string and to_string (reading the inputs, printing the result)
test "quantize by a quantum that underflows to zero in the subset (qua530, qua531)" {
  let subset = GdaContext::new(
    precision=9,
    rounding=GdaRoundingMode::HalfUp,
    e_min=-999,
    e_max=999,
    extended=false,
  )
  let wide = GdaContext::new(
    precision=13,
    rounding=GdaRoundingMode::HalfEven,
    e_min=-999_999_999,
    e_max=999_999_999,
    extended=false,
  )
  for text in ["1e-1000000014", "1e-12345678903"] {
    let quantum = to_number(text, wide).value()
    let outcome = quantize(
      Decimal::from_string("123.456").unwrap(),
      quantum,
      subset,
    )
    assert_eq(outcome.value().to_string(), "123")
    assert_true(outcome.raised().inexact())
    assert_true(outcome.raised().rounded())
  }
}
