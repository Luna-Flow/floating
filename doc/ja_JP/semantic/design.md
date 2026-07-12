# `semantic` 設計

具体表現を exact `ExactRational`、符号付き無限大、NaN、閉区間、semantic error に射影します。二進は 2 の冪、十進は 10 の冪で変換し、区間端点は独立に射影します。checked error は `SemanticError` に写します。

precision、quantum/cohort、負の零、NaN payload/signaling、装飾、context flags は意図的に失います。比較/シリアライズ境界であり、丸め、解析、交換、区間の tightening は行いません。

## Projection の計算量

scalar projection は係数桁数に対する rational reduction、interval は二つの endpoint を独立に処理します。pure function で context を変更しません。

## Stability 境界

cross-representation の診断・test 用 provisional boundary です。precision、cohort、payload、flags が必要なら元の concrete package を使います。
