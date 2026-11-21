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
