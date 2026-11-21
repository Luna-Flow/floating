///|
/// The text of `payload` after a conversion to a NaN of precision
/// `precision`: its low `precision - 2` bits (IEEE 754-2019 6.2.1, 6.2.3).
fn nan_payload_in(payload : BinCoeff, precision : Int32) -> String {
  Binary::quiet_nan(precision~) |> ignore
  binary_convert_nan(false, false, payload.0, precision)
  .nan_payload()
  .to_string()
}

///|
test "a NaN of precision p has p - 2 payload bits" {
  // binary64: 51 bits, binary16: 9 bits
  let wide = BinCoeff::from_uint64((1UL << 51) - 1UL)
  assert_eq(Binary::quiet_nan(payload=wide).nan_payload(), wide)
  let nine = BinCoeff::from_uint64(511UL)
  assert_eq(Binary::quiet_nan(payload=nine, precision=11).nan_payload(), nine)
  assert_eq(
    Binary::signaling_nan(payload=nine, precision=11).nan_payload(),
    nine,
  )
  // no payload bits below precision 3
  assert_eq(Binary::quiet_nan(precision=1).nan_payload(), BinCoeff::zero())
  assert_eq(Binary::quiet_nan(precision=2).nan_payload(), BinCoeff::zero())
  // a zero payload of a signaling NaN is replaced by 1
  let snan = Binary::signaling_nan(precision=3)
  assert_true(snan.is_signaling_nan())
  assert_eq(snan.nan_payload(), BinCoeff::one())
}

///|
test "conversions keep the low payload bits and quiet a signaling NaN that cannot keep one" {
  let snan = Binary::signaling_nan(
    payload=BinCoeff::from_uint64(0b110UL),
    precision=53,
  )
  // precision 5: 3 payload bits, all kept
  let kept = snan.with_precision(5, BinaryRoundingMode::RoundTiesToEven)
  assert_true(kept.is_signaling_nan())
  assert_eq(kept.nan_payload(), BinCoeff::from_uint64(0b110UL))
  // precision 4: 2 bits, 0b10 kept
  let cut = snan.with_precision(4, BinaryRoundingMode::RoundTiesToEven)
  assert_true(cut.is_signaling_nan())
  assert_eq(cut.nan_payload(), BinCoeff::from_uint64(0b10UL))
  // precision 2 or 1: no payload bits, quiet
  let none = snan.with_precision(2, BinaryRoundingMode::RoundTiesToEven)
  assert_true(none.is_quiet_nan())
  assert_eq(none.nan_payload(), BinCoeff::zero())
  // low bits zero: the signaling NaN would have payload 0, so it is quiet
  let low = Binary::signaling_nan(
    payload=BinCoeff::from_uint64(0b100UL),
    precision=53,
  ).with_precision(4, BinaryRoundingMode::RoundTiesToEven)
  assert_true(low.is_quiet_nan())
  // from_double narrows the same way
  let sbits = 0x7ff0000000000007UL.reinterpret_as_double()
  let d = Binary::from_double(sbits, precision=5)
  assert_true(d.is_signaling_nan())
  assert_eq(d.nan_payload(), BinCoeff::from_uint64(7UL))
  let d2 = Binary::from_double(sbits, precision=4)
  assert_true(d2.is_signaling_nan())
  assert_eq(d2.nan_payload(), BinCoeff::from_uint64(3UL))
  assert_true(Binary::from_double(sbits, precision=2).is_quiet_nan())
  // hex literals
  let hex_snan = Binary::from_hex("snan", 2).unwrap()
  assert_true(hex_snan.is_quiet_nan())
  assert_true(Binary::from_hex("snan", 3).unwrap().is_signaling_nan())
}

///|
test "precision is checked where a value is made" {
  let max = binary_precision_max
  // the limits are accepted
  assert_eq(Binary::from_int(3, precision=1).precision(), 1)
  assert_eq(Binary::from_int(3, precision=max).precision(), max)
  assert_eq(Binary::zero(precision=max).precision(), max)
  assert_eq(Binary::nan(precision=max).precision(), max)
  assert_eq(Binary::inf(precision=max).precision(), max)
  // the Result constructors return Err
  assert_true(Binary::from_string("1.5", precision=0) is Err(_))
  assert_true(Binary::from_string("1.5", precision=-4) is Err(_))
  assert_true(Binary::from_string("1.5", precision=max + 1) is Err(_))
  assert_true(Binary::from_hex("0x1p0", 0) is Err(_))
  assert_true(Binary::from_hex("0x1p0", max + 1) is Err(_))
  assert_true(Binary::from_hex("0x1p0", max) is Ok(_))
  // issue 442: operations that build a context from the value's precision
  // work on every precision a constructor accepts below the work limits of
  // the kernels (the operations at exactly the maximum still need the
  // unchecked working context of the context rework)
  let x = Binary::from_int(3, precision=1 << 20)
  assert_eq(x.remainder(Binary::from_int(2)).precision(), 1 << 20)
  assert_eq(x.to_shortest_string(), "3")
}
