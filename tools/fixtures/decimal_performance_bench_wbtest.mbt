///|
fn decimal_performance_pow10(digits : Int) -> BigInt {
  let mut value = 1N
  for _ in 0..<digits {
    value = value * 10N
  }
  value
}

///|
fn decimal_performance_name(
  implementation : String,
  operation : String,
  digits : Int,
) -> String {
  "\{implementation}/\{operation}/\{digits}/dense"
}

///|
fn[T] decimal_performance_warmup(
  bencher : @bench.Bench,
  coefficient : () -> T,
  repetitions : Int,
) -> Unit {
  let warmups = Int::min(4, repetitions)
  let mut sink = coefficient()
  for _ in 1..<warmups {
    sink = coefficient()
  }
  bencher.keep(sink)
}

///|
fn[T] decimal_performance_pair(
  bencher : @bench.Bench,
  operation : String,
  digits : Int,
  coefficient : () -> T,
) -> Unit {
  let repetitions = if operation == "add" {
    if digits <= 34 {
      65536
    } else if digits <= 100 {
      16384
    } else if digits <= 300 {
      4096
    } else {
      512
    }
  } else if operation == "mul" {
    if digits <= 34 {
      16384
    } else if digits <= 100 {
      2048
    } else if digits <= 300 {
      256
    } else {
      16
    }
  } else if digits <= 34 {
    8192
  } else if digits <= 100 {
    1024
  } else if digits <= 300 {
    128
  } else {
    8
  }
  decimal_performance_warmup(bencher, coefficient, repetitions)
  bencher.bench(
    name=decimal_performance_name("deccoeff", operation, digits),
    count=9,
    fn() {
      let mut sink = coefficient()
      for _ in 1..<repetitions {
        sink = coefficient()
      }
      bencher.keep(sink)
    },
  )
}

///|
#skip("performance benchmark")
test "decimal performance baseline" {
  let bencher = @bench.Bench()
  for digits in [16, 34, 100, 300, 1000] {
    let power = decimal_performance_pow10(digits)
    let left_bigint = power - 1N
    let right_bigint = decimal_performance_pow10(digits - 1) +
      decimal_performance_pow10(digits / 2) +
      7N
    let left = dec_coeff_from_bigint_repr(left_bigint)
    let right = dec_coeff_from_bigint_repr(right_bigint)
    decimal_performance_pair(
      bencher,
      "add",
      digits,
      fn() { dec_coeff_magnitude_add_repr(left, right) },
    )
    decimal_performance_pair(
      bencher,
      "mul",
      digits,
      fn() { dec_coeff_multiply_repr(left, right) },
    )
    let numerator_bigint = left_bigint * power + right_bigint
    let numerator = dec_coeff_from_bigint_repr(numerator_bigint)
    decimal_performance_pair(
      bencher,
      "div_rem",
      digits,
      fn() { dec_coeff_div_rem_repr(numerator, right) },
    )
  }
  println("DECIMAL_BENCH_CHECKSUM=725ab4b283617ee1624fbe9ae2157a83679508a4953312e1abf0baafbbc64fb2")
  println("DECIMAL_BENCH_JSON=" + bencher.dump_summaries())
}
