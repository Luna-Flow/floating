// Text output against the independent oracle `tools/interval_text_oracle.py` (level A: expected
// texts computed with exact fractions from the rules of the documentation and of IEEE
// 1788-2015 13.3 and 13.4, with no `interval` code; the oracle also checks containment of every
// text against its bound as exact fractions). The table is interval_text_table_wbtest.mbt.

///|
fn oracle_bound(text : String, precision : Int32) -> @bin_float.BinFloat {
  if text == "inf" {
    @bin_float.BinFloat::inf(@def.Sign::Positive, precision~)
  } else if text == "-inf" {
    @bin_float.BinFloat::inf(@def.Sign::Negative, precision~)
  } else {
    @bin_float.BinFloat::from_hex(text, precision).unwrap()
  }
}

///|
test "Show and to_exact_string agree with the independent oracle on every row of the table" {
  let mut count = 0
  for table in text_tables() {
    for line in table.split("\n") {
      let line = line.to_owned()
      if line == "" {
        continue
      }
      let fields = line.split("\t").map(fn(f) { f.to_owned() }).collect()
      let mut precision = 0
      for c in fields[2] {
        precision = precision * 10 + (c.to_int() - '0'.to_int())
      }
      let x = Interval::from_bounds(
        oracle_bound(fields[0], precision),
        oracle_bound(fields[1], precision),
        precision~,
      )
      assert_eq(x.to_string(), fields[3], msg=line)
      assert_eq(x.to_exact_string(), fields[4], msg=line)
      // the exact text is read back identically
      let back = Interval::from_exact_string(fields[4], precision~).unwrap()
      assert_true(x.identical(back), msg=line)
      count += 1
    }
  }
  assert_eq(count, 2570)
}

///|
/// `from_exact_string` against the oracle's reader (`Fraction`, level A): every text with its
/// precision, the verdict (a text that fits is read, one that does not fit or is not an exact
/// text is refused) and, for the accepted ones, the canonical exact text of the result. The texts
/// have fractional mantissas, leading and trailing zeros, upper case, `0x.8p1`, mantissas longer
/// than the precision whose low digits are zero, reversed bounds, decimal bounds and a bound that
/// is one bit too wide.
test "from_exact_string agrees with the independent oracle on every row of the exact-read table" {
  let mut accepted = 0
  let mut refused = 0
  for table in exact_read_tables() {
    for line in table.split("\n") {
      let line = line.to_owned()
      if line == "" {
        continue
      }
      let fields = line.split("\t").map(fn(f) { f.to_owned() }).collect()
      let mut precision = 0
      for c in fields[1] {
        precision = precision * 10 + (c.to_int() - '0'.to_int())
      }
      match Interval::from_exact_string(fields[0], precision~) {
        Ok(x) => {
          assert_eq(fields[2], "ok", msg=line)
          assert_eq(x.to_exact_string(), fields[3], msg=line)
          accepted += 1
        }
        Err(_) => {
          assert_eq(fields[2], "err", msg=line)
          refused += 1
        }
      }
    }
  }
  assert_eq(accepted, 1406)
  assert_eq(refused, 214)
}

///|
/// `Show` and `to_exact_string` of intervals whose bounds have more bits than the precision
/// (level A: the oracle's expected texts; the intervals are built by `from_exact_string`, which
/// the exact-read table above checks against the oracle's reader, not by a rounding constructor).
/// The oracle also checks the containment of every `Show` text against its bound.
test "Show and to_exact_string of intervals with ends wider than the precision agree with the oracle" {
  let mut count = 0
  for table in wide_text_tables() {
    for line in table.split("\n") {
      let line = line.to_owned()
      if line == "" {
        continue
      }
      let fields = line.split("\t").map(fn(f) { f.to_owned() }).collect()
      let mut precision = 0
      for c in fields[2] {
        precision = precision * 10 + (c.to_int() - '0'.to_int())
      }
      let x = Interval::from_exact_string(
        "[" + fields[0] + ", " + fields[1] + "]",
        precision~,
      ).unwrap()
      assert_eq(x.precision(), precision, msg=line)
      assert_eq(x.to_string(), fields[3], msg=line)
      assert_eq(x.to_exact_string(), fields[4], msg=line)
      count += 1
    }
  }
  assert_eq(count, 400)
}
