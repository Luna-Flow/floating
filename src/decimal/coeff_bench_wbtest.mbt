///|
fn decimal_coeff_bench_pow10(digits : Int) -> BigInt {
  let mut value = 1N
  for _ in 0..<digits {
    value = value * 10N
  }
  value
}

///|
fn decimal_coeff_bench_name(
  implementation : String,
  operation : String,
  digits : Int,
) -> String {
  "\{implementation}/\{operation}/\{digits}/dense"
}

///|
fn decimal_coeff_bench_pair(
  bencher : @bench.Bench,
  operation : String,
  digits : Int,
  coefficient : () -> Unit,
  bigint : () -> Unit,
) -> Unit {
  bencher.bench(
    name=decimal_coeff_bench_name("deccoeff", operation, digits),
    count=7,
    coefficient,
  )
  bencher.bench(
    name=decimal_coeff_bench_name("bigint", operation, digits),
    count=7,
    bigint,
  )
}

///|
#skip("performance benchmark")
test "decimal coefficient primitive baseline" {
  let bencher = @bench.Bench()
  for digits in [16, 34, 100, 300] {
    let power = decimal_coeff_bench_pow10(digits)
    let left_bigint = power - 1N
    let right_bigint = decimal_coeff_bench_pow10(digits - 1) +
      decimal_coeff_bench_pow10(digits / 2) +
      7N
    let left = dec_coeff_from_bigint_repr(left_bigint)
    let right = dec_coeff_from_bigint_repr(right_bigint)
    decimal_coeff_bench_pair(
      bencher,
      "add",
      digits,
      fn() { bencher.keep(dec_coeff_magnitude_add_repr(left, right)) },
      fn() { bencher.keep(left_bigint + right_bigint) },
    )
    decimal_coeff_bench_pair(
      bencher,
      "mul",
      digits,
      fn() { bencher.keep(dec_coeff_multiply_repr(left, right)) },
      fn() { bencher.keep(left_bigint * right_bigint) },
    )
    let numerator_bigint = left_bigint * power + right_bigint
    let numerator = dec_coeff_from_bigint_repr(numerator_bigint)
    decimal_coeff_bench_pair(
      bencher,
      "div_rem",
      digits,
      fn() { bencher.keep(dec_coeff_div_rem_repr(numerator, right)) },
      fn() {
        bencher.keep(
          (numerator_bigint / right_bigint, numerator_bigint % right_bigint),
        )
      },
    )
  }
  println("DEC_COEFF_BENCH_JSON=" + bencher.dump_summaries())
}
