// Tests of the harness itself. Oracle: none needed, the vectors are written out
// (level A, literals). They check that the harness judges the operation under
// test, not the operation followed by a rounding of the harness: a result that
// is not a number of the format, or a result with a missing or extra flag, must
// fail, whatever a later rounding would make of it.

///|
fn harness_case(
  function : String,
  row : String,
) -> (TestFloatSpec, TestFloatCase) {
  let spec = TestFloatSpec::parse(function, "rnear_even").unwrap()
  let document = parse_testfloat("harness.testfloat", row + "\n", spec).unwrap()
  (spec, document.cases()[0])
}

///|
fn harness_value(text : String) -> @bin_float.BinFloat {
  @bin_float.BinFloat::from_hex(text, 200).unwrap()
}

///|
fn harness_inexact() -> @bin_float.BinaryFlags {
  // 1 / 3 at 24 bits: inexact only
  let context = @bin_float.BinaryContext::new(precision=24)
  let (_, flags) = @bin_float.BinFloat::from_int(1).div_ctx(
    @bin_float.BinFloat::from_int(3),
    context,
  )
  flags
}

///|
fn harness_judge(
  function : String,
  row : String,
  actual : @bin_float.BinFloat,
  flags : @bin_float.BinaryFlags,
) -> Bool {
  let (spec, case) = harness_case(function, row)
  let format = match spec.operation {
    ConvertFormat(target) => target
    _ => spec.format
  }
  judge_float_result(case, format, spec, actual, flags).passed()
}

///|
test "the harness fails a result that is not a number of the format" {
  // f32 sqrt: the vector says 1.0, inexact. 1 + 2^-25 has 26 bits.
  let wide = harness_value("0x2000001p-25")
  // an unrounded result with the inexact flag dropped
  assert_false(
    harness_judge(
      "f32_sqrt",
      "3F800000 3F800000 01",
      wide,
      @bin_float.BinaryFlags::new(),
    ),
  )
  // an unrounded result that carries the inexact flag
  assert_false(
    harness_judge("f32_sqrt", "3F800000 3F800000 01", wide, harness_inexact()),
  )
}

///|
test "the harness fails a conversion that is not rounded to the destination format" {
  // f64_to_f32 of 1 + 2^-52: the vector says 1.0, inexact; 1 + 2^-52 is a
  // number of binary64 and not of binary32
  let wide = harness_value("0x10000000000001p-52")
  assert_false(
    harness_judge(
      "f64_to_f32",
      "3FF0000000000001 3F800000 01",
      wide,
      @bin_float.BinaryFlags::new(),
    ),
  )
  assert_false(
    harness_judge(
      "f64_to_f32",
      "3FF0000000000001 3F800000 01",
      wide,
      harness_inexact(),
    ),
  )
}

///|
test "the harness fails a result below the smallest subnormal of the format" {
  // f16 sqrt: 2^-30 is below 2^-24, the smallest subnormal of binary16; the
  // vector (invented for the test) says zero, underflow and inexact
  let tiny = harness_value("0x1p-30")
  assert_false(
    harness_judge(
      "f16_sqrt",
      "0000 0000 03",
      tiny,
      @bin_float.BinaryFlags::new(),
    ),
  )
}

///|
test "the harness compares the flags of the operation and nothing else" {
  let one = harness_value("0x1p0")
  let none = @bin_float.BinaryFlags::new()
  // right value, right flags
  assert_true(
    harness_judge("f32_sqrt", "3F800000 3F800000 01", one, harness_inexact()),
  )
  assert_true(harness_judge("f32_sqrt", "3F800000 3F800000 00", one, none))
  // right value, the inexact flag dropped
  assert_false(harness_judge("f32_sqrt", "3F800000 3F800000 01", one, none))
  // right value, an extra flag
  assert_false(
    harness_judge("f32_sqrt", "3F800000 3F800000 00", one, harness_inexact()),
  )
  // wrong value, right flags
  assert_false(harness_judge("f32_sqrt", "3F800000 3F800001 00", one, none))
}
