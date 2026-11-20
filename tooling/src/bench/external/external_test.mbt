///|
/// One operand row of the external-baseline input file. `b` is empty for
/// unary operations. Binary operands are exact hexadecimal values
/// (`-0x1fp-3`), decimal operands exact `<coefficient>E<exponent>` strings,
/// so both sides read the same value without rounding.
struct InputRow {
  kind : String
  op : String
  size : Int32
  index : Int32
  a : String
  b : String
}

///|
fn InputRow::case_id(self : InputRow) -> String {
  self.kind + "/" + self.op + "/" + self.size.to_string()
}

///|
fn parse_row(line : StringView) -> InputRow? {
  let fields : Array[StringView] = line.split(" ").collect()
  if fields.length() < 5 {
    return None
  }
  let size = @string.parse_int(fields[2].to_owned()) catch { _ => return None }
  let index = @string.parse_int(fields[3].to_owned()) catch { _ => return None }
  Some({
    kind: fields[0].to_owned(),
    op: fields[1].to_owned(),
    size,
    index,
    a: fields[4].to_owned(),
    b: if fields.length() > 5 {
      fields[5].to_owned()
    } else {
      ""
    },
  })
}

///|
/// Groups the rows of an input (or reference) file by case, in file order,
/// each case ordered by operand index. Comment lines start with `#`.
fn parse_cases(text : String) -> Map[String, Array[InputRow]] {
  let cases : Map[String, Array[InputRow]] = Map([])
  for line in text.split("\n") {
    let trimmed = line.trim()
    if trimmed.is_empty() || trimmed.has_prefix("#") {
      continue
    }
    match parse_row(trimmed) {
      Some(row) =>
        match cases.get(row.case_id()) {
          Some(rows) => rows.push(row)
          None => cases[row.case_id()] = [row]
        }
      None => ()
    }
  }
  for _, rows in cases {
    rows.sort_by_key(row => row.index)
  }
  cases
}

///|
fn parse_case_id(id : String) -> (String, String, Int32)? {
  let parts : Array[StringView] = id.split("/").collect()
  if parts.length() != 3 {
    return None
  }
  let size = @string.parse_int(parts[2].to_owned()) catch { _ => return None }
  Some((parts[0].to_owned(), parts[1].to_owned(), size))
}

///|
fn all_equal(count : Int32, same : (Int32) -> Bool) -> Bool {
  for i in 0..<count {
    if !same(i) {
      return false
    }
  }
  true
}

// ---------------------------------------------------------------------------
// Binary cases
// ---------------------------------------------------------------------------

///|
/// A binary case: parsed operands, the MPFR reference results and a result
/// buffer the timed pass fills (so the timed region allocates no result array).
struct BinaryCase {
  size : Int32
  count : Int32
  a : Array[@binary.BinFloat]
  b : Array[@binary.BinFloat]
  expected : Array[@binary.BinFloat]
  out : Array[@binary.BinFloat]
}

///|
fn binary_value(text : String, size : Int32) -> @binary.BinFloat {
  match @binary.BinFloat::from_hex(text, size) {
    Ok(value) => value
    Err(_) => abort("cannot read binary operand " + text)
  }
}

///|
fn binary_case(
  size : Int32,
  inputs : Array[InputRow],
  references : Array[InputRow],
) -> BinaryCase {
  let count = inputs.length()
  let a = inputs.map(row => binary_value(row.a, size))
  let b = inputs.map(row => {
    binary_value(if row.b.is_empty() { row.a } else { row.b }, size)
  })
  let expected = if references.is_empty() {
    a.copy()
  } else {
    references.map(row => binary_value(row.a, size))
  }
  { size, count, a, b, expected, out: a.copy(), }
}

///|
fn binary_function(
  op : String,
) -> ((@binary.BinFloat, @binary.BinFloat) -> @binary.BinFloat)? {
  match op {
    "add" => Some((x, y) => x.add(y))
    "mul" => Some((x, y) => x.mul(y))
    "div" => Some((x, y) => x.div(y))
    "sqrt" => Some((x, _) => x.sqrt().unwrap())
    "exp" => Some((x, _) => x.exp())
    "ln" => Some((x, _) => x.ln())
    "sin" => Some((x, _) => x.sin())
    _ => None
  }
}

///|
/// The closure of the null implementation: the shape of the operation
/// closures (an indirect call with two arguments), returning its first one. It
/// sits in a `Ref` so that the compiler cannot see its body: a top-level
/// function with a known body is called directly (and may be inlined), while the
/// operation of a case is a closure chosen at run time by the operation name.
let binary_null : Ref[(@binary.BinFloat, @binary.BinFloat) -> @binary.BinFloat] = {
  val: (x, _) => x,
}

///|
fn binary_matches(
  expected : Array[@binary.BinFloat],
  actual : Array[@binary.BinFloat],
) -> Bool {
  expected.length() == actual.length() &&
  all_equal(expected.length(), i => expected[i].compare(actual[i]) == 0)
}

///|
fn binary_text(values : Array[@binary.BinFloat]) -> String {
  values.map(value => value.to_hex()).join(",")
}

///|
fn binary_spec(
  op : String,
  size : Int32,
  inputs : Array[InputRow],
  references : Array[InputRow],
) -> @runner.BenchSpec[
  Int32,
  BinaryCase,
  BinaryCase,
  Array[@binary.BinFloat],
  Array[@binary.BinFloat],
  Unit,
  Array[@binary.BinFloat]?,
  Array[@binary.BinFloat]?,
]? {
  let function = binary_function(op)
  guard function is Some(f) else { return None }
  Some(
    @benchkit.immutable_bench(
      "external/binary/" + op,
      op,
      [size],
      bits => bits.to_string() + "bit",
      _ => {
        let prepared = binary_case(size, inputs, references)
        if references.is_empty() {
          // No reference file (the quick check): the validation compares the
          // timed pass with this untimed pass of the same function.
          for i in 0..<prepared.count {
            prepared.expected[i] = f(prepared.a[i], prepared.b[i])
          }
        }
        prepared
      },
      input => op + ":" + input.size.to_string() + ":" + input.count.to_string(),
      [
        @runner.Implementation::stateless("floating", "0.11.0", input => {
          for i in 0..<input.count {
            input.out[i] = f(input.a[i], input.b[i])
          }
          @model.OperationResult::completed(input.out, ())
        }),
        // The null of the case: the same loop through the same closure call,
        // with the library call removed. It reads `expected` instead of `a`
        // (so that its output validates) and stores an existing value.
        @runner.Implementation::stateless("null", "0.11.0", input => {
          for i in 0..<input.count {
            input.out[i] = (binary_null.val)(input.expected[i], input.b[i])
          }
          @model.OperationResult::completed(input.out, ())
        }),
      ],
      input => input.expected,
      binary_matches,
      input => op + ":" + input.size.to_string(),
      binary_text,
    ),
  )
}

// ---------------------------------------------------------------------------
// Decimal cases
// ---------------------------------------------------------------------------

///|
struct DecimalCase {
  size : Int32
  count : Int32
  context : @gda.GdaContext
  a : Array[@gda.Decimal]
  b : Array[@gda.Decimal]
  expected : Array[@gda.Decimal]
  out : Array[@gda.Decimal]
}

///|
fn decimal_context(size : Int32) -> @gda.GdaContext {
  @gda.GdaContext::new(
    precision=size,
    rounding=HalfEven,
    e_min=-999999,
    e_max=999999,
  )
}

///|
fn decimal_value(text : String, context : @gda.GdaContext) -> @gda.Decimal {
  @gda.to_number(text, context).value()
}

///|
fn decimal_case(
  size : Int32,
  inputs : Array[InputRow],
  references : Array[InputRow],
) -> DecimalCase {
  let context = decimal_context(size)
  let a = inputs.map(row => decimal_value(row.a, context))
  let b = inputs.map(row => {
    decimal_value(if row.b.is_empty() { row.a } else { row.b }, context)
  })
  let expected = if references.is_empty() {
    a.copy()
  } else {
    references.map(row => decimal_value(row.a, context))
  }
  { size, count: inputs.length(), context, a, b, expected, out: a.copy(), }
}

///|
fn decimal_function(
  op : String,
) -> ((@gda.Decimal, @gda.Decimal, @gda.GdaContext) -> @gda.Decimal)? {
  match op {
    "add" => Some((x, y, c) => @gda.add(x, y, c).value())
    "mul" => Some((x, y, c) => @gda.multiply(x, y, c).value())
    "div" => Some((x, y, c) => @gda.divide(x, y, c).value())
    "sqrt" => Some((x, _, c) => @gda.sqrt(x, c).value())
    "exp" => Some((x, _, c) => @gda.exp(x, c).value())
    "ln" => Some((x, _, c) => @gda.ln(x, c).value())
    _ => None
  }
}

///|
/// See `binary_null`.
let decimal_null : Ref[
  (@gda.Decimal, @gda.Decimal, @gda.GdaContext) -> @gda.Decimal,
] = { val: (x, _, _) => x, }

///|
fn decimal_matches(
  expected : Array[@gda.Decimal],
  actual : Array[@gda.Decimal],
) -> Bool {
  expected.length() == actual.length() &&
  all_equal(expected.length(), i => expected[i].compare(actual[i]) == 0)
}

///|
fn decimal_text(values : Array[@gda.Decimal]) -> String {
  values.map(value => value.to_string()).join(",")
}

///|
fn decimal_spec(
  op : String,
  size : Int32,
  inputs : Array[InputRow],
  references : Array[InputRow],
) -> @runner.BenchSpec[
  Int32,
  DecimalCase,
  DecimalCase,
  Array[@gda.Decimal],
  Array[@gda.Decimal],
  Unit,
  Array[@gda.Decimal]?,
  Array[@gda.Decimal]?,
]? {
  let function = decimal_function(op)
  guard function is Some(f) else { return None }
  Some(
    @benchkit.immutable_bench(
      "external/decimal_gda/" + op,
      op,
      [size],
      digits => digits.to_string() + "digit",
      _ => {
        let prepared = decimal_case(size, inputs, references)
        if references.is_empty() {
          for i in 0..<prepared.count {
            prepared.expected[i] = f(
              prepared.a[i],
              prepared.b[i],
              prepared.context,
            )
          }
        }
        prepared
      },
      input => op + ":" + input.size.to_string() + ":" + input.count.to_string(),
      [
        @runner.Implementation::stateless("floating", "0.11.0", input => {
          for i in 0..<input.count {
            input.out[i] = f(input.a[i], input.b[i], input.context)
          }
          @model.OperationResult::completed(input.out, ())
        }),
        @runner.Implementation::stateless("null", "0.11.0", input => {
          for i in 0..<input.count {
            input.out[i] = (decimal_null.val)(
              input.expected[i],
              input.b[i],
              input.context,
            )
          }
          @model.OperationResult::completed(input.out, ())
        }),
      ],
      input => input.expected,
      decimal_matches,
      input => op + ":" + input.size.to_string(),
      decimal_text,
    ),
  )
}

///|
test "external input rows group by case" {
  let text =
    #|# external-baseline inputs
    #|binary add 53 1 0x1fp-3 -0x15p-2
    #|binary add 53 0 0x13p-3 0x11p-2
    #|decimal_gda sqrt 16 0 1234567890123456E-14
  let cases = parse_cases(text)
  assert_eq(cases.length(), 2)
  let add = cases.get("binary/add/53").unwrap()
  assert_eq(add.map(row => row.index), [0, 1])
  assert_eq(add[1].b, "-0x15p-2")
  assert_eq(cases.get("decimal_gda/sqrt/16").unwrap()[0].b, "")
  assert_eq(parse_case_id("binary/add/53"), Some(("binary", "add", 53)))
  assert_eq(parse_case_id("binary/add"), None)
}

///|
test "external binary and decimal_gda plans compile" {
  let binary = parse_cases(
      (
        #|binary add 8 0 0xa5p0 0x93p-1
        #|binary add 8 1 0xc1p-2 -0xb7p-3
      ),
    )
    .get("binary/add/8")
    .unwrap()
  ignore(binary_spec("add", 8, binary, []).unwrap().compile().unwrap())
  assert_true(binary_spec("sin", 8, binary, []) is Some(_))
  assert_true(binary_spec("nope", 8, binary, []) is None)
  let decimal = parse_cases("decimal_gda mul 4 0 1234E-3 5678E-2")
    .get("decimal_gda/mul/4")
    .unwrap()
  ignore(decimal_spec("mul", 4, decimal, []).unwrap().compile().unwrap())
  assert_true(decimal_spec("sin", 4, decimal, []) is None)
}

///|
test "external operand parsing is exact" {
  let value = binary_value("0xa5p-3", 8)
  let expected = @binary.BinFloat::from_double(165.0 / 8.0, precision=8)
  assert_eq(value.compare(expected), 0)
  let context = decimal_context(4)
  assert_eq(decimal_value("1234E-3", context).to_string(), "1.234")
}
