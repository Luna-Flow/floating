///|
/// Scale of the randomized comparison with the certified loop. The committed
/// value keeps the test cheap; the full runs quoted in the PR use 20000.
let rootn_integer_cases : Int32 = 3

///|
struct RootnRng {
  mut rootn_state : UInt64
}

///|
fn RootnRng::next(self : RootnRng) -> UInt64 {
  self.rootn_state = self.rootn_state * 6364136223846793005UL +
    1442695040888963407UL
  self.rootn_state >> 11
}

///|
fn rootn_random_value(rng : RootnRng, allow_negative : Bool) -> BinFloat {
  let words = (rng.next() % 3UL).to_int() + 1
  let mut coefficient = BinCoeff::from_uint64(rng.next() | 1UL)
  for _ in 1..<words {
    coefficient = coefficient
      .shift_left(37)
      .add(BinCoeff::from_uint64(rng.next()))
  }
  let trim = (rng.next() % 90UL).to_int()
  let trimmed = coefficient.shift_right(trim)
  let odd = if trimmed.is_zero() { BinCoeff::one() } else { trimmed }
  let exponent = match (rng.next() % 6UL).to_int() {
    0 => (rng.next() % 40UL).to_int() - 20
    1 => (rng.next() % 4000UL).to_int() - 2000
    2 => (rng.next() % 2000000UL).to_int() - 1000000
    3 => binary_implementation_e_max - 130 - (rng.next() % 60UL).to_int()
    4 => binary_implementation_e_min + 5 + (rng.next() % 60UL).to_int()
    _ => (rng.next() % 300UL).to_int() - 150
  }
  let negative = allow_negative && rng.next() % 2UL == 0UL
  BinFloat::make(odd, exponent, Int32::max(1, odd.bit_length()), negative~)
}

///|
fn rootn_contexts() -> Array[BinaryContext] {
  let out : Array[BinaryContext] = []
  for
    mode in [
      BinaryRoundingMode::RoundTiesToEven,
      BinaryRoundingMode::RoundTiesToAway,
      BinaryRoundingMode::RoundTowardZero,
      BinaryRoundingMode::RoundTowardPositive,
      BinaryRoundingMode::RoundTowardNegative,
      BinaryRoundingMode::RoundAwayFromZero,
    ] {
    for
      tininess in [
        TininessDetection::BeforeRounding,
        TininessDetection::AfterRounding,
      ] {
      out.push(BinaryContext::binary16(rounding=mode, tininess~))
      out.push(BinaryContext::binary32(rounding=mode, tininess~))
      out.push(
        BinaryContext::new(5, rounding=mode, e_min=-30, e_max=30, tininess~),
      )
    }
    for p in [1, 2, 24, 53, 130] {
      out.push(BinaryContext::unbounded(p, rounding=mode))
    }
  }
  out
}

///|
/// Local full runs (quoted in the PR) set this to `true`: every context in the
/// deterministic tests and the larger value sets; the committed `false` keeps
/// the file under one second.
let rootn_integer_full : Bool = false

///|
/// Twelve contexts covering every rounding mode, both tininess rules, the
/// bounded formats and the unbounded range, for the deterministic tests.
fn rootn_small_contexts() -> Array[BinaryContext] {
  if rootn_integer_full {
    return rootn_contexts()
  }
  [
    BinaryContext::binary16(),
    BinaryContext::binary16(
      rounding=BinaryRoundingMode::RoundTowardPositive,
      tininess=TininessDetection::BeforeRounding,
    ),
    BinaryContext::binary32(rounding=BinaryRoundingMode::RoundTowardNegative),
    BinaryContext::binary32(
      rounding=BinaryRoundingMode::RoundTiesToAway,
      tininess=TininessDetection::BeforeRounding,
    ),
    BinaryContext::binary64(rounding=BinaryRoundingMode::RoundTowardZero),
    BinaryContext::new(
      5,
      rounding=BinaryRoundingMode::RoundAwayFromZero,
      e_min=-30,
      e_max=30,
    ),
    BinaryContext::unbounded(1),
    BinaryContext::unbounded(
      24,
      rounding=BinaryRoundingMode::RoundTowardPositive,
    ),
    BinaryContext::unbounded(53),
    BinaryContext::unbounded(
      53,
      rounding=BinaryRoundingMode::RoundTowardNegative,
    ),
    BinaryContext::unbounded(130, rounding=BinaryRoundingMode::RoundTowardZero),
    BinaryContext::unbounded(2, rounding=BinaryRoundingMode::RoundTiesToAway),
  ]
}

///|
let rootn_skipped_loop : Ref[Int32] = { val: 0, }

///|
let rootn_checked : Ref[Int32] = { val: 0, }

///|
fn rootn_compare(
  value : BinFloat,
  degree : Int32,
  context : BinaryContext,
  label : String,
) -> Unit raise {
  let magnitude_degree = if degree < 0 { -degree } else { degree }
  if magnitude_degree % 2 == 0 && value.is_negative() {
    return
  }
  // Exact roots take the exactness path before either method.
  if binary_exact_rootn_int64(value, magnitude_degree.to_int64()) is Some(_) {
    return
  }
  let fresh = binary_rootn_integer(value, degree, context)
  let reference = binary_rootn_certified_loop(
    value,
    value.abs(),
    degree,
    magnitude_degree.to_int64(),
    context,
  )
  match reference {
    Ok(old) => {
      assert_true(fresh.0 == old.0, msg="value \{label}")
      assert_true(fresh.1 == old.1, msg="flags \{label}")
      rootn_checked.val += 1
    }
    // The loop could not certify (it fails at extreme ranges or budgets); the
    // integer root has no such limit, so there is nothing to compare.
    Err(_) => rootn_skipped_loop.val += 1
  }
}

///|
test "rootn by an integer root equals the certified loop (random)" {
  let rng : RootnRng = { rootn_state: 20261121UL, }
  let contexts = rootn_contexts()
  let degrees = [2, -2, 3, -3, 4, -4, 5, -5, 7, -7, 8, 16, -16, 32, -32]
  let mut compared = 0
  for degree in degrees {
    for context in contexts {
      for i in 0..<rootn_integer_cases {
        let value = rootn_random_value(rng, degree % 2 != 0)
        rootn_compare(value, degree, context, "n=\{degree} i=\{i} x=\{value}")
        compared += 1
      }
    }
  }
  println(
    "rootn compared=\{rootn_checked.val} loop_failed=\{rootn_skipped_loop.val}",
  )
  assert_true(compared > 1000)
}

///|
test "rootn by an integer root: perfect powers plus or minus one, both sides of every rounding boundary" {
  let contexts = rootn_small_contexts()
  let degrees = if rootn_integer_full {
    [2, 3, 4, 5, 6, 7, 9, 16, 31, 32]
  } else {
    [2, 3, 5, 32]
  }
  let widths = if rootn_integer_full { [3, 11, 24, 53] } else { [3, 53] }
  for n in degrees {
    for p in widths {
      let two_p = BinCoeff::one().shift_left(p)
      for
        base in [
          two_p.sub_checked(BinCoeff::one()).unwrap(),
          two_p.add(BinCoeff::one()),
          two_p.shift_right(1).add(BinCoeff::one()),
          two_p.add(two_p.shift_right(1)),
        ] {
        let power = base.pow_nat(n.reinterpret_as_uint())
        for delta in [-1, 0, 1] {
          let near = if delta < 0 {
            power.sub_checked(BinCoeff::one()).unwrap()
          } else if delta == 0 {
            power
          } else {
            power.add(BinCoeff::one())
          }
          for
            exponent in (if rootn_integer_full {
              [-3 * n, 0, n, 5 * n + 1]
            } else {
              [0, 5 * n + 1]
            }) {
            let value = BinFloat::make(
              near,
              exponent,
              Int32::max(1, near.bit_length()),
            )
            for context in contexts {
              rootn_compare(
                value,
                n,
                context,
                "perfect n=\{n} p=\{p} d=\{delta} e=\{exponent}",
              )
              rootn_compare(
                value,
                -n,
                context,
                "perfect -n=\{n} p=\{p} d=\{delta} e=\{exponent}",
              )
              if n % 2 == 1 {
                rootn_compare(value.neg(), n, context, "perfect neg n=\{n}")
                rootn_compare(value.neg(), -n, context, "perfect neg -n=\{n}")
              }
            }
          }
        }
      }
    }
  }
  println(
    "rootn perfect-power compared=\{rootn_checked.val} loop_failed=\{rootn_skipped_loop.val}",
  )
}

///|
test "rootn by an integer root at the exponent limits and the subnormal boundary" {
  let contexts = rootn_small_contexts()
  let top_limits = [
    binary_implementation_e_max,
    binary_implementation_e_max - 1,
    binary_implementation_e_min + 1,
    binary_implementation_e_min + 2,
    0,
    -1,
    1,
  ]
  for n in [2, 3, 4, 5, 32] {
    for top in top_limits {
      for c in [3UL, 5UL, 0x1fffffffffffffUL, 0xffffffffffffffffUL] {
        let coefficient = BinCoeff::from_uint64(c)
        let exponent = top - (coefficient.bit_length() - 1)
        let value = BinFloat::make(coefficient, exponent, 64)
        for context in contexts {
          rootn_compare(value, n, context, "limit n=\{n} top=\{top}")
          rootn_compare(value, -n, context, "limit -n=\{n} top=\{top}")
          if n % 2 == 1 {
            rootn_compare(
              value.neg(),
              -n,
              context,
              "limit neg -n=\{n} top=\{top}",
            )
          }
        }
      }
    }
  }
  // x^(-1/n) near the smallest normal and subnormal results of binary32 and
  // binary64: x = 2^(n k) times a mantissa just above or below 1.
  for n in [2, 3, 5] {
    for k in [126, 127, 149, 150, 1022, 1023, 1074, 1075] {
      for
        mantissa in [
          BinCoeff::from_uint64(0x1fffffffffffffUL),
          BinCoeff::from_uint64(0x10000000000001UL),
          BinCoeff::from_uint64(3UL),
        ] {
        let exponent = n * k - (mantissa.bit_length() - 1)
        let value = BinFloat::make(mantissa, exponent, 64)
        for context in contexts {
          rootn_compare(value, -n, context, "subnormal n=\{n} k=\{k}")
        }
      }
    }
  }
  println(
    "rootn limits compared=\{rootn_checked.val} loop_failed=\{rootn_skipped_loop.val}",
  )
}

///|
test "rootn of large degrees keeps the certified loop" {
  let value = BinFloat::from_double(7.5, precision=53)
  let context = BinaryContext::binary64()
  for degree in [33, -33, 100, 1000, -1000] {
    let fresh = value.try_rootn_ctx(degree, context).unwrap()
    let reference = binary_rootn_certified_loop(
      value,
      value.abs(),
      degree,
      (if degree < 0 { -degree } else { degree }).to_int64(),
      context,
    ).unwrap()
    assert_true(fresh.0 == reference.0 && fresh.1 == reference.1)
  }
}
