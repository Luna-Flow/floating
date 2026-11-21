///|
/// The representation of a `Binary` (native, wasm and llvm targets). Every
/// constructor is one heap object that holds its scalars inline (a constructor
/// with several scalar fields is a single allocation), so a finite value whose
/// coefficient has at most 128 bits costs one object, not a record plus a
/// coefficient object.
///
/// The form of a finite value is unique: `Fin64` when the coefficient has at
/// most 64 bits (zero included, as `word = 0` with `exponent2 = 0`), `Fin128`
/// for 65 to 128 bits, `FinBig` beyond; a non-zero coefficient is odd. Only
/// `bin_repr_nonjs.mbt` of `binary` and the `_nonjs` fast paths match on it.
/// The type is internal: it carries no compatibility promise.
#derive(Eq, Debug)
pub(all) enum BinRepr {
  Fin64(
    negative~ : Bool,
    word~ : UInt64,
    exponent2~ : Int32,
    precision~ : Int32,
  )
  Fin128(
    negative~ : Bool,
    high~ : UInt64,
    low~ : UInt64,
    exponent2~ : Int32,
    precision~ : Int32,
  )
  FinBig(
    negative~ : Bool,
    coefficient~ : Coeff,
    exponent2~ : Int32,
    precision~ : Int32,
  )
  Inf(negative~ : Bool, precision~ : Int32)
  NaN(negative~ : Bool, signaling~ : Bool, payload~ : Coeff, precision~ : Int32)
}
