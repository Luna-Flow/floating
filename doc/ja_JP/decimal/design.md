# `decimal` 設計

## 責務と表現

有限値は独立符号、非負 `BigInt` 係数、10 進指数、精度を保存し、負の零、無限大、qNaN/sNaN、payload を観測可能にします。解析と quantum 操作は末尾零/cohort を保持でき、`normalized()`/`reduce_ctx()` が値を変えず cohort を正規化します。

## 係数と丸め algorithm

内部 `DecCoeff` は little-endian base-1000 配列で、シフト、加減算、schoolbook 乗算、長除、正確な冪、丸め補助を実装します。公開係数は `BigInt` のままで、二進系の `BinCoeff` 移行とは異なります。現状 Karatsuba/Toom/FFT の分岐はありません。

## Context と effect 境界

`*_ctx` は特殊値、正確な係数/指数、8 種の decimal rounding、指数境界/subnormal/clamp、`DecimalFlags` の順に処理します。FMA は加算後に一度だけ丸め、quantize は目標指数を固定し precision 超過を `invalid_operation` にします。

## 能力境界

算術、FMA、整数除算/余り、quantize/rescale、total 比較、logical digit、隣接値、分類、書式、decimal32/64/128 交換、初等関数を提供します。固定 official/official0 corpus の合法な executable scalar 行はすべて通過し、unsupported/legacy はゼロです。除外するのは `#` placeholder/non-scalar の不正入力だけです。

## 数学モデルと cohort

有限値は `(-1)^negative × coefficient × 10^exponent10` です。`1.20` と `1.2`
は同じ数学値でも quantum が異なります。`normalized()`/`reduce_ctx()` は値を
変えず cohort だけを変換するため、通常の equality、`same_quantum`、total order
は別の観測です。

`*_ctx` は特殊値、exact coefficient/exponent、precision と八つの rounding、
指数境界、clamp、`DecimalFlags` の順で処理します。`rounded` は常に inexact では
なく、`subnormal` は常に underflow ではありません。

## 計算量と選択

`n` 個の base-1000 limb では加減算・比較・shift・正規化が `O(n)`、schoolbook
乗算と long division が `O(n²)` です。base-1000 は parse、carry、GDA rounding
を監査しやすくし、bounded precision では Karatsuba/Toom/FFT の tuning overhead
を避けます。将来 kernel を交換しても公開契約は変わりません。

## Context と effect 境界

`DecimalContext` は明示的な input、`DecimalFlags` は明示的な output であり、ambient rounding state は使いません。
