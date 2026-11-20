// Audit of the functions that decide underflow and overflow from log2 bounds
// before their Ziv loop (exp, exp2, exp10, expm1, pow, pown, rootn), checked
// after #271. Each case is compared with an independent construction: the
// function is evaluated in an unbounded context with `p + 120` bits, which is
// far from every boundary in these narrow ranges, and that value is rounded
// into the narrow context by `round_ctx`, whose rounding and tininess logic is
// tested on its own. The result is irrational (or not a rounding breakpoint),
// so the result is inexact unless the reference already was, and the clauses
// decide the rest:
//
//   [9.2]   "A conforming operation shall return results correctly rounded for
//           the applicable rounding direction for all operands in its domain."
//   [7.5.a] "after rounding — when a non-zero result computed as though the
//           exponent range were unbounded would lie strictly between ± b emin"
//   [7.5.b] "before rounding — when a non-zero result computed as though both
//           the exponent range and the precision were unbounded would lie
//           strictly between ± b emin"
//   [7.5.f] "if the rounded result is inexact — that is, it differs from what
//           would have been computed were both exponent range and precision
//           unbounded — the underflow flag shall be raised and the inexact (see
//           7.6) exception shall be signaled."
//
// The arguments sit within 2^-10, 2^-20 and 2^-40 of the thresholds
// log2(result) = q - 1 (half the smallest subnormal), q, e_min and e_max + 1.

///|
fn sib_show(value : BinFloat, flags : BinaryFlags) -> String {
  "\{value} \{e2s_flags(flags)}"
}

///|
fn sib_check(
  name : String,
  f : (BinFloat, BinaryContext) -> (BinFloat, BinaryFlags),
  x : BinFloat,
  p : Int32,
  e_min : Int32,
  e_max : Int32,
) -> Int32 raise {
  let (reference, reference_flags) = f(x, BinaryContext::unbounded(p + 120))
  let mut cases = 0
  for mode in e2s_modes() {
    for
      tininess in [
        TininessDetection::AfterRounding,
        TininessDetection::BeforeRounding,
      ] {
      let ctx = BinaryContext::new(p, rounding=mode, e_min~, e_max~, tininess~)
      let (value, flags) = f(x, ctx)
      let (expected, expected_flags) = reference.round_ctx(ctx)
      let expected_flags = {
        ..expected_flags,
        inexact: expected_flags.inexact() || reference_flags.inexact(),
      }
      let label = "\{name}(\{x}) p=\{p} e_min=\{e_min} \{e2s_mode_name(mode)} \{e2s_tininess_name(tininess)}"
      assert_eq(
        "\{label} => \{sib_show(value, flags)}",
        "\{label} => \{sib_show(expected, expected_flags)}",
      )
      cases += 1
    }
  }
  cases
}

///|
/// `center` plus the offsets 0, +-2^-10, +-2^-20 and +-2^-40, exactly.
fn sib_around(center : Double) -> Array[BinFloat] {
  let base = BinFloat::from_double(center)
  let result = [base]
  for shift in [10, 20, 40] {
    let step = BinFloat::make(BinCoeff::one(), -shift, 64)
    result.push(base.add_ctx(step, BinaryContext::unbounded(256)).0)
    result.push(base.sub_ctx(step, BinaryContext::unbounded(256)).0)
  }
  result
}

///|
fn sib_is_integer(x : BinFloat) -> Bool {
  x.floor().compare(x) == 0
}

///|
fn sib_threshold_args(
  scale : Double,
  p : Int32,
  e_min : Int32,
  e_max : Int32,
  integers : Bool,
) -> Array[BinFloat] {
  let q = e_min - (p - 1)
  let result : Array[BinFloat] = []
  for level in [q - 1, q, e_min, e_max + 1, e_max] {
    for x in sib_around(level.to_double() * scale) {
      if integers || !sib_is_integer(x) {
        result.push(x)
      }
    }
  }
  result
}

///|
test "exp family decides underflow and overflow like the reference" {
  let ln2 = 0.6931471805599453
  let log10_2 = 0.3010299956639812
  let ranges : Array[(Int32, Int32)] = [(-6, 7), (-20, 21)]
  let mut cases = 0
  for p in [2, 5, 53] {
    for range in ranges {
      let (e_min, e_max) = range
      for x in sib_threshold_args(ln2, p, e_min, e_max, true) {
        cases += sib_check("exp", fn(v, c) { v.exp_ctx(c) }, x, p, e_min, e_max)
      }
      for x in sib_threshold_args(1.0, p, e_min, e_max, false) {
        cases += sib_check(
          "exp2",
          fn(v, c) { v.exp2_ctx(c) },
          x,
          p,
          e_min,
          e_max,
        )
      }
      for x in sib_threshold_args(log10_2, p, e_min, e_max, false) {
        cases += sib_check(
          "exp10",
          fn(v, c) { v.exp10_ctx(c) },
          x,
          p,
          e_min,
          e_max,
        )
      }
      // expm1: the overflow side, the saturation at -(p + 3) ln 2, and
      // arguments so small that the result is the argument itself, tiny.
      for x in sib_threshold_args(ln2, p, e_min, e_max, true) {
        if x.compare(BinFloat::zero()) > 0 {
          cases += sib_check(
            "expm1",
            fn(v, c) { v.expm1_ctx(c) },
            x,
            p,
            e_min,
            e_max,
          )
        }
      }
      for x in sib_around(-(p + 3).to_double() * ln2) {
        cases += sib_check(
          "expm1",
          fn(v, c) { v.expm1_ctx(c) },
          x,
          p,
          e_min,
          e_max,
        )
      }
      for level in [e_min - p, e_min - p + 1, e_min - 1, e_min, e_min + 1] {
        for numerator in [1024, 1025, 1023, 1536] {
          let x = BinFloat::make(
            BinCoeff::from_uint64(numerator.to_uint64()),
            level - 10,
            64,
          )
          cases += sib_check(
            "expm1",
            fn(v, c) { v.expm1_ctx(c) },
            x,
            p,
            e_min,
            e_max,
          )
          cases += sib_check(
            "expm1",
            fn(v, c) { v.expm1_ctx(c) },
            x.neg(),
            p,
            e_min,
            e_max,
          )
        }
      }
    }
  }
  assert_true(cases > 5000)
}

///|
test "pow decides underflow and overflow like the reference" {
  let log2_3 = 1.584962500721156
  let three = BinFloat::from_int(3, precision=53)
  let mut cases = 0
  for p in [2, 5] {
    for range in [(-6, 7), (-20, 21)] {
      let (e_min, e_max) = range
      for y in sib_threshold_args(1.0 / log2_3, p, e_min, e_max, false) {
        cases += sib_check(
          "pow3",
          fn(v, c) { three.pow_ctx(v, c) },
          y,
          p,
          e_min,
          e_max,
        )
      }
    }
  }
  assert_true(cases > 500)
}

///|
test "pown and rootn decide underflow and overflow like the reference" {
  let three = BinFloat::from_int(3, precision=53)
  let mut cases = 0
  for p in [2, 5] {
    for range in [(-6, 7), (-20, 21)] {
      let (e_min, e_max) = range
      for n in -40..<41 {
        if n != 0 {
          cases += sib_check(
            "pown(3, \{n})",
            fn(v, c) { v.pown_ctx(n, c) },
            three,
            p,
            e_min,
            e_max,
          )
        }
      }
      // rootn(x, -k) = x^(-1/k) leaves the range for large or tiny x.
      for degree in [-2, -3, 5] {
        for step in 0..<61 {
          let exponent = -90 + 3 * step
          let x = BinFloat::make(BinCoeff::from_uint64(5UL), exponent, 53)
          cases += sib_check(
            "rootn(\{degree})",
            fn(v, c) { v.rootn_ctx(degree, c) },
            x,
            p,
            e_min,
            e_max,
          )
        }
      }
    }
  }
  assert_true(cases > 500)
}
