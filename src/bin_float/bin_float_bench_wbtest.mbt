///|
struct BinFloatBenchCase {
  left_bigint : BigInt
  left_coefficient : BinCoeff
  left : BinFloat
  right : BinFloat
  legacy_left : LegacyBigIntBinFloat
  legacy_right : LegacyBigIntBinFloat
  context : BinaryContext
}

///|
fn bin_float_bench_dense(bits : Int, phase : Int) -> BigInt {
  let mut value = 1N << (bits - 1)
  for index in 0..<(bits - 1) {
    if (index + phase) % 4 != 0 {
      value = value + (1N << index)
    }
  }
  value
}

///|
fn legacy_round_increment(
  quotient : BigInt,
  remainder : BigInt,
  denominator : BigInt,
) -> Bool {
  let comparison = (remainder << 1).compare(denominator)
  comparison > 0 || (comparison == 0 && quotient % 2N == 1N)
}

///|
fn legacy_round_shift(value : BigInt, shift : Int) -> (BigInt, Bool) {
  let quotient = value >> shift
  let remainder = value - (quotient << shift)
  let denominator = 1N << shift
  (
    if legacy_round_increment(quotient, remainder, denominator) {
      quotient + 1N
    } else {
      quotient
    },
    !remainder.is_zero(),
  )
}

///|
fn legacy_round_quotient(
  numerator : BigInt,
  denominator : BigInt,
) -> (BigInt, Bool) {
  let quotient = numerator / denominator
  let remainder = numerator % denominator
  (
    if legacy_round_increment(quotient, remainder, denominator) {
      quotient + 1N
    } else {
      quotient
    },
    !remainder.is_zero(),
  )
}

///|
fn legacy_integer_sqrt_floor(value : BigInt) -> BigInt {
  if value <= 1N {
    return value
  }
  let mut root = 1N << ((value.bit_length() + 1) / 2)
  let mut next = (root + value / root) / 2N
  while next < root {
    root = next
    next = (root + value / root) / 2N
  }
  root
}

///|
fn bin_float_bench_case(bits : Int, shape : String) -> BinFloatBenchCase {
  let (left_bigint, right_bigint) = if shape == "dense" {
    (bin_float_bench_dense(bits, 0), bin_float_bench_dense(bits - 1, 1))
  } else {
    (
      (1N << (bits - 1)) + (1N << (bits / 2)) + 1N,
      (1N << (bits - 2)) + (1N << (bits / 3)) + 1N,
    )
  }
  let left_coefficient = BinCoeff::parse(left_bigint.to_string()).unwrap()
  let right_coefficient = BinCoeff::parse(right_bigint.to_string()).unwrap()
  {
    left_bigint,
    left_coefficient,
    left: BinFloat::from_coefficient(left_coefficient, precision=bits),
    right: BinFloat::from_coefficient(right_coefficient, precision=bits),
    legacy_left: LegacyBigIntBinFloat::make(left_bigint, 0, bits),
    legacy_right: LegacyBigIntBinFloat::make(right_bigint, 0, bits),
    context: BinaryContext::unbounded(bits),
  }
}

///|
fn bin_float_bench_name(
  implementation : String,
  operation : String,
  bits : Int,
  shape : String,
) -> String {
  "\{implementation}/\{operation}/\{bits}/\{shape}"
}

///|
fn bin_float_bench_single(
  bencher : @bench.Bench,
  implementation : String,
  operation : String,
  bits : Int,
  shape : String,
  run : () -> Unit,
) -> Unit {
  bencher.bench(
    name=bin_float_bench_name(implementation, operation, bits, shape),
    count=9,
    run,
  )
}

///|
fn bin_float_bench_pair(
  bencher : @bench.Bench,
  operation : String,
  bits : Int,
  shape : String,
  legacy_run : () -> Unit,
  candidate_run : () -> Unit,
) -> Unit {
  bin_float_bench_single(bencher, "legacy", operation, bits, shape, legacy_run)
  bin_float_bench_single(
    bencher, "binfloat", operation, bits, shape, candidate_run,
  )
}

///|
#skip("performance benchmark")
test "BigInt floating-kernel oracle baseline" {
  let bencher = @bench.Bench()
  for bits in [53, 113, 256, 1024, 4096] {
    let value = bin_float_bench_dense(bits, 0)
    let shift = bits / 3 + 1
    let denominator = value - 3N
    bin_float_bench_single(
      bencher,
      "bigint_oracle",
      "round_shift",
      bits,
      "dense",
      fn() { bencher.keep(legacy_round_shift(value, shift)) },
    )
    bin_float_bench_single(
      bencher,
      "bigint_oracle",
      "rounded_div",
      bits,
      "near_equal",
      fn() { bencher.keep(legacy_round_quotient(value, denominator)) },
    )
    bin_float_bench_single(
      bencher,
      "bigint_oracle",
      "integer_sqrt",
      bits,
      "dense",
      fn() { bencher.keep(legacy_integer_sqrt_floor(value)) },
    )
  }
  println("BIN_FLOAT_BENCH_JSON=" + bencher.dump_summaries())
}

///|
#skip("performance benchmark")
test "BinFloat contextual arithmetic baseline" {
  let bencher = @bench.Bench()
  for bits in [53, 113, 256, 1024, 4096] {
    for shape in ["dense", "sparse"] {
      let case = bin_float_bench_case(bits, shape)
      bin_float_bench_single(bencher, "legacy", "construct", bits, shape, fn() {
        bencher.keep(LegacyBigIntBinFloat::make(case.left_bigint, 0, bits))
      })
      bin_float_bench_single(bencher, "binfloat", "construct", bits, shape, fn() {
        bencher.keep(BinFloat::make(case.left_coefficient, 0, bits))
      })
      bin_float_bench_pair(
        bencher,
        "add",
        bits,
        shape,
        fn() { bencher.keep(case.legacy_left.add(case.legacy_right)) },
        fn() { bencher.keep(case.left.add(case.right)) },
      )
      bin_float_bench_pair(
        bencher,
        "sub",
        bits,
        shape,
        fn() { bencher.keep(case.legacy_left.sub(case.legacy_right)) },
        fn() { bencher.keep(case.left.sub(case.right)) },
      )
      bin_float_bench_pair(
        bencher,
        "mul",
        bits,
        shape,
        fn() { bencher.keep(case.legacy_left.mul(case.legacy_right)) },
        fn() { bencher.keep(case.left.mul(case.right)) },
      )
      bin_float_bench_pair(
        bencher,
        "div",
        bits,
        shape,
        fn() { bencher.keep(case.legacy_left.div(case.legacy_right)) },
        fn() { bencher.keep(case.left.div(case.right)) },
      )
      bin_float_bench_pair(
        bencher,
        "sqrt",
        bits,
        shape,
        fn() { bencher.keep(case.legacy_left.sqrt()) },
        fn() { bencher.keep(case.left.sqrt()) },
      )
      bin_float_bench_pair(
        bencher,
        "pow_int_ctx",
        bits,
        shape,
        fn() { bencher.keep(case.legacy_left.pow_positive(7)) },
        fn() { bencher.keep(case.left.pow_int_ctx(7, case.context)) },
      )
      bin_float_bench_pair(
        bencher,
        "pow_int_ctx_exact_oracle",
        bits,
        shape,
        fn() {
          bencher.keep(
            binary_pow_exact_magnitude(case.left, 7U, false, case.context),
          )
        },
        fn() { bencher.keep(case.left.pow_int_ctx(7, case.context)) },
      )
    }
  }
  println("BIN_FLOAT_BENCH_JSON=" + bencher.dump_summaries())
}

///|
#skip("performance benchmark")
test "BinFloat sqrt hotspot baseline" {
  let bencher = @bench.Bench()
  for bits in [53, 113, 256, 1024, 4096] {
    for shape in ["dense", "sparse"] {
      let case = bin_float_bench_case(bits, shape)
      bin_float_bench_pair(
        bencher,
        "sqrt",
        bits,
        shape,
        fn() { bencher.keep(case.legacy_left.sqrt()) },
        fn() { bencher.keep(case.left.sqrt()) },
      )
    }
  }
  println("BIN_FLOAT_BENCH_JSON=" + bencher.dump_summaries())
}

///|
#skip("performance benchmark")
test "BinFloat 4096-bit sparse hotspot baseline" {
  let bencher = @bench.Bench()
  let bits = 4096
  let shape = "sparse"
  let case = bin_float_bench_case(bits, shape)
  bin_float_bench_pair(
    bencher,
    "add",
    bits,
    shape,
    fn() { bencher.keep(case.legacy_left.add(case.legacy_right)) },
    fn() { bencher.keep(case.left.add(case.right)) },
  )
  bin_float_bench_pair(
    bencher,
    "sub",
    bits,
    shape,
    fn() { bencher.keep(case.legacy_left.sub(case.legacy_right)) },
    fn() { bencher.keep(case.left.sub(case.right)) },
  )
  bin_float_bench_pair(
    bencher,
    "mul",
    bits,
    shape,
    fn() { bencher.keep(case.legacy_left.mul(case.legacy_right)) },
    fn() { bencher.keep(case.left.mul(case.right)) },
  )
  println("BIN_FLOAT_BENCH_JSON=" + bencher.dump_summaries())
}
