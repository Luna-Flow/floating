///|
fn remainder_flags_text(f : DecimalFlags) -> String {
  (if f.inexact { "x" } else { "-" }) +
  (if f.rounded { "r" } else { "-" }) +
  (if f.invalid_operation { "i" } else { "-" }) +
  (if f.division_by_zero { "z" } else { "-" }) +
  (if f.overflow { "o" } else { "-" }) +
  (if f.underflow { "u" } else { "-" }) +
  (if f.subnormal { "s" } else { "-" }) +
  (if f.clamped { "c" } else { "-" }) +
  (if f.division_impossible { "d" } else { "-" }) +
  (if f.division_undefined { "U" } else { "-" }) +
  (if f.invalid_context { "C" } else { "-" })
}

///|
fn check_remainder_row(
  row : (
    String,
    String,
    Int32,
    Int32,
    Int32,
    Bool,
    Bool,
    String,
    String,
    String,
  ),
) -> Unit raise {
  let (x, y, p, emin, emax, clamp, ext, op, value, flags) = row
  let ctx = DecimalContext::new(
    precision=p,
    e_min=emin,
    e_max=emax,
    clamp~,
    extended=ext,
  ).unwrap()
  let a = Decimal::from_string(x).unwrap()
  let b = Decimal::from_string(y).unwrap()
  let r = if op == "rem" {
    a.remainder(b, ctx)
  } else {
    a.remainder_near(b, ctx)
  }
  assert_eq(r.0.to_string(), value)
  assert_eq(remainder_flags_text(r.1), flags)
}

///|
/// GDA remainder and remainder-near: the integer part of the quotient decides only
/// whether the operation is possible (division impossible); the remainder is
/// formed from the exact quotient and only the delivered remainder is rounded
/// and clamped, so the internal quotient never changes the value or raises
/// clamped, overflow or rounded flags. Expected values and flags come from
/// Python `decimal` (General Decimal Arithmetic) in an extended context; the
/// flag letters are inexact, rounded, invalid, divide-by-zero, overflow,
/// underflow, subnormal, clamped, division-impossible, division-undefined and
/// invalid-context.
test "remainder and remainder_near follow the exact quotient (extended contexts)" {
  let rows : Array[
    (String, String, Int32, Int32, Int32, Bool, Bool, String, String, String),
  ] = [
    ("7E-8", "2E-8", 9, 0, 1, true, true, "rem", "1E-8", "------s----"),
    ("7E-8", "2E-8", 9, 0, 1, true, true, "near", "-1E-8", "------s----"),
    ("0", "5E-8", 9, 0, 1, true, true, "rem", "0E-8", "-----------"),
    ("0", "5E-8", 9, 0, 1, true, true, "rem", "0E-8", "-----------"),
    ("0E-1", "9E-5", 9, -5, 5, true, true, "near", "0.00000", "-----------"),
    ("0E-4", "863E-4", 9, -24, 4, true, true, "rem", "0.0000", "-----------"),
    (
      "0E3", "4930781E-12", 3, -2, 3, false, true, "rem", "0.0000", "-------c---",
    ),
    ("0E-1", "81616E-11", 9, -24, 4, true, true, "rem", "0E-11", "-----------"),
    ("0E-8", "3102617E-1", 9, -24, 4, true, true, "rem", "0E-8", "-----------"),
    ("0E3", "59887E-8", 9, -2, 3, true, true, "rem", "0E-8", "-----------"),
    ("1E-4", "-4E-6", 9, -5, 5, true, true, "rem", "0.000000", "-----------"),
    ("0E-5", "953E-6", 9, -24, 4, true, true, "rem", "0.000000", "-----------"),
    ("0E0", "13930E-8", 3, -5, 5, true, true, "rem", "0E-7", "-------c---"),
    (
      "54449E-3", "70963E-8", 9, 0, 1, false, true, "rem", "0.00050936", "------s----",
    ),
    (
      "9447933E-8", "-24E-9", 9, -2, 3, true, true, "rem", "1.8E-8", "------s----",
    ),
    (
      "-10869E-8", "-78346E-10", 3, -7, 0, true, true, "rem", "-0.00000684", "xr---------",
    ),
    ("0E-3", "-4512E-12", 3, -24, 4, true, true, "rem", "0E-12", "-----------"),
    (
      "-422754229E-5", "-80425E-4", 9, -5, 5, true, true, "rem", "-5.22979", "-----------",
    ),
    ("0E-1", "97E-10", 3, 0, 1, false, true, "rem", "0.00", "-------c---"),
    ("391E2", "6503E-2", 3, 0, 1, false, true, "rem", "17.0", "xr---------"),
    (
      "35249E1", "5151E-7", 9, 0, 1, false, true, "rem", "0.0002525", "------s----",
    ),
    (
      "53E-4", "-46697E-12", 9, -24, 4, true, true, "rem", "3.0591E-8", "-----------",
    ),
    (
      "91748E-1", "693389647767E-6", 9, -2, 3, true, true, "rem", "9174.80000", "-r---------",
    ),
    (
      "2E4", "21849E-8", 9, -7, 0, false, true, "near", "0.00002870", "-----------",
    ),
    ("2E0", "8E-9", 9, -5, 5, true, true, "near", "0E-9", "-----------"),
    (
      "295E-1", "1125045065E-4", 9, -5, 5, true, true, "near", "29.5000", "-----------",
    ),
    ("0E-7", "8E-11", 3, -7, 0, false, true, "near", "0E-9", "-------c---"),
    (
      "760229E-6", "753E-3", 9, 0, 1, true, true, "near", "0.0072290", "------sc---",
    ),
    ("913E-9", "-33E-10", 3, 0, 1, false, true, "near", "-0.00", "xr---usc---"),
    ("2770E-5", "69E-4", 3, -7, 0, true, true, "near", "0.00010", "-----------"),
    (
      "-459199830E3", "51E6", 9, -7, 0, false, true, "near", "inf", "xr--o------",
    ),
    (
      "6371589275E4", "441857613978E-5", 9, -24, 4, true, true, "near", "-inf", "xr--o------",
    ),
    ("0E-3", "73E-2", 9, -5, 5, true, true, "near", "0.000", "-----------"),
    ("0E-5", "8E-11", 3, -2, 3, true, true, "near", "0.0000", "-------c---"),
    (
      "2E-3", "9759625982E-8", 9, -7, 0, true, true, "near", "0.00200000", "-----------",
    ),
    ("0E-7", "9615E-5", 9, 0, 1, true, true, "near", "0E-7", "-----------"),
    ("4993343713E0", "5E3", 9, 0, 1, true, true, "near", "-inf", "xr--o------"),
  ]
  for row in rows {
    check_remainder_row(row)
  }
}

///|
/// A subset context (extended = false) takes the remainder the same way; these rows
/// agree with the `decimal` package, whose identical fix was checked against
/// Python `decimal` (the integer quotient is internal in both).
test "remainder and remainder_near in subset contexts do not use the clamped quotient" {
  let rows : Array[
    (String, String, Int32, Int32, Int32, Bool, Bool, String, String, String),
  ] = [
    ("-329E0", "74E-6", 9, -5, 5, false, false, "near", "0", "xr---us----"),
    ("-20E-5", "2E-7", 9, -7, 0, true, false, "rem", "0", "-----------"),
    ("0E-3", "47450E4", 9, -24, 4, true, false, "rem", "0", "-----------"),
    ("891E-8", "87732E-11", 9, 0, 1, true, false, "near", "0", "xr---us----"),
    ("34758E3", "9E0", 9, -24, 4, false, false, "rem", "0", "-----------"),
    ("0E0", "1E-10", 9, -2, 3, true, false, "rem", "0", "-----------"),
    ("0E1", "4E-2", 9, -5, 5, true, false, "rem", "0", "-----------"),
    (
      "847E0", "-84423E-10", 9, -7, 0, true, false, "near", "-0.0000030530", "-----------",
    ),
  ]
  for row in rows {
    check_remainder_row(row)
  }
}

///|
/// The integer quotient inside `remainder` is internal: only its digit count
/// matters. Its overflow or clamping must not reach the remainder's flags,
/// and the remainder must be taken with the exact quotient, not with one that
/// has overflowed to infinity. Expected values from Python `decimal`.
test "remainder keeps only the flags of the delivered remainder (issue 183)" {
  let x = Decimal::from_string("6E-6").unwrap()
  let y = Decimal::from_string("-9.99999999E-15").unwrap()
  for extended in [true, false] {
    for clamp in [false, true] {
      let ctx = DecimalContext::new(
        precision=9,
        e_min=-24,
        e_max=4,
        clamp~,
        extended~,
      ).unwrap()
      let (value, flags) = x.remainder(y, ctx)
      assert_eq(value.to_string(), "6.00000000E-15")
      assert_true(flags == DecimalFlags::new())
    }
  }
  // In a subset context the rounded quotient 17636684 overflows e_max = 4.
  let subset = DecimalContext::new(
    precision=9,
    e_min=-24,
    e_max=4,
    extended=false,
  ).unwrap()
  let (value, flags) = Decimal::from_string("123456789")
    .unwrap()
    .remainder(Decimal::from_string("7").unwrap(), subset)
  assert_eq(value.to_string(), "1")
  assert_true(flags == DecimalFlags::new())
}

///|
/// With a zero quotient the remainder is the dividend at the smaller exponent;
/// only that result may be clamped, not the dividend at its own exponent.
test "a zero-quotient remainder is clamped only at its result" {
  let ctx = DecimalContext::new(precision=9, e_min=-24, e_max=4, clamp=true).unwrap()
  let d = fn(s : String) { Decimal::from_string(s).unwrap() }
  let (r, r_flags) = d("-80E-3").remainder(d("4442621E-4"), ctx)
  assert_eq(r.to_string(), "-0.0800")
  assert_true(r_flags == DecimalFlags::new())
  let (r2, r2_flags) = d("4736E-3").remainder(d("91945766E-7"), ctx)
  assert_eq(r2.to_string(), "4.7360000")
  assert_true(r2_flags == DecimalFlags::new())
  let (n, n_flags) = d("-73E-2").remainder_near(d("69846238E-6"), ctx)
  assert_eq(n.to_string(), "-0.730000")
  assert_true(n_flags == DecimalFlags::new())
}

///|
/// The reproduction of floating#183: the integer quotient `3` is clamped to
/// `30000000E-7` when Emax - p + 1 = -7, and that must not alter the remainder.
test "remainder keeps the exact quotient when the quotient would be clamped" {
  let ctx = DecimalContext::new(precision=9, e_min=0, e_max=1, clamp=true).unwrap()
  let d = fn(s : String) { Decimal::from_string(s).unwrap() }
  let (r, f) = d("7E-8").remainder(d("2E-8"), ctx)
  assert_eq(r.to_string(), "1E-8")
  assert_eq(remainder_flags_text(f), "------s----")
  let (n, nf) = d("7E-8").remainder_near(d("2E-8"), ctx)
  assert_eq(n.to_string(), "-1E-8")
  assert_eq(remainder_flags_text(nf), "------s----")
  let (z, zf) = d("0").remainder(d("5E-8"), ctx)
  assert_eq(z.to_string(), "0E-8")
  assert_eq(remainder_flags_text(zf), "-----------")
}
