///|
fn issue194_flags(flags : DecimalFlags) -> String {
  (if flags.inexact { "x" } else { "." }) +
  (if flags.rounded { "r" } else { "." }) +
  (if flags.overflow { "o" } else { "." }) +
  (if flags.underflow { "u" } else { "." }) +
  (if flags.subnormal { "s" } else { "." }) +
  (if flags.clamped { "c" } else { "." })
}

///|
fn issue194_int(text : String) -> Int32 {
  let mut value = 0
  let mut negative = false
  for ch in text {
    if ch == '-' {
      negative = true
    } else {
      value = value * 10 + (ch.to_int() - '0'.to_int())
    }
  }
  if negative {
    -value
  } else {
    value
  }
}

///|
/// IEEE 754-2019 §9.2.2: `Q(pow(x, y)) = floor(y * Q(x))` and
/// `Q(pown(x, n)) = floor(n * Q(x))`; §5.2: an exact result takes the cohort
/// member closest to the preferred exponent that represents it. Rows are
/// (operation, x, y or n, expected, flags), decimal64 unless noted.
test "pow and pown results take the preferred exponent (#194)" {
  let ctx = DecimalContext::decimal64()
  let rows : Array[(String, String, String, String, String)] = [
    ("pown", "1.00", "2", "1.0000", "......"),
    ("pown", "-1.0", "3", "-1.000", "......"),
    ("pown", "-1.0", "2", "1.00", "......"),
    ("pown", "1.00", "1", "1.00", "......"),
    ("pown", "1.00", "0", "1", "......"),
    ("pown", "1.00", "-2", "1", "......"),
    ("pown", "1.0", "-1", "1", "......"),
    ("pown", "0.50", "3", "0.125000", "......"),
    ("pown", "2.0", "2", "4.00", "......"),
    ("pown", "-1E+5", "5", "-1E+25", "......"),
    ("pown", "1E+5", "2", "1E+10", "......"),
    ("pown", "1E-2", "3", "0.000001", "......"),
    ("pown", "1E+2", "-2", "0.0001", "......"),
    ("pown", "1E+2", "20", "1E+40", "......"),
    ("pown", "10", "3", "1000", "......"),
    ("pown", "100", "3", "1000000", "......"),
    ("pown", "0.10", "2", "0.0100", "......"),
    ("power", "1.00", "2", "1.0000", "......"),
    ("power", "1.00", "1.5", "1.000", "......"),
    ("power", "1.00", "0.5", "1.0", "......"),
    ("power", "1.00", "-1.5", "1", "......"),
    ("power", "1.0", "2.5", "1.000", "......"),
    ("power", "1.00", "Infinity", "1", "......"),
    ("power", "4.00", "1.5", "8.000", "......"),
    ("power", "4", "1.5", "8", "......"),
    ("power", "32.0", "0.2", "2.0", "......"),
    ("power", "16.00", "0.75", "8.00", "......"),
    ("power", "1.2100", "1.5", "1.331000", "......"),
    ("power", "0.040", "1.5", "0.00800", "......"),
    ("power", "1E+2", "0.5", "1E+1", "......"),
    ("power", "100", "0.5", "10", "......"),
  ]
  for row in rows {
    let (op, operand, count, expected, expected_flags) = row
    let base = Decimal::from_string(operand).unwrap()
    let (value, flags) = if op == "pown" {
      base.pown_ctx(issue194_int(count), ctx)
    } else {
      base.power_ctx(Decimal::from_string(count).unwrap(), ctx)
    }
    assert_eq(
      (op, operand, count, value.to_string(), issue194_flags(flags)),
      (op, operand, count, expected, expected_flags),
    )
  }
}
