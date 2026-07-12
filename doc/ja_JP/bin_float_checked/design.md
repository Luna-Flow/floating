# `bin_float_checked` 設計

`BinFloatResult` は閉じた `Result[BinFloat, ArithmeticError]` pipeline です。constructor が境界で検証し、unary は成功値だけを map、binary は左から最初の error を保持し、両方成功時だけ checked scalar を呼びます。`bind` は新しい失敗を返せますが `map` は返せません。

算術、IEEE flags、交換、回復戦略は追加せず `bin_float` に委譲します。context IEEE pipeline は底層の `(value, flags)` API を直接使います。

各 wrapper step は底層演算以外 `O(1)` です。error を `BinFloat` 自体へ埋め込まず、
通常の algebraic value と first-error pipeline を別契約にするための設計です。
