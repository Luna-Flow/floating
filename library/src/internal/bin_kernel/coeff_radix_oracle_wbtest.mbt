///|
/// Oracle of the radix conversions of `Coeff`: level A. The expected text of a
/// value and the expected value of a text are computed by `tools/kernel_oracle.py`
/// with CPython integers (`divmod` by a power of the radix, `int(text, radix)`) and
/// folded into FNV-1a digests; nothing of this repository takes part. The
/// operands are built from the row and verified against CPython digests before
/// the route runs: a value is a `regression_value` operand, `radix^k + delta` or
/// `(radix^b - 1) radix^a + delta` (long runs of the digit `radix - 1` followed
/// by zeros, `radix^k - 1` all nines, `radix^k + 1` a long run of zeros), built
/// with `pow_nat`, `mul`, `add` and `sub_checked`, whose results the digest of
/// the row checks; a text is a list of runs of one digit and of pseudo-random
/// digits, and the digest of the text is checked as well.
///
/// Routes, and how it is known that a row takes one (`coeff_nonjs.mbt`,
/// `Coeff::to_radix_string` and `Coeff::parse`): a radix that is a power of two
/// goes to the shift routines (`fmt` and `parse` only); other radices format by
/// dividing a copy of the limbs chunk by chunk below
/// `bin_coeff_radix_format_dc_words` (3,072 limbs) and by divide and conquer from
/// there, and parse with an in-place loop below `bin_coeff_radix_parse_dc_chunks`
/// (4,608 chunks of `bin_coeff_radix_chunk` digits: 41,472 decimal digits) and by
/// divide and conquer from there. The rows have values of 3,071, 3,072 and 3,073
/// limbs and texts of 4,607, 4,608 and 4,609 chunks (and one digit more than
/// the previous chunk count), so each production route runs on both sides of
/// its threshold; the functions of both routes are also called directly
/// (`fmt_ip`, `fmt_dc`, `parse_ip`, `parse_dc`) at the sizes of the default
/// test, where production takes the other one, with the chunk width and power
/// of `bin_coeff_radix_chunk`, so both are checked against CPython at
/// every size. The divide-and-conquer parse recurses down to 32 chunks, which
/// the 33 and 34 chunk rows cross.

///|
fn radix_oracle_digit_char(digit : Int32) -> Char {
  if digit < 10 {
    Int32::unsafe_to_char(48 + digit)
  } else {
    Int32::unsafe_to_char(97 + digit - 10)
  }
}

///|
fn radix_oracle_text(
  radix : Int32,
  spec : String,
  random : RegressionRandom,
) -> String {
  let builder = StringBuilder()
  for segment in oracle_split(spec, ',') {
    let parts = oracle_split(segment, '*')
    let count = oracle_int(parts[1])
    for _ in 0..<count {
      if parts[0] == "r" {
        let digit = (random.next() % radix.to_uint64()).to_int()
        builder.write_char(radix_oracle_digit_char(digit))
      } else {
        builder.write_char(parts[0][0].to_int().unsafe_to_char())
      }
    }
  }
  builder.to_string()
}

///|
fn radix_oracle_value(
  kind : String,
  radix : Int32,
  spec : String,
  delta : Int32,
  random : RegressionRandom,
) -> Coeff raise {
  let base = Coeff::from_uint64(radix.to_uint64())
  let raw = match kind {
    "v" => {
      let parts = oracle_split(spec, '.')
      regression_value(random, oracle_int(parts[0]), oracle_int(parts[1]))
    }
    "pw" => base.pow_nat(oracle_int(spec).reinterpret_as_uint())
    _ => {
      let parts = oracle_split(spec, '.')
      let nines = match
        base
        .pow_nat(oracle_int(parts[1]).reinterpret_as_uint())
        .sub_checked(Coeff::one()) {
        Ok(value) => value
        Err(_) => fail("radix^nines below one")
      }
      nines.mul(base.pow_nat(oracle_int(parts[0]).reinterpret_as_uint()))
    }
  }
  if delta < 0 {
    match raw.sub_checked(Coeff::one()) {
      Ok(value) => value
      Err(_) => fail("a value below one")
    }
  } else if delta > 0 {
    raw.add(Coeff::one())
  } else {
    raw
  }
}

///|
fn radix_oracle_run(row : Array[String]) -> Unit raise {
  let name = row[0]
  let route = row[1]
  let radix = oracle_int(row[2])
  let kind = row[3]
  let seed = oracle_u64(row[6])
  let check = oracle_u64(row[8])
  let expected = oracle_u64(row[9])
  let random : RegressionRandom = { regression_state: seed, }
  let (chunk_width, chunk_power) = bin_coeff_radix_chunk(radix)
  let basis = 0xcbf29ce484222325UL
  if kind == "t" {
    let text = radix_oracle_text(radix, row[4], random)
    if regression_mix_string(basis, text) != check {
      fail("\{name}: the text differs from CPython")
    }
    let value = match route {
      "parse" => Coeff::parse(text, radix~).unwrap()
      _ => {
        let chunks = bin_coeff_parse_radix_chunks(text, 0, radix, chunk_width).unwrap()
        if route == "parse_ip" {
          bin_coeff_parse_chunks_in_place(chunks, chunk_power)
        } else {
          bin_coeff_parse_chunks_divide_and_conquer(
            chunks,
            0,
            chunks.length(),
            chunk_power,
          ).value
        }
      }
    }
    if regression_mix(basis, value) != expected {
      fail("\{name}: the parsed value differs from CPython (route \{route})")
    }
    return
  }
  let value = radix_oracle_value(
    kind,
    radix,
    row[4],
    oracle_signed(row[5]),
    random,
  )
  if regression_mix(basis, value) != check {
    fail("\{name}: the value differs from CPython")
  }
  let text = match route {
    "fmt" => value.to_radix_string(radix)
    "fmt_ip" =>
      bin_coeff_to_radix_in_place(value, radix, chunk_width, chunk_power)
    _ =>
      bin_coeff_to_radix_divide_and_conquer(
        value, radix, chunk_width, chunk_power,
      )
  }
  if regression_mix_string(basis, text) != expected {
    fail("\{name}: the text differs from CPython (route \{route})")
  }
}

///|
fn radix_oracle_run_where(where_ : String) -> Int32 raise {
  let mut total = 0
  for row in oracle_rows(radix_oracle_table) {
    if row[7] == where_ {
      total += 1
      radix_oracle_run(row)
    }
  }
  total
}

///|
// oracle: A
// source: texts and values computed by tools/kernel_oracle.py with CPython integers (divmod, int(text, radix)); operands verified by CPython digests before use
// shares: the construction of the operands (regression_value, pow_nat, mul, add, sub_checked) and of the texts, verified per row against the CPython digest of the value or the text before the route is called
test "oracle: radix conversion against CPython, values up to 200 limbs and texts up to 200 chunks" {
  assert_true(radix_oracle_run_where("pr") > 1000)
}

///|
// oracle: A
// source: texts and values computed by tools/kernel_oracle.py with CPython integers (divmod, int(text, radix)); operands verified by CPython digests before use
// shares: the construction of the operands (regression_value, pow_nat, mul, add, sub_checked) and of the texts, verified per row against the CPython digest of the value or the text before the route is called
#skip("binary gate stage: values of 3,071 to 3,073 limbs and texts of 4,607 to 4,609 chunks, both sides of the divide-and-conquer thresholds")
test "oracle: radix conversion against CPython, both sides of the divide-and-conquer thresholds" {
  assert_true(radix_oracle_run_where("gate") > 100)
}
