// The labels of the bounds of a `BallFloat` (the comment of the type): a stored
// bound has `precision() == p`, the precision of the interval, exactly when it is a
// number of the format of `p` bits (at most `p` significant bits and on the grid of
// `p` bits, the band below the range floor included), and so do the infinities and
// the zeros; an exact end that is not such a number keeps another label.
//
// ORACLE (level S, self-consistency: an invariant of the representation, not a
// value): the rule is checked on every bound of the result of every public
// operation of the package for a seeded corpus (`db_interval` of
// `directed_bounds_wbtest.mbt`: random precisions 24 to 200, endpoints of 1 to 40
// random bytes anywhere in the exponent range, zero and infinite ends), and by the
// written-out cases at the end of the file (a wide end, an end below the range
// floor, the ends of `BallFloat::new(sqrt 3, 1024 ulp, 53)`). The corpus is
// the same for every operation: the test does not say what the value is, only what
// it is labelled.

///|
fn bl_fits(x : @bin_float.BinFloat, p : Int32) -> Bool {
  if x.classify() == FpClass::Infinity || x.is_zero() {
    return true
  }
  // written here, not `bound_fits`: the rule under test is not called by its test
  x.coefficient().bit_length() <= p &&
  x.exponent2() >= @bin_float.binary_implementation_e_min - p + 1
}

///|
/// Returns the failure text of the first bound of `x` that breaks the rule, or "".
fn bl_check(x : BallFloat) -> String {
  let p = x.precision()
  let mut failure = ""
  for b in [x.lower_bound(), x.upper_bound()] {
    let fits = bl_fits(b, p)
    if fits != (b.precision() == p) && failure == "" {
      failure = "bound \{b} of \{x} has the label \{b.precision()} for the precision \{p} (fits: \{fits})"
    }
  }
  failure
}

///|
fn bl_run(name : String, x : BallFloat, stats : Ref[Int32]) -> Unit raise {
  stats.val += 1
  let failure = bl_check(x)
  if failure != "" {
    fail("\{name}: \{failure}")
  }
}

///|
fn bl_corpus(divisor : Int32) -> Unit raise {
  let state = Ref(0x1b873593c2b2ae35UL)
  let count = Ref(0)
  for _ in 0..<(3000 / divisor) {
    let a = db_interval(state)
    let b = db_interval(state)
    let c = db_interval(state)
    let p2 = db_precisions[db_below(state, db_precisions.length())]
    bl_run("operand", a, count)
    bl_run("add", a.add(b), count)
    bl_run("sub", a.sub(b), count)
    bl_run("mul", a.mul(b), count)
    bl_run("div", a.div(b), count)
    bl_run("recip", a.recip(), count)
    bl_run("sqr", a.sqr(), count)
    bl_run("sqrt", a.sqrt(), count)
    bl_run("pown 3", a.pown(3), count)
    bl_run("pown -2", a.pown(-2), count)
    bl_run("fma", a.fma(b, c), count)
    bl_run("neg", a.neg(), count)
    bl_run("abs", a.abs(), count)
    bl_run("min", a.min(b), count)
    bl_run("max", a.max(b), count)
    bl_run("intersection", a.intersection(b), count)
    bl_run("convex_hull", a.convex_hull(b), count)
    bl_run("cancel_minus", a.cancel_minus(b), count)
    bl_run("cancel_plus", a.cancel_plus(b), count)
    bl_run("ceil", a.ceil(), count)
    bl_run("floor", a.floor(), count)
    bl_run("trunc", a.trunc(), count)
    bl_run("round_ties_to_even", a.round_ties_to_even(), count)
    bl_run("round_ties_to_away", a.round_ties_to_away(), count)
    bl_run("sign", a.sign(), count)
    bl_run("with_precision", a.with_precision(p2), count)
    bl_run("normalized", a.normalized(), count)
    bl_run("empty", BallFloat::empty(precision=p2), count)
    bl_run("entire", BallFloat::entire(precision=p2), count)
    // constructors from values
    let x = db_operand(state)
    let y = db_operand(state).abs()
    bl_run("exact", BallFloat::exact(x, precision=p2), count)
    bl_run("new", BallFloat::new(x, y, precision=p2), count)
    bl_run(
      "from_int",
      BallFloat::from_int(db_below(state, 100000) - 50000, precision=p2),
      count,
    )
    let d = (db_below(state, 2000000) - 1000000).to_double() / 977.0
    bl_run("from_double", BallFloat::from_double(d, precision=p2), count)
    // elementary functions on tame arguments
    let t = BallFloat::from_double(d / 1000.0, precision=p2)
    bl_run("exp", t.exp(), count)
    bl_run("atan", t.atan(), count)
    bl_run("sin", t.sin(), count)
    bl_run("cosh", t.cosh(), count)
    // the decorated wrappers keep the interval of the bare operation
    let da = BallFloatDecorated::new(a)
    let db = BallFloatDecorated::new(b)
    bl_run("decorated add", da.add(db).interval(), count)
    bl_run("decorated mul", da.mul(db).interval(), count)
    bl_run("decorated sqrt", da.sqrt().interval(), count)
  }
  assert_true(count.val > 0)
}

///|
test "labels of the bounds: every operation, sample" {
  bl_corpus(30)
}

///|
#skip("long run: the interval gate runs it with --include-skipped")
test "labels of the bounds: every operation, long" {
  bl_corpus(1)
}

///|
test "labels of the bounds: written-out cases" {
  // (1) the ends of BallFloat::new(sqrt 3, 1024 ulp, 53): numbers of 53 bits
  // whose coefficient has a trailing zero bit were labelled 52
  let three = @bin_float.BinFloat::from_int(3, precision=53)
  let root = three.sqrt()
  let ulp = @bin_float.BinFloat::make(
    @bin_float.BinCoeff::from_uint64(1024UL),
    -51,
    53,
  )
  let ball = BallFloat::new(root, ulp, precision=53)
  assert_true(ball.lower_bound().precision() == 53)
  assert_true(ball.upper_bound().precision() == 53)
  // a bound is identical (the structural equality, which reads the label) to the
  // value of the same number made at 53 bits
  assert_true(
    ball
    .lower_bound()
    .identical(
      ball.lower_bound().with_precision(53, BinaryRoundingMode::RoundTiesToEven),
    ),
  )
  // (2) wide ends: new(1, 2^-100, p = 24) has the exact ends 1 -/+ 2^-100 of 100
  // bits, kept unrounded with the label of their own bit count; the center 1 is
  // a number of 24 bits and the radius 2^-100 a number of the grid: labelled 24
  let one = @bin_float.BinFloat::one(precision=53)
  let tiny = @bin_float.BinFloat::make(@bin_float.BinCoeff::one(), -100, 24)
  let w = BallFloat::new(one, tiny, precision=24)
  assert_true(w.lower_bound().precision() >= 100)
  assert_true(w.upper_bound().precision() >= 100)
  assert_true(w.lower_bound().coefficient().bit_length() == 100)
  // `from_bounds` rounds wide ends outward: labelled 24
  let narrow = @bin_float.BinFloat::make(
    @bin_float.BinCoeff::from_uint64(3UL),
    0,
    200,
  )
  let rounded = BallFloat::from_bounds(w.lower_bound(), narrow, precision=24)
  assert_true(rounded.lower_bound().precision() == 24)
  assert_true(rounded.upper_bound().precision() == 24)
  // (3) the rule on a number finer than the grid of 24 bits below the range floor
  // (2^(e_min - 30)) and on the smallest positive number of 24 bits
  // (2^(e_min - 23)), through the stamping of the single writer
  let e_min = @bin_float.binary_implementation_e_min
  let fine = @bin_float.BinFloat::make(
    @bin_float.BinCoeff::one(),
    e_min - 30,
    31,
  )
  assert_true(stamped_bound(fine, 24).precision() == 31)
  let grid = @bin_float.BinFloat::make(
    @bin_float.BinCoeff::one(),
    e_min - 23,
    24,
  )
  assert_true(
    stamped_bound(
      grid.with_precision(24, BinaryRoundingMode::RoundTiesToEven),
      53,
    ).precision() ==
    53,
  )
  assert_true(stamped_bound(fine, 53).precision() == 53)
  // (4) zeros and infinities carry p, the empty interval too
  let z = BallFloat::from_bounds(
    @bin_float.BinFloat::zero(precision=7),
    narrow,
    precision=24,
  )
  assert_true(z.lower_bound().precision() == 24)
  let all = BallFloat::entire(precision=24)
  assert_true(
    all.lower_bound().precision() == 24 && all.upper_bound().precision() == 24,
  )
  let empty = BallFloat::empty(precision=24)
  assert_true(
    empty.lower_bound().precision() == 24 &&
    empty.upper_bound().precision() == 24,
  )
  // (5) `==` and `identical` of BallFloat do not read a label
  let a = BallFloat::from_bounds(narrow, narrow, precision=24)
  let b = BallFloat::from_bounds(
    @bin_float.BinFloat::make(@bin_float.BinCoeff::from_uint64(3UL), 0, 24),
    @bin_float.BinFloat::make(@bin_float.BinCoeff::from_uint64(3UL), 0, 53),
    precision=24,
  )
  assert_true(a == b)
  assert_true(a.identical(b))
}
