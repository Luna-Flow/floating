///|
// #478: a special operand (NaN, infinity, zero) and an exactly defined point is
// a value in every context, also where the kernels do not serve the context (a
// precision above 999,999, an exponent range above it).
//
// oracle: A
// source: the expected values are written out from
// IEEE Std 754-2019 9.2.1 (the table of special cases of each function), 9.2
// (a signaling NaN signals invalid and the result is a quiet NaN) and Table 9.1
// (domain), value and flags, and the cohort of an exact result is the
// preferred exponent 0 of 9.2.2 (5.2), so each value is compared as text,
// quantum included. Not from the library.
// shares: nothing
//
// Provenance of the rows: the first list of functions and rows came from an
// unpublished prototype; on 2026-11-21 every row was compared with the text
// of 9.2.1 (special values), 9.2 (signaling NaN) and Table 9.1 (domain and
// exceptions) extracted from the PDF. A row is in the table only when the
// clause lists it: f(+-0), f(+-inf), a domain error, a pole, and the listed
// f(1) (ln, log2, log10, acos, acosPi, acosh), atanPi(+-inf), the atan2 and
// atan2Pi constants, compound, rootn, hypot and rSqrt rows. Exact results of
// ordinary operands that the clause does not list (`atanpi(1)`, `acospi(0)`,
// `acospi(-1)`, `log10(1E+5)`, `atan2pi(1, 1)`, `hypot(3, 4)`) are not in the
// table: they follow the limit, see the last test.
//
// Cost: no row of the table computes a constant. `atan(+-inf)` and the
// `atan2` multiples of pi other than zero compute pi at the precision of the
// context (about 100 s at 10^6 digits, measured by the reviewer); they are
// not rows here, see the last test for the limit.
//
// Contexts: `a` has a precision of 1,000,000 (above the limit of the kernels),
// `b` an exponent range of 999,999,999. The same rows hold in the
// default context. Results that need a constant (the angle of an infinity
// argument of atan, a multiple of pi) are not in the table: in `a` they are
// computed at the precision of the context, which is the limit.

///|
fn special_call(
  op : String,
  x : String,
  y : String,
  ctx : DecimalContext,
) -> String {
  let a = pm1_exact(x)
  let result = match op {
    "compound0" => a.try_compound_ctx(0, ctx)
    "compound2" => a.try_compound_ctx(2, ctx)
    "compound-2" => a.try_compound_ctx(-2, ctx)
    "rootn3" => a.try_rootn_ctx(3, ctx)
    "rootn0" => a.try_rootn_ctx(0, ctx)
    _ => {
      let mut found : Result[(Decimal, DecimalFlags), @def.ArithmeticError]? = None
      for row in elementary_outcome_table() {
        if row.0 == op {
          found = Some(
            (row.1)(a, pm1_exact(if y == "" { "0.5" } else { y }), ctx),
          )
        }
      }
      match found {
        Some(result) => result
        None => abort("no such function: " + op)
      }
    }
  }
  match result {
    Ok((value, flags)) => "\{value} \{pm1_flags_text(flags)}"
    Err(_) => "certification-failure"
  }
}

///|
fn special_rows() -> Array[(String, String, String, String)] {
  let rows : Array[(String, String, String, String)] = []
  let nans = [("NaN", "nan -"), ("sNaN", "nan v")]
  let add = fn(ops : Array[String], cases : Array[(String, String)]) {
    for op in ops {
      for c in cases {
        rows.push((op, c.0, "", c.1))
      }
    }
  }
  add(
    ["exp", "exp2", "exp10"],
    nans +
    [("Infinity", "inf -"), ("-Infinity", "0 -"), ("0", "1 -"), ("-0", "1 -")],
  )
  add(
    ["expm1", "exp2m1", "exp10m1"],
    nans +
    [("Infinity", "inf -"), ("-Infinity", "-1 -"), ("0", "0 -"), ("-0", "-0 -")],
  )
  add(
    ["ln", "log2", "log10"],
    nans +
    [
      ("Infinity", "inf -"),
      ("-Infinity", "nan v"),
      ("0", "-inf z"),
      ("-0", "-inf z"),
      ("-1", "nan v"),
    ],
  )
  add(
    ["log1p", "log2p1", "log10p1"],
    nans +
    [
      ("Infinity", "inf -"),
      ("-Infinity", "nan v"),
      ("0", "0 -"),
      ("-0", "-0 -"),
    ],
  )
  add(
    ["sin", "tan", "sinpi", "tanpi"],
    nans +
    [
      ("Infinity", "nan v"),
      ("-Infinity", "nan v"),
      ("0", "0 -"),
      ("-0", "-0 -"),
    ],
  )
  add(
    ["cos", "cospi"],
    nans +
    [("Infinity", "nan v"), ("-Infinity", "nan v"), ("0", "1 -"), ("-0", "1 -")],
  )
  add(
    ["cosh"],
    nans + [("Infinity", "inf -"), ("-Infinity", "inf -"), ("0", "1 -")],
  )
  add(
    ["sinh", "asinh"],
    nans +
    [
      ("Infinity", "inf -"),
      ("-Infinity", "-inf -"),
      ("0", "0 -"),
      ("-0", "-0 -"),
    ],
  )
  add(
    ["tanh"],
    nans +
    [("Infinity", "1 -"), ("-Infinity", "-1 -"), ("0", "0 -"), ("-0", "-0 -")],
  )
  add(["asin", "atan", "asinpi"], nans + [("0", "0 -"), ("-0", "-0 -")])
  add(
    ["atanh"],
    nans + [("0", "0 -"), ("-0", "-0 -"), ("1", "inf z"), ("-1", "-inf z")],
  )
  add(["asin", "asinpi"], [("Infinity", "nan v"), ("-Infinity", "nan v")])
  add(["atanh"], [("Infinity", "nan v"), ("-Infinity", "nan v")])
  add(["atanpi"], [("Infinity", "0.5 -"), ("-Infinity", "-0.5 -")])
  add(["acospi"], [("1", "0 -")])
  add(["acosh"], nans + [("Infinity", "inf -"), ("1", "0 -"), ("0.5", "nan v")])
  add(
    ["rsqrt"],
    nans +
    [
      ("Infinity", "0 -"),
      ("-Infinity", "nan v"),
      ("0", "inf z"),
      ("-0", "-inf z"),
      ("-1", "nan v"),
    ],
  )
  add(["log2", "acos"], [("1", "0 -")])
  add(["log1p"], [("-1", "-inf z")])
  add(["log10"], [("1", "0 -")])
  add(["compound0"], [("NaN", "1 -"), ("0", "1 -"), ("7", "1 -")])
  add(["compound2"], [("Infinity", "inf -"), ("-1", "0 -"), ("0", "1 -")])
  add(["compound-2"], [("-1", "inf z")])
  add(["rootn3"], nans + [("Infinity", "inf -"), ("0", "0 -"), ("-0", "-0 -")])
  add(["rootn0"], [("0", "nan v"), ("1", "nan v")])
  // two operands: (op, x, y)
  for
    entry in [
      ("atan2", "0", "1", "0 -"),
      ("atan2", "-0", "1", "-0 -"),
      ("atan2", "1", "Infinity", "0 -"),
      ("atan2", "NaN", "1", "nan -"),
      ("atan2", "sNaN", "1", "nan v"),
      ("atan2pi", "0", "1", "0 -"),
      ("atan2pi", "-0", "1", "-0 -"),
      ("atan2pi", "0", "-1", "1 -"),
      ("hypot", "Infinity", "NaN", "inf -"),
      ("hypot", "0", "0", "0 -"),
      ("hypot", "NaN", "1", "nan -"),
    ] {
    rows.push(entry)
  }
  rows
}

///|
// oracle: A
// source: IEEE 754-2019 9.2.1 and Table 9.1 written out in `special_rows`, see the file header
// shares: nothing
test "special operands and exact points are values beyond the limits of the kernels (#478)" {
  let a = DecimalContext::new(precision=1_000_000, e_max=999_999)
  let b = DecimalContext::new(precision=34, e_max=999_999_999)
  let default = DecimalContext::new(precision=34)
  let failures = StringBuilder()
  let mut count = 0
  let rows = special_rows()
  for row in rows {
    let (op, x, y, want) = row
    for ctx in [a, b, default] {
      let got = special_call(op, x, y, ctx)
      if got != want {
        count += 1
        if count <= 60 {
          failures.write_string(
            "\{op}(\{x}\{if y == "" { "" } else { ", " + y }}) p=\{ctx.precision} emax=\{ctx.e_max}: want \{want}, got \{got}\n",
          )
        }
      }
    }
  }
  inspect(failures.to_string(), content="")
  assert_eq(rows.length(), 202)
}

///|
// oracle: A
// source: the ordinary operand 0.5 is not a special operand or an exact point of any function of the table, so the outcome is the limit of the context (Err, not_computed) that issue 478 leaves in place for this round
// shares: nothing
test "an ordinary operand in a restricted context is still not computed (#478)" {
  let a = DecimalContext::new(precision=1_000_000, e_max=999_999)
  assert_eq(special_call("exp", "0.5", "", a), "certification-failure")
  assert_eq(special_call("ln", "0.5", "", a), "certification-failure")
  assert_eq(special_call("sin", "0.5", "", a), "certification-failure")
  let b = DecimalContext::new(precision=34, e_max=999_999_999)
  assert_eq(special_call("ln", "0.5", "", b), "certification-failure")
  assert_eq(special_call("sin", "0.5", "", b), "certification-failure")
  assert_eq(special_call("exp", "0.5", "", b), "certification-failure")
  // an exact result of ordinary operands is not an exact point of 9.2.1
  assert_eq(special_call("hypot", "3", "4", b), "certification-failure")
  // exact results of ordinary operands that 9.2.1 does not list
  for
    row in [
      ("atanpi", "1", ""),
      ("acospi", "0", ""),
      ("acospi", "-1", ""),
      ("log10", "1E+5", ""),
      ("log10", "1E+1000000", ""),
      ("rsqrt", "4", ""),
      ("sinpi", "0.5", ""),
      ("cospi", "1", ""),
      ("exp2", "3", ""),
      ("rootn3", "8", ""),
      ("atan2pi", "1", "1"),
    ] {
    assert_eq(
      special_call(row.0, row.1, row.2, b),
      "certification-failure",
      msg=row.0 + "(" + row.1 + ")",
    )
  }
  // the integer with the listed values stays a value
  assert_eq(special_call("sinpi", "2", "", b), "0 -")
  assert_eq(special_call("cospi", "0.5", "", b), "0 -")
}

///|
// oracle: S
// source: pins an explicit refusal of the implementation, not a value of the standard. `decimal_certified_work_refusal` (certified_math.mbt) refuses a first working precision above `binary_precision_max` = 268,435,456 bits (bin_float/context.mbt:43). The working precision is `max(64, digits * 3,321,929 / 1,000,000 + 31)` bits: 80,807,093 digits give 268,435,456 bits (accepted), 80,807,094 digits give 268,435,457 bits (refused). Computed by hand with Python integers on 2026-11-21.
// shares: nothing
test "a multiple of pi beyond the binary precision limit is refused at once (#478)" {
  let d = fn(s : String) { Decimal::from_string(s).unwrap() }
  for digits in [80_807_094, 700_000_000, 999_999_999] {
    let huge = DecimalContext::new(precision=digits, e_max=999_999_999)
    match d("0").try_atan2_ctx(d("-1"), huge) {
      Err(error) => assert_true(error.is_certification_failure())
      Ok(_) => abort("atan2(0, -1) at \{digits} digits must be refused")
    }
    assert_true(d("Infinity").try_atan_ctx(huge) is Err(_))
    // the cases that need no constant are values in the same context
    assert_true(d("0").try_atan2_ctx(d("1"), huge) is Ok(_))
    assert_true(d("NaN").try_exp_ctx(huge) is Ok(_))
  }
}
