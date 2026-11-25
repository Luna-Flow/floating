// Decimal::class_of (IEEE Std 754-2019 5.7.2 class) in the three decimal
// interchange contexts. Subnormal means a nonzero value whose adjusted
// exponent is below emin; class_name must be the text of the same class.

///|
fn dcls_name(c : IeeeClass) -> String {
  match c {
    SignalingNaN => "sNaN"
    QuietNaN => "NaN"
    NegativeInfinity => "-Infinity"
    NegativeNormal => "-Normal"
    NegativeSubnormal => "-Subnormal"
    NegativeZero => "-Zero"
    PositiveZero => "+Zero"
    PositiveSubnormal => "+Subnormal"
    PositiveNormal => "+Normal"
    PositiveInfinity => "+Infinity"
  }
}

///|
fn dcls_cases(
  emin : Int32,
  etiny : Int32,
  digits : Int32,
  emax : Int32,
) -> Array[(String, IeeeClass)] {
  let nines = "9".repeat(digits)
  [
    ("sNaN", SignalingNaN),
    ("-sNaN123", SignalingNaN),
    ("NaN", QuietNaN),
    ("-NaN7", QuietNaN),
    ("Infinity", PositiveInfinity),
    ("-Infinity", NegativeInfinity),
    ("0", PositiveZero),
    ("-0", NegativeZero),
    ("0E+\{emax}", PositiveZero),
    ("-0E\{etiny}", NegativeZero),
    ("1", PositiveNormal),
    ("-1", NegativeNormal),
    ("1E\{emin}", PositiveNormal),
    ("-1E\{emin}", NegativeNormal),
    ("\{nines}E+\{emax - digits + 1}", PositiveNormal),
    ("-\{nines}E+\{emax - digits + 1}", NegativeNormal),
    // smallest positive subnormal: coefficient 1 at the tiny exponent
    ("1E\{etiny}", PositiveSubnormal),
    ("-1E\{etiny}", NegativeSubnormal),
    // largest subnormal: adjusted exponent emin - 1
    ("\{nines}E\{emin - digits}", PositiveSubnormal),
    ("-\{nines}E\{emin - digits}", NegativeSubnormal),
  ]
}

///|
// oracle: A
// source: written out from IEEE 754-2019 5.7.2 (class: sNaN, qNaN, infinities, normal, subnormal when the adjusted exponent is below emin, zero) and the formats of 3.6 Table 3.6 (decimal32 emin -95 etiny -101 p 7 emax 96, decimal64 -383 -398 16 384, decimal128 -6143 -6176 34 6144): each of the twenty operand texts has the class named beside it, at the smallest and largest subnormal, the smallest normal, the largest finite and the zeros of both signs
// shares: Decimal::from_string and class_of (the code under test); the text of the operands is built from the format parameters by string interpolation
test "Decimal::class_of matches class_name for every class in every format" {
  let formats : Array[(DecimalContext, Int32, Int32, Int32, Int32)] = [
    (DecimalContext::decimal32(), -95, -101, 7, 96),
    (DecimalContext::decimal64(), -383, -398, 16, 384),
    (DecimalContext::decimal128(), -6143, -6176, 34, 6144),
  ]
  let seen : Map[String, Int32] = Map([])
  for f in formats {
    let (ctx, emin, etiny, digits, emax) = f
    for c in dcls_cases(emin, etiny, digits, emax) {
      let (text, expected) = c
      let x = Decimal::from_string(text, precision=digits).unwrap()
      assert_true(x.class_of(ctx) == expected, msg="class_of \{text}")
      seen[dcls_name(expected)] = 1
    }
  }
  assert_eq(seen.length(), 10)
}
