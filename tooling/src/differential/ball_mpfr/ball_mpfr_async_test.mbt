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
fn read_bound(text : String, size : Int32) -> @binary.BinFloat {
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
  match @binary.BinFloat::from_hex(text, bits) {
    Ok(value) => value
    Err(_) => abort("cannot read the bound " + text)
  }
}

///|
fn read_operand(token : String, size : Int32) -> @ball.BallFloat {
  let parts : Array[StringView] = token.split(":").collect()
  if parts.length() != 2 {
    abort("malformed operand " + token)
  }
  @ball.BallFloat::from_bounds(
    read_bound(parts[0].to_owned(), size),
    read_bound(parts[1].to_owned(), size),
    precision=size,
  )
}

///|
fn run_operation(
  op : String,
  operands : Array[@ball.BallFloat],
) -> @ball.BallFloat {
  match op {
    "add" => operands[0].add(operands[1])
    "sub" => operands[0].sub(operands[1])
    "mul" => operands[0].mul(operands[1])
    "div" => operands[0].div(operands[1])
    "sqr" => operands[0].sqr()
    "sqrt" => operands[0].sqrt()
    "fma" => operands[0].fma(operands[1], operands[2])
    _ => abort("unknown operation " + op)
  }
}

///|
fn echo_of(operands : Array[@ball.BallFloat]) -> String {
  operands
  .map(x => {
    canonical_bound(x.lower_bound()) + ":" + canonical_bound(x.upper_bound())
  })
  .join(",")
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
/// Reads the rows of `BALLDIFF_INPUTS` and the oracle rows of `BALLDIFF_ORACLE`
/// (same ids, same order), runs every row on `BallFloat` and compares each bound
/// of the result, and the operands as the library read them, with MPFR's.
/// Prints `BALLDIFF_FAIL` per differing row and `BALLDIFF_SUMMARY`; the test fails
/// when any row differs. Without the two variables it does nothing.
async test "ball_float against the MPFR oracle: tightest results, directed roundings" {
  guard @env.get_env_var("BALLDIFF_INPUTS") is Some(inputs_path) else { return }
  guard @env.get_env_var("BALLDIFF_ORACLE") is Some(oracle_path) else {
    abort("BALLDIFF_ORACLE is not set")
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
      println("BALLDIFF_UNDECIDED " + row[0])
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
    if !same_bound(expected[1], got_lo) ||
      !same_bound(expected[2], got_hi) ||
      expected[4] != got_echo {
      failed += 1
      println(
        "BALLDIFF_FAIL " +
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
        (if expected[4] != got_echo {
          " operands differ: expected " + expected[4] + " got " + got_echo
        } else {
          ""
        }),
      )
    }
  }
  println(
    "BALLDIFF_SUMMARY rows=" +
    inputs.length().to_string() +
    " failed=" +
    failed.to_string() +
    " undecided=" +
    undecided.to_string(),
  )
  assert_eq(failed, 0)
}
