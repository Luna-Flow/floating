///|
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
    "\{signed_nan.is_negative()} \{signed_nan.nan_payload() == payload}",
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
