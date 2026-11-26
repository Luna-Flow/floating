///|
fn remainder_show(result : (Binary, BinaryFlags)) -> String {
  "\{result.0} flags=\{result.1.to_testfloat_bits()}"
}

///|
// oracle: A
// source: written out from IEEE Std 754-2019 5.3.1 (remainder(x, y) = x - y n with n the integer nearest to x / y, ties to even; the sign of a zero result is the sign of x): 5 rem 3 = -1 (n = 2), 7 rem 2 = -1 (3.5 gives 4), 5 rem 2 = 1 (2.5 gives 2), 6 rem 4 = -2 (1.5 gives 2), 10 rem 4 = 2, 1 rem 3 = 1, 0.75 rem 0.5 = -0.25, 3 rem -2 = -1, 4 rem 2 = +0 and -4 rem 2 = -0
// shares: Binary::from_double builds the operands; remainder_ctx is the code under test; remainder_show prints value and flag bits
test "remainder rounds the quotient to nearest, ties to even" {
  let context = BinaryContext::binary64()
  let lines = StringBuilder()
  for
    pair in [
      (5.0, 3.0),
      (7.0, 2.0),
      (5.0, 2.0),
      (-5.0, 2.0),
      (6.0, 4.0),
      (10.0, 4.0),
      (1.0, 3.0),
      (-1.0, 3.0),
      (0.75, 0.5),
      (3.0, -2.0),
      (4.0, 2.0),
      (-4.0, 2.0),
    ] {
    let (x, y) = pair
    let value = Binary::from_double(x).remainder_ctx(
      Binary::from_double(y),
      context,
    )
    lines.write_string("\{x} rem \{y} = \{remainder_show(value)}\n")
  }
  inspect(
    lines.to_string(),
    content=(
      #|5 rem 3 = -1p0 flags=0
      #|7 rem 2 = -1p0 flags=0
      #|5 rem 2 = 1p0 flags=0
      #|-5 rem 2 = -1p0 flags=0
      #|6 rem 4 = -1p1 flags=0
      #|10 rem 4 = 1p1 flags=0
      #|1 rem 3 = 1p0 flags=0
      #|-1 rem 3 = -1p0 flags=0
      #|0.75 rem 0.5 = -1p-2 flags=0
      #|3 rem -2 = -1p0 flags=0
      #|4 rem 2 = 0 flags=0
      #|-4 rem 2 = -0 flags=0
      #|
    ),
  )
}

///|
// oracle: A
// source: written out from IEEE Std 754-2019 7.2 f) and 5.3.1: remainder(inf, 1) and remainder(1, 0) are invalid (flags 16), remainder(1, -inf) = 1 exactly, remainder(-0, 1) = -0 and a signaling NaN operand is invalid
// shares: Binary::one, zero, inf, negative_zero and signaling_nan build the operands; remainder_ctx is the code under test; remainder_show prints value and flag bits
test "remainder special cases" {
  let context = BinaryContext::binary64()
  let one = Binary::one()
  inspect(
    remainder_show(Binary::inf().remainder_ctx(one, context)),
    content=(
      #|nan flags=16
    ),
  )
  inspect(
    remainder_show(one.remainder_ctx(Binary::zero(), context)),
    content=(
      #|nan flags=16
    ),
  )
  inspect(
    remainder_show(one.remainder_ctx(Binary::inf(negative=true), context)),
    content=(
      #|1p0 flags=0
    ),
  )
  inspect(
    remainder_show(Binary::negative_zero().remainder_ctx(one, context)),
    content=(
      #|-0 flags=0
    ),
  )
  inspect(
    remainder_show(Binary::signaling_nan().remainder_ctx(one, context)),
    content=(
      #|nan flags=16
    ),
  )
}

///|
// oracle: A
// source: written out: 2^1000000000 = 1 (mod 3) because 2^2 = 1 (mod 3), so the remainder is 1; 2^1000000001 = 2 (mod 3), whose nearest representative is -1; remainder(2^-1000000000, 1) is the dividend itself, which is below the binary64 range and rounds to 0 with underflow and inexact (flags 3)
// shares: Binary::make and from_int build the operands; remainder_ctx is the code under test; remainder_show prints value and flag bits
test "remainder of huge exponent gaps uses modular reduction" {
  let context = BinaryContext::binary64()
  // 2^1000000000 mod 3: 2^even = 1 (mod 3), so the remainder is 1.
  let huge = Binary::make(BinCoeff::one(), 1000000000, 53)
  inspect(
    remainder_show(huge.remainder_ctx(Binary::from_int(3), context)),
    content=(
      #|1p0 flags=0
    ),
  )
  // 2^1000000001 mod 3 = 2 = -1 (mod 3): the nearest multiple is above.
  let odd = Binary::make(BinCoeff::one(), 1000000001, 53)
  inspect(
    remainder_show(odd.remainder_ctx(Binary::from_int(3), context)),
    content=(
      #|-1p0 flags=0
    ),
  )
  // A dividend far below half the divisor is returned unchanged.
  let tiny = Binary::make(BinCoeff::one(), -1000000000, 53)
  inspect(
    remainder_show(tiny.remainder_ctx(Binary::one(), context)),
    content=(
      #|0 flags=3
    ),
  )
}

///|
// oracle: S
// source: an integer model written in the test with Int64 arithmetic of the language (the nearest integer to x / y with ties to even, expected = x - n y, the sign of a zero result by the sign of x) on 3000 pairs of a fixed linear congruential sequence; the model is independent of the library, but the operands and the expected values are built with Binary::from_int and compared with Binary::compare, shared builders without a level A block of their own here, so the level is stated as S
// shares: Binary::from_int and Binary::compare on both sides; remainder_ctx is the code under test
test "remainder agrees with an exact quotient reference" {
  let context = BinaryContext::new(precision=53)
  let mut state = 0x2545F4914F6CDD1DUL
  let next = fn() {
    state = state * 6364136223846793005UL + 1442695040888963407UL
    state >> 11
  }
  for _ in 0..<3000 {
    let x = (next() % 2000001UL).reinterpret_as_int64() - 1000000L
    let y = (next() % 2001UL).reinterpret_as_int64() - 1000L
    if y == 0L {
      continue
    }
    // Nearest quotient with ties to even, computed on integers.
    let q = x / y
    let r = x - q * y
    let twice = (if r < 0L { -r } else { r }) * 2L
    let magnitude = if y < 0L { -y } else { y }
    let n = if twice > magnitude || (twice == magnitude && q % 2L != 0L) {
      q + (if (r < 0L) == (y < 0L) { 1L } else { -1L })
    } else {
      q
    }
    let expected = x - n * y
    let actual = Binary::from_int(x.to_int(), precision=53).remainder_ctx(
      Binary::from_int(y.to_int(), precision=53),
      context,
    )
    assert_eq(
      actual.0.compare(Binary::from_int(expected.to_int(), precision=53)),
      0,
      msg="\{x} rem \{y}",
    )
    if expected == 0L {
      assert_eq(actual.0.is_sign_minus(), x < 0L, msg="zero sign \{x} rem \{y}")
    }
  }
}
