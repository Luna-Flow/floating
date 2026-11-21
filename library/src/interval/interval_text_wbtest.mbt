// Text output (IEEE 1788-2015 13.3, 13.4): the portable literal of `Show`, the exact text,
// and the midpoint-radius view.
//
// Oracles (level as in the oracle rule of the repository):
// - the tables of interval_text_oracle_wbtest.mbt (2,312 rows, `tools/interval_text_oracle.py`):
//   level A, expected texts computed with exact fractions, containment checked there;
// - the written-out texts below (the standard's forms, 0.1, the hexadecimal fallback, the
//   refusals of `from_exact_string`): level A, expected values written out;
// - the two round-trip tests (Show read back by `from_string`, exact text read back by
//   `from_exact_string`) use the library's own reader: level S, consistency only; they are
//   there to catch a printer that the written-out tables do not reach (other precisions and
//   exponents), and the containment bound is checked against endpoints that the printer does not
//   compute (`next_up_ctx` of the reader's result against the original endpoint).

///|
fn text_bound(
  coefficient : UInt64,
  exponent : Int32,
  precision : Int32,
  negative : Bool,
) -> @bin_float.BinFloat {
  if coefficient == 0UL {
    @bin_float.BinFloat::zero(precision~)
  } else {
    @bin_float.BinFloat::make(
      @bin_float.BinCoeff::from_uint64(coefficient),
      exponent,
      precision,
      negative~,
    )
  }
}

///|
fn text_interval(
  a : @bin_float.BinFloat,
  b : @bin_float.BinFloat,
  precision : Int32,
) -> Interval {
  if a.compare(b) <= 0 {
    Interval::from_bounds(a, b, precision~)
  } else {
    Interval::from_bounds(b, a, precision~)
  }
}

///|
test "Show: the portable literal of the standard's cases" {
  inspect(Interval::empty().to_string(), content="[empty]")
  inspect(Interval::entire().to_string(), content="[entire]")
  inspect(
    Interval::exact(@bin_float.BinFloat::one()).to_string(),
    content="[1, 1]",
  )
  inspect(
    Interval::from_bounds(
      @bin_float.BinFloat::zero(),
      @bin_float.BinFloat::inf(@def.Sign::Positive),
    ).to_string(),
    content="[0, inf]",
  )
  inspect(
    Interval::from_bounds(
      @bin_float.BinFloat::inf(@def.Sign::Negative),
      @bin_float.BinFloat::one(),
    ).to_string(),
    content="[-inf, 1]",
  )
  // the literal [0.1] has the doubles on both sides of 0.1 as its bounds; each bound is
  // written with the fewest digits within one unit in the last place
  let tenth = Interval::from_string("[0.1]").unwrap()
  inspect(
    tenth.to_string(),
    content="[9.999999999999999e-2, 1.0000000000000001e-1]",
  )
  inspect(
    DecoratedInterval::new(tenth, decoration=Def).to_string(),
    content="[9.999999999999999e-2, 1.0000000000000001e-1]_def",
  )
  inspect(DecoratedInterval::nai().to_string(), content="[nai]")
}

///|
test "Show reads back, at its precision, to an interval that contains it with the same decoration" {
  let precisions = [2, 8, 11, 24, 53, 64, 113]
  let mut state = 0x9e3779b97f4a7c15UL
  let mut count = 0
  for i in 0..<1500 {
    state = state * 6364136223846793005UL + 1442695040888963407UL
    let a = state >> (state & 63UL).to_int()
    state = state * 6364136223846793005UL + 1442695040888963407UL
    let b = state >> (state & 63UL).to_int()
    state = state * 6364136223846793005UL + 1442695040888963407UL
    let e1 = (state >> 40).to_int() % 600 - 300
    state = state * 6364136223846793005UL + 1442695040888963407UL
    let e2 = (state >> 40).to_int() % 600 - 300
    let p = precisions[i % precisions.length()]
    let x = text_interval(
      text_bound(a, e1, p, i % 3 == 0),
      text_bound(b, e2, p, i % 5 == 0),
      p,
    )
    let text = x.to_string()
    let back = Interval::from_string(text, precision=p).unwrap()
    assert_true(x.subset(back), msg=text)
    // no more than one unit in the last place beyond each bound
    let context = @bin_float.BinaryContext::new(precision=p)
    assert_true(
      back.lower_bound().next_up_ctx(context).0.compare(x.lower_bound()) >= 0,
      msg=text,
    )
    assert_true(
      back.upper_bound().next_down_ctx(context).0.compare(x.upper_bound()) <= 0,
      msg=text,
    )
    let decorated = DecoratedInterval::new(x, decoration=Def)
    let decorated_back = DecoratedInterval::from_string(
      decorated.to_string(),
      precision=p,
    ).unwrap()
    assert_true(decorated.subset(decorated_back), msg=text)
    assert_eq(decorated_back.decoration(), Def)
    count += 1
  }
  assert_eq(count, 1500)
}

///|
test "Show: a bound far down the exponent range is written in hexadecimal, not expanded" {
  let e_max = @bin_float.binary_implementation_e_max
  let x = Interval::from_bounds(
    text_bound(3UL, e_max - 10, 53, false),
    text_bound(5UL, e_max - 5, 53, false),
  )
  let text = x.to_string()
  assert_true(text.has_prefix("[0x"), msg=text)
  let back = Interval::from_string(text).unwrap()
  assert_true(x.identical(back), msg=text)
}

///|
test "to_exact_string and from_exact_string recover the datum" {
  let precisions = [2, 8, 11, 24, 53, 64, 113]
  let mut state = 0xd1b54a32d192ed03UL
  for i in 0..<1500 {
    state = state * 6364136223846793005UL + 1442695040888963407UL
    let a = state >> (state & 63UL).to_int()
    state = state * 6364136223846793005UL + 1442695040888963407UL
    let b = state >> (state & 63UL).to_int()
    state = state * 6364136223846793005UL + 1442695040888963407UL
    let e1 = (state >> 40).to_int() % 4000 - 2000
    state = state * 6364136223846793005UL + 1442695040888963407UL
    let e2 = (state >> 40).to_int() % 4000 - 2000
    let p = precisions[i % precisions.length()]
    let x = text_interval(
      text_bound(a, e1, p, i % 3 == 0),
      text_bound(b, e2, p, i % 5 == 0),
      p,
    )
    let text = x.to_exact_string()
    let back = Interval::from_exact_string(text, precision=p).unwrap()
    assert_true(x.identical(back), msg=text)
    let decorated = DecoratedInterval::new(x, decoration=Dac)
    let decorated_back = DecoratedInterval::from_exact_string(
      decorated.to_exact_string(),
      precision=p,
    ).unwrap()
    assert_true(decorated.identical(decorated_back), msg=text)
  }
  for
    x in [
      Interval::empty(),
      Interval::entire(),
      Interval::from_bounds(
        @bin_float.BinFloat::zero(),
        @bin_float.BinFloat::inf(@def.Sign::Positive),
      ),
    ] {
    let back = Interval::from_exact_string(x.to_exact_string()).unwrap()
    assert_true(x.identical(back), msg=x.to_exact_string())
  }
  assert_true(DecoratedInterval::from_exact_string("[nai]").unwrap().is_nai())
}

///|
test "exact text: hexadecimal bounds, refused when reading would round" {
  inspect(
    Interval::from_bounds(
      text_bound(1UL, -1, 53, false),
      text_bound(3UL, 4, 53, false),
    ).to_exact_string(),
    content="[0x1p-1, 0x3p4]",
  )
  inspect(
    DecoratedInterval::new(
      Interval::from_bounds(
        text_bound(1UL, 0, 53, true),
        text_bound(0UL, 0, 53, false),
      ),
      decoration=Com,
    ).to_exact_string(),
    content="[-0x1p0, 0x0p0]_com",
  )
  // a decimal bound would round
  assert_true(Interval::from_exact_string("[0.1, 0.2]") is Err(_))
  assert_true(Interval::from_exact_string("0x1p0") is Err(_))
  assert_true(Interval::from_exact_string("[0x1p0]") is Err(_))
  // the bounds have more bits than the precision gives: read exactly, with the precision 8
  inspect(
    Interval::from_exact_string("[0x2p0, 0x1fffffp0]", precision=8)
    .map(fn(v) { v.to_exact_string() })
    .unwrap_or("err"),
    content="[0x1p1, 0x1fffffp0]",
  )
  assert_eq(
    Interval::from_exact_string("[0x2p0, 0x1fffffp0]", precision=21)
    .map(fn(v) { v.to_exact_string() })
    .unwrap_or("err"),
    "[0x1p1, 0x1fffffp0]",
  )
  assert_true(DecoratedInterval::from_exact_string("[0x1p0, 0x2p0]") is Err(_))
  assert_true(
    DecoratedInterval::from_exact_string("[0x1p0, 0x2p0]_xyz") is Err(_),
  )
}

///|
test "to_ball_string keeps the midpoint-radius view and is not a literal" {
  let x = Interval::from_bounds(
    text_bound(1UL, 0, 53, false),
    text_bound(3UL, 0, 53, false),
  )
  inspect(x.to_ball_string(), content="1p1 +/- 1p0")
  inspect(Interval::empty().to_ball_string(), content="[empty]")
  inspect(
    DecoratedInterval::new(x, decoration=Com).to_ball_string(),
    content="1p1 +/- 1p0_com",
  )
  assert_true(Interval::from_string(x.to_ball_string()) is Err(_))
}

///|
/// The exact text is written from the stored coefficient and exponent, which is sound because
/// the stored coefficient of a nonzero finite `BinFloat` is odd (level A: written-out
/// expectations). `make` and `from_hex` of an even coefficient, reading at a precision,
/// `with_precision`, an integer, a double and the results of operations all give the odd form,
/// so one value has one text whatever the way it was made.
test "the stored coefficient is odd, so the exact text is the value's" {
  let ctx = @bin_float.BinaryContext::new(precision=53)
  let values : Array[(@bin_float.BinFloat, String)] = [
    (@bin_float.BinFloat::from_int(2, precision=53), "0x1p1"),
    (@bin_float.BinFloat::from_int(1024, precision=64), "0x1p10"),
    (@bin_float.BinFloat::from_double(6.0), "0x3p1"),
    (@bin_float.BinFloat::from_double(0.5), "0x1p-1"),
    (@bin_float.BinFloat::from_hex("0x8000p3", 53).unwrap(), "0x1p18"),
    (@bin_float.BinFloat::from_hex_ctx("0x1.8p0", ctx).unwrap().0, "0x3p-1"),
    (@bin_float.BinFloat::from_string_ctx("0.5", ctx).unwrap().0, "0x1p-1"),
    (@bin_float.BinFloat::from_string_ctx("1024", ctx).unwrap().0, "0x1p10"),
    (
      @bin_float.BinFloat::make(
        @bin_float.BinCoeff::from_uint64(0x13000000000000UL),
        -53,
        53,
        negative=true,
      ),
      "-0x13p-5",
    ),
    (
      @bin_float.BinFloat::from_int(3, precision=53).mul_ctx(
        @bin_float.BinFloat::from_int(8, precision=53),
        ctx,
      ).0,
      "0x3p3",
    ),
    (
      @bin_float.BinFloat::from_int(1, precision=53).with_precision(
        113,
        @bin_float.BinaryRoundingMode::RoundTiesToEven,
      ),
      "0x1p0",
    ),
    (
      @bin_float.BinFloat::from_int(5, precision=53).sub_ctx(
        @bin_float.BinFloat::from_int(1, precision=53),
        ctx,
      ).0,
      "0x1p2",
    ),
  ]
  for pair in values {
    let (value, expected) = pair
    assert_true(
      value.coefficient().to_radix_string(2).has_suffix("1"),
      msg=expected,
    )
    let x = Interval::from_bounds(
      value,
      @bin_float.BinFloat::inf(@def.Sign::Positive, precision=64),
    )
    assert_eq(x.to_exact_string(), "[" + expected + ", inf]", msg=expected)
  }
}

///|
/// `from_exact_string` reads exactly or refuses; the texts and verdicts are written out
/// (level A), the oracle table covers many more (interval_text_oracle_wbtest.mbt).
test "from_exact_string: read exactly at the bit count of the text, never widened" {
  let read = fn(text : String, precision : Int32) -> String {
    Interval::from_exact_string(text, precision~)
    .map(fn(v) { v.to_exact_string() })
    .unwrap_or("err")
  }
  // 0x1.8 is 1.5 (two bits); a bound with more bits than the precision is kept as it is, with the
  // precision of the interval (13.4: the datum comes back): neither `[1, 2]` nor an error
  assert_eq(read("[0x1.8p0, 0x2p0]", 2), "[0x3p-1, 0x1p1]")
  assert_eq(read("[0x1.8p0, 0x2p0]", 1), "[0x3p-1, 0x1p1]")
  assert_eq(
    read("[0x1.00000000000001p0, 0x2p0]", 53),
    "[0x100000000000001p-56, 0x1p1]",
  )
  assert_eq(
    read("[0x1.00000000000001p0, 0x2p0]", 57),
    "[0x100000000000001p-56, 0x1p1]",
  )
  assert_eq(
    Interval::from_exact_string("[0x1.00000000000001p0, 0x2p0]", precision=53)
    .unwrap()
    .precision(),
    53,
  )
  // leading zeros, upper case, a bare point and a leading point
  assert_eq(read("[0X00A.80P0, 0X00B.0P0]", 5), "[0x15p-1, 0xbp0]")
  assert_eq(read("[0X002.80P0, 0x3p0]", 3), "[0x5p-1, 0x3p0]")
  assert_eq(read("[0x.8p1, 0x1.8p0]", 53), "[0x1p0, 0x3p-1]")
  assert_eq(read("[0x1.p0, 0x2.p0]", 53), "[0x1p0, 0x1p1]")
  // a mantissa longer than the precision whose low digits are zero
  assert_eq(read("[0x1.800000000000000000p0, 0x2p0]", 2), "[0x3p-1, 0x1p1]")
  assert_eq(read("[0x100000000000000000000p-80, 0x2p0]", 1), "[0x1p0, 0x1p1]")
  // refused: not an exact text, a decimal bound, a reversed pair, malformed
  assert_eq(read("[0.1, 0.2]", 53), "err")
  assert_eq(read("[0x1p0, 0x2p0, 0x3p0]", 53), "err")
  assert_eq(read("[0x2p0, 0x1p0]", 53), "err")
  assert_eq(read("[0x1, 0x2p0]", 53), "err")
  assert_eq(read("[-inf, 0x2p0]", 53), "[-inf, 0x1p1]")
  assert_eq(read("[0x0p0, -0x0p0]", 53), "[0x0p0, 0x0p0]")
  // refused: beyond the exponent range of the library (EMAX = 2^30 - 1, the grid floor is
  // e_min - max(bits, precision) + 1 with e_min = 2 - 2^30)
  assert_eq(read("[-inf, 0x1p1073741823]", 53), "[-inf, 0x1p1073741823]")
  assert_eq(read("[-inf, 0x1p1073741824]", 53), "err")
  assert_eq(read("[0x1p-1073741874, inf]", 53), "[0x1p-1073741874, inf]")
  assert_eq(read("[0x1p-1073741875, inf]", 53), "err")
  // finer than the grid of 53 bits below the floor, with 60 bits of its own: stored with its own
  // label (0x800000000000001 has 60 bits; the grid of 60 bits ends at e_min - 59)
  assert_eq(
    read("[0x800000000000001p-1073741881, inf]", 53),
    "[0x800000000000001p-1073741881, inf]",
  )
  assert_eq(read("[0x800000000000001p-1073741882, inf]", 53), "err")
}

///|
/// The round trip of the exact text for the intervals of the type with ends wider than the
/// precision (13.4: every interval of the type): an end of `new` kept unrounded, its mirror from
/// `cancel_minus`, an end finer than the grid below the range floor. The texts are written out
/// (level A); the identical round trip uses the reader that the oracle table checks.
test "the exact text of an interval with an end wider than the precision reads back identical" {
  let wide = @bin_float.BinFloat::from_hex("0x1.00000000000001p0", 60).unwrap()
  let zero = @bin_float.BinFloat::zero(precision=53)
  let x = Interval::new(wide, zero, precision=53)
  assert_eq(x.precision(), 53)
  inspect(
    x.to_exact_string(),
    content="[0xffffffffffffffp-56, 0x100000000000001p-56]",
  )
  let back = Interval::from_exact_string(x.to_exact_string(), precision=53).unwrap()
  assert_true(x.identical(back))
  // the mirror: the end of a cancellation, kept unrounded (written out from the exact values)
  let u = @bin_float.BinFloat::from_hex("0x1p-60", 60).unwrap()
  let big = Interval::from_bounds(
    @bin_float.BinFloat::from_hex("0x1p0", 53).unwrap(),
    @bin_float.BinFloat::from_hex("0x2p0", 53).unwrap(),
    precision=53,
  )
  let small = Interval::from_bounds(
    u,
    u.mul_ctx(
      @bin_float.BinFloat::from_int(2, precision=53),
      @bin_float.BinaryContext::new(precision=60),
    ).0,
    precision=60,
  )
  let c = big.cancel_minus(small)
  let c_back = Interval::from_exact_string(
    c.to_exact_string(),
    precision=c.precision(),
  ).unwrap()
  assert_true(c.identical(c_back), msg=c.to_exact_string())
  // an end finer than the grid of 53 bits below the range floor
  let fine = Interval::from_exact_string(
    "[0x800000000000001p-1073741881, 0x1p0]",
    precision=53,
  ).unwrap()
  assert_eq(fine.precision(), 53)
  let fine_back = Interval::from_exact_string(
    fine.to_exact_string(),
    precision=53,
  ).unwrap()
  assert_true(fine.identical(fine_back))
}

///|
/// `Show` of such intervals: the literal contains the interval and reads back containing it
/// (written-out texts; the generated rows are in the oracle table above).
test "Show of an interval with an end wider than the precision contains it" {
  let x = Interval::from_exact_string(
    "[0x1.00000000000001p0, 0x2p0]",
    precision=53,
  ).unwrap()
  // the lower end is rounded down to 1 and the upper end 2 is exact: the literal contains x
  inspect(x.to_string(), content="[1, 2]")
  let back = Interval::from_string(x.to_string(), precision=53).unwrap()
  assert_true(x.subset(back))
  let mirror = Interval::from_exact_string(
    "[-0x2p0, -0x1.00000000000001p0]",
    precision=53,
  ).unwrap()
  let mirror_back = Interval::from_string(mirror.to_string(), precision=53).unwrap()
  assert_true(mirror.subset(mirror_back))
}

///|
/// A zero bound is written without a sign in `Show` and in the exact text, whatever sign it
/// has on input and whatever sign the observers give it after 12.12.8 (`lower_bound` of a zero
/// is -0): the literal of [0, 0] does not carry signs (13.3 does not ask for them).
test "a zero bound has no sign in the texts" {
  let negative_zero = @bin_float.BinFloat::negative_zero(precision=53)
  let zero = @bin_float.BinFloat::zero(precision=53)
  let one = @bin_float.BinFloat::one(precision=53)
  for pair in [(zero, one), (negative_zero, one)] {
    let x = Interval::from_bounds(pair.0, pair.1)
    inspect(x.to_string(), content="[0, 1]")
    inspect(x.to_exact_string(), content="[0x0p0, 0x1p0]")
    assert_true(x.lower_bound().is_negative())
  }
  for pair in [(one.neg(), zero), (one.neg(), negative_zero)] {
    let x = Interval::from_bounds(pair.0, pair.1)
    inspect(x.to_string(), content="[-1, 0]")
    inspect(x.to_exact_string(), content="[-0x1p0, 0x0p0]")
  }
}

///|
/// Level S (consistency, the reader and the printer are ours): intervals made by `new` with a
/// center wider than the precision, and by `cancel_minus`, whose ends are kept unrounded, give
/// back an identical interval from their exact text, and their `Show` literal contains them and
/// reads back containing them. The evidence for the texts themselves is the oracle table of wide
/// ends (level A); this adds reach over other precisions and exponents.
test "ends wider than the precision: exact text identical, Show contains (consistency)" {
  let precisions = [2, 8, 11, 24, 53, 64, 113]
  let mut state = 0x2545f4914f6cdd1dUL
  let mut wide_ends = 0
  for i in 0..<1500 {
    state = state * 6364136223846793005UL + 1442695040888963407UL
    let p = precisions[i % precisions.length()]
    let extra = 1 + (state >> 59).to_int() % 8
    state = state * 6364136223846793005UL + 1442695040888963407UL
    let coefficient = (state >> 3) | 1UL
    let bits = Int32::min(p + extra, 62)
    let m = (coefficient >> (64 - bits).max(0)) | 1UL
    state = state * 6364136223846793005UL + 1442695040888963407UL
    let exponent = (state >> 40).to_int() % 200 - 100
    let center = @bin_float.BinFloat::make(
      @bin_float.BinCoeff::from_uint64(m),
      exponent,
      bits,
      negative=i % 3 == 0,
    )
    let radius = if i % 4 == 0 {
      @bin_float.BinFloat::zero(precision=p)
    } else {
      @bin_float.BinFloat::make(
        @bin_float.BinCoeff::from_uint64(1UL),
        exponent - bits / 2,
        p,
      )
    }
    let x = Interval::new(center, radius, precision=p)
    if x.lower_bound().precision() > p || x.upper_bound().precision() > p {
      wide_ends += 1
    }
    let text = x.to_exact_string()
    let back = Interval::from_exact_string(text, precision=p).unwrap()
    assert_true(x.identical(back), msg=text)
    let shown = x.to_string()
    let reread = Interval::from_string(shown, precision=p).unwrap()
    assert_true(x.subset(reread), msg=shown)
  }
  // the draw reaches intervals whose ends really are wider than the precision
  assert_true(wide_ends > 100)
}

///|
/// The label of a bound read from an exact text: a bound with more bits than the precision
/// carries the label of its own bit count (the type comment of `Interval`), not a label that
/// depends on the digits of the text; a bound of the format carries the precision. Written out:
/// `0x1.00000000000001p0` has 57 bits, with any number of trailing zero digits.
test "from_exact_string: the label of a wide bound is its own bit count" {
  for
    text in [
      "[0x1.00000000000001p0, 0x2p0]", "[0x1.000000000000010000p0, 0x2p0]", "[0x1.00000000000001000000000000000000000000000000p0, 0x2p0]",
      "[0X100000000000001P-56, 0X2P0]",
    ] {
    let x = Interval::from_exact_string(text, precision=53).unwrap()
    assert_eq(x.precision(), 53, msg=text)
    assert_eq(x.lower_bound().precision(), 57, msg=text)
    assert_eq(x.upper_bound().precision(), 53, msg=text)
  }
  // the same number made by `new` carries the same label
  let made = Interval::new(
    @bin_float.BinFloat::from_hex("0x1.00000000000001p0", 60).unwrap(),
    @bin_float.BinFloat::zero(precision=53),
    precision=53,
  )
  assert_eq(made.upper_bound().precision(), 57)
  // a bound of the format carries the precision, and so do zeros and infinities
  let y = Interval::from_exact_string("[-inf, 0x3p0]", precision=53).unwrap()
  assert_eq(y.upper_bound().precision(), 53)
  let z = Interval::from_exact_string("[0x0p0, 0x1.8p0]", precision=24).unwrap()
  assert_eq(z.lower_bound().precision(), 24)
  assert_eq(z.upper_bound().precision(), 24)
}

///|
/// The reason of a refusal is the one of the interval rules, true for the infinite cases too.
test "from_exact_string: the refusal names the broken rule" {
  let reason = fn(text : String) -> String {
    match Interval::from_exact_string(text) {
      Ok(_) => "ok"
      Err(e) => e.message
    }
  }
  assert_true(reason("[inf, inf]").contains("positive infinity"))
  assert_true(reason("[-inf, -inf]").contains("negative infinity"))
  assert_true(reason("[inf, 0x1p0]").contains("positive infinity"))
  assert_true(reason("[0x2p0, 0x1p0]").contains("must not exceed"))
  assert_true(reason("[0x1p1073741824, inf]").contains("exponent range"))
}
