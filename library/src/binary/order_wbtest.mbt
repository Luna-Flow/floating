///|
// oracle: A
// source: written out from IEEE Std 754-2019 5.5.1 (copySign(x, y) has the magnitude of x and the sign of y, also for a NaN x with its payload and for zeros): 3 with the sign of -1 is -3, -3 with the sign of +0 is 3, a NaN of payload 7 takes the sign and keeps the payload, +0 with the sign of -0 is -0
// shares: Binary::from_int, quiet_nan, zero and negative_zero build the operands; copy_sign is the code under test; Display prints
test "copySign keeps the magnitude and NaN payload" {
  let payload = BinCoeff::from_uint64(7UL)
  let nan = Binary::quiet_nan(payload~)
  let negative = Binary::from_int(-1)
  inspect(
    Binary::from_int(3).copy_sign(negative),
    content=(
      #|-3p0
    ),
  )
  inspect(
    Binary::from_int(-3).copy_sign(Binary::zero()),
    content=(
      #|3p0
    ),
  )
  let signed_nan = nan.copy_sign(negative)
  inspect(
    "\{signed_nan.is_sign_minus()} \{signed_nan.nan_payload() == payload}",
    content=(
      #|true true
    ),
  )
  inspect(
    Binary::zero().copy_sign(Binary::negative_zero()),
    content=(
      #|-0
    ),
  )
}

///|
// oracle: A, S
// source: A: written out from IEEE Std 754-2019 5.10 (negative sign below positive, signaling below quiet for +NaN and the reverse for -NaN, -inf, negative finite numbers, -0 below +0, positive finite numbers, +inf), checked for all 14 x 14 pairs; total_order_mag of -3 and 2 is false; S: 5.10 d) 5) iii) leaves the order of NaNs of the same sign and kind by payload implementation-defined, and the block states the order of this library (a larger payload sorts later for a positive NaN and earlier for a negative one) as a convention, not as an external value
// shares: Binary constructors build the operands; total_order_compare and total_order are the code under test
test "totalOrder sorts every class, signed zeros, and NaN payloads" {
  let ordered = [
    Binary::quiet_nan(payload=BinCoeff::from_uint64(2UL), negative=true),
    Binary::quiet_nan(payload=BinCoeff::from_uint64(1UL), negative=true),
    Binary::signaling_nan(negative=true),
    Binary::inf(negative=true),
    Binary::from_int(-2),
    Binary::make(BinCoeff::one(), -1074, 53, negative=true),
    Binary::negative_zero(),
    Binary::zero(),
    Binary::make(BinCoeff::one(), -1074, 53),
    Binary::from_int(2),
    Binary::inf(),
    Binary::signaling_nan(),
    Binary::quiet_nan(payload=BinCoeff::from_uint64(1UL)),
    Binary::quiet_nan(payload=BinCoeff::from_uint64(2UL)),
  ]
  for i in 0..<ordered.length() {
    for j in 0..<ordered.length() {
      let expected = if i < j { -1 } else if i > j { 1 } else { 0 }
      assert_eq(
        ordered[i].total_order_compare(ordered[j]),
        expected,
        msg="\{i} vs \{j}",
      )
      assert_eq(ordered[i].total_order(ordered[j]), i <= j, msg="\{i} <= \{j}")
    }
  }
  inspect(
    Binary::from_int(-3).total_order_mag(Binary::from_int(2)),
    content="false",
  )
}

///|
// oracle: A
// source: written out from IEEE Std 754-2019 5.11 and 7.2: compareQuietEqual of +0 and -0 is equal; a quiet comparison with a quiet NaN is unordered without flag, a signaling comparison with a quiet NaN raises invalid (flags 16), a quiet comparison with a signaling NaN raises invalid, and the predicates compareQuietLess, compareSignalingLess, compareQuietLessEqual, compareQuietUnordered and compareSignalingEqual give the listed truth values with those flags
// shares: Binary::one, zero, negative_zero, nan and signaling_nan build the operands; the compare_quiet and compare_signaling functions are the code under test
test "quiet and signaling comparisons differ only in NaN flags" {
  let one = Binary::one()
  let qnan = Binary::nan()
  let snan = Binary::signaling_nan()
  let show = fn(result : (@def.PartialOrder, BinaryFlags)) {
    let relation = match result.0 {
      Less => "less"
      Equal => "equal"
      Greater => "greater"
      Unordered => "unordered"
    }
    "\{relation}/\{result.1.to_testfloat_bits()}"
  }
  inspect(
    "\{show(Binary::zero().compare_quiet(Binary::negative_zero()))} \{show(one.compare_quiet(qnan))} \{show(one.compare_signaling(qnan))} \{show(one.compare_quiet(snan))} \{show(one.compare_signaling(Binary::from_int(2)))}",
    content=(
      #|equal/0 unordered/0 unordered/16 unordered/16 less/0
    ),
  )
  let flag = fn(result : (Bool, BinaryFlags)) {
    "\{result.0}/\{result.1.to_testfloat_bits()}"
  }
  inspect(
    "\{flag(one.compare_quiet_less(qnan))} \{flag(one.compare_signaling_less(qnan))} \{flag(one.compare_quiet_less_equal(one))} \{flag(qnan.compare_quiet_unordered(one))} \{flag(Binary::zero().compare_signaling_equal(Binary::negative_zero()))}",
    content=(
      #|false/0 false/16 true/0 true/0 true/0
    ),
  )
}
