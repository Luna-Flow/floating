///|
struct CoeffBenchCase {
  shape : String
  left_bigint : BigInt
  right_bigint : BigInt
  left : Coeff
  right : Coeff
}

///|
fn coeff_bench_dense(bits : Int, phase : Int) -> BigInt {
  let mut value = 1N << (bits - 1)
  for index in 0..<(bits - 1) {
    if (index + phase) % 4 != 0 {
      value = value + (1N << index)
    }
  }
  value
}

///|
fn coeff_bench_case(
  _bits : Int,
  shape : String,
  left_bigint : BigInt,
  right_bigint : BigInt,
) -> CoeffBenchCase {
  {
    shape,
    left_bigint,
    right_bigint,
    left: coeff_from_nonnegative_bigint(left_bigint),
    right: coeff_from_nonnegative_bigint(right_bigint),
  }
}

///|
fn coeff_bench_cases(bits : Int) -> Array[CoeffBenchCase] {
  let top = 1N << (bits - 1)
  let half_top = 1N << (bits - 2)
  [
    coeff_bench_case(
      bits,
      "dense",
      coeff_bench_dense(bits, 0),
      coeff_bench_dense(bits - 1, 1),
    ),
    coeff_bench_case(
      bits,
      "sparse",
      top + (1N << (bits / 2)) + 1N,
      half_top + (1N << (bits / 3)) + 1N,
    ),
    coeff_bench_case(
      bits,
      "all_ones",
      (1N << bits) - 1N,
      (1N << (bits - 1)) - 1N,
    ),
    coeff_bench_case(bits, "power_boundary", top, 1N),
  ]
}

///|
fn coeff_bench_division_cases(bits : Int) -> Array[CoeffBenchCase] {
  let numerator = (1N << bits) - 1N
  [
    coeff_bench_case(bits, "near_equal", numerator, numerator - 3N),
    coeff_bench_case(
      bits,
      "wide_quotient",
      coeff_bench_dense(bits, 0),
      (1N << (bits / 2)) - 1N,
    ),
    coeff_bench_case(bits, "single_limb_divisor", numerator, (1N << 29) + 3N),
  ]
}

///|
fn coeff_bench_small_add_cases() -> Array[CoeffBenchCase] {
  let maximum = (1N << 64) - 1N
  [
    coeff_bench_case(
      64,
      "small_carry_dense",
      maximum,
      (1N << 63) + (1N << 31) + 1N,
    ),
    coeff_bench_case(64, "small_carry_zero_low", maximum, 1N),
    coeff_bench_case(64, "small_no_carry", 1N << 63, (1N << 63) - 1N),
  ]
}

///|
fn coeff_bench_name(
  implementation : String,
  operation : String,
  bits : Int,
  shape : String,
) -> String {
  "\{implementation}/\{operation}/\{bits}/\{shape}"
}

///|
fn coeff_bench_pair(
  bencher : @bench.Bench,
  operation : String,
  bits : Int,
  shape : String,
  coefficient : () -> Unit,
  bigint : () -> Unit,
) -> Unit {
  bencher.bench(
    name=coeff_bench_name("coeff", operation, bits, shape),
    count=9,
    coefficient,
  )
  bencher.bench(
    name=coeff_bench_name("bigint", operation, bits, shape),
    count=9,
    bigint,
  )
}

///|
fn coeff_bench_single(
  bencher : @bench.Bench,
  implementation : String,
  operation : String,
  bits : Int,
  shape : String,
  run : () -> Unit,
) -> Unit {
  bencher.bench(
    name=coeff_bench_name(implementation, operation, bits, shape),
    count=9,
    run,
  )
}

///|
fn coeff_bench_round_shift(value : Coeff, shift : Int) -> (Coeff, Bool) {
  if shift <= 0 {
    return (value, false)
  }
  let quotient = coeff_shift_right(value, shift)
  let remainder = coeff_sub(value, coeff_shift_left(quotient, shift))
  if coeff_is_zero(remainder) {
    return (quotient, false)
  }
  let half = coeff_shift_left(coeff_one(), shift - 1)
  let comparison = coeff_compare(remainder, half)
  let increment = comparison > 0 ||
    (comparison == 0 && coeff_mod_int(quotient, 2) == 1)
  (if increment { coeff_increment(quotient) } else { quotient }, true)
}

///|
fn coeff_bench_add_small_overflow_legacy(left : Coeff, right : Coeff) -> Coeff {
  let left_units = coeff_units(left)
  let right_units = coeff_units(right)
  let length = Int::max(left_units.length(), right_units.length())
  let units : Array[UInt] = []
  let mut carry = 0UL
  for index in 0..<length {
    let left_unit = if index < left_units.length() {
      left_units[index].to_uint64()
    } else {
      0UL
    }
    let right_unit = if index < right_units.length() {
      right_units[index].to_uint64()
    } else {
      0UL
    }
    let sum = left_unit + right_unit + carry
    units.push((sum & coeff_mask).to_uint())
    carry = sum >> coeff_unit_bits
  }
  if carry != 0UL {
    units.push(carry.to_uint())
  }
  coeff_make(units)
}

///|
fn coeff_bench_from_bigint_medium_legacy(value : BigInt) -> Coeff {
  let base = BigInt::from_uint64(coeff_base)
  let units : Array[UInt] = []
  let mut remaining = value
  while !remaining.is_zero() {
    let quotient = remaining / base
    units.push((remaining - quotient * base).to_uint64().to_uint())
    remaining = quotient
  }
  coeff_make(units)
}

///|
fn coeff_bench_round_shift_fused(value : Coeff, shift : Int) -> (Coeff, Bool) {
  coeff_round_shift_ties_even(value, shift)
}

///|
fn bigint_bench_round_shift(value : BigInt, shift : Int) -> (BigInt, Bool) {
  if shift <= 0 {
    return (value, false)
  }
  let quotient = value >> shift
  let remainder = value - (quotient << shift)
  if remainder.is_zero() {
    return (quotient, false)
  }
  let half = 1N << (shift - 1)
  let increment = remainder > half || (remainder == half && quotient % 2N == 1N)
  (if increment { quotient + 1N } else { quotient }, true)
}

///|
fn coeff_bench_round_div(
  numerator : Coeff,
  denominator : Coeff,
) -> (Coeff, Bool) {
  let (quotient, remainder) = coeff_div_rem(numerator, denominator)
  if coeff_is_zero(remainder) {
    return (quotient, false)
  }
  let comparison = coeff_compare(coeff_add(remainder, remainder), denominator)
  let increment = comparison > 0 ||
    (comparison == 0 && coeff_mod_int(quotient, 2) == 1)
  (if increment { coeff_increment(quotient) } else { quotient }, true)
}

///|
fn bigint_bench_round_div(
  numerator : BigInt,
  denominator : BigInt,
) -> (BigInt, Bool) {
  let quotient = numerator / denominator
  let remainder = numerator % denominator
  if remainder.is_zero() {
    return (quotient, false)
  }
  let comparison = (remainder << 1).compare(denominator)
  let increment = comparison > 0 || (comparison == 0 && quotient % 2N == 1N)
  (if increment { quotient + 1N } else { quotient }, true)
}

///|
fn coeff_bench_sqrt_floor(value : Coeff) -> Coeff {
  if coeff_compare(value, coeff_one()) <= 0 {
    return value
  }
  let mut root = coeff_shift_left(coeff_one(), (coeff_bits(value) + 1) / 2)
  while true {
    let quotient = coeff_div_rem(value, root).0
    let next = coeff_shift_right(coeff_add(root, quotient), 1)
    if coeff_compare(next, root) >= 0 {
      return root
    }
    root = next
  }
  abort("unreachable")
}

///|
fn bigint_bench_sqrt_floor(value : BigInt) -> BigInt {
  if value <= 1N {
    return value
  }
  let mut root = 1N << ((value.bit_length() + 1) / 2)
  while true {
    let next = (root + value / root) >> 1
    if next >= root {
      return root
    }
    root = next
  }
  abort("unreachable")
}

///|
test "coefficient benchmark compositions match BigInt oracle" {
  for bits in [53, 113, 256] {
    let case = coeff_bench_cases(bits)[0]
    let shift = bits / 3 + 1
    let (coefficient_shift, coefficient_shift_inexact) = coeff_bench_round_shift(
      case.left,
      shift,
    )
    let (bigint_shift, bigint_shift_inexact) = bigint_bench_round_shift(
      case.left_bigint,
      shift,
    )
    assert_eq(coeff_to_bigint(coefficient_shift), bigint_shift)
    assert_eq(coefficient_shift_inexact, bigint_shift_inexact)
    let (fused_shift, fused_shift_inexact) = coeff_bench_round_shift_fused(
      case.left,
      shift,
    )
    assert_eq(coeff_to_bigint(fused_shift), bigint_shift)
    assert_eq(fused_shift_inexact, bigint_shift_inexact)
    let division = coeff_bench_division_cases(bits)[1]
    let (coefficient_quotient, coefficient_div_inexact) = coeff_bench_round_div(
      division.left,
      division.right,
    )
    let (bigint_quotient, bigint_div_inexact) = bigint_bench_round_div(
      division.left_bigint,
      division.right_bigint,
    )
    assert_eq(coeff_to_bigint(coefficient_quotient), bigint_quotient)
    assert_eq(coefficient_div_inexact, bigint_div_inexact)
    let product = coeff_mul(case.left, case.right)
    let product_bigint = case.left_bigint * case.right_bigint
    let (coefficient_product, coefficient_product_inexact) = coeff_bench_round_shift(
      product,
      bits - 1,
    )
    let (bigint_product, bigint_product_inexact) = bigint_bench_round_shift(
      product_bigint,
      bits - 1,
    )
    assert_eq(coeff_to_bigint(coefficient_product), bigint_product)
    assert_eq(coefficient_product_inexact, bigint_product_inexact)
    let (fused_product, fused_product_inexact) = coeff_bench_round_shift_fused(
      product,
      bits - 1,
    )
    assert_eq(coeff_to_bigint(fused_product), bigint_product)
    assert_eq(fused_product_inexact, bigint_product_inexact)
    let coefficient_root = coeff_bench_sqrt_floor(case.left)
    let bigint_root = bigint_bench_sqrt_floor(case.left_bigint)
    assert_eq(coeff_to_bigint(coefficient_root), bigint_root)
  }
  for case in coeff_bench_small_add_cases() {
    let expected = case.left_bigint + case.right_bigint
    assert_eq(coeff_to_bigint(coeff_add(case.left, case.right)), expected)
    if case.shape != "small_no_carry" {
      assert_eq(
        coeff_to_bigint(
          coeff_bench_add_small_overflow_legacy(case.left, case.right),
        ),
        expected,
      )
    }
  }
  for bits in [65, 113, 127, 128] {
    for case in coeff_bench_cases(bits) {
      assert_eq(
        coeff_to_bigint(coeff_bench_from_bigint_medium_legacy(case.left_bigint)),
        case.left_bigint,
      )
      assert_eq(
        coeff_to_bigint(coeff_from_nonnegative_bigint(case.left_bigint)),
        case.left_bigint,
      )
    }
  }
}

///|
#skip("performance benchmark")
test "coefficient conversion baseline" {
  let bencher = @bench.Bench()
  for bits in [53, 113, 256, 1024, 4096] {
    for case in coeff_bench_cases(bits) {
      coeff_bench_single(bencher, "coeff", "from_bigint", bits, case.shape, fn() {
        bencher.keep(coeff_from_nonnegative_bigint(case.left_bigint))
      })
      coeff_bench_single(bencher, "coeff", "to_bigint", bits, case.shape, fn() {
        bencher.keep(coeff_to_bigint(case.left))
      })
    }
  }
  for bits in [65, 113, 127, 128] {
    for case in coeff_bench_cases(bits) {
      coeff_bench_single(
        bencher,
        "legacy",
        "from_bigint_medium",
        bits,
        case.shape,
        fn() {
          bencher.keep(coeff_bench_from_bigint_medium_legacy(case.left_bigint))
        },
      )
      coeff_bench_single(
        bencher,
        "coeff",
        "from_bigint_medium",
        bits,
        case.shape,
        fn() { bencher.keep(coeff_from_nonnegative_bigint(case.left_bigint)) },
      )
    }
  }
  println("BIN_COEFF_BENCH_JSON=" + bencher.dump_summaries())
}

///|
#skip("performance benchmark")
test "coefficient primitive baseline" {
  let bencher = @bench.Bench()
  for bits in [53, 113, 256, 1024, 4096] {
    for case in coeff_bench_cases(bits) {
      let shift = bits / 3 + 1
      coeff_bench_pair(
        bencher,
        "compare",
        bits,
        case.shape,
        fn() { bencher.keep(coeff_compare(case.left, case.right)) },
        fn() { bencher.keep(case.left_bigint.compare(case.right_bigint)) },
      )
      coeff_bench_pair(
        bencher,
        "add",
        bits,
        case.shape,
        fn() { bencher.keep(coeff_add(case.left, case.right)) },
        fn() { bencher.keep(case.left_bigint + case.right_bigint) },
      )
      coeff_bench_pair(
        bencher,
        "sub",
        bits,
        case.shape,
        fn() { bencher.keep(coeff_sub(case.left, case.right)) },
        fn() { bencher.keep(case.left_bigint - case.right_bigint) },
      )
      coeff_bench_pair(
        bencher,
        "shift_left",
        bits,
        case.shape,
        fn() { bencher.keep(coeff_shift_left(case.left, shift)) },
        fn() { bencher.keep(case.left_bigint << shift) },
      )
      coeff_bench_pair(
        bencher,
        "shift_right",
        bits,
        case.shape,
        fn() { bencher.keep(coeff_shift_right(case.left, shift)) },
        fn() { bencher.keep(case.left_bigint >> shift) },
      )
      coeff_bench_pair(
        bencher,
        "mul_exact",
        bits,
        case.shape,
        fn() { bencher.keep(coeff_mul(case.left, case.right)) },
        fn() { bencher.keep(case.left_bigint * case.right_bigint) },
      )
    }
    let huge = coeff_bench_cases(bits)[1]
    let huge_shift = bits * 4 + 17
    coeff_bench_pair(
      bencher,
      "shift_left",
      bits,
      "huge_shift",
      fn() { bencher.keep(coeff_shift_left(huge.left, huge_shift)) },
      fn() { bencher.keep(huge.left_bigint << huge_shift) },
    )
    coeff_bench_pair(
      bencher,
      "shift_right",
      bits,
      "huge_shift",
      fn() { bencher.keep(coeff_shift_right(huge.left, huge_shift)) },
      fn() { bencher.keep(huge.left_bigint >> huge_shift) },
    )
  }
  println("BIN_COEFF_BENCH_JSON=" + bencher.dump_summaries())
}

///|
#skip("performance benchmark")
test "coefficient division baseline" {
  let bencher = @bench.Bench()
  for bits in [53, 113, 256, 1024, 4096] {
    for case in coeff_bench_division_cases(bits) {
      coeff_bench_pair(
        bencher,
        "div_rem",
        bits,
        case.shape,
        fn() { bencher.keep(coeff_div_rem(case.left, case.right)) },
        fn() {
          bencher.keep(
            (
              case.left_bigint / case.right_bigint,
              case.left_bigint % case.right_bigint,
            ),
          )
        },
      )
    }
  }
  println("BIN_COEFF_BENCH_JSON=" + bencher.dump_summaries())
}

///|
#skip("performance benchmark")
test "coefficient composed floating kernel baseline" {
  let bencher = @bench.Bench()
  for bits in [53, 113, 256, 1024, 4096] {
    let case = coeff_bench_cases(bits)[0]
    let division = coeff_bench_division_cases(bits)[1]
    let shift = bits / 3 + 1
    coeff_bench_pair(
      bencher,
      "round_shift_composed",
      bits,
      "dense",
      fn() { bencher.keep(coeff_bench_round_shift(case.left, shift)) },
      fn() { bencher.keep(bigint_bench_round_shift(case.left_bigint, shift)) },
    )
    coeff_bench_pair(
      bencher,
      "round_shift_fused",
      bits,
      "dense",
      fn() { bencher.keep(coeff_bench_round_shift_fused(case.left, shift)) },
      fn() { bencher.keep(bigint_bench_round_shift(case.left_bigint, shift)) },
    )
    coeff_bench_pair(
      bencher,
      "mul_round_composed",
      bits,
      "dense",
      fn() {
        bencher.keep(
          coeff_bench_round_shift(coeff_mul(case.left, case.right), bits - 1),
        )
      },
      fn() {
        bencher.keep(
          bigint_bench_round_shift(
            case.left_bigint * case.right_bigint,
            bits - 1,
          ),
        )
      },
    )
    coeff_bench_pair(
      bencher,
      "mul_round_fused",
      bits,
      "dense",
      fn() {
        bencher.keep(
          coeff_bench_round_shift_fused(
            coeff_mul(case.left, case.right),
            bits - 1,
          ),
        )
      },
      fn() {
        bencher.keep(
          bigint_bench_round_shift(
            case.left_bigint * case.right_bigint,
            bits - 1,
          ),
        )
      },
    )
    coeff_bench_pair(
      bencher,
      "rounded_div",
      bits,
      "wide_quotient",
      fn() {
        bencher.keep(coeff_bench_round_div(division.left, division.right))
      },
      fn() {
        bencher.keep(
          bigint_bench_round_div(division.left_bigint, division.right_bigint),
        )
      },
    )
    coeff_bench_pair(
      bencher,
      "integer_sqrt",
      bits,
      "dense",
      fn() { bencher.keep(coeff_bench_sqrt_floor(case.left)) },
      fn() { bencher.keep(bigint_bench_sqrt_floor(case.left_bigint)) },
    )
  }
  println("BIN_COEFF_BENCH_JSON=" + bencher.dump_summaries())
}

///|
#skip("performance benchmark")
test "coefficient representation and algorithm boundaries" {
  let bencher = @bench.Bench()
  for bits in [63, 64, 65, 127, 128, 129] {
    let case = coeff_bench_cases(bits)[0]
    let division = coeff_bench_division_cases(bits)[0]
    coeff_bench_single(
      bencher,
      "coeff",
      "from_bigint",
      bits,
      "representation_boundary",
      fn() { bencher.keep(coeff_from_nonnegative_bigint(case.left_bigint)) },
    )
    coeff_bench_pair(
      bencher,
      "add",
      bits,
      "representation_boundary",
      fn() { bencher.keep(coeff_add(case.left, case.right)) },
      fn() { bencher.keep(case.left_bigint + case.right_bigint) },
    )
    coeff_bench_pair(
      bencher,
      "mul_exact",
      bits,
      "representation_boundary",
      fn() { bencher.keep(coeff_mul(case.left, case.right)) },
      fn() { bencher.keep(case.left_bigint * case.right_bigint) },
    )
    coeff_bench_pair(
      bencher,
      "div_rem",
      bits,
      "representation_boundary",
      fn() { bencher.keep(coeff_div_rem(division.left, division.right)) },
      fn() {
        bencher.keep(
          (
            division.left_bigint / division.right_bigint,
            division.left_bigint % division.right_bigint,
          ),
        )
      },
    )
  }
  for bits in [1536, 1600, 1632] {
    let case = coeff_bench_cases(bits)[0]
    coeff_bench_pair(
      bencher,
      "mul_exact",
      bits,
      "bigint_karatsuba_boundary",
      fn() { bencher.keep(coeff_mul(case.left, case.right)) },
      fn() { bencher.keep(case.left_bigint * case.right_bigint) },
    )
  }
  for case in coeff_bench_small_add_cases() {
    if case.shape != "small_no_carry" {
      coeff_bench_single(
        bencher,
        "legacy",
        "add_small_overflow",
        64,
        case.shape,
        fn() {
          bencher.keep(
            coeff_bench_add_small_overflow_legacy(case.left, case.right),
          )
        },
      )
    }
    coeff_bench_pair(
      bencher,
      "add_small_overflow",
      64,
      case.shape,
      fn() { bencher.keep(coeff_add(case.left, case.right)) },
      fn() { bencher.keep(case.left_bigint + case.right_bigint) },
    )
  }
  println("BIN_COEFF_BENCH_JSON=" + bencher.dump_summaries())
}
