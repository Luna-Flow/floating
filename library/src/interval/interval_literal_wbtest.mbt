///|
fn lt_category(category : String) -> String {
  match category {
    "rational-denominator" =>
      "the denominator must be a positive natural number"
    "rational-numerator" => "the numerator must be an integer literal"
    "trailing" => "unexpected character after the interval"
    "uncertain-exponent" => "uncertain form exponent"
    "uncertain-base" => "the base point m needs at least one decimal digit"
    "uncertain-question" =>
      "the question mark must follow the base point m directly"
    "decoration-literal" => "decoration literal: expected trv, def, dac or com"
    "decoration-trailing" =>
      "unexpected characters after the decoration literal"
    "hex-exponent" => "hexadecimal number literal"
    "number" => "number literal"
    "structure" => "inf-sup form"
    "lower-inf" => "the lower bound may not be +inf"
    "upper-inf" => "the upper bound may not be -inf"
    "order" => "the lower bound is greater than the upper bound"
    "nai-decoration" => "[nai] takes no decoration"
    "nai-bare" => "[nai] is a decorated literal"
    "bare-decorated" => "a bare interval literal has no decoration"
    "empty-decoration" =>
      "the empty interval is only permitted with the decoration trv"
    "com-unbounded" => "the decoration com needs a bounded interval"
    other => other
  }
}

///|
fn lt_float(text : String, p : Int32) -> @bin_float.BinFloat {
  if text == "inf" {
    pos_inf(p)
  } else if text == "-inf" {
    neg_inf(p)
  } else if text == "0" {
    @bin_float.BinFloat::zero(precision=p)
  } else {
    match @bin_float.BinFloat::from_hex(text, p) {
      Ok(value) => value
      Err(error) => abort("bad table value " + text + ": " + error.message)
    }
  }
}

///|
fn lt_decoration(text : String) -> Decoration {
  match text {
    "trv" => Trv
    "def" => Def
    "dac" => Dac
    _ => Com
  }
}

///|
fn lt_same(a : @bin_float.BinFloat, b : @bin_float.BinFloat) -> Bool {
  a.compare(b) == 0
}

///|
/// Runs one entry of the table; returns an empty string on success, else the disagreement.
fn lt_run(
  entry : (String, Int32, Bool, String, String, String, String),
) -> String {
  let (text, p, decorated, kind, extra, lo, hi) = entry
  if decorated {
    match DecoratedInterval::from_string(text, precision=p) {
      Err(error) =>
        if kind == "err" && error.message.contains(lt_category(extra)) {
          ""
        } else {
          "\{text}: unexpected Err \{error.message}"
        }
      Ok(value) =>
        match kind {
          "err" => "\{text}: expected Err, got \{value.to_string()}"
          "nai" => if value.is_nai() { "" } else { "\{text}: expected NaI" }
          "empty" =>
            if value.is_empty() && value.decoration() == lt_decoration(extra) {
              ""
            } else {
              "\{text}: expected empty"
            }
          _ =>
            if !value.is_nai() &&
              value.decoration() == lt_decoration(extra) &&
              lt_same(value.interval().lo_, lt_float(lo, p)) &&
              lt_same(value.interval().hi_, lt_float(hi, p)) {
              ""
            } else {
              "\{text}: expected [\{lo}, \{hi}]_\{extra}, got \{value.to_string()}"
            }
        }
    }
  } else {
    match Interval::from_string(text, precision=p) {
      Err(error) =>
        if kind == "err" && error.message.contains(lt_category(extra)) {
          ""
        } else {
          "\{text}: unexpected Err \{error.message}"
        }
      Ok(value) =>
        match kind {
          "err" => "\{text}: expected Err, got \{value.to_string()}"
          "nai" => "\{text}: a bare literal cannot be NaI"
          "empty" =>
            if value.is_empty() {
              ""
            } else {
              "\{text}: expected empty"
            }
          _ =>
            if lt_same(value.lo_, lt_float(lo, p)) &&
              lt_same(value.hi_, lt_float(hi, p)) {
              ""
            } else {
              "\{text}: expected [\{lo}, \{hi}], got \{value.to_string()}"
            }
        }
    }
  }
}

///|
test "interval literals: the table of the independent oracle" {
  let mut failures = 0
  let mut total = 0
  for chunk in literal_tables() {
    for line in chunk.split("\n") {
      let text = line.to_owned()
      if text == "" {
        continue
      }
      let fields : Array[String] = []
      for field in text.split("\t") {
        fields.push(field.to_owned())
      }
      let literal = fields[0].replace_all(old="\\t", new="\t")
      let mut precision : Int32 = 0
      for c in fields[1] {
        precision = precision * 10 + (c.to_int() - '0'.to_int())
      }
      let entry = (
        literal,
        precision,
        fields[2] == "true",
        fields[3],
        fields[4],
        fields[5],
        fields[6],
      )
      total += 1
      let message = lt_run(entry)
      if message != "" {
        failures += 1
        if failures <= 20 {
          println("DISAGREE " + message)
        }
      }
    }
  }
  println("table entries: \{total}, disagreements: \{failures}")
  assert_true(failures == 0)
}

///|
fn lt_f(x : Double) -> @bin_float.BinFloat {
  @bin_float.BinFloat::from_double(x)
}

///|
/// Tables 9.4 and 12.1 of the standard, the exact values written as the rounded bounds.
test "interval literals: the vectors of Tables 9.4 and 12.1" {
  // dyadic literals are exact
  let r = Interval::from_string("[0x1.3p-1,]").unwrap()
  assert_true(r.lo_.compare(lt_f(19.0 / 32.0)) == 0)
  assert_true(is_pos_inf(r.hi_))
  let point = Interval::from_string("[3.5]").unwrap()
  assert_true(
    point.lo_.compare(lt_f(3.5)) == 0 && point.hi_.compare(lt_f(3.5)) == 0,
  )
  // 3.56?1 is [3.55, 3.57] exactly; the bounds are the two floats around each
  let u = Interval::from_string("3.56?1").unwrap()
  let ctx = @bin_float.BinaryContext::new(precision=53)
  assert_true(u.lo_.compare(lt_f(3.55)) <= 0)
  assert_true(u.lo_.next_up_ctx(ctx).0.compare(lt_f(3.55)) >= 0)
  assert_true(u.hi_.compare(lt_f(3.57)) >= 0)
  assert_true(u.hi_.next_down_ctx(ctx).0.compare(lt_f(3.57)) <= 0)
  // 3.56?1e2 is [355, 357], exact
  let scaled = Interval::from_string("3.56?1e2").unwrap()
  assert_true(
    scaled.lo_.compare(lt_f(355.0)) == 0 && scaled.hi_.compare(lt_f(357.0)) == 0,
  )
  // -10?12 is [-22, 2]; -10?u is [-10, -9.5]; -10?: [-10.5, -9.5]
  let wide = Interval::from_string("-10?12").unwrap()
  assert_true(
    wide.lo_.compare(lt_f(-22.0)) == 0 && wide.hi_.compare(lt_f(2.0)) == 0,
  )
  let up = Interval::from_string("-10?u").unwrap()
  assert_true(
    up.lo_.compare(lt_f(-10.0)) == 0 && up.hi_.compare(lt_f(-9.5)) == 0,
  )
  let half = Interval::from_string("-10?").unwrap()
  assert_true(
    half.lo_.compare(lt_f(-10.5)) == 0 && half.hi_.compare(lt_f(-9.5)) == 0,
  )
  // the unbounded uncertain forms
  let ray = Interval::from_string("-10??u").unwrap()
  assert_true(ray.lo_.compare(lt_f(-10.0)) == 0 && is_pos_inf(ray.hi_))
  assert_true(Interval::from_string("-10??").unwrap().is_entire())
  // special forms and spaces
  assert_true(Interval::from_string("[]").unwrap().is_empty())
  assert_true(Interval::from_string("[ EMPTY ]").unwrap().is_empty())
  assert_true(Interval::from_string("[,]").unwrap().is_entire())
  assert_true(Interval::from_string("[ entire ]").unwrap().is_entire())
  // the rational literal: [-Inf, 2/3] has the upper bound rounded up
  let rational = Interval::from_string("[-Inf, 2/3]").unwrap()
  assert_true(is_neg_inf(rational.lo_))
  assert_true(rational.hi_.compare(lt_f(2.0 / 3.0)) >= 0)
  assert_true(rational.hi_.next_down_ctx(ctx).0.compare(lt_f(2.0 / 3.0)) <= 0)
  // decorated: com, dac, NaI, and com made dac by an unbounded value
  let com = DecoratedInterval::from_string("3.56?1_com").unwrap()
  assert_true(com.decoration() == Com)
  assert_true(
    DecoratedInterval::from_string("[,]_dac").unwrap().decoration() == Dac,
  )
  assert_true(DecoratedInterval::from_string("[nai]").unwrap().is_nai())
  assert_true(
    DecoratedInterval::from_string("[1,2]").unwrap().decoration() == Com,
  )
  assert_true(
    DecoratedInterval::from_string("[1,]").unwrap().decoration() == Dac,
  )
}

///|
/// The failed call is `Err` and the message names the rule (the table asserts it for each
/// vector); a few by name here, with the standard's examples of strings that are not
/// literals.
test "interval literals: rejections name the broken rule" {
  let cases = [
    ("[1 000 000]", "inf-sup form"),
    ("[2,1]", "the lower bound is greater than the upper bound"),
    ("[5?1]", "number literal"),
    ("[ganz]", "number literal"),
    ("[1/0]", "the denominator must be a positive natural number"),
    ("[0x1.8]", "hexadecimal number literal: the exponent field p"),
    ("[0x]", "the significand needs at least one hexadecimal digit"),
    ("[inf]", "the lower bound may not be +inf"),
    ("[-inf]", "the upper bound may not be -inf"),
    ("[1,inf]x", "unexpected character after the interval"),
    ("[]_ill", "decoration literal: expected trv, def, dac or com"),
    ("[nai]_com", "[nai] takes no decoration"),
    ("5???u", "unexpected character after the interval"),
    ("[1,2]_com", "a bare interval literal has no decoration"),
    ("", "a bare interval literal is an inf-sup form"),
  ]
  for entry in cases {
    let (text, reason) = entry
    match Interval::from_string(text) {
      Ok(value) => fail("\{text} should fail, got \{value.to_string()}")
      Err(error) => {
        assert_true(error.is_parse_error())
        assert_true(
          error.message.contains(reason),
          msg=text + ": " + error.message,
        )
      }
    }
  }
  for
    entry in [
      ("[]_def", "the empty interval is only permitted with the decoration trv"),
      ("[0,inf]_com", "the decoration com needs a bounded interval"),
      ("[entire]_com", "the decoration com needs a bounded interval"),
    ] {
    let (text, reason) = entry
    match DecoratedInterval::from_string(text) {
      Ok(value) => fail("\{text} should fail, got \{value.to_string()}")
      Err(error) =>
        assert_true(
          error.message.contains(reason),
          msg=text + ": " + error.message,
        )
    }
  }
  // [nai] is NaI for the decorated form only
  assert_true(Interval::from_string("[nai]") is Err(_))
  // the precision is checked
  assert_true(Interval::from_string("[1]", precision=0) is Err(_))
}

///|
/// A string longer than `interval_literal_max_length` gives Entire (12.11.5), decorated
/// `dac` or the `trv` / `def` the literal ends with.
test "interval literals: the length limit gives Entire" {
  let digits = String::make(interval_literal_max_length.to_int(), '1')
  let long = "[" + digits + "]"
  assert_true(Interval::from_string(long).unwrap().is_entire())
  assert_true(DecoratedInterval::from_string(long).unwrap().decoration() == Dac)
  assert_true(
    DecoratedInterval::from_string(long + "_def").unwrap().decoration() == Def,
  )
  assert_true(
    DecoratedInterval::from_string(long + "_trv").unwrap().decoration() == Trv,
  )
  // a string at the limit is parsed
  let at_limit = "[" +
    String::make(interval_literal_max_length.to_int() - 2, '1') +
    "]"
  assert_true(!Interval::from_string(at_limit).unwrap().is_entire())
}

///|
/// Exponents beyond the range are decided without forming the value, and the bounds of
/// the result stay outward.
test "interval literals: huge exponents" {
  let ctx = @bin_float.BinaryContext::new(precision=53)
  let largest = pw_largest(53)
  let smallest = pw_smallest(53)
  ignore(ctx)
  let big = Interval::from_string("[1e400000000, 1e400000001]").unwrap()
  assert_true(big.lo_.compare(largest) == 0 && is_pos_inf(big.hi_))
  let tiny = Interval::from_string("[1e-400000000]").unwrap()
  assert_true(tiny.lo_.is_zero() && tiny.hi_.compare(smallest) == 0)
  let neg = Interval::from_string("[-1e400000000, -1e-400000000]").unwrap()
  assert_true(is_neg_inf(neg.lo_) && neg.hi_.is_zero())
  // a saturated exponent field
  let saturated = Interval::from_string("[1e999999999999999999999]").unwrap()
  assert_true(saturated.lo_.compare(largest) == 0 && is_pos_inf(saturated.hi_))
  assert_true(
    Interval::from_string("[0x1p+2000000000]").unwrap().lo_.compare(largest) ==
    0,
  )
  // two bounds of the same radix are compared exactly whatever the exponent
  assert_true(Interval::from_string("[2e100000, 1e100001]") is Ok(_))
  assert_true(Interval::from_string("[1e100001, 2e100000]") is Err(_))
}

///|
/// 12.12.7 case (b): two finite bounds of different radices, equal to 100 bits and with an
/// exponent beyond 65,536, cannot be ordered; the result contains both bounds (the first
/// is 10^65537, the second is below it by 2^-100 relative, so the literal is in fact not
/// an interval).
test "interval literals: the order of two bounds of different radices that is undecided" {
  let lower = "1e65537"
  let upper = "0x1266242e06c1b921f4e432aa84p217609"
  let both = Interval::from_string("[" + lower + "," + upper + "]").unwrap()
  assert_true(!both.is_empty())
  // Expected bounds written out by `tools/interval_literal_oracle.py` (level A): both numbers
  // are equal to 53 bits, so the result is the hull of the two outward roundings, which are
  // the same interval; the single bounds are rows of the oracle table too.
  let lo = @bin_float.BinFloat::from_hex("0x1266242e06c1b9p217657", 53).unwrap()
  let hi = @bin_float.BinFloat::from_hex("0x1266242e06c1bap217657", 53).unwrap()
  assert_eq(both.lo_.compare(lo), 0)
  assert_eq(both.hi_.compare(hi), 0)
  assert_eq(
    Interval::from_string("[" + lower + "]").unwrap().lo_.compare(lo),
    0,
  )
  assert_eq(
    Interval::from_string("[" + upper + "]").unwrap().hi_.compare(hi),
    0,
  )
  // exponents within the limit are decided exactly: the same pair at 10^1000 is Err
  assert_true(Interval::from_string("[1e1000, 0x1p+3322]") is Ok(_))
  assert_true(Interval::from_string("[1e1000, 0x1p+3321]") is Err(_))
}

///|
/// The two converters (`from_string_ctx`, `from_hex_ctx`) at and beyond every limit of their
/// exponent: 2^31 - 1, 2^31, 10^10 and the saturation value 10^15, each sign, decimal and
/// hexadecimal, each as a point. A positive literal gives `[largest finite, +inf]` or
/// `[0, smallest stored]` (negated for a negative literal), never an infinite lower bound.
test "interval literals: exponents at and beyond the limits of the converters" {
  for p in [24, 53, 113] {
    let largest = pw_largest(p)
    let smallest = pw_smallest(p)
    for
      exponent in [
        "2147483647", "2147483648", "10000000000", "1000000000000000", "999999999999999999999",
      ] {
      for kind in ["dec", "hex"] {
        let mantissa = if kind == "dec" { "1" } else { "0x1" }
        let marker = if kind == "dec" { "e" } else { "p" }
        // a positive huge exponent
        let big = Interval::from_string(
          "[" + mantissa + marker + exponent + "]",
          precision=p,
        ).unwrap()
        assert_true(big.lo_.compare(largest) == 0 && is_pos_inf(big.hi_))
        let neg_big = Interval::from_string(
          "[-" + mantissa + marker + exponent + "]",
          precision=p,
        ).unwrap()
        assert_true(
          is_neg_inf(neg_big.lo_) && neg_big.hi_.compare(largest.neg()) == 0,
        )
        // a negative huge exponent
        let tiny = Interval::from_string(
          "[" + mantissa + marker + "-" + exponent + "]",
          precision=p,
        ).unwrap()
        assert_true(tiny.lo_.is_zero() && tiny.hi_.compare(smallest) == 0)
        let neg_tiny = Interval::from_string(
          "[-" + mantissa + marker + "-" + exponent + "]",
          precision=p,
        ).unwrap()
        assert_true(
          neg_tiny.lo_.compare(smallest.neg()) == 0 && neg_tiny.hi_.is_zero(),
        )
        if p == 53 &&
          (exponent == "2147483647" || exponent == "1000000000000000") {
          println(
            "EXP \{kind} e\{exponent}: [\{big.lo_.to_string()}, \{big.hi_.to_string()}] neg [\{neg_big.lo_.to_string()}, \{neg_big.hi_.to_string()}] tiny [\{tiny.lo_.to_string()}, \{tiny.hi_.to_string()}] neg_tiny [\{neg_tiny.lo_.to_string()}, \{neg_tiny.hi_.to_string()}]",
          )
        }
      }
    }
  }
}
