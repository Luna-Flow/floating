///|
fn fields_of(line : String) -> Array[String] {
  let result : Array[String] = []
  for part in line.split(" ") {
    let text = part.to_owned()
    if !text.is_empty() {
      result.push(text)
    }
  }
  result
}

///|
fn read_rows(path : String) -> Array[Array[String]] raise {
  let rows : Array[Array[String]] = []
  for line in @fs.read_file_to_string(path).split("\n") {
    let text = line.trim().to_owned()
    if text.is_empty() || text.has_prefix("#") {
      continue
    }
    rows.push(fields_of(text))
  }
  rows
}

///|
fn parse_int_or_abort(text : String) -> Int32 {
  @string.parse_int(text) catch {
    _ => abort("not an integer: " + text)
  }
}

///|
/// An operand token `lo:hi`: the two bounds as the library writes them. A bound
/// carries at least as many bits as its digits hold, so the precision of the
/// reading is the larger of the case precision and four bits per hexadecimal digit.
fn read_bound(text : String, size : Int32) -> @binary.Binary {
  let mut digits = 0
  let mut in_digits = false
  for c in text {
    if c == 'x' {
      in_digits = true
    } else if c == 'p' {
      in_digits = false
    } else if in_digits && c != '.' {
      digits += 1
    }
  }
  let bits = Int32::max(size, digits * 4)
  match @binary.Binary::from_hex(text, bits) {
    Ok(value) => value
    Err(_) => abort("cannot read the bound " + text)
  }
}

///|
fn read_operand(token : String, size : Int32) -> @interval.Interval {
  let parts : Array[StringView] = token.split(":").collect()
  if parts.length() != 2 {
    abort("malformed operand " + token)
  }
  @interval.Interval::from_bounds(
    read_bound(parts[0].to_owned(), size),
    read_bound(parts[1].to_owned(), size),
    precision=size,
  )
}

///|
fn run_operation(
  op : String,
  operands : Array[@interval.Interval],
) -> @interval.Interval {
  match op {
    "add" => operands[0].add(operands[1])
    "sub" => operands[0].sub(operands[1])
    "mul" => operands[0].mul(operands[1])
    "div" => operands[0].div(operands[1])
    "sqr" => operands[0].sqr()
    "sqrt" => operands[0].sqrt()
    "fma" => operands[0].fma(operands[1], operands[2])
    "exp" => operands[0].exp()
    "ln" => operands[0].ln()
    _ => abort("unknown operation " + op)
  }
}

///|
/// The two zeros are one number in the set-based flavour (and `lower_bound` of a
/// zero is `-0`, IEEE 1788-2015): in the echo of the operands a bound `-0` is
/// compared as `0`.
fn identify_zeros(echo : String) -> String {
  echo
  .split(",")
  .map(operand => {
    operand
    .split(":")
    .map(bound => if bound.to_owned() == "-0" { "0" } else { bound.to_owned() })
    .collect()
    .join(":")
  })
  .collect()
  .join(",")
}

///|
fn echo_of(operands : Array[@interval.Interval]) -> String {
  identify_zeros(
    operands
    .map(x => {
      canonical_bound(x.lower_bound()) + ":" + canonical_bound(x.upper_bound())
    })
    .join(","),
  )
}

///|
/// The two zeros are one number in the set-based flavour: a bound is compared with
/// the sign of a zero identified.
fn same_bound(expected : String, actual : String) -> Bool {
  (expected == "-0" && actual == "0") ||
  (expected == "0" && actual == "-0") ||
  expected == actual
}

///|
/// How many units of the last place of the oracle bound the library bound may be
/// outside it: IEEE 1788-2015 12.10.2 asks `exp` and `ln` (valid, "should be
/// accurate") to enclose the tightest result and not be much wider than it.
let accurate_ulps : Int32 = 1024

///|
/// `got` is the library's lower (`lower`) or upper bound, `expected` the bound of the
/// tightest result. Encloses: the library bound is not inside the tightest result.
/// Too wide: it is outside it by more than `accurate_ulps` units of the last place
/// of the oracle bound (an infinite or zero oracle bound must be met exactly).
fn bound_verdict(
  expected : @binary.Binary,
  got : @binary.Binary,
  lower : Bool,
) -> (Bool, Bool) {
  let order = got.compare(expected)
  let encloses = if lower { order <= 0 } else { order >= 0 }
  if order == 0 {
    return (encloses, false)
  }
  let exact_only = expected.is_zero() ||
    (match expected.classify() {
      Finite => false
      _ => true
    })
  if exact_only {
    return (encloses, true)
  }
  let slack = expected
    .ulp()
    .mul(
      @binary.Binary::from_int(accurate_ulps, precision=expected.precision()),
    )
  let limit = if lower { expected.sub(slack) } else { expected.add(slack) }
  let too_wide = if lower {
    got.compare(limit) < 0
  } else {
    got.compare(limit) > 0
  }
  (encloses, too_wide)
}

///|
/// Reads the rows of `INTERVALDIFF_INPUTS` and the oracle rows of `INTERVALDIFF_ORACLE`
/// (same ids, same order), runs every row on `Interval` and compares each bound
/// of the result, and the operands as the library read them, with MPFR's.
/// Prints `INTERVALDIFF_FAIL` per differing row and `INTERVALDIFF_SUMMARY`; the test fails
/// when any row differs. Without the two variables it does nothing.
async test "interval against the MPFR oracle: tightest results, directed roundings" {
  guard @env.get_env_var("INTERVALDIFF_INPUTS") is Some(inputs_path) else {
    return
  }
  guard @env.get_env_var("INTERVALDIFF_ORACLE") is Some(oracle_path) else {
    abort("INTERVALDIFF_ORACLE is not set")
  }
  let inputs = read_rows(inputs_path)
  let oracle = read_rows(oracle_path)
  if inputs.length() != oracle.length() {
    abort("the oracle has a different number of rows than the inputs")
  }
  let mut failed = 0
  let mut undecided = 0
  for i in 0..<inputs.length() {
    let row = inputs[i]
    let expected = oracle[i]
    if row[0] != expected[0] {
      abort("row " + row[0] + " is not oracle row " + expected[0])
    }
    if expected[3].contains("u") {
      undecided += 1
      println("INTERVALDIFF_UNDECIDED " + row[0])
      continue
    }
    let size = parse_int_or_abort(row[2])
    let operands = Array::makei(row.length() - 4, k => {
      read_operand(row[4 + k], size)
    })
    let result = run_operation(row[1], operands)
    let got_lo = canonical_bound(result.lower_bound())
    let got_hi = canonical_bound(result.upper_bound())
    let got_echo = echo_of(operands)
    let elementary = row[1] == "exp" || row[1] == "ln"
    let mut reason = ""
    if elementary {
      // the bounds of every `exp` and `ln` row, for the report of the excess over the tightest result
      println(
        "INTERVALDIFF_ELEM " +
        row[0] +
        " " +
        row[1] +
        " " +
        row[2] +
        " " +
        row[3] +
        " " +
        got_lo +
        " " +
        got_hi,
      )
      // valid only (12.10.2): enclose the tightest result, and not be much wider
      let lower = bound_verdict(
        read_bound(expected[5], size),
        result.lower_bound(),
        true,
      )
      let upper = bound_verdict(
        read_bound(expected[6], size),
        result.upper_bound(),
        false,
      )
      if !lower.0 || !upper.0 {
        reason = " (does not enclose the tightest result)"
      } else if lower.1 || upper.1 {
        reason = " (wider than " +
          accurate_ulps.to_string() +
          " units of the last place)"
      }
    } else if !same_bound(expected[1], got_lo) ||
      !same_bound(expected[2], got_hi) {
      reason = " (not the tightest result)"
    }
    if reason.is_empty() && identify_zeros(expected[4]) != got_echo {
      reason = " (operands read differently)"
    }
    if !reason.is_empty() {
      failed += 1
      println(
        "INTERVALDIFF_FAIL " +
        row[0] +
        " " +
        row[1] +
        " " +
        row[2] +
        " " +
        row[3] +
        " expected " +
        expected[1] +
        " " +
        expected[2] +
        " got " +
        got_lo +
        " " +
        got_hi +
        reason +
        (if identify_zeros(expected[4]) != got_echo {
          " operands: expected " + expected[4] + " got " + got_echo
        } else {
          ""
        }),
      )
    }
  }
  println(
    "INTERVALDIFF_SUMMARY rows=" +
    inputs.length().to_string() +
    " failed=" +
    failed.to_string() +
    " undecided=" +
    undecided.to_string(),
  )
  assert_eq(failed, 0)
}

///|
// Oracle: level A (the verdicts are worked out by hand: units of the last place of
// the oracle bound 1.5 at 8 bits are 2^-7).
test "bound_verdict: enclosing, equal, a little wider, too wide, zero and infinite bounds" {
  let p = 8
  let one_and_a_half = @binary.Binary::from_double(1.5, precision=p)
  let unit = one_and_a_half.ulp()
  // equal
  assert_eq(bound_verdict(one_and_a_half, one_and_a_half, true), (true, false))
  assert_eq(bound_verdict(one_and_a_half, one_and_a_half, false), (true, false))
  // a lower bound 3 units below encloses and is accurate; 5000 units below is too wide
  let few = one_and_a_half.sub(
    unit.mul(@binary.Binary::from_int(3, precision=p)),
  )
  let many = one_and_a_half.sub(
    unit.mul(@binary.Binary::from_int(5000, precision=p)),
  )
  assert_eq(bound_verdict(one_and_a_half, few, true), (true, false))
  assert_eq(bound_verdict(one_and_a_half, many, true), (true, true))
  // a lower bound above the oracle's does not enclose
  let above = one_and_a_half.add(unit)
  assert_eq(bound_verdict(one_and_a_half, above, true).0, false)
  // the same for an upper bound
  assert_eq(
    bound_verdict(one_and_a_half, one_and_a_half.add(unit), false),
    (true, false),
  )
  assert_eq(
    bound_verdict(one_and_a_half, one_and_a_half.sub(unit), false).0,
    false,
  )
  // a zero oracle bound is met exactly: a negative lower bound is too wide
  let zero = @binary.Binary::zero(precision=p)
  assert_eq(bound_verdict(zero, zero, true), (true, false))
  assert_eq(bound_verdict(zero, one_and_a_half.neg(), true), (true, true))
  // an infinite oracle upper bound is met by infinity only
  let inf = @binary.Binary::inf(precision=p)
  assert_eq(bound_verdict(inf, inf, false), (true, false))
  assert_eq(bound_verdict(inf, one_and_a_half, false).0, false)
}

///|
// Oracle: level A (written-out texts).
test "identify_zeros: -0 is 0 in the echo of the operands, nothing else changes" {
  assert_eq(identify_zeros("-0:0,0b1p0:-0"), "0:0,0b1p0:0")
  assert_eq(identify_zeros("-0b1p0:0b11p1"), "-0b1p0:0b11p1")
  assert_eq(identify_zeros("0:0"), "0:0")
}
