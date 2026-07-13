# `bin_float_bench` 設計

## 責務

代表的な `BinCoeff` 操作を測定する benchmark 専用 package です。

## データフロー

test harness が固定 shape の operand を構築し、MoonBit bench cell を実行して測定値を返します。production dispatch には関与しません。

## アルゴリズムと不変条件

timed loop の外で setup を行い、結果を保持する必要があります。測定値は選択根拠であり correctness contract ではありません。

## 失敗と副作用

skip された benchmark test は local allocation と計時だけを行い、application IO は実行しません。

## 実装上のトレードオフ

package を分離すると benchmark dependency が `bin_float` に漏れませんが、threshold 用 white-box bench は core package 側に残ります。

## 安定性

repository infrastructure として保守されます。生成宣言は runner とともに変更され得るため、downstream compatibility は保証しません。
