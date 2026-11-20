// Tiny arguments within a few bits of the implementation subnormal limit
// 2^(e_min - (p - 1)): expm1, log1p, sinh, tanh, asinh, atanh, sin, tan and
// asin lost both the rounding direction and the inexact/underflow flags,
// because `binary_tiny_argument_result` built its offset 2^k with a one-bit
// `BinFloat::make`, which flushes it below 2^e_min, so the enclosure
// collapsed to the exact anchor x.
//
// Clauses, quoted from the text of IEEE Std 754-2019 (pdftotext of the PDF):
//
//   [9.2]   "A conforming operation shall return results correctly rounded for
//           the applicable rounding direction for all operands in its domain."
//   [7.6]   "an operation delivering a numerical result that signals no other
//           exception shall signal inexact if its rounded result differs from
//           what would have been computed were both exponent range and
//           precision unbounded."
//   [7.5]   underflow "when a tiny non-zero result is detected", both tininess
//           rules.
//
// Model: for such an x, f(x) = x (1 + epsilon) with |epsilon| below 2^-1000 and
// a known direction: larger magnitude than x for sinh, tan, asin, atanh,
// smaller for tanh, asinh, sin, numerically above x for expm1 and below x for
// log1p (x +- x^2/2). No breakpoint
// lies between f(x) and x(1 +- 2^-300), so rounding that dyadic with `round_ctx`
// (which owns the range rules) is the correctly rounded result and its flags.

///|
fn tiny_model(
  x : BinFloat,
  kind : Int32,
  ctx : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  // x * (1 +- 2^-300), exactly: (2^300 +- 1) * 2^-300 * x.
  let sign_up = match kind {
    0 => true
    1 => false
    2 => !x.is_negative()
    _ => x.is_negative()
  }
  let base = Coeff::one().shift_left(300)
  let factor = if sign_up {
    base.add(Coeff::one())
  } else {
    base.sub_checked(Coeff::one()).unwrap()
  }
  let magnitude = x.coefficient_().mul(factor)
  let (value, flags) = binary_round_dyadic(
    x.is_negative(),
    magnitude,
    x.exponent2() - 300,
    ctx,
  )
  (value, flags)
}

///|
test "tiny arguments near the implementation subnormal limit round with their flags" {
  let functions : Array[
    (String, Int32, (BinFloat, BinaryContext) -> (BinFloat, BinaryFlags)),
  ] = [
    ("expm1", 2, fn(x, c) { x.expm1_ctx(c) }),
    ("sinh", 0, fn(x, c) { x.sinh_ctx(c) }),
    ("tan", 0, fn(x, c) { x.tan_ctx(c) }),
    ("asin", 0, fn(x, c) { x.asin_ctx(c) }),
    ("atanh", 0, fn(x, c) { x.atanh_ctx(c) }),
    ("log1p", 3, fn(x, c) { x.log1p_ctx(c) }),
    ("tanh", 1, fn(x, c) { x.tanh_ctx(c) }),
    ("asinh", 1, fn(x, c) { x.asinh_ctx(c) }),
    ("sin", 1, fn(x, c) { x.sin_ctx(c) }),
  ]
  let mut cases = 0
  for f in functions {
    let (name, kind, run) = f
    for exponent in [-1073741870, -1073741860, -1073741823, -1073741800] {
      for coefficient in [1UL, 5UL] {
        for negative in [false, true] {
          let x = BinFloat::make_coeff(
            Coeff::from_uint64(coefficient),
            exponent,
            64,
            negative~,
          )
          for p in [2, 10, 53, 100] {
            for mode in e2s_modes() {
              for
                tininess in [
                  TininessDetection::AfterRounding,
                  TininessDetection::BeforeRounding,
                ] {
                let ctx = BinaryContext::new(
                  precision=p,
                  rounding=mode,
                  tininess~,
                )
                let (value, flags) = run(x, ctx)
                let (expected, expected_flags) = tiny_model(x, kind, ctx)
                let label = "\{name}(\{x}) p=\{p} \{e2s_mode_name(mode)} \{e2s_tininess_name(tininess)}"
                assert_eq(
                  "\{label} => \{value} \{e2s_flags(flags)}",
                  "\{label} => \{expected} \{e2s_flags(expected_flags)}",
                )
                cases += 1
              }
            }
          }
        }
      }
    }
  }
  assert_eq(cases, 9 * 4 * 2 * 2 * 4 * 5 * 2)
}
