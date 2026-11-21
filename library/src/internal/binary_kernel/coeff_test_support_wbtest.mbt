///|
/// Parses `text` as a BigInt; malformed text aborts.
fn bigint_from_text(text : StringView, radix~ : Int32 = 10) -> BigInt {
  @string.parse_bigint(text, radix~) catch {
    _ => abort("invalid BigInt text")
  }
}
