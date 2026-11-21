// Regression tests for #271: exp2 of an exact power-of-two result below
// 2^(1 - 2^30) returned +0 with no flags, although 2^n is representable by the
// gradual-underflow range rule (smallest positive value 2^(e_min - (p - 1))).
//
// Clauses, quoted from the text of IEEE Std 754-2019 (pdftotext of the PDF):
//
//   [9.2]   "A conforming operation shall return results correctly rounded for
//           the applicable rounding direction for all operands in its domain."
//   [7.5.a] "after rounding — when a non-zero result computed as though the
//           exponent range were unbounded would lie strictly between ± b emin"
//   [7.5.b] "before rounding — when a non-zero result computed as though both
//           the exponent range and the precision were unbounded would lie
//           strictly between ± b emin"
//   [7.5.r] "The method for detecting tininess does not affect the rounded
//           result delivered, which might be zero, subnormal, or ± b emin."
//   [7.5.f] "if the rounded result is inexact — that is, it differs from what
//           would have been computed were both exponent range and precision
//           unbounded — the underflow flag shall be raised and the inexact (see
//           7.6) exception shall be signaled. If the rounded result is exact,
//           no flag is raised and no inexact exception is signaled."
//
// The model below is independent of the implementation: for an integer n the
// exact value is 2^n, representable iff q <= n <= e_max with
// q = e_min - (p - 1), and otherwise rounded against the two neighbours
// 0 and 2^q (below q) or the largest finite value and infinity (above e_max).

///|
fn e2s_flags(flags : BinaryFlags) -> String {
  (if flags.inexact() { "I" } else { "-" }) +
  (if flags.underflow() { "U" } else { "-" }) +
  (if flags.overflow() { "O" } else { "-" })
}

///|
fn e2s_mode_name(mode : BinaryRoundingMode) -> String {
  match mode {
    RoundTiesToEven => "RNE"
    RoundTiesToAway => "RNA"
    RoundTowardZero => "RTZ"
    RoundTowardPositive => "RTP"
    RoundTowardNegative => "RTN"
  }
}

///|
fn e2s_tininess_name(tininess : TininessDetection) -> String {
  match tininess {
    AfterRounding => "after"
    BeforeRounding => "before"
  }
}

///|
fn e2s_modes() -> Array[BinaryRoundingMode] {
  [
    BinaryRoundingMode::RoundTiesToEven,
    BinaryRoundingMode::RoundTiesToAway,
    BinaryRoundingMode::RoundTowardZero,
    BinaryRoundingMode::RoundTowardPositive,
    BinaryRoundingMode::RoundTowardNegative,
  ]
}

///|
/// Rounding direction of a positive inexact value that lies strictly between
/// two neighbours: `true` when the upper neighbour is chosen. `above_half` is
/// `Some(true)` above the midpoint, `Some(false)` below it and `None` on it.
fn e2s_round_up(mode : BinaryRoundingMode, above_half : Bool?) -> Bool {
  match mode {
    RoundTiesToEven =>
      match above_half {
        Some(above) => above
        None => false // the lower neighbour 0 is even; the tie only occurs there
      }
    RoundTiesToAway =>
      match above_half {
        Some(above) => above
        None => true
      }
    RoundTowardZero | RoundTowardNegative => false
    RoundTowardPositive => true
  }
}

///|
fn e2s_pow2(n : Int32, p : Int32) -> Binary {
  Binary::make_coeff(Coeff::one(), n, p)
}

///|
/// Independent model of the correctly rounded `exp2(n)` for an integer `n`.
fn e2s_model(
  n : Int32,
  p : Int32,
  mode : BinaryRoundingMode,
  e_min : Int32,
  e_max : Int32,
) -> (Binary, String) {
  let q = e_min - (p - 1)
  if n > e_max {
    // [9.2] overflow: infinity or the largest finite value by direction.
    let to_infinity = match mode {
      RoundTowardZero | RoundTowardNegative => false
      _ => true
    }
    let value = if to_infinity {
      Binary::inf(precision=p)
    } else {
      Binary::make_coeff(
        Coeff::one().shift_left(p).sub_checked(Coeff::one()).unwrap(),
        e_max - (p - 1),
        p,
      )
    }
    return (value, "I-O")
  }
  if n >= q {
    // [7.5.f] exact result, representable (normal or subnormal): no flags.
    return (e2s_pow2(n, p), "---")
  }
  // n < q: 2^n < 2^q; the midpoint of [0, 2^q] is 2^(q - 1).
  let above_half = if n > q - 1 {
    Some(true)
  } else if n == q - 1 {
    None
  } else {
    Some(false)
  }
  let value = if e2s_round_up(mode, above_half) {
    e2s_pow2(q, p)
  } else {
    Binary::zero(precision=p)
  }
  // [7.5.a]/[7.5.b]: 2^n < 2^q <= 2^e_min is tiny in both modes and inexact.
  (value, "IU-")
}

///|
fn e2s_arg(n : Int32) -> Binary {
  Binary::from_int(n, precision=64)
}

///|
test "exp2 of an integer matches the model at every range boundary" {
  let precisions = [1, 2, 3, 24, 53, 113, 300]
  let ranges : Array[(Int32?, Int32?)] = [
    (None, None),
    (Some(-1022), Some(1023)),
    (Some(-6), Some(7)),
  ]
  let mut cases = 0
  for p in precisions {
    for mode in e2s_modes() {
      for
        tininess in [
          TininessDetection::AfterRounding,
          TininessDetection::BeforeRounding,
        ] {
        for range in ranges {
          let ctx = match range {
            (Some(_), Some(hi)) =>
              BinaryContext::new(
                precision=p,
                rounding=mode,
                e_max=hi,
                tininess~,
              )
            _ => BinaryContext::new(precision=p, rounding=mode, tininess~)
          }
          let e_min = match range.0 {
            Some(lo) => lo
            None => binary_implementation_e_min
          }
          let e_max = match range.1 {
            Some(hi) => hi
            None => binary_implementation_e_max
          }
          let q = e_min - (p - 1)
          let args = [
            q - 3,
            q - 2,
            q - 1,
            q,
            q + 1,
            e_min - 1,
            e_min,
            e_min + 1,
            0,
            1,
            e_max - 1,
            e_max,
            e_max + 1,
          ]
          for n in args {
            let (value, flags) = e2s_arg(n).exp2_ctx(ctx)
            let (expected, expected_flags) = e2s_model(n, p, mode, e_min, e_max)
            let label = "exp2(\{n}) p=\{p} \{e2s_mode_name(mode)} \{e2s_tininess_name(tininess)} e_min=\{e_min}"
            assert_eq("\{label} => \{value}", "\{label} => \{expected}")
            assert_eq(
              "\{label} => \{e2s_flags(flags)}",
              "\{label} => \{expected_flags}",
            )
            cases += 1
          }
        }
      }
    }
  }
  assert_eq(cases, 7 * 5 * 2 * 3 * 13)
}

///|
test "exp2 of exactly -2^30 is the exact subnormal 2^-2^30 (#271)" {
  // The regression rows: unbounded context, precision 2 and 28.
  let two = BinaryContext::new(precision=2)
  let (r, f) = e2s_arg(-1073741823).exp2_ctx(two)
  assert_eq("\{r} \{e2s_flags(f)}", "1p-1073741823 ---")
  let (r, f) = e2s_arg(-1073741825).exp2_ctx(BinaryContext::new(precision=28))
  assert_eq("\{r} \{e2s_flags(f)}", "1p-1073741825 ---")
  // Both neighbours of e_min = 2 - 2^30 are representable at p = 2.
  let (r, f) = e2s_arg(-1073741822).exp2_ctx(two)
  assert_eq("\{r} \{e2s_flags(f)}", "1p-1073741822 ---")
}

///|
fn e2s_shifted(n : Int32, numerator : Int32) -> Binary {
  // Exactly n + numerator * 2^-20.
  e2s_arg(n).add_ctx(
    e2s_arg(numerator).mul_ctx(
      Binary::make_coeff(Coeff::one(), -20, 64),
      BinaryContext::new(precision=128),
    ).0,
    BinaryContext::new(precision=128),
  ).0
}

///|
/// Non-integer arguments `x = q + r` with `r = numerator * 2^-20`, so that
/// `2^x = 2^r * 2^q`. Every row: [9.2] picks the neighbour in `{0, 1, 2} * 2^q`
/// by the rounding direction (the midpoints are 1/2 and 3/2), and [7.5.f]
/// raises inexact and underflow because the result differs from the exact value
/// and lies below 2^e_min (p >= 3 keeps both tininess modes equal).
test "exp2 of non-integers around the smallest subnormal" {
  // numerator, then the multiplier m (result = m * 2^q) for
  // [even, away, zero, up, down]
  let rows : Array[(Int32, Array[Int32])] = [
    // r < -1: 2^r < 1/2, below the midpoint of [0, 2^q]
    (-1048577, [0, 0, 0, 1, 0]),
    // r = -1: the exact midpoint is impossible for a non-integer x, covered by
    // the integer model above; r slightly above -1: 2^r > 1/2
    (-1048575, [1, 1, 0, 1, 0]),
    // r just below 0: 1/2 < 2^r < 1
    (-1, [1, 1, 0, 1, 0]),
    // r just above 0: 1 < 2^r < 3/2
    (1, [1, 1, 1, 2, 1]),
    // r = 0.75: 2^r = 1.68 > 3/2
    (786432, [2, 2, 1, 2, 1]),
    // r just below 1: 3/2 < 2^r < 2
    (1048575, [2, 2, 1, 2, 1]),
  ]
  let precisions = [3, 4, 24, 53, 113]
  for p in precisions {
    let q = binary_implementation_e_min - (p - 1)
    for row in rows {
      let (numerator, expected) = row
      let x = e2s_shifted(q, numerator)
      let modes = e2s_modes()
      for index in 0..<5 {
        for
          tininess in [
            TininessDetection::AfterRounding,
            TininessDetection::BeforeRounding,
          ] {
          let ctx = BinaryContext::new(
            precision=p,
            rounding=modes[index],
            tininess~,
          )
          let (value, flags) = x.exp2_ctx(ctx)
          let m = expected[index]
          let expected_value = if m == 0 {
            Binary::zero(precision=p)
          } else if m == 1 {
            e2s_pow2(q, p)
          } else {
            e2s_pow2(q + 1, p)
          }
          let label = "exp2(q + \{numerator}/2^20) p=\{p} \{e2s_mode_name(modes[index])} \{e2s_tininess_name(tininess)}"
          assert_eq("\{label} => \{value}", "\{label} => \{expected_value}")
          assert_eq("\{label} => \{e2s_flags(flags)}", "\{label} => IU-")
        }
      }
    }
  }
}

///|
test "exp2 true underflow to zero threshold carries inexact and underflow" {
  // [9.2]/[7.5.f]: far below the smallest subnormal the result is the
  // rounding of a positive value smaller than any midpoint.
  for p in [2, 53, 300] {
    let q = binary_implementation_e_min - (p - 1)
    for far in [q - 2, q - 1000, -2147483640] {
      for mode in e2s_modes() {
        let ctx = BinaryContext::new(precision=p, rounding=mode)
        let (value, flags) = e2s_arg(far).exp2_ctx(ctx)
        let up = e2s_round_up(mode, Some(false))
        let expected = if up {
          e2s_pow2(q, p)
        } else {
          Binary::zero(precision=p)
        }
        assert_eq(
          "far=\{far} p=\{p} \{e2s_mode_name(mode)} => \{value} \{e2s_flags(flags)}",
          "far=\{far} p=\{p} \{e2s_mode_name(mode)} => \{expected} IU-",
        )
      }
    }
  }
  // 2^-2^40: beyond the 32-bit exponent field of the implementation.
  let huge = Binary::make_coeff(Coeff::one(), 40, 64).neg()
  let (value, flags) = huge.exp2_ctx(BinaryContext::new(precision=53))
  assert_eq("\{value} \{e2s_flags(flags)}", "0 IU-")
}
