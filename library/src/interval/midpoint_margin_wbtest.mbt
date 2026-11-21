// `midpoint_ctx` at a precision larger than the margin of the far-addend stand-in
// (#645): the exact centre `(lo + hi) / 2` of an interval whose bounds are further apart
// than `max(65,536, precision)` places was formed with the stand-in of the smaller
// bound inside the bits that the rounding to the context keeps.
//
// ORACLE: (1) level A for the first test: the expected centre of `[1, 2^100000]` is
// `2^99999 + 1/2 = (2^100000 + 1) * 2^-1`, written out as a hexadecimal coefficient
// (a 1, 24,999 zeros, a 1) and an exponent, and compared with `compare`. (2) level B for
// the sweep: the exact sum of the two bounds in a `binary` context of more bits than
// the span (`add_ctx`, exact there: no rounding path of `interval` is used), halved
// by a power of two (exact), and rounded once to nearest even with `with_precision`;
// the shared primitives are `make`, `add_ctx` and `with_precision` (level A rows named
// in the audit PR).

///|
fn mm_zeros(n : Int32) -> String {
  let mut text = ""
  for _ in 0..<n {
    text = text + "0"
  }
  text
}

///|
test "midpoint_ctx of [1, 2^100000] at 200,000 bits is 2^99999 + 1/2" {
  let one = @binary.Binary::one(precision=53)
  let big = @binary.Binary::make(@binary.BinCoeff::one(), 100000, 53)
  let interval = Interval::from_bounds(one, big, precision=53)
  let (m, _) = interval.midpoint_ctx(IntervalContext::new(precision=200000))
  // (2^100000 + 1) is "1", 24,999 hex zeros, "1": 100,001 bits
  let expected = match
    @binary.BinCoeff::parse("1" + mm_zeros(24999) + "1", radix=16) {
    Ok(coefficient) => @binary.Binary::make(coefficient, -1, 200000)
    Err(error) => abort(error)
  }
  assert_true(m.compare(expected) == 0)
  assert_true(m.exponent2() == -1)
}

///|
fn mm_oracle(
  lo : @binary.Binary,
  hi : @binary.Binary,
  context_precision : Int32,
  span : Int32,
) -> @binary.Binary {
  let wide = @binary.BinaryContext::new(precision=span + 64)
  let half = @binary.Binary::make(@binary.BinCoeff::one(), -1, 1)
  let sum = lo.add_ctx(hi, wide).0
  sum.mul_ctx(half, wide).0.with_precision(
    context_precision,
    BinaryRoundingMode::RoundTiesToEven,
  )
}

///|
fn mm_sweep(divisor : Int32) -> Unit raise {
  // interval precisions, context precisions around the margin 65,536 on both sides,
  // exponents of the larger bound around the margin, both orders of magnitude and
  // both signs
  let interval_precisions = [24, 53, 200]
  let context_precisions = [53, 65535, 65536, 65537, 70000, 140000]
  let spans = [10, 100, 65535, 65536, 65600, 100000, 131000]
  let mut cases = 0
  for interval_precision in interval_precisions {
    for context_precision in context_precisions {
      for span in spans {
        cases += 1
        if cases % divisor != 0 {
          continue
        }
        let small = @binary.Binary::make(
          @binary.BinCoeff::from_uint64(5UL),
          0,
          interval_precision,
        )
        let large = @binary.Binary::make(
          @binary.BinCoeff::from_uint64(3UL),
          span,
          interval_precision,
        )
        // [small, large], [-large, small], [-large, -small], [-small, large]
        let pairs = [
          (small, large),
          (large.neg(), small),
          (large.neg(), small.neg()),
          (small.neg(), large),
        ]
        for pair in pairs {
          let interval = Interval::from_bounds(
            pair.0,
            pair.1,
            precision=interval_precision,
          )
          let (m, _) = interval.midpoint_ctx(
            IntervalContext::new(precision=context_precision),
          )
          let expected = mm_oracle(
            interval.lower_bound(),
            interval.upper_bound(),
            context_precision,
            span + 8,
          )
          if m.compare(expected) != 0 {
            fail(
              "[\{pair.0}, \{pair.1}] p=\{interval_precision} context \{context_precision}: \{m.exponent2()} / \{m.coefficient().bit_length()} bits, expected \{expected.exponent2()} / \{expected.coefficient().bit_length()} bits",
            )
          }
        }
      }
    }
  }
}

///|
test "midpoint_ctx sweep around the margin, sample" {
  mm_sweep(9)
}

///|
#skip("long run: the interval gate runs it with --include-skipped")
test "midpoint_ctx sweep around the margin, long" {
  mm_sweep(1)
}
