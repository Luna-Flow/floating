///|
fn benchmark_binfloat_size(
  bencher : @bench.Bench,
  label : String,
  left_bigint : BigInt,
  right_bigint : BigInt,
  precision : Int,
) -> Unit {
  let left = @bin_float.BinFloat::from_coefficient(
    @bin_float.BinCoeff::parse(left_bigint.to_string()).unwrap(),
    precision~,
  )
  let right = @bin_float.BinFloat::from_coefficient(
    @bin_float.BinCoeff::parse(right_bigint.to_string()).unwrap(),
    precision~,
  )
  bencher.bench(name="binfloat_add_" + label, count=5, fn() {
    let mut result = left
    for _ in 0..<100 {
      result = result + right
    }
    bencher.keep(result)
  })
  bencher.bench(name="bigint_add_" + label, count=5, fn() {
    let mut result = left_bigint
    for _ in 0..<100 {
      result = result + right_bigint
    }
    bencher.keep(result)
  })
  bencher.bench(name="binfloat_mul_" + label, count=5, fn() {
    let mut result = left
    for _ in 0..<10 {
      result = left * right
    }
    bencher.keep(result)
  })
  bencher.bench(name="bigint_mul_" + label, count=5, fn() {
    let mut result = left_bigint
    for _ in 0..<10 {
      result = left_bigint * right_bigint
    }
    bencher.keep(result)
  })
  bencher.bench(name="binfloat_div_" + label, count=5, fn() {
    let mut result = left
    for _ in 0..<10 {
      result = left / right
    }
    bencher.keep(result)
  })
  bencher.bench(name="bigint_div_" + label, count=5, fn() {
    let mut result = left_bigint
    for _ in 0..<10 {
      result = left_bigint / right_bigint
    }
    bencher.keep(result)
  })
}

///|
#skip("performance benchmark")
test "BinFloat arithmetic versus MoonBit BigInt by operand width" {
  let bencher = @bench.Bench()
  benchmark_binfloat_size(bencher, "53", (1N << 53) - 1N, (1N << 51) + 3N, 128)
  benchmark_binfloat_size(
    bencher,
    "128",
    (1N << 127) + (1N << 63) + 1N,
    (1N << 113) + (1N << 31) + 3N,
    272,
  )
  benchmark_binfloat_size(
    bencher,
    "1024",
    (1N << 1024) + (1N << 511) + 1N,
    (1N << 1001) + (1N << 257) + 3N,
    2064,
  )
  println(bencher.dump_summaries())
}

///|
fn benchmark_coeff_size(
  bencher : @bench.Bench,
  label : String,
  left_bigint : BigInt,
  right_bigint : BigInt,
) -> Unit {
  let left = @bin_float.BinCoeff::parse(left_bigint.to_string()).unwrap()
  let right = @bin_float.BinCoeff::parse(right_bigint.to_string()).unwrap()
  bencher.bench(name="coeff_add_" + label, count=5, fn() {
    let mut result = left
    for _ in 0..<100 {
      result = result.add(right)
    }
    bencher.keep(result)
  })
  bencher.bench(name="bigint_coeff_add_" + label, count=5, fn() {
    let mut result = left_bigint
    for _ in 0..<100 {
      result = result + right_bigint
    }
    bencher.keep(result)
  })
  bencher.bench(name="coeff_mul_" + label, count=5, fn() {
    let mut result = left
    for _ in 0..<20 {
      result = left.mul(right)
    }
    bencher.keep(result)
  })
  bencher.bench(name="bigint_coeff_mul_" + label, count=5, fn() {
    let mut result = left_bigint
    for _ in 0..<20 {
      result = left_bigint * right_bigint
    }
    bencher.keep(result)
  })
  bencher.bench(name="coeff_div_" + label, count=5, fn() {
    let mut result = left
    for _ in 0..<20 {
      result = left.div_rem_checked(right).unwrap().0
    }
    bencher.keep(result)
  })
  bencher.bench(name="bigint_coeff_div_" + label, count=5, fn() {
    let mut result = left_bigint
    for _ in 0..<20 {
      result = left_bigint / right_bigint
    }
    bencher.keep(result)
  })
}

///|
#skip("performance benchmark")
test "specialized coefficient kernel versus MoonBit BigInt" {
  let bencher = @bench.Bench()
  benchmark_coeff_size(bencher, "53", (1N << 53) - 1N, (1N << 51) + 3N)
  benchmark_coeff_size(
    bencher,
    "128",
    (1N << 127) + (1N << 63) + 1N,
    (1N << 113) + (1N << 31) + 3N,
  )
  benchmark_coeff_size(
    bencher,
    "1024",
    (1N << 1024) + (1N << 511) + 1N,
    (1N << 1001) + (1N << 257) + 3N,
  )
  println(bencher.dump_summaries())
}
