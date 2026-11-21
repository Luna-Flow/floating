///|
/// `testdata/context_vectors.txt` against the library constructors. The Python
/// rules (`tools/context_rules.py`) are tested against the same file, so a
/// change of a limit or of a rule in one place fails a test until the other
/// agrees. A vector that the constructors cannot express (an `e_min` that is not
/// `1 - e_max`, clamp 0 or tininess `a` for `decimal`, a rounding outside their
/// type) is skipped here and checked by the Python rules only.
struct ContextVector {
  standard : String
  precision : Int32
  e_min : Int32?
  e_max : Int32?
  rounding : String
  clamp : Int32?
  tininess : String
  legal : Bool
  line : String
}

///|
fn[T, E] vec_ok(result : Result[T, E]) -> Bool {
  match result {
    Ok(_) => true
    Err(_) => false
  }
}

///|
fn vector_int(text : String) -> Int32? {
  if text == "-" {
    None
  } else {
    Some(
      @string.parse_int(text) catch {
        _ => abort("not an integer: " + text)
      },
    )
  }
}

///|
fn parse_context_vectors(text : String) -> Array[ContextVector] {
  let vectors : Array[ContextVector] = []
  for raw in text.split("\n") {
    let body = match raw.find("#") {
      Some(index) => raw[:index].to_owned()
      None => raw.to_owned()
    }
    let fields : Array[String] = []
    for field in body.split(" ") {
      let trimmed = field.trim().to_owned()
      if !trimmed.is_empty() {
        fields.push(trimmed)
      }
    }
    if fields.length() == 0 {
      continue
    }
    guard fields.length() == 8 else {
      abort("a vector has 8 columns: " + raw.to_owned())
    }
    vectors.push({
      standard: fields[0],
      precision: vector_int(fields[1]).unwrap(),
      e_min: vector_int(fields[2]),
      e_max: vector_int(fields[3]),
      rounding: fields[4],
      clamp: vector_int(fields[5]),
      tininess: fields[6],
      legal: fields[7] == "legal",
      line: body.trim().to_owned(),
    })
  }
  vectors
}

///|
/// `Some(ok)` when the constructor can be asked the question of the vector,
/// `None` when the vector depends on something the constructor does not have.
fn context_vector_accepted(vector : ContextVector) -> Bool? {
  match vector.standard {
    "binary" => {
      let rounding : @binary.BinaryRoundingMode = match vector.rounding {
        "n" => RoundTiesToEven
        "na" => RoundTiesToAway
        "z" => RoundTowardZero
        "u" => RoundTowardPositive
        "d" => RoundTowardNegative
        _ => return None
      }
      let tininess : @binary.TininessDetection = match vector.tininess {
        "a" => AfterRounding
        "b" => BeforeRounding
        _ => return None
      }
      match (vector.e_min, vector.e_max) {
        (None, None) =>
          Some(
            @binary.BinaryContext::try_new(
              precision=vector.precision,
              rounding~,
              tininess~,
            )
            |> vec_ok,
          )
        (None, Some(e_max)) =>
          Some(
            @binary.BinaryContext::try_new(
              precision=vector.precision,
              e_max~,
              rounding~,
              tininess~,
            )
            |> vec_ok,
          )
        (Some(e_min), Some(e_max)) if e_min == 1 - e_max =>
          Some(
            @binary.BinaryContext::try_new(
              precision=vector.precision,
              e_max~,
              rounding~,
              tininess~,
            )
            |> vec_ok,
          )
        _ => None
      }
    }
    "decimal" => {
      let rounding : @decimal.DecimalRoundingMode = match vector.rounding {
        "half_even" => RoundTiesToEven
        "half_up" => RoundTiesToAway
        "down" => RoundTowardZero
        "ceiling" => RoundTowardPositive
        "floor" => RoundTowardNegative
        _ => return None
      }
      match (vector.e_min, vector.e_max, vector.clamp) {
        (Some(e_min), Some(e_max), Some(1)) if e_min == 1 - e_max &&
          vector.tininess == "b" =>
          Some(
            @decimal.DecimalContext::try_new(
              precision=vector.precision,
              e_max~,
              rounding~,
            )
            |> vec_ok,
          )
        _ => None
      }
    }
    "gda" => {
      let rounding : @decimal_gda.GdaRoundingMode = match vector.rounding {
        "half_even" => HalfEven
        "half_up" => HalfUp
        "half_down" => HalfDown
        "down" => Down
        "ceiling" => Ceiling
        "floor" => Floor
        "up" => Up
        "05up" => ZeroFiveUp
        _ => return None
      }
      match (vector.e_min, vector.e_max, vector.clamp) {
        (Some(e_min), Some(e_max), Some(clamp)) =>
          Some(
            @decimal_gda.GdaContext::try_new(
              precision=vector.precision,
              rounding~,
              e_min~,
              e_max~,
              clamp=clamp != 0,
            )
            |> vec_ok,
          )
        _ => None
      }
    }
    _ => abort("unknown standard " + vector.standard)
  }
}

///|
// oracle: A, S
// source: testdata/context_vectors.txt, written by hand from IEEE 754-2019 3.3, 3.7, 4.3, 7.5 and GDA 1.70 page 10 (A
//   for the shape rules: e_min = 1 - e_max, the rounding attributes, clamp and tininess); the limit rows (268435456,
//   1073741823, 999999999) are the library own limits typed into the table (S); 57 rows are checked, 12 are skipped
//   for columns the constructors do not have
// shares: binary_precision_max, binary_value_e_max, decimal_precision_max, decimal_context_e_max_limit (the limits),
//   tools/context_rules.py is a second reader of the same table
test "the library constructors agree with testdata/context_vectors.txt" {
  let vectors = parse_context_vectors(
    @fs.read_file_to_string("../testdata/context_vectors.txt") catch {
      _ => abort("cannot read ../testdata/context_vectors.txt")
    },
  )
  let mut checked = 0
  let mut skipped = 0
  let disagreements : Array[String] = []
  for vector in vectors {
    match context_vector_accepted(vector) {
      Some(accepted) => {
        checked += 1
        if accepted != vector.legal {
          disagreements.push(vector.line)
        }
      }
      None => skipped += 1
    }
  }
  assert_true(disagreements.is_empty(), msg=disagreements.join(" | "))
  // Stated numbers (the list is `testdata/context_vectors.txt`, 69 vectors):
  // 57 are checked against the constructors and 12 are skipped by name because
  // the constructors lack a column of the vector (see the header of the file).
  // The numbers are exact on purpose: a vector that turns from checked into
  // skipped, or a deleted line, must change these numbers in the same commit,
  // not pass a lower bound. Oracle of the verdicts (level A): the file, written
  // from IEEE 754-2019 3.3 and 3.7 and GDA 1.70 page 10; its limits are the
  // library's own constants (hand-copied: see the test of the constants in
  // `consistency/oracle_constants_wbtest.mbt`).
  assert_eq(vectors.length(), 69)
  assert_eq(checked, 57)
  assert_eq(skipped, 12)
}
