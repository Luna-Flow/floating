///|
fn remainder_show(result : (BinFloat, BinaryFlags)) -> String {
  "\{result.0} flags=\{result.1.to_testfloat_bits()}"
}

///|
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
    let value = BinFloat::from_double(x).remainder_ctx(
      BinFloat::from_double(y),
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
test "remainder special cases" {
  let context = BinaryContext::binary64()
  let one = BinFloat::one()
  inspect(
    remainder_show(BinFloat::inf(Sign::Positive).remainder_ctx(one, context)),
    content=(
      #|nan flags=16
    ),
  )
  inspect(
    remainder_show(one.remainder_ctx(BinFloat::zero(), context)),
    content=(
      #|nan flags=16
    ),
  )
  inspect(
    remainder_show(one.remainder_ctx(BinFloat::inf(Sign::Negative), context)),
    content=(
      #|1p0 flags=0
    ),
  )
  inspect(
    remainder_show(BinFloat::negative_zero().remainder_ctx(one, context)),
    content=(
      #|-0 flags=0
    ),
  )
  inspect(
    remainder_show(BinFloat::signaling_nan().remainder_ctx(one, context)),
    content=(
      #|nan flags=16
    ),
  )
}

///|
test "remainder of huge exponent gaps uses modular reduction" {
  let context = BinaryContext::binary64()
  // 2^1000000000 mod 3: 2^even = 1 (mod 3), so the remainder is 1.
  let huge = BinFloat::make(BinCoeff::one(), 1000000000, 53)
  inspect(
    remainder_show(huge.remainder_ctx(BinFloat::from_int(3), context)),
    content=(
      #|1p0 flags=0
    ),
  )
  // 2^1000000001 mod 3 = 2 = -1 (mod 3): the nearest multiple is above.
  let odd = BinFloat::make(BinCoeff::one(), 1000000001, 53)
  inspect(
    remainder_show(odd.remainder_ctx(BinFloat::from_int(3), context)),
    content=(
      #|-1p0 flags=0
    ),
  )
  // A dividend far below half the divisor is returned unchanged.
  let tiny = BinFloat::make(BinCoeff::one(), -1000000000, 53)
  inspect(
    remainder_show(tiny.remainder_ctx(BinFloat::one(), context)),
    content=(
      #|0 flags=3
    ),
  )
}

///|
test "remainder agrees with an exact quotient reference" {
  let context = BinaryContext::unbounded(53)
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
    let actual = BinFloat::from_int(x.to_int(), precision=53).remainder_ctx(
      BinFloat::from_int(y.to_int(), precision=53),
      context,
    )
    assert_eq(
      actual.0.compare(BinFloat::from_int(expected.to_int(), precision=53)),
      0,
      msg="\{x} rem \{y}",
    )
    if expected == 0L {
      assert_eq(actual.0.is_negative(), x < 0L, msg="zero sign \{x} rem \{y}")
    }
  }
}
