///|
fn scale_show(result : (BinFloat, BinaryFlags)) -> String {
  "\{result.0} flags=\{result.1.to_testfloat_bits()}"
}

///|
test "scaleB rounds once with range handling" {
  let context = BinaryContext::binary64()
  let three = BinFloat::from_int(3)
  inspect(
    scale_show(three.scaleb_ctx(10, context)),
    content=(
      #|3p10 flags=0
    ),
  )
  inspect(
    scale_show(three.scaleb_ctx(1023, context)),
    content=(
      #|inf flags=5
    ),
  )
  inspect(
    scale_show(three.scaleb_ctx(-1074, context)),
    content=(
      #|3p-1074 flags=0
    ),
  )
  inspect(
    scale_show(three.scaleb_ctx(-1076, context)),
    content=(
      #|1p-1074 flags=3
    ),
  )
  inspect(
    scale_show(three.scaleb_ctx(2147483647, context)),
    content=(
      #|inf flags=5
    ),
  )
  inspect(
    scale_show(three.neg().scaleb_ctx(-2147483647 - 1, context)),
    content=(
      #|-0 flags=3
    ),
  )
  inspect(
    scale_show(BinFloat::negative_zero().scaleb_ctx(5, context)),
    content=(
      #|-0 flags=0
    ),
  )
}

///|
test "logB returns the leading-bit exponent" {
  let context = BinaryContext::binary64()
  inspect(
    scale_show(BinFloat::from_double(10.0).logb_ctx(context)),
    content=(
      #|3p0 flags=0
    ),
  )
  inspect(
    scale_show(BinFloat::from_double(0.75).logb_ctx(context)),
    content=(
      #|-1p0 flags=0
    ),
  )
  inspect(
    scale_show(BinFloat::from_double(-1.0).logb_ctx(context)),
    content=(
      #|0 flags=0
    ),
  )
  inspect(
    scale_show(BinFloat::make(BinCoeff::one(), -1074, 53).logb_ctx(context)),
    content=(
      #|-537p1 flags=0
    ),
  )
  inspect(
    scale_show(BinFloat::zero().logb_ctx(context)),
    content=(
      #|-inf flags=8
    ),
  )
  inspect(
    scale_show(BinFloat::inf(Sign::Negative).logb_ctx(context)),
    content=(
      #|inf flags=0
    ),
  )
}
