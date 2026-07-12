# `numeric_expr` 設計

literal、operation、source span、呼び出し木だけを持つ private IR です。`evaluate` は深さ優先の後順走査を行い、意味論は callback、ノード失敗は元ノード付き、未対応形は `UnsupportedExpression` として返します。

tokenize、型選択、arity、丸め、IO、スケジューリングは担当せず、frontend が入力方針、backend が数値意味論を所有します。

## Pure traversal と計算量

`evaluate` は post-order traversal で、`n` node の callback 呼出しは `O(n)`、stack は tree depth `O(h)` です。数値 operation の費用は callback 側が決めます。

## Stability 境界

construction と callback interface は provisional integration surface で、tree layout は private です。frontend の syntax 変更を backend 表現へ漏らしません。
