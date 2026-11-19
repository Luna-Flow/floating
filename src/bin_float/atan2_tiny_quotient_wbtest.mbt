// atan2(y, x) with x > 0 and |y/x| far below the exponent range
// (floating#383): the directed quotient used to flush to zero, the lower
// bound of the enclosure stayed 0 and the loop never certified.
//
// Contract (IEEE Std 754-2019 9.2 "A conforming operation shall return results
// correctly rounded for the applicable rounding direction", 7.5 underflow,
// 7.6 inexact): atan(t) = t (1 - e) with 0 < e < t^2 / 3, so for 0 < t = |y/x|
// the result lies strictly inside (0, t) with the sign of y. When t is below a
// quarter of the smallest subnormal of the context, no breakpoint lies in
// (0, t], so the result rounds exactly as the quotient does: zero or the
// smallest subnormal, inexact and underflow. Above that bound the certified
// loop decides; for an exactly representable quotient (x a power of two) the
// result must equal `atan_ctx` of the quotient.

///|
fn a2t_contexts() -> Array[BinaryContext] {
  let result : Array[BinaryContext] = [
    BinaryContext::unbounded(2),
    BinaryContext::unbounded(53),
    BinaryContext::unbounded(100),
  ]
  for mode in e2s_modes() {
    for
      tininess in [
        TininessDetection::AfterRounding,
        TininessDetection::BeforeRounding,
      ] {
      result.push(
        BinaryContext::new(
          53,
          rounding=mode,
          e_min=-1022,
          e_max=1023,
          tininess~,
        ),
      )
      result.push(
        BinaryContext::new(11, rounding=mode, e_min=-14, e_max=15, tininess~),
      )
      result.push(BinaryContext::unbounded(53, rounding=mode))
    }
  }
  result
}

///|
fn a2t_text(value : BinFloat, flags : BinaryFlags) -> String {
  "\{value} \{e2s_flags(flags)}"
}

///|
test "atan2 of a quotient below the implementation range rounds like the quotient" {
  // The rows of floating#383 and their neighbours, both signs of y.
  let mut cases = 0
  for e in [1073741000, 540000000, 1073741823, 700000000] {
    for negative in [false, true] {
      let y = BinFloat::make(BinCoeff::from_uint64(5UL), -e, 64, negative~)
      let x = BinFloat::make(BinCoeff::from_uint64(7UL), e, 64)
      for c in a2t_contexts() {
        let (value, flags) = y.try_atan2_ctx(x, c).unwrap()
        let (expected, expected_flags) = y.div_ctx(x, c)
        let label = "atan2(\{y}, \{x}) p=\{c.precision()} \{e2s_mode_name(c.rounding())}"
        assert_eq(
          "\{label} => \{a2t_text(value, flags)}",
          "\{label} => \{a2t_text(expected, expected_flags)}",
        )
        assert_eq(value.is_negative(), negative)
        cases += 1
      }
    }
  }
  assert_eq(cases, 4 * 2 * a2t_contexts().length())
}

///|
test "atan2 across the shortcut boundary agrees with atan of the quotient" {
  // x = 2^m makes y/x exact. For each context the shortcut applies when
  // D = top(y) - top(x) <= e_min - p - 2; the window covers the last distances
  // where it does not and the first where it does, in bounded and unbounded
  // contexts, with a one-bit and an all-ones coefficient (q near 2^D and near
  // 2^(D+1)).
  let mut cases = 0
  for c in a2t_contexts() {
    let p = c.precision().to_int64()
    let e_min = match c.e_min() {
      Some(v) => v.to_int64()
      None => binary_implementation_e_min.to_int64()
    }
    let threshold = e_min - p - 2L
    for shift in [0, 300] {
      for offset in [-3L, -2L, -1L, 0L, 1L, 2L, 3L] {
        let d = threshold + offset
        for coefficient in [1UL, 255UL] {
          for negative in [false, true] {
            let y_exponent = d + shift.to_int64()
            let y = BinFloat::make(
              BinCoeff::from_uint64(coefficient),
              y_exponent.to_int(),
              Int32::max(
                64,
                (binary_implementation_e_min.to_int64() - y_exponent + 70L).to_int(),
              ),
              negative~,
            )
            let x = BinFloat::make(BinCoeff::one(), shift, 2)
            let quotient = BinFloat::make(
              BinCoeff::from_uint64(coefficient),
              d.to_int(),
              // wide enough that the value is stored, not flushed
              Int32::max(
                64,
                (binary_implementation_e_min.to_int64() - d + 70L).to_int(),
              ),
              negative~,
            )
            let (value, flags) = y.try_atan2_ctx(x, c).unwrap()
            let (expected, expected_flags) = quotient.atan_ctx(c)
            let label = "atan2(\{y}, \{x}) p=\{c.precision()} \{e2s_mode_name(c.rounding())} e_min=\{e_min}"
            assert_eq(
              "\{label} => \{a2t_text(value, flags)}",
              "\{label} => \{a2t_text(expected, expected_flags)}",
            )
            cases += 1
          }
        }
      }
    }
  }
  assert_eq(cases, a2t_contexts().length() * 2 * 7 * 2 * 2)
}
