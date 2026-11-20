///|
/// The representation of a `BinFloat` on the JavaScript target, where a
/// coefficient is a host bigint and no word path exists: no `Fin64` and no
/// `Fin128`. A finite value, zero included, is `FinBig`. Only `bin_repr_js.mbt`
/// of `bin_float` matches on it. The type is internal.
#derive(Eq, Debug)
pub(all) enum BinRepr {
  FinBig(
    negative~ : Bool,
    coefficient~ : Coeff,
    exponent2~ : Int32,
    precision~ : Int32,
  )
  Inf(negative~ : Bool, precision~ : Int32)
  NaN(negative~ : Bool, signaling~ : Bool, payload~ : Coeff, precision~ : Int32)
}
