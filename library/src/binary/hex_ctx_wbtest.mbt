// Binary::from_hex_ctx (IEEE Std 754-2019 5.12.3, issue #256).
//
// 5.12.3: "conversions from hexadecimal-significand character sequences to
// supported binary formats, are correctly rounded according to the applicable
// binary rounding-direction attribute, and signal all exceptions appropriately."
//
// The rows of hex_ctx_rows_wbtest.mbt come from exact rational arithmetic
// (tools/generate_hex_ctx_rows.py), independent of the library.

///|
fn hex_ctx_mode(name : String) -> BinaryRoundingMode {
  match name {
    "RNE" => BinaryRoundingMode::RoundTiesToEven
    "RNA" => BinaryRoundingMode::RoundTiesToAway
    "RTZ" => BinaryRoundingMode::RoundTowardZero
    "RTP" => BinaryRoundingMode::RoundTowardPositive
    _ => BinaryRoundingMode::RoundTowardNegative
  }
}

///|
test "from_hex_ctx rounds every sequence like exact arithmetic, with the flags" {
  let rows = hex_ctx_rows()
  let mut count = 0
  for row in rows {
    let (text, name, p, _, emax, mode, tininess, expected, flags) = row
    let context = BinaryContext::new(
      precision=p,
      rounding=hex_ctx_mode(mode),
      e_max=emax,
      tininess=if tininess == "before" {
        TininessDetection::BeforeRounding
      } else {
        TininessDetection::AfterRounding
      },
    )
    let (value, actual_flags) = Binary::from_hex_ctx(text, context).unwrap()
    let label = "\{text} \{name} \{mode} \{tininess}"
    assert_eq(
      "\{label} => \{value} \{e2s_flags(actual_flags)}",
      "\{label} => \{expected} \{flags}",
    )
    count += 1
  }
  assert_eq(count, rows.length())
}

///|
test "from_hex_ctx: exact inputs raise nothing, inexact ones raise inexact only" {
  let context = BinaryContext::binary64()
  // 53 bits exactly
  let (exact, flags) = Binary::from_hex_ctx("0x1.fffffffffffffp0", context).unwrap()
  assert_eq(exact.to_hex(), "0x1fffffffffffffp-52")
  assert_eq(flags, BinaryFlags::new())
  // 54 bits: the last bit is dropped (ties to even: rounds to the even neighbour)
  let (tie, tie_flags) = Binary::from_hex_ctx("0x1.fffffffffffff8p0", context).unwrap()
  assert_eq(tie.to_hex(), "0x1p1")
  assert_eq(e2s_flags(tie_flags), "I--")
  // the same sequence in the four directed modes
  let up = BinaryContext::new(
    precision=53,
    rounding=BinaryRoundingMode::RoundTowardPositive,
  )
  let down = BinaryContext::new(
    precision=53,
    rounding=BinaryRoundingMode::RoundTowardNegative,
  )
  assert_eq(
    Binary::from_hex_ctx("0x1.fffffffffffff8p0", up).unwrap().0.to_hex(),
    "0x1p1",
  )
  assert_eq(
    Binary::from_hex_ctx("0x1.fffffffffffff8p0", down).unwrap().0.to_hex(),
    "0x1fffffffffffffp-52",
  )
  assert_eq(
    Binary::from_hex_ctx("-0x1.fffffffffffff8p0", up).unwrap().0.to_hex(),
    "-0x1fffffffffffffp-52",
  )
  assert_eq(
    Binary::from_hex_ctx("-0x1.fffffffffffff8p0", down).unwrap().0.to_hex(),
    "-0x1p1",
  )
}

///|
test "from_hex_ctx: overflow and underflow of the four interchange formats" {
  let formats = [
    ("binary16", 11, -14, 15),
    ("binary32", 24, -126, 127),
    ("binary64", 53, -1022, 1023),
    ("binary128", 113, -16382, 16383),
  ]
  for f in formats {
    let (name, p, emin, emax) = f
    let context = BinaryContext::new(precision=p, e_max=emax)
    // 2^(emax + 1) overflows to infinity (round to nearest)
    let (big, big_flags) = Binary::from_hex_ctx("0x1p\{emax + 1}", context).unwrap()
    assert_eq(big.classify() == FpClass::Infinity, true, msg=name)
    assert_eq(e2s_flags(big_flags), "I-O", msg=name)
    // 2^emax is the largest power of two: exact
    let (top, top_flags) = Binary::from_hex_ctx("0x1p\{emax}", context).unwrap()
    assert_eq(top.to_hex(), "0x1p\{emax}", msg=name)
    assert_eq(top_flags, BinaryFlags::new(), msg=name)
    // the smallest subnormal 2^(emin - p + 1) is exact and raises nothing
    let (tiny, tiny_flags) = Binary::from_hex_ctx(
      "0x1p\{emin - p + 1}",
      context,
    ).unwrap()
    assert_eq(tiny.to_hex(), "0x1p\{emin - p + 1}", msg=name)
    assert_eq(tiny_flags, BinaryFlags::new(), msg=name)
    // a quarter of it underflows to zero, inexact
    let (zero, zero_flags) = Binary::from_hex_ctx(
      "0x1p\{emin - p - 1}",
      context,
    ).unwrap()
    assert_eq(zero.is_zero(), true, msg=name)
    assert_eq(e2s_flags(zero_flags), "IU-", msg=name)
  }
}

///|
test "from_hex_ctx agrees with from_hex where from_hex succeeds" {
  // from_hex is the unbounded round-to-nearest-even case without the flags.
  let sources = [
    "0x1.fffffffffffff8p0", "-0x1.00000000000008p0", "0x1.0000018p0", "0x.8p1", "0xABCDEF123456789p-40",
    "0x1p-1074", "-0x1.8p-1075", "0x1p1023", "0x0p0", "-0x0.0p5",
  ]
  for source in sources {
    for p in [1, 11, 24, 53, 64, 113] {
      let old = Binary::from_hex(source, p).unwrap()
      let (value, _) = Binary::from_hex_ctx(
        source,
        BinaryContext::new(precision=p),
      ).unwrap()
      assert_eq(value.to_hex(), old.to_hex(), msg="\{source} \{p}")
      assert_eq(value.is_negative(), old.is_negative(), msg="\{source} \{p}")
    }
  }
}

///|
test "from_hex_ctx: an exponent outside the 32-bit range overflows or underflows" {
  // from_hex reports a parse error here; the context version rounds.
  let context = BinaryContext::binary64()
  let (big, big_flags) = Binary::from_hex_ctx("0x1p99999999999", context).unwrap()
  assert_eq(big.classify() == FpClass::Infinity, true)
  assert_eq(e2s_flags(big_flags), "I-O")
  let (small, small_flags) = Binary::from_hex_ctx("-0x1p-99999999999", context).unwrap()
  assert_eq(small.is_zero() && small.is_negative(), true)
  assert_eq(e2s_flags(small_flags), "IU-")
  assert_true(Binary::from_hex("0x1p99999999999", 53) is Err(_))
  // beyond the old limit of the parser (10^12) the field saturates (issue #597): the same
  // result, the context overflows or underflows (more cases in hex_exponent_wbtest.mbt)
  let (huge, huge_flags) = Binary::from_hex_ctx("0x1p9999999999999", context).unwrap()
  assert_eq(huge.classify() == FpClass::Infinity, true)
  assert_eq(e2s_flags(huge_flags), "I-O")
  assert_true(Binary::from_hex("0x1p9999999999999", 53) is Err(_))
}
