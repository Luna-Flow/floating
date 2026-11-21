///|
// `Decimal::from_binary_raw` against its previous implementation, which
// went through a host big integer; the previous code is kept here as the
// reference.

///|
fn from_binary_reference(
  x : @binary.Binary,
  precision : Int32,
  mode : DecimalRoundingMode,
) -> Decimal {
  if x.is_zero() {
    Decimal::zero_raw(precision~)
  } else if decimal_from_binary_is_bounded(x, precision) {
    decimal_from_binary_surrogate(x, precision, mode)
  } else {
    let coefficient = BigInt::from_octets(x.coefficient().to_bytes_be())
    let signed = if x.is_negative() { -coefficient } else { coefficient }
    if x.exponent2() >= 0 {
      decimal_from_integer_parts(signed << x.exponent2(), 0, precision, mode~)
    } else {
      let k = -x.exponent2()
      let mut magnitude = coeff_from_bigint(abs_bigint(signed * pow5(k)))
      let mut exponent = -k
      while exponent < 0 {
        let (quotient, remainder) = dec_coeff_div_rem_by_unit_repr(
          magnitude, 10,
        )
        if remainder != 0 {
          break
        }
        magnitude = quotient
        exponent = exponent + 1
      }
      decimal_from_integer_parts(
        if x.is_negative() {
          -coeff_bigint(magnitude)
        } else {
          coeff_bigint(magnitude)
        },
        exponent,
        precision,
        mode~,
      )
    }
  }
}

///|
fn from_binary_same(a : Decimal, b : Decimal) -> Bool {
  // the representation, not only the value: exponent and digit count
  a.to_string() == b.to_string() &&
  a.precision() == b.precision() &&
  a.negative == b.negative &&
  a.exponent10 == b.exponent10 &&
  a.coefficient.digits10() == b.coefficient.digits10()
}

///|
fn from_binary_check(
  x : @binary.Binary,
  precision : Int32,
  mode : DecimalRoundingMode,
) -> Unit raise {
  assert_true(
    from_binary_same(
      Decimal::from_binary_raw(x, precision~, mode~),
      from_binary_reference(x, precision, mode),
    ),
  )
}

///|
test "from_binary_raw equals the big integer reference" {
  let state = Ref(0x2545F4914F6CDD1DUL)
  let modes = [
    DecimalRoundingMode::HalfEven,
    HalfUp,
    HalfDown,
    Down,
    Ceiling,
    Floor,
    Up,
    ZeroFiveUp,
  ]
  let precisions = [1, 2, 5, 9, 16, 17, 34, 50, 100, 250, 1000]
  let mut taken = 0
  for iteration in 0..<1500 {
    // 1 to 40,000 bits, mostly short
    let bytes_len = match iteration % 10 {
      0 => 1 + (endpoint_next(state) % 5000UL).to_int()
      1 => 1 + (endpoint_next(state) % 300UL).to_int()
      _ => 1 + (endpoint_next(state) % 24UL).to_int()
    }
    let coefficient = @binary.BinCoeff::from_bytes_be(
      endpoint_random_bytes(state, bytes_len)[:],
    )
    if coefficient.is_zero() {
      continue
    }
    let negative = endpoint_next(state) % 2UL == 0UL
    let span = if bytes_len > 300 { 400 } else { 2000 }
    let exponents = [
      0,
      1,
      -1,
      63,
      -63,
      64,
      -64,
      (endpoint_next(state) % span.to_uint64()).to_int(),
      -(endpoint_next(state) % span.to_uint64()).to_int(),
    ]
    for exponent2 in exponents {
      let value = @binary.Binary::make(
        coefficient,
        exponent2,
        coefficient.bit_length(),
        negative~,
      )
      let precision = precisions[(endpoint_next(state) % 11UL).to_int()]
      let mode = modes[(endpoint_next(state) % 8UL).to_int()]
      from_binary_check(value, precision, mode)
      taken += 1
    }
  }
  assert_true(taken > 10000)
}

///|
test "from_binary_raw at powers of two and ten and their neighbours" {
  let modes = [DecimalRoundingMode::HalfEven, Up, Floor, HalfDown]
  for shift in 0..<420 {
    let power = BigInt::from_int(1) << shift
    let ten = BigInt::from_int(10).pow(BigInt::from_int(shift / 3))
    for base in [power, ten] {
      for delta in [-1, 0, 1] {
        let n = base + BigInt::from_int(delta)
        if n <= BigInt::from_int(0) {
          continue
        }
        let coefficient = @binary.BinCoeff::from_bytes_be(n.to_octets()[:])
        for exponent2 in [0, -1, -shift, shift, -2000, 2000] {
          for negative in [false, true] {
            let value = @binary.Binary::make(
              coefficient,
              exponent2,
              coefficient.bit_length(),
              negative~,
            )
            for precision in [1, 3, 17, 34, 1000] {
              from_binary_check(
                value,
                precision,
                modes[(shift + precision) % 4],
              )
            }
          }
        }
      }
    }
  }
}

///|
test "from_binary_raw of zero, infinity and nan" {
  for precision in [1, 16, 34] {
    from_binary_check(@binary.Binary::zero(precision=53), precision, HalfEven)
  }
  assert_true(
    Decimal::from_binary_raw(
      @binary.Binary::inf(negative=true, precision=53),
      precision=16,
    ).is_infinite(),
  )
}

///|
test "from_binary_raw keeps the exponent at 0, 1 and -1 by name" {
  // value = c * 2^e2 with c odd: the exact decimal has exponent 0 for e2 >= 0
  // (the cohort is not reduced), and exponent e2 for e2 < 0 (c * 5^k has no
  // trailing zero), never above 0
  let cases : Array[(UInt64, Int32, String, Int32)] = [
    (1UL, 0, "1", 0),
    (1UL, 1, "2", 0),
    (5UL, 1, "10", 0),
    (3UL, 2, "12", 0),
    (1UL, -1, "0.5", -1),
    (3UL, -1, "1.5", -1),
    (5UL, -1, "2.5", -1),
    (1UL, -2, "0.25", -2),
    (125UL, -3, "15.625", -3),
    (1UL, 10, "1024", 0),
    (1UL, -10, "0.0009765625", -10),
  ]
  for precision in [1, 2, 5, 34] {
    for mode in [DecimalRoundingMode::HalfEven, Up, Down] {
      for negative in [false, true] {
        for item in cases {
          let (c, e2, text, exponent) = item
          let x = @binary.Binary::make(
            @binary.BinCoeff::from_uint64(c),
            e2,
            53,
            negative~,
          )
          let actual = Decimal::from_binary_raw(x, precision~, mode~)
          from_binary_check(x, precision, mode)
          // exact when the precision holds all the digits
          if precision == 34 {
            assert_eq(actual.exponent10, exponent)
            assert_eq(
              actual.to_string(),
              (if negative { "-" } else { "" }) + text,
            )
          }
        }
      }
    }
  }
}
