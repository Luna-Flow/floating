///|
fn gda_performance_source(digits : Int) -> String {
  if digits == 1 {
    return "8"
  }
  let builder = StringBuilder::new()
  builder.write_char('3')
  for index in 1..<(digits - 1) {
    builder.write_char(((index * 7 + 1) % 10 + 48).to_char().unwrap())
  }
  builder.write_char('8')
  builder.to_string()
}

///|
fn gda_performance_fraction(digits : Int) -> String {
  let builder = StringBuilder::new()
  builder.write_string("1.")
  for index in 0..<digits {
    builder.write_char(((index * 7 + 3) % 10 + 48).to_char().unwrap())
  }
  builder.to_string()
}

///|
fn gda_performance_repetitions(operation : String, digits : Int) -> Int {
  if operation == "context" {
    if digits <= 18 { 1048576 } else { 131072 }
  } else if operation == "parse" {
    if digits == 1 {
      262144
    } else if digits <= 18 {
      32768
    } else if digits <= 34 {
      4096
    } else {
      1024
    }
  } else if operation == "add" || operation == "sub" {
    if digits <= 18 { 131072 } else if digits <= 34 { 16384 } else { 8192 }
  } else if operation == "mul" {
    if digits <= 18 { 131072 } else { 32768 }
  } else if operation == "exact-div" {
    if digits <= 18 { 32768 } else if digits <= 34 { 8192 } else { 4096 }
  } else if operation == "fma" {
    if digits <= 18 { 65536 } else { 32768 }
  } else if operation == "sqrt" {
    if digits <= 9 { 2048 } else { 1024 }
  } else if operation == "power" {
    if digits <= 9 { 4096 } else { 2048 }
  } else if operation == "ln" {
    if digits <= 9 { 32 } else { 16 }
  } else {
    if digits <= 9 { 16 } else { 8 }
  }
}

///|
fn[T] gda_performance_cell(
  bencher : @bench.Bench,
  operation : String,
  digits : Int,
  body : () -> T,
) -> Unit {
  let repetitions = gda_performance_repetitions(operation, digits)
  bencher.bench(
    name="gda/" + operation + "/" + digits.to_string(),
    count=3,
    fn() {
      let mut result = body()
      for _ in 1..<repetitions {
        result = body()
      }
      bencher.keep(result)
    },
  )
}

///|
#skip("performance benchmark")
test "independent GDA native quick benchmark" {
  let bencher = @bench.Bench()
  for digits in [1, 9, 18, 34, 128] {
    let source = gda_performance_source(digits)
    let precision = (digits * 2 + 4).max(9)
    let context = GdaContext::new(
      precision~,
      e_min=-999999,
      e_max=999999,
    )
    let left = Decimal::from_string(source).unwrap()
    let right = Decimal::from_string("2").unwrap()
    let addend = Decimal::from_string("3").unwrap()
    gda_performance_cell(bencher, "add", digits, fn() {
      add(left, right, context).value()
    })
    gda_performance_cell(bencher, "sub", digits, fn() {
      subtract(left, right, context).value()
    })
    gda_performance_cell(bencher, "mul", digits, fn() {
      multiply(left, right, context).value()
    })
    gda_performance_cell(bencher, "exact-div", digits, fn() {
      divide(left, right, context).value()
    })
    gda_performance_cell(bencher, "fma", digits, fn() {
      fma(left, right, addend, context).value()
    })
    gda_performance_cell(bencher, "parse", digits, fn() {
      parse(source, context).value()
    })
    gda_performance_cell(bencher, "context", digits, fn() {
      GdaContext::new(precision~, e_min=-999999, e_max=999999)
    })
  }
  for digits in [9, 34] {
    let source = gda_performance_fraction(digits)
    let context = GdaContext::new(
      precision=(digits + 8).max(17),
      e_min=-999999,
      e_max=999999,
    )
    let value = Decimal::from_string(source).unwrap()
    let exponent = Decimal::from_string("3").unwrap()
    gda_performance_cell(bencher, "sqrt", digits, fn() {
      sqrt(value, context).value()
    })
    gda_performance_cell(bencher, "power", digits, fn() {
      power(value, exponent, context).value()
    })
    gda_performance_cell(bencher, "exp", digits, fn() {
      exp(value, context).value()
    })
    gda_performance_cell(bencher, "ln", digits, fn() {
      ln(value, context).value()
    })
    gda_performance_cell(bencher, "log10", digits, fn() {
      log10(value, context).value()
    })
  }
  println("GDA_PERFORMANCE_CHECKSUM=gda-quick-v1")
  println("GDA_PERFORMANCE_JSON=" + bencher.dump_summaries())
}
