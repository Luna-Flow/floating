# `semantic` API

このパッケージは具体的な数値表現を、表現に依存しない小さな意味モデルへ投影します。

## 厳密値とスカラー

- `ExactRational::new` は正規化有理数、`from_scaled_integer` は厳密な基数付きスケール整数を作ります。
- `SemanticScalar` は `Rational`、`Infinity(Sign)`、`NaN` です。
- `from_bin_float` と `from_decimal` が具体的スカラーを投影します。

## 区間とエラー

- `SemanticInterval` は公開 `lower`、`upper` を持ち、`from_ball_float` が区間を投影します。
- `SemanticError` は除算、解析、定義域、形式、未対応操作、順序不能比較を区別します。
- `SemanticError::from_arithmetic` は `ArithmeticError` をこの意味エラー語彙へ写します。
- `SemanticResult[T]` は `Value(T)` または `Error(SemanticError)` です。
- `semantic_scalar_result` と `semantic_interval_result` は指定された投影関数で checked 結果を変換します。
