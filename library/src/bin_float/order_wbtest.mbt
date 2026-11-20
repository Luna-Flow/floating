///|
test "copySign keeps the magnitude and NaN payload" {
  let payload = BinCoeff::from_uint64(7UL)
  let nan = BinFloat::quiet_nan(payload~)
  let negative = BinFloat::from_int(-1)
  inspect(
    BinFloat::from_int(3).copy_sign(negative),
    content=(
      #|-3p0
    ),
  )
  inspect(
    BinFloat::from_int(-3).copy_sign(BinFloat::zero()),
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
    BinFloat::zero().copy_sign(BinFloat::negative_zero()),
    content=(
      #|-0
    ),
  )
}

///|
test "totalOrder sorts every class, signed zeros, and NaN payloads" {
  let ordered = [
    BinFloat::quiet_nan(payload=BinCoeff::from_uint64(2UL), negative=true),
    BinFloat::quiet_nan(payload=BinCoeff::from_uint64(1UL), negative=true),
    BinFloat::signaling_nan(negative=true),
    BinFloat::inf(Sign::Negative),
    BinFloat::from_int(-2),
    BinFloat::make(BinCoeff::one(), -1074, 53, negative=true),
    BinFloat::negative_zero(),
    BinFloat::zero(),
    BinFloat::make(BinCoeff::one(), -1074, 53),
    BinFloat::from_int(2),
    BinFloat::inf(Sign::Positive),
    BinFloat::signaling_nan(),
    BinFloat::quiet_nan(payload=BinCoeff::from_uint64(1UL)),
    BinFloat::quiet_nan(payload=BinCoeff::from_uint64(2UL)),
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
    BinFloat::from_int(-3).total_order_mag(BinFloat::from_int(2)),
    content="false",
  )
}

///|
test "quiet and signaling comparisons differ only in NaN flags" {
  let one = BinFloat::one()
  let qnan = BinFloat::nan()
  let snan = BinFloat::signaling_nan()
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
    "\{show(BinFloat::zero().compare_quiet(BinFloat::negative_zero()))} \{show(one.compare_quiet(qnan))} \{show(one.compare_signaling(qnan))} \{show(one.compare_quiet(snan))} \{show(one.compare_signaling(BinFloat::from_int(2)))}",
    content=(
      #|equal/0 unordered/0 unordered/16 unordered/16 less/0
    ),
  )
  let flag = fn(result : (Bool, BinaryFlags)) {
    "\{result.0}/\{result.1.to_testfloat_bits()}"
  }
  inspect(
    "\{flag(one.less_quiet(qnan))} \{flag(one.less_signaling(qnan))} \{flag(one.less_equal_quiet(one))} \{flag(qnan.unordered_quiet(one))} \{flag(BinFloat::zero().equal_signaling(BinFloat::negative_zero()))}",
    content=(
      #|false/0 false/16 true/0 true/0 true/0
    ),
  )
}
