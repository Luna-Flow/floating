# `bin_float` 設計

## 責務と表現

`bin_float` は任意精度の二進スカラー、IEEE コンテキスト/交換形式、および `BinCoeff` カーネルを担当します。有限値は独立符号、非負係数、`2^exponent2`、精度で表し、非零係数から取り除ける 2 の因子を除きます。符号付き零、無限大、qNaN/sNaN、payload は観測可能です。

非 JS では inline 値または little-endian limb、JS では同じ API の裏側に host `bigint` を使います。表現レイアウトは API ではなく、`Decimal`/`Semantic` の `BigInt` 境界は変更しません。

## 係数アルゴリズム

乗算は limb 数と形状で schoolbook（96 未満）、Karatsuba（96 以上）、不均衡 block（長辺が短辺の 2 倍超）、Toom-3、条件を満たす二素数 Montgomery NTT+CRT、overlap-add に分岐します。Native/LLVM の Toom/NTT 閾値は 2048、NTT square は 768、Wasm 系は 4096 と 3072 です。これは benchmark 調整値であり安定 API ではありません。

除算は word、Knuth（48 未満）、Burnikel–Ziegler（48 以上）、Newton reciprocal（1024 以上）を選び、平方根は 512 bit まで固定幅、その上は divide-and-conquer です。GCD は大きな入力で Lehmer batching を使います。

## 丸めと境界

コンテキスト演算は特殊値を解決し、正確な dyadic/rational 結果を作り、商/余りと guard/sticky で一度だけ丸め、指数境界と tininess を適用します。整数冪には can-round 判定と正確な係数冪の恒久的 fallback があります。検証済み行列は文書記載の TestFloat/MPFR に限られ、IEEE 754 全体の実装を意味しません。

## 数学モデルと丸め pipeline

有限非零値は `(-1)^negative × coefficient × 2^exponent2` です。係数は非負で、
正規化は 2 の因子を指数へ移すため同じ dyadic に一つの canonical 表現を与えます。
context 演算は特殊値、exact result、商と余りによる一回の丸め、指数 encoding、
flags の順で処理し、inexact は非零余りから決めます。

通常演算は任意精度値、`*_ctx` は IEEE format/rounding/status、
`BinaryInterchange` は binary16/32/64/128 の bit 境界です。

## 計算量と trade-off

`n` limb の schoolbook、Karatsuba、Toom-3、NTT は概ね `O(n²)`、
`O(n^1.585)`、`O(n^1.465)`、`O(n log n)` です。小入力では定数の小さい方式、
巨大で均衡した入力だけ transform を選びます。大きな除算は `M(n)` に近づき、
高速経路には exact fallback があるため公開結果は変わりません。

## API 境界

通常演算、`*_ctx`、`BinaryInterchange` はそれぞれ任意精度、format/status、固定幅 bit encoding の契約です。
