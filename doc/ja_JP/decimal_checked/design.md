# `decimal_checked` Design

## State Model

`DecimalChecked` は value、IEEE context、latest flags、accumulated flags の immutable
product です。Construction は `DecimalContext::ieee754()` を強制し、GDA profile が
この package に入ることを防ぎます。

## Transitions

各 method は一つの contextual operation を実行します。返された value が next value、
flags が `raised` になり、`combine` で `flags` に蓄積されます。Exceptional IEEE
result は defined value のままです。`with_context` は new IEEE context で current
value を明示的に再適用し、その step を記録します。

## Composition Boundary

Binary method は plain `Decimal` を取ります。別の `DecimalChecked` を取ると context
と flag history の merge rule が恣意的になるためです。同じ理由で operator は実装
しません。Wrapper overhead は constant state copy と flag combine です。
