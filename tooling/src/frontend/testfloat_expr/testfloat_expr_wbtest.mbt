// Evidence tools: the `source:` lines of this file that say "per the evidence header" name runs of CPython 3.13.16 fractions, struct and integers, executed on 2026-11-25 by the author of the declarations over the rows quoted in each line; rerun the quoted values with the same tool to check them.

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
fn harness_value(text : String) -> @binary.Binary {
  @binary.Binary::from_hex(text, 200).unwrap()
}

///|
fn harness_inexact() -> @binary.BinaryFlags {
  // 1 / 3 at 24 bits: inexact only
  let context = @binary.BinaryContext::new(precision=24)
  let (_, flags) = @binary.Binary::from_int(1).div_ctx(
    @binary.Binary::from_int(3),
    context,
  )
  flags
}

///|
fn harness_judge(
  function : String,
  row : String,
  actual : @binary.Binary,
  flags : @binary.BinaryFlags,
) -> Bool {
  let (spec, case) = harness_case(function, row)
  let format = match spec.operation {
    ConvertFormat(target) => target
    _ => spec.format
  }
  judge_float_result(case, format, actual, flags).passed()
}

///|
// oracle: A
// source: verdicts written out: 1 + 2^-25 has 26 bits and is not a binary32 number, so the harness fails it with or
//   without the inexact flag
// shares: harness_value (Binary::from_hex builds the actual result) and harness_inexact, the NaN and the infinity
//   built with Binary::div_ctx (they only supply a flag set or a special value to be judged)
test "the harness fails a result that is not a number of the format" {
  // f32 sqrt: the vector says 1.0, inexact. 1 + 2^-25 has 26 bits.
  let wide = harness_value("0x2000001p-25")
  // an unrounded result with the inexact flag dropped
  assert_false(
    harness_judge(
      "f32_sqrt",
      "3F800000 3F800000 01",
      wide,
      @binary.BinaryFlags::new(),
    ),
  )
  // an unrounded result that carries the inexact flag
  assert_false(
    harness_judge("f32_sqrt", "3F800000 3F800000 01", wide, harness_inexact()),
  )
}

///|
// oracle: A
// source: verdicts written out: 1 + 2^-52 is a binary64 number and not a binary32 number, so a conversion that returns
//   it unrounded fails whatever the flags
// shares: harness_value (Binary::from_hex builds the actual result) and harness_inexact, the NaN and the infinity
//   built with Binary::div_ctx (they only supply a flag set or a special value to be judged)
test "the harness fails a conversion that is not rounded to the destination format" {
  // f64_to_f32 of 1 + 2^-52: the vector says 1.0, inexact; 1 + 2^-52 is a
  // number of binary64 and not of binary32
  let wide = harness_value("0x10000000000001p-52")
  assert_false(
    harness_judge(
      "f64_to_f32",
      "3FF0000000000001 3F800000 01",
      wide,
      @binary.BinaryFlags::new(),
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
// oracle: A
// source: verdict written out: 2^-30 is below the smallest binary16 subnormal 2^-24, so it is not a number of the
//   format and the judged result fails
// shares: harness_value (Binary::from_hex builds the actual result) and harness_inexact, the NaN and the infinity
//   built with Binary::div_ctx (they only supply a flag set or a special value to be judged)
test "the harness fails a result below the smallest subnormal of the format" {
  // f16 sqrt: 2^-30 is below 2^-24, the smallest subnormal of binary16; the
  // vector (invented for the test) says zero, underflow and inexact
  let tiny = harness_value("0x1p-30")
  assert_false(
    harness_judge("f16_sqrt", "0000 0000 03", tiny, @binary.BinaryFlags::new()),
  )
}

///|
// oracle: A
// source: verdicts written out: sqrt(1) = 1 is exact, the vector flag 01 (inexact) is wrong on purpose and the flag
//   column must match the flags of the operation exactly, with an extra or a missing flag failing; a wrong value
//   fails with the right flags
// shares: harness_value (Binary::from_hex builds the actual result) and harness_inexact, the NaN and the infinity
//   built with Binary::div_ctx (they only supply a flag set or a special value to be judged)
test "the harness compares the flags of the operation and nothing else" {
  let one = harness_value("0x1p0")
  let none = @binary.BinaryFlags::new()
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

///|
fn harness_pack(
  text : String,
  format : @binary.BinaryInterchangeFormat,
) -> String? {
  pack_exact(harness_value(text), format)
}

///|
// oracle: A
// source: bit patterns recomputed with Python struct (binary16, binary32, binary64) and with the layout of binary128
//   by hand (exponent field 0x3fff gives 1, largest finite 0x7ffe with an all ones fraction, smallest subnormal
//   2^-16494) per the evidence header; the infinities are +inf 0x7f800000 and -inf 0xfc00
// shares: harness_value (Binary::from_hex builds the actual result) and harness_inexact, the NaN and the infinity
//   built with Binary::div_ctx (they only supply a flag set or a special value to be judged)
test "pack_exact writes the bit fields of each format (literals, level A)" {
  let b16 = @binary.BinaryInterchangeFormat::Binary16
  let b32 = @binary.BinaryInterchangeFormat::Binary32
  let b64 = @binary.BinaryInterchangeFormat::Binary64
  let b128 = @binary.BinaryInterchangeFormat::Binary128
  // binary16: 1, -2, the largest finite 65504, the smallest normal 2^-14, the
  // largest subnormal, the smallest subnormal 2^-24, zeros
  assert_eq(harness_pack("0x1p0", b16), Some("3c00"))
  assert_eq(harness_pack("-0x1p1", b16), Some("c000"))
  assert_eq(harness_pack("0x7ffp5", b16), Some("7bff"))
  assert_eq(harness_pack("0x1p-14", b16), Some("0400"))
  assert_eq(harness_pack("0x3ffp-24", b16), Some("03ff"))
  assert_eq(harness_pack("0x1p-24", b16), Some("0001"))
  assert_eq(harness_pack("0x0p0", b16), Some("0000"))
  assert_eq(harness_pack("-0x0p0", b16), Some("8000"))
  // binary32
  assert_eq(harness_pack("0x1p0", b32), Some("3f800000"))
  assert_eq(harness_pack("0xffffffp104", b32), Some("7f7fffff"))
  assert_eq(harness_pack("0x1p-126", b32), Some("00800000"))
  assert_eq(harness_pack("0x7fffffp-149", b32), Some("007fffff"))
  assert_eq(harness_pack("0x1p-149", b32), Some("00000001"))
  assert_eq(harness_pack("-0x1p-149", b32), Some("80000001"))
  // binary64
  assert_eq(harness_pack("0x1p0", b64), Some("3ff0000000000000"))
  assert_eq(harness_pack("0x1fffffffffffffp971", b64), Some("7fefffffffffffff"))
  assert_eq(harness_pack("0x1p-1074", b64), Some("0000000000000001"))
  // binary128
  assert_eq(
    harness_pack("0x1p0", b128),
    Some("3fff0000000000000000000000000000"),
  )
  assert_eq(
    harness_pack("0x1ffffffffffffffffffffffffffffp16271", b128),
    Some("7ffeffffffffffffffffffffffffffff"),
  )
  assert_eq(
    harness_pack("0x1p-16494", b128),
    Some("00000000000000000000000000000001"),
  )
  // infinities
  let context = @binary.BinaryContext::new(precision=24)
  let (infinity, _) = @binary.Binary::from_int(1).div_ctx(
    @binary.Binary::from_int(0),
    context,
  )
  assert_eq(pack_exact(infinity, b32), Some("7f800000"))
  assert_eq(pack_exact(infinity.neg(), b16), Some("fc00"))
}

///|
// oracle: A
// source: values checked with Python struct per the evidence header: 4095 needs 12 bits and packs to 4096 in binary16 (so it is
//   not exact), 2^16 does not fit, 2^-25 and 3 * 2^-25 are below or between the subnormal grid of binary16,
//   2^128 and 2^-150 in binary32; a NaN has no bit fields here (the verdict of the harness)
// shares: harness_value (Binary::from_hex builds the actual result) and harness_inexact, the NaN and the infinity
//   built with Binary::div_ctx (they only supply a flag set or a special value to be judged)
test "pack_exact refuses what is not a number of the format" {
  let b16 = @binary.BinaryInterchangeFormat::Binary16
  let b32 = @binary.BinaryInterchangeFormat::Binary32
  // 12 significant bits in binary16 (11)
  assert_eq(harness_pack("0xfffp0", b16), None)
  // above the largest exponent: 2^16 in binary16, 2^128 in binary32
  assert_eq(harness_pack("0x1p16", b16), None)
  assert_eq(harness_pack("0x1p128", b32), None)
  // below the last place of the smallest subnormal: 2^-25 in binary16, 2^-150 in binary32
  assert_eq(harness_pack("0x1p-25", b16), None)
  assert_eq(harness_pack("0x1p-150", b32), None)
  // a subnormal needing one bit more than the last place: 3 * 2^-25
  assert_eq(harness_pack("0x3p-25", b16), None)
  // NaN has no bit fields here
  let context = @binary.BinaryContext::new(precision=24)
  let (nan, _) = @binary.Binary::from_int(0).div_ctx(
    @binary.Binary::from_int(0),
    context,
  )
  assert_eq(pack_exact(nan, b32), None)
}

///|
// oracle: A
// source: verdicts written out: a NaN expected (any payload in the vector) accepts only a NaN result, and a number
//   expected rejects a NaN result
// shares: harness_value (Binary::from_hex builds the actual result) and harness_inexact, the NaN and the infinity
//   built with Binary::div_ctx (they only supply a flag set or a special value to be judged)
test "the harness compares a NaN column with a quiet NaN and nothing more" {
  let context = @binary.BinaryContext::new(precision=24)
  let (nan, _) = @binary.Binary::from_int(0).div_ctx(
    @binary.Binary::from_int(0),
    context,
  )
  let invalid = @binary.BinaryFlags::new()
  // expected NaN (any payload in the column), a quiet NaN result
  assert_true(harness_judge("f32_sqrt", "FF800000 7FC00000 00", nan, invalid))
  assert_true(harness_judge("f32_sqrt", "FF800000 7F800001 00", nan, invalid))
  // expected NaN, a number result
  assert_false(
    harness_judge(
      "f32_sqrt",
      "FF800000 7FC00000 00",
      harness_value("0x1p0"),
      invalid,
    ),
  )
  // expected number, a NaN result
  assert_false(harness_judge("f32_sqrt", "3F800000 3F800000 00", nan, invalid))
}
