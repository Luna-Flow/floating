# はじめに

このガイドは `Luna-Flow/floating` **`0.7.1`** を対象とし、package の選択、
module の追加、値の構築、失敗モデルの選択、参照先を説明します。

## 数値領域を選ぶ

入力文字列の見た目ではなく、application が必要とする意味論から表現を選びます。

| 要件 | Package | 主な値 | 結果モデル |
| --- | --- | --- | --- |
| 任意精度 dyadic 値または IEEE binary interchange | `bin_float` | `BinFloat` | 値、または context 付き `(value, BinaryFlags)` |
| IEEE 任意精度 decimal と decimal interchange | `decimal` | `Decimal` | 値、または context 付き `(value, DecimalFlags)` |
| General Decimal Arithmetic の status と trap | `decimal_gda` | `Decimal` | next context と raised flags を持つ `GdaOutcome[Decimal]` |
| 証明可能な実数 enclosure | `ball_float` | `BallFloat` / `BallFloatDecorated` | enclosure、または `(enclosure, BallFlags)` |
| flags を蓄積する IEEE decimal pipeline | `decimal_checked` | `DecimalChecked` | defined value と latest/accumulated `DecimalFlags` |
| trap control を持つ GDA pipeline | `decimal_gda_checked` | `GdaDecimalChecked` | sticky context と `GdaOutcome[Decimal]` |
| short-circuit binary/interval pipeline | `bin_float_checked`、`ball_float_checked` | `*Result` | wrapper 内の `Result[..., ArithmeticError]` |
| 表現に依存しない比較 | `semantic` | `SemanticScalar` / `SemanticInterval` | metadata を意図的に落とす exact projection |

`numeric_expr` と `frontend/*` は parser や conformance tool を構築するときに
使用します。`internal/*`、`consistency`、`doc_examples`、`*_bench` は
maintainer infrastructure であり、application dependency ではありません。

## Install と import

現在の release を追加します。

```sh
moon add Luna-Flow/floating@0.7.1
moon add Luna-Flow/arithmetic
```

現在の MoonBit package が必要とする package 境界だけを import します。

```moonbit nocheck
import {
  "Luna-Flow/arithmetic"
  "Luna-Flow/floating/bin_float"
  "Luna-Flow/floating/decimal"
  "Luna-Flow/floating/decimal_gda"
  "Luna-Flow/floating/decimal_checked"
  "Luna-Flow/floating/decimal_gda_checked"
  "Luna-Flow/floating/ball_float"
}
```

Import は source file ではなく package を指します。同じ `moon.pkg` 内の file は
一つの compilation unit であり、個別の submodule を作りません。

`Luna-Flow/arithmetic` は、明示的な precision 変更と変換境界で使う rounding
mode の型を提供します。すべての操作で default rounding を使う場合は不要ですが、
import すると境界 policy が code 上で明示されます。

## 値を構築する

Binary coefficient は `BinCoeff` で表し、sign は独立です。Decimal parser は
有意な末尾 zero を含む input quantum を保持します。Interval は通常、順序付けた
binary endpoint から作ります。

```moonbit nocheck
let binary = @bin_float.BinFloat::make(
  @bin_float.BinCoeff::from_uint64(3UL),
  -1,
  53,
)
let decimal = @decimal.Decimal::from_string("12.3400").unwrap()
let interval = @ball_float.BallFloat::from_bounds(
  @bin_float.BinFloat::from_int(1),
  @bin_float.BinFloat::from_int(2),
)
```

`binary` は exact dyadic 値 `3 × 2^-1`、`decimal` は exponent `-4` を保持し、
`interval` は 1 から 2 までの全実数を表します。canonical cohort が必要な場合
だけ `normalized()` を呼びます。

## Context モデルを選ぶ

固定 format に制約されない任意精度計算では通常 method を使います。precision、
exponent limit、rounding、tininess、clamp、status flags が結果の一部なら
`*_ctx` を使います。

```moonbit nocheck
let binary_context = @bin_float.BinaryContext::binary64()
let (binary_sum, binary_flags) = binary.add_ctx(binary, binary_context)

let decimal_context = @decimal.DecimalContext::decimal64()
let (decimal_value, decimal_flags) =
  @decimal.Decimal::from_string_ctx("1.234567890123456789", decimal_context)
```

IEEE context は immutable input、flags は explicit output です。複数 step の
accumulated status が必要なら flags を combine します。GDA は各
`GdaOutcome` に更新済み sticky context を返します。

## 失敗モデルを選ぶ

Library は同一ではない複数の failure channel を意図的に公開します。

- `Option` は追加 diagnostic contract を持たない単純 constructor 用です。
- `Result[T, ArithmeticError]` は checked scalar capability 用です。
- `BinaryFlags`、`DecimalFlags`、`BallFlags` は定義済み値を生成する際の IEEE/
  domain condition を報告します。
- `GdaOutcome[T]` は設定した trap が発火しても GDA-defined result を保持します。
- `DecimalChecked` は defined NaN/infinity を置き換えず IEEE flags を蓄積し、
  `GdaDecimalChecked` は完全な `GdaOutcome` を保持したまま trap で短絡します。
- `Entire`、`Empty`、`NaI` は interval-domain value であり generic error ではありません。

これらを一つの exception や万能 `Result` に変換すると、観測可能な数値意味論が
失われます。

## 結果を正しく読む

- Scalar 表現は signed zero、infinity、quiet/signaling NaN、payload を保持できます。
- NaN がある通常 scalar comparison は partial で、total-order API は別 operation です。
- `BallFloat` には containment/set relation があり、scalar total order はありません。
- Interval は数学的結果を enclosure すれば正しく、tightness は別の品質です。
- `SemanticScalar` は数学的意味を比較しますが、precision、quantum、signed zero、
  NaN payload、decoration、flags を意図的に失います。

## 次に読む文書

- [数値意味論](./numeric_semantics.md)は precision、rounding、status、特殊値、interval enclosure を説明します。
- [Architecture](./architecture.md)は stable package と parsing/execution/verification layer を対応付けます。
- [検証](./verification.md)は quick/authoritative gate と各 conformance claim の正確な範囲を示します。
- 各 package の `api.md`、`tutorial.md`、`design.md` は callable 名、workflow、実装境界を扱います。
- numeric core の evidence は package ごとに記録します：[`bin_float`](./bin_float/conformance.md)、[`decimal`](./decimal/conformance.md)、[`decimal_gda`](./decimal_gda/conformance.md)、[`ball_float`](./ball_float/conformance.md)。
