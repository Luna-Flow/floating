// The bottom of the exponent range and the far margins, against the table of
// `tools/interval_bottom_oracle.py` (Python integers, level A). A number of the table is written
// `[-]0x<tokens>p<exponent>`; a token is a run of hexadecimal digits or `<digit>*<count>`, a run
// of equal digits.

///|
fn bt_digits(tokens : String) -> String {
  let mut out = ""
  for token in tokens.split(",") {
    let token = token.to_owned()
    match token.find("*") {
      Some(star) => {
        let digit = token[:star].to_owned()
        let count = bt_count(token[star + 1:].to_owned())
        for _ in 0..<count {
          out = out + digit
        }
      }
      None => out = out + token
    }
  }
  out
}

///|
fn bt_count(text : String) -> Int32 {
  let mut n = 0
  for c in text {
    n = n * 10 + (c.to_int() - '0'.to_int())
  }
  n
}

///|
/// A number of the table, exactly (the precision of the result is larger than any run).
fn bt_number(text : String) -> @binary.Binary {
  let negative = text.has_prefix("-")
  let body = if negative { text[1:].to_owned() } else { text }
  // body is "0x<tokens>p<exponent>"
  let p = body.find("p").unwrap()
  let tokens = body[2:p].to_owned()
  let rest = body[p:].to_owned()
  let value = @binary.Binary::from_hex("0x" + bt_digits(tokens) + rest, 300000).unwrap()
  if negative {
    value.neg()
  } else {
    value
  }
}

///|
fn bt_equal(expected : @binary.Binary, got : @binary.Binary) -> Bool {
  if expected.is_zero() {
    got.is_zero()
  } else {
    got.compare(expected) == 0
  }
}

///|
// oracle: A
// source: the midpoint, radius and width of 1,630 intervals at the bottom of the exponent range (bounds c * 2^e with e from e_min - 70 to e_min + 19, rounded outward to p = 24, 53, 113, 128 bits by the constructor, a zero bound with the smallest stored value, the precision limit, the interval of the issue 579 and negative bounds), computed with Python integers from IEEE 1788-2015 12.12.8 (tools/interval_bottom_oracle.py, table bottom_table_wbtest.mbt); this replaces the comparisons with a sum in a context of 600 bits halved and rounded by with_precision (level B), which shared the directed rounding of Binary
// shares: Binary::from_hex, String::split and a run expander read the table; Interval::from_bounds, Binary::from_hex build the operands
test "midpoint, radius and width at the bottom of the range are those of the exact hull" {
  let mut count = 0
  for table in bottom_tables() {
    for line in table.split("\n") {
      let line = line.to_owned()
      if !line.has_prefix("mid ") {
        continue
      }
      let f = line.split(" ").map(fn(s) { s.to_owned() }).collect()
      let precision = bt_count(f[3])
      let x = Interval::from_bounds(
        bt_number(f[1]),
        bt_number(f[2]),
        precision~,
      )
      assert_true(bt_equal(bt_number(f[4]), x.midpoint()), msg=line)
      assert_true(bt_equal(bt_number(f[5]), x.radius()), msg=line)
      assert_true(bt_equal(bt_number(f[6]), x.width()), msg=line)
      count += 1
    }
  }
  assert_eq(count, 1630)
}

///|
// oracle: A
// source: the endpoints c - r (rounded down) and c + r (rounded up), and the midpoint of that interval, for 3,802 centres and radii (near the bottom of the range with 1 to 60 bit centres, centres of 129 to 200 bits with radii of 1 to 11 bytes, and away from the bottom with 20 bit centres at exponents -200 to 199), at p = 24, 53, 64, 113, 128, the first case of issue 578 and the center of 152 bits, computed with Python integers from IEEE 1788-2015 12.12.7 (tools/interval_bottom_oracle.py); the interval contains its center by construction, which the rows state through the endpoints; this replaces comparisons with a sum in a context of 600 bits rounded by with_precision (level B)
// shares: Binary::from_hex, String::split and a run expander read the table; Interval::from_midpoint_radius is the code under test
test "from_midpoint_radius gives the hull of the center minus and plus the radius, and its midpoint" {
  let mut count = 0
  for table in bottom_tables() {
    for line in table.split("\n") {
      let line = line.to_owned()
      if !line.has_prefix("mpr ") {
        continue
      }
      let f = line.split(" ").map(fn(s) { s.to_owned() }).collect()
      let precision = bt_count(f[3])
      let c = bt_number(f[1])
      let x = Interval::from_midpoint_radius(c, bt_number(f[2]), precision~)
      assert_true(bt_equal(bt_number(f[4]), x.lower_bound()), msg=line)
      assert_true(bt_equal(bt_number(f[5]), x.upper_bound()), msg=line)
      assert_true(bt_equal(bt_number(f[6]), x.midpoint()), msg=line)
      assert_true(x.is_member(c), msg=line)
      count += 1
    }
  }
  assert_eq(count, 3802)
}

///|
// oracle: A
// source: the hull of x * y + z for 1,501 triples of intervals near the bottom of the range (bounds of 1 to 40 bits at exponents e_min - 60 to e_min - 1, multipliers of 6 bits near 1), the operands rounded outward to p = 53, 113, 128 bits by the constructor, the products and the sum exact in Python integers and one outward rounding at the end, from IEEE 1788-2015 12.10.2 (tools/interval_bottom_oracle.py); the first row is the fma of issue 607, t * 1 + t = 2t with t = 2^(e_min - 3); this replaces comparisons with products and sums in a context of 600 bits rounded by with_precision (level B)
// shares: Binary::from_hex, String::split and a run expander read the table; Interval::from_bounds builds the operands
test "fma near the bottom of the range is the tightest interval" {
  let mut count = 0
  for table in bottom_tables() {
    for line in table.split("\n") {
      let line = line.to_owned()
      if !line.has_prefix("fma ") {
        continue
      }
      let f = line.split(" ").map(fn(s) { s.to_owned() }).collect()
      let precision = bt_count(f[1])
      let pair = fn(i : Int32) {
        Interval::from_bounds(bt_number(f[i]), bt_number(f[i + 1]), precision~)
      }
      let r = pair(2).fma(pair(4), pair(6))
      assert_true(bt_equal(bt_number(f[8]), r.lower_bound()), msg=line)
      assert_true(bt_equal(bt_number(f[9]), r.upper_bound()), msg=line)
      count += 1
    }
  }
  assert_eq(count, 1501)
}

///|
// oracle: A
// source: the exact sum of two numbers of 1 to 40 bits at exponents e_min - 60 to e_min + 9 and its half, 800 rows computed with Python integers (tools/interval_bottom_oracle.py); this replaces comparisons with add_ctx in a context of 600 bits (level B)
// shares: Binary::from_hex, String::split and a run expander read the table
test "exact_add_full and halve give the exact sum of two numbers at the bottom and its half" {
  let mut count = 0
  for table in bottom_tables() {
    for line in table.split("\n") {
      let line = line.to_owned()
      if !line.has_prefix("sum ") {
        continue
      }
      let f = line.split(" ").map(fn(s) { s.to_owned() }).collect()
      let s = exact_add_full(bt_number(f[1]), bt_number(f[2]))
      assert_true(bt_equal(bt_number(f[3]), s), msg=line)
      assert_true(bt_equal(bt_number(f[4]), halve(s)), msg=line)
      count += 1
    }
  }
  assert_eq(count, 800)
}

///|
// oracle: A
// source: the centre (lo + hi) / 2 of [5, 3 * 2^span], [-3 * 2^span, 5], [-3 * 2^span, -5] and [-5, 3 * 2^span] for span 10, 100, 65,535, 65,536, 65,600, 100,000 and 131,000, interval precisions 24, 53 and 200 and context precisions 53, 65,535, 65,536, 65,537, 70,000 and 140,000, and [1, 2^100000] at 200,000 bits, rounded once to nearest even at the context precision, computed with Python integers (tools/interval_bottom_oracle.py); the results are written as runs of equal hexadecimal digits; this replaces the comparisons with a sum in a context of span + 72 bits halved and rounded by with_precision (level B)
// shares: Binary::from_hex, String::split and a run expander read the table; Interval::from_bounds builds the operands
test "midpoint_ctx around the margin of the far addend is the centre rounded once" {
  let mut count = 0
  for table in bottom_tables() {
    for line in table.split("\n") {
      let line = line.to_owned()
      if !line.has_prefix("ctx ") {
        continue
      }
      let f = line.split(" ").map(fn(s) { s.to_owned() }).collect()
      let x = Interval::from_bounds(
        bt_number(f[3]),
        bt_number(f[4]),
        precision=bt_count(f[1]),
      )
      let (m, _) = x.midpoint_ctx(
        IntervalContext::new(precision=bt_count(f[2])),
      )
      assert_true(bt_equal(bt_number(f[5]), m), msg=line)
      count += 1
    }
  }
  assert_eq(count, 505)
}
