# `bin_float` 適合性

この文書は `0.6.0` における 2 進浮動小数点の意味論と検証境界を記録
します。有限のテストが全通過しても、すべての実数入力に対する形式的証明を
意味しません。

## 標準・論文・参照実装

- IEEE 754-2019：interchange format、丸め方向、符号付きゼロ、NaN、例外、
  丸め前/後 tininess の意味論。
- Fousse、Hanrot、Lefèvre、Pélissier、Zimmermann、
  [MPFR: A Multiple-Precision Binary Floating-Point Library with Correct Rounding](https://doi.org/10.1145/1236463.1236468)、
  ACM TOMS 33(2), 2007：厳密結果を一度だけ丸める任意精度モデル。
- Berkeley SoftFloat/TestFloat 3e：IEEE の結果ビットと例外フラグを独立に
  生成する参照実装・ベクトル。

## 数学的意味論とアルゴリズム

有限非ゼロ値は次の dyadic 実数を表します。

`(-1)^negative * coefficient * 2^exponent2`（`coefficient` は非負の `BinCoeff`）

非ゼロ coefficient から 2 の因子を除去して正規化しますが、`+0` と `-0` は
統合しません。無限大、qNaN、sNaN、NaN の符号と payload は明示的な状態です。

`add_ctx`、`sub_ctx`、`mul_ctx`、`div_ctx`、`sqrt_ctx`、`pow_int_ctx` は、IEEE
特殊値を先に解決し、dyadic/有理数または平方根の境界で厳密な数学結果を求め、
目標精度・方向で一回だけ丸め、最後に指数範囲/subnormal の量子化と五つの IEEE
フラグを導出します。テスト ID やテスト値に基づく分岐はありません。

binary16 の `0x0400 * 0x3BFF` は `0x0400` になりますが、
`inexact | underflow` です。after-rounding tininess は最終 normal encoding では
なく、目標精度で丸めた無界指数の結果から判定します。

## 固定コーパスと結果

完全ゲートは
[`testdata/bin_float/README.md`](../../../testdata/bin_float/README.md) に定義します。

| ソース | 範囲 | 結果 |
| --- | --- | --- |
| TestFloat 3e level 1、seed 1 | 4 format × 5 operation × 5 rounding × 2 tininess | 7,461,360 / 7,461,360 |
| MPFR 4.2.2 `tests/data/sqrt` | 実行可能な 16 進 sqrt 行すべて | 1,055 / 1,055 |
| MPFR 4.2.2 `pow_si` fixture | 4 precision × 5 supported rounding × 6 input | 120 / 120 |
| コミット済み smoke | TestFloat、sqrt、`pow_si` witness | 183 / 183 |
| TestFloat 3e level 2 | binary16 の全 declared operation/direction/tininess | 50,205,600 / 50,205,600 |

binary16 level-2 の結果は追加の streaming stress evidence であり、より大きい
binary32/64/128 level-2 corpus を完了済みと主張するものではありません。NaN 以外では encoding bit と exception bit を厳密に比較します。期待値が NaN の
場合だけ quiet-NaN class と exception bit を比較します。IEEE 754 では新規に
生成される NaN payload の選択が許されるためです。実装は選択した入力 NaN の
符号/payload を保持し、sNaN を quiet にします。`--level 2` は行を捨てない
有界 chunk で実行できますが、巨大な任意 stress corpus であり、上記の有限
ゲート結果には含めません。

## 主張の境界

## Evidence の安定性

固定 matrix が release evidence の境界です。新しい operation には新しい corpus contract と oracle が必要です。

## Evidence の記録

各 gate は format、rounding、tininess、encoded result、exception bits を summary に残し、再検証できます。

ここで主張するのは four interchange format における contextual add/sub/mul/div/
sqrt のみです。FMA、remainder、変換、比較、min/max、total order、十進形式、
または全 IEEE 754 operation の適合性は主張しません。`pow_int_ctx` の値と
inexact は MPFR fixture、nearest-away、before/after tininess、全 flags は exact
dyadic/rational oracle で検証します。MPFR は `MPFR_RNDNA` を一般の `pow_si`
rounding 引数として使うことを禁止しています。

日常の確認は `just conformance smoke binary`、固定 full gate は `just bin-ci` を実行します。
