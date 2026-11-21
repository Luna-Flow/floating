// `sinpi`, `tanpi` and `cospi` of a tiny argument within a few bits of the
// implementation subnormal limit (#316). The periodic reduction rebuilt the
// argument with a `Binary::make` at the bit length of its residue, which
// flushes a value that small: sinpi gave a certification error, tanpi -0 and
// cospi exactly 1 with no flags.
//
// Clauses, quoted from the text of IEEE Std 754-2019 (pdftotext of the PDF):
//
//   [9.2]   "A conforming operation shall return results correctly rounded for
//           the applicable rounding direction for all operands in its domain."
//   [Table 9.1] sinPi: sin(π × x), "underflow"; tanPi: tan(π × x), "underflow".
//   [7.6]   inexact "if its rounded result differs from what would have been
//           computed were both exponent range and precision unbounded."
//   [9.2.1] "For the operations sin, tan, sinPi, tanPi, ... f (+0) is +0 and
//           f (−0) is −0 with no exception." (not this case: x is nonzero).
//
// Model: for such an x, sinPi(x) = πx (1 - eps), tanPi(x) = πx (1 + eps) and
// cosPi(x) = 1 - eps with eps below 2^-1000. π x is taken from a 450-bit π
// (relative error 2^-450), no rounding breakpoint lies within 2^-300 of it for
// these arguments, so the correctly rounded result is the rounding of
// πx(1 -+ 2^-300) (resp. 1 - 2^-300) by `binary_round_dyadic`, which owns the
// range rules and both tininess modes.

///|
fn pi_tiny_model(
  x : Binary,
  kind : Int32,
  ctx : BinaryContext,
) -> (Binary, BinaryFlags) {
  let base = Coeff::one().shift_left(300)
  let below = base.sub_checked(Coeff::one()).unwrap()
  let above = base.add(Coeff::one())
  if kind == 2 {
    // cosPi: 1 - 2^-300, positive for either sign of x.
    return binary_round_dyadic(false, below, -300, ctx)
  }
  let pi = binary_pi_bounds(450).unwrap().0
  let product = x.abs().mul_ctx(pi, BinaryContext::new(precision=900)).0
  let factor = if kind == 0 { below } else { above }
  binary_round_dyadic(
    x.is_negative(),
    product.coefficient_().mul(factor),
    product.exponent2() - 300,
    ctx,
  )
}

///|
test "sinpi, tanpi and cospi of tiny arguments round with their flags" {
  let functions : Array[
    (String, Int32, (Binary, BinaryContext) -> (Binary, BinaryFlags)),
  ] = [
    ("sinpi", 0, fn(x, c) { x.sinpi_ctx(c) }),
    ("tanpi", 1, fn(x, c) { x.tanpi_ctx(c) }),
    ("cospi", 2, fn(x, c) { x.cospi_ctx(c) }),
  ]
  let mut cases = 0
  for f in functions {
    let (name, kind, run) = f
    for exponent in [-1073741870, -1073741860, -1073741823, -1073741800] {
      for coefficient in [1UL, 5UL] {
        for negative in [false, true] {
          let x = Binary::make_coeff(
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
                let (expected, expected_flags) = pi_tiny_model(x, kind, ctx)
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
  assert_eq(cases, 3 * 4 * 2 * 2 * 4 * 5 * 2)
}
