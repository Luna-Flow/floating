// The word route of `add_ctx` / `sub_ctx` against the general route
// (`add_ctx_general`: `Coeff`s and `binary_round_dyadic`): the same value (the same
// representation, the precision label included) and the same flags, for every
// rounding mode, both tininess rules, contexts of 1 to 62 bits, one-word operands
// of 1 to 64 bits with exponents near zero, far apart and near the limits of the
// fast routes.

///|
fn wf_next(state : Ref[UInt64]) -> UInt64 {
  let mut x = state.val
  x = x ^ (x << 13)
  x = x ^ (x >> 7)
  x = x ^ (x << 17)
  state.val = x
  x
}

///|
fn wf_operand(state : Ref[UInt64]) -> Binary {
  let bits = 1 + (wf_next(state) % 64UL).to_int()
  let mut word = wf_next(state)
  if bits < 64 {
    word = word & ((1UL << bits) - 1UL)
  }
  word = word | (1UL << (bits - 1))
  let exponent = match wf_next(state) % 6UL {
    0UL => (wf_next(state) % 130UL).to_int() - 65
    1UL => (wf_next(state) % 40UL).to_int() - 20
    2UL => binary_fast_exponent_limit - (wf_next(state) % 70UL).to_int()
    3UL => -binary_fast_exponent_limit + (wf_next(state) % 70UL).to_int()
    _ => (wf_next(state) % 300UL).to_int() - 150
  }
  let precisions = [24, 53, 64, 113, 200]
  finite_normalized(
    wf_next(state) % 2UL == 0UL,
    bin_coeff_inline(0UL, word),
    exponent,
    precisions[(wf_next(state) % 5UL).to_int()],
  )
}

///|
/// An operand whose leading bit lies within 70 bits of the leading bit of `a`
/// (the pairs the word route takes), or an independent one.
fn wf_partner(state : Ref[UInt64], a : Binary) -> Binary {
  if wf_next(state) % 5UL == 0UL {
    return wf_operand(state)
  }
  let bits = 1 + (wf_next(state) % 64UL).to_int()
  let mut word = wf_next(state)
  if bits < 64 {
    word = word & ((1UL << bits) - 1UL)
  }
  word = word | (1UL << (bits - 1))
  let top = a.exact_top() + (wf_next(state) % 141UL).to_int() - 70
  finite_normalized(
    wf_next(state) % 2UL == 0UL,
    bin_coeff_inline(0UL, word),
    top - (bits - 1),
    53,
  )
}

///|
// oracle: B
// source: add_ctx_general (Coeff addition, then binary_round_dyadic), value, representation and flags, every rounding direction and both tininess rules, contexts of 1 to 62 bits: a different algorithm from the route under test. The general route is itself checked against exact arithmetic on the inputs this test draws from (precisions from 2 to 8192, all five directions, ties, carries between words, borrow, cancellation, far operands, exact quotients, perfect squares) by the tests "add, mul, div and sqrt are rounded once, exactly: rows from exact arithmetic" and "add, mul, div and sqrt without a context: the ties-to-even rows" of arith_rows_check_wbtest.mbt (rows of arith_rows_wbtest.mbt from tools/generate_arith_rows.py: Python fractions and math.isqrt, library-ran: no); the exponent-range edges of binary16, binary32 and binary64 are rows there for add, mul and div.
// shares: Coeff arithmetic and binary_round_dyadic (the general route)
// primitives: Coeff::add, Coeff::sub_checked, Coeff::mul, Coeff::shift_left, binary_round_dyadic, binary_round_rational, binary_round_sqrt: level A on the same operations and widths in arith_rows_wbtest.mbt and, up to 128 bits, in the TestFloat gate
test "the word route of add_ctx and sub_ctx equals the general route" {
  let state = Ref(0x9e3779b97f4a7c15UL)
  let modes = [
    BinaryRoundingMode::RoundTiesToEven,
    BinaryRoundingMode::RoundTiesToAway,
    BinaryRoundingMode::RoundTowardZero,
    BinaryRoundingMode::RoundTowardPositive,
    BinaryRoundingMode::RoundTowardNegative,
  ]
  let precisions = [1, 2, 3, 5, 11, 24, 53, 61, 62]
  let mut taken = 0
  let mut inexact = 0
  let mut skipped = 0
  for _ in 0..<20000 {
    let a = wf_operand(state)
    let b = wf_partner(state, a)
    let precision = precisions[(wf_next(state) % 9UL).to_int()]
    let mode = modes[(wf_next(state) % 5UL).to_int()]
    let tininess = if wf_next(state) % 2UL == 0UL {
      TininessDetection::BeforeRounding
    } else {
      TininessDetection::AfterRounding
    }
    let context = BinaryContext::new(precision~, rounding=mode, tininess~)
    for flip in [false, true] {
      match binary_ctx_add_words(a, b, flip, context) {
        Some((value, flags)) => {
          let (expected, expected_flags) = a.add_ctx_general(
            if flip {
              b.neg()
            } else {
              b
            },
            context,
          )
          if !value.identical(expected) || flags != expected_flags {
            abort(
              "\{a} \{if flip { "-" } else { "+" }} \{b} p=\{precision}: word \{value} \{flags.inexact()}, general \{expected} \{expected_flags.inexact()}",
            )
          }
          taken += 1
          if flags.inexact() {
            inexact += 1
          }
        }
        None => skipped += 1
      }
    }
  }
  println(
    "word route cases \{taken}, inexact \{inexact}, general route \{skipped}",
  )
  assert_true(taken > 10000 && inexact > 3000)
}

///|
// oracle: B
// source: add_ctx_general against the public add_ctx and sub_ctx (the public function dispatches to the word route and otherwise to add_ctx_general): a different algorithm from the route under test. The general route is itself checked against exact arithmetic on the inputs this test draws from (precisions from 2 to 8192, all five directions, ties, carries between words, borrow, cancellation, far operands, exact quotients, perfect squares) by the tests "add, mul, div and sqrt are rounded once, exactly: rows from exact arithmetic" and "add, mul, div and sqrt without a context: the ties-to-even rows" of arith_rows_check_wbtest.mbt (rows of arith_rows_wbtest.mbt from tools/generate_arith_rows.py: Python fractions and math.isqrt, library-ran: no); the exponent-range edges of binary16, binary32 and binary64 are rows there for add, mul and div.
// shares: both routes call binary_inexact_flags for the flags of an exact result and the Binary constructors (finite_normalized, bin_repr_word) to build the value, which the differential does not check and the table does through the flags and the printed value; the rounding decision is written twice, in the word, pair or limb finish of the fast route and in binary_apply_round_bits behind binary_round_dyadic / binary_round_rational / binary_round_sqrt in the general route, so it is not shared; fast_test_same compares value, precision label, sign and exponent
// primitives: Coeff::add, Coeff::sub_checked, Coeff::mul, Coeff::shift_left, binary_round_dyadic, binary_round_rational, binary_round_sqrt: level A on the same operations and widths in arith_rows_wbtest.mbt and, up to 128 bits, in the TestFloat gate
test "add_ctx and sub_ctx are unchanged on the public path" {
  // through the public functions the word route and the general route agree
  let state = Ref(0x2545f4914f6cdd1dUL)
  for _ in 0..<5000 {
    let a = wf_operand(state)
    let b = wf_operand(state)
    let context = BinaryContext::new(precision=53)
    let (sum, sum_flags) = a.add_ctx(b, context)
    let (expected, expected_flags) = a.add_ctx_general(b, context)
    assert_true(sum.identical(expected) && sum_flags == expected_flags)
    let (difference, difference_flags) = a.sub_ctx(b, context)
    let (expected, expected_flags) = a.add_ctx_general(b.neg(), context)
    assert_true(
      difference.identical(expected) && difference_flags == expected_flags,
    )
  }
}

///|
// oracle: B
// source: mul_ctx_general (Coeff product, then binary_round_dyadic), value, representation and flags, every direction and tininess rule: a different algorithm from the route under test. The general route is itself checked against exact arithmetic on the inputs this test draws from (precisions from 2 to 8192, all five directions, ties, carries between words, borrow, cancellation, far operands, exact quotients, perfect squares) by the tests "add, mul, div and sqrt are rounded once, exactly: rows from exact arithmetic" and "add, mul, div and sqrt without a context: the ties-to-even rows" of arith_rows_check_wbtest.mbt (rows of arith_rows_wbtest.mbt from tools/generate_arith_rows.py: Python fractions and math.isqrt, library-ran: no); the exponent-range edges of binary16, binary32 and binary64 are rows there for add, mul and div.
// shares: both routes call binary_inexact_flags for the flags of an exact result and the Binary constructors (finite_normalized, bin_repr_word) to build the value, which the differential does not check and the table does through the flags and the printed value; the rounding decision is written twice, in the word, pair or limb finish of the fast route and in binary_apply_round_bits behind binary_round_dyadic / binary_round_rational / binary_round_sqrt in the general route, so it is not shared; fast_test_same compares value, precision label, sign and exponent
// primitives: Coeff::add, Coeff::sub_checked, Coeff::mul, Coeff::shift_left, binary_round_dyadic, binary_round_rational, binary_round_sqrt: level A on the same operations and widths in arith_rows_wbtest.mbt and, up to 128 bits, in the TestFloat gate
test "the word route of mul_ctx equals the general route" {
  let state = Ref(0x5851f42d4c957f2dUL)
  let modes = [
    BinaryRoundingMode::RoundTiesToEven,
    BinaryRoundingMode::RoundTiesToAway,
    BinaryRoundingMode::RoundTowardZero,
    BinaryRoundingMode::RoundTowardPositive,
    BinaryRoundingMode::RoundTowardNegative,
  ]
  let precisions = [1, 2, 3, 5, 11, 24, 53, 61, 62]
  let mut taken = 0
  let mut inexact = 0
  for _ in 0..<20000 {
    let a = wf_operand(state)
    let b = wf_operand(state)
    let context = BinaryContext::new(
      precision=precisions[(wf_next(state) % 9UL).to_int()],
      rounding=modes[(wf_next(state) % 5UL).to_int()],
      tininess=if wf_next(state) % 2UL == 0UL {
        TininessDetection::BeforeRounding
      } else {
        TininessDetection::AfterRounding
      },
    )
    match binary_ctx_mul_words(a, b, context) {
      Some((value, flags)) => {
        let (expected, expected_flags) = a.mul_ctx_general(b, context)
        if !value.identical(expected) || flags != expected_flags {
          abort(
            "\{a} * \{b} p=\{context.precision}: word \{value}, general \{expected}",
          )
        }
        taken += 1
        if flags.inexact() {
          inexact += 1
        }
      }
      None => ()
    }
  }
  println("mul word route cases \{taken}, inexact \{inexact}")
  assert_true(taken > 15000 && inexact > 8000)
}

///|
// oracle: B
// source: div_ctx_general (Coeff division, then binary_round_rational), value, representation and flags, every direction and tininess rule: a different algorithm from the route under test. The general route is itself checked against exact arithmetic on the inputs this test draws from (precisions from 2 to 8192, all five directions, ties, carries between words, borrow, cancellation, far operands, exact quotients, perfect squares) by the tests "add, mul, div and sqrt are rounded once, exactly: rows from exact arithmetic" and "add, mul, div and sqrt without a context: the ties-to-even rows" of arith_rows_check_wbtest.mbt (rows of arith_rows_wbtest.mbt from tools/generate_arith_rows.py: Python fractions and math.isqrt, library-ran: no); the exponent-range edges of binary16, binary32 and binary64 are rows there for add, mul and div.
// shares: both routes call binary_inexact_flags for the flags of an exact result and the Binary constructors (finite_normalized, bin_repr_word) to build the value, which the differential does not check and the table does through the flags and the printed value; the rounding decision is written twice, in the word, pair or limb finish of the fast route and in binary_apply_round_bits behind binary_round_dyadic / binary_round_rational / binary_round_sqrt in the general route, so it is not shared; fast_test_same compares value, precision label, sign and exponent
// primitives: Coeff::add, Coeff::sub_checked, Coeff::mul, Coeff::shift_left, binary_round_dyadic, binary_round_rational, binary_round_sqrt: level A on the same operations and widths in arith_rows_wbtest.mbt and, up to 128 bits, in the TestFloat gate
test "the word route of div_ctx equals the general route" {
  let state = Ref(0x2545f4914f6cdd1dUL)
  let modes = [
    BinaryRoundingMode::RoundTiesToEven,
    BinaryRoundingMode::RoundTiesToAway,
    BinaryRoundingMode::RoundTowardZero,
    BinaryRoundingMode::RoundTowardPositive,
    BinaryRoundingMode::RoundTowardNegative,
  ]
  let precisions = [1, 2, 3, 5, 11, 24, 53, 59, 60]
  let mut taken = 0
  let mut inexact = 0
  for _ in 0..<20000 {
    let a = wf_operand(state)
    let b = wf_operand(state)
    let context = BinaryContext::new(
      precision=precisions[(wf_next(state) % 9UL).to_int()],
      rounding=modes[(wf_next(state) % 5UL).to_int()],
      tininess=if wf_next(state) % 2UL == 0UL {
        TininessDetection::BeforeRounding
      } else {
        TininessDetection::AfterRounding
      },
    )
    match binary_ctx_div_words(a, b, context) {
      Some((value, flags)) => {
        let (expected, expected_flags) = a.div_ctx_general(b, context)
        if !value.identical(expected) || flags != expected_flags {
          abort(
            "\{a} / \{b} p=\{context.precision}: word \{value}, general \{expected}",
          )
        }
        taken += 1
        if flags.inexact() {
          inexact += 1
        }
      }
      None => ()
    }
  }
  println("div word route cases \{taken}, inexact \{inexact}")
  assert_true(taken > 3000 && inexact > 1000)
}
