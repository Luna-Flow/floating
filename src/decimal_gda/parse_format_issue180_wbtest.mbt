///|
/// General Decimal Arithmetic 1.70, *to-number*: a literal with more digits
/// than the precision has its coefficient shortened to exactly `precision`
/// digits and the exponent raised by the digits removed; trailing zeros of the
/// rounded coefficient stay (`1.0001` at 3 digits is `1.00`, not `1`). A carry
/// into 10^p moves the exponent up by one and leaves p digits (`99999` is
/// `1.00E+5`, `9.9999` is `10.0`). Same behaviour as `decimal` (#178).
test "decimal_gda parse keeps the rounded cohort for literals longer than the precision (#180)" {
  let p = fn(text : String, precision : Int32) {
    Decimal::parse(text, precision~).unwrap().to_string()
  }
  inspect(p("1.0001", 3), content="1.00")
  inspect(p("1.000", 3), content="1.00")
  inspect(p("10001", 3), content="1.00E+4")
  inspect(p("99999", 3), content="1.00E+5")
  inspect(p("-99999", 3), content="-1.00E+5")
  inspect(p("9.9999", 3), content="10.0")
  inspect(p("999.5", 3), content="1.00E+3")
  inspect(p("9995", 3), content="1.00E+4")
  inspect(p("0.0009999", 3), content="0.00100")
  inspect(p("998.5", 3), content="998")
  inspect(p("9.5", 1), content="1E+1")
  inspect(p("1.20000", 3), content="1.20")
  inspect(p("100000", 3), content="1.00E+5")
  inspect(p("12.30", 3), content="12.3")
  inspect(p("12.300", 3), content="12.3")
  inspect(p("123.0", 3), content="123")
}
