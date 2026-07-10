# `decimal` 設計ノート

`Decimal` はこのリポジトリの 10 進優先表現です。このページは現在の `0.4.0`
実装基準と、第一段階の GDA 表現移行に合わせています。

## 不変条件

- 有限値は `(-1)^negative * magnitude * 10^exponent10`
- 保存される `magnitude` は非負 coefficient で、符号は独立保持されます。これ
  により `-0` と符号付き NaN payload を表現できます
- 数値コンストラクタ経路では除去可能な `10` 因子を取り除きます
- canonical 形のゼロは exponent `0` を使いますが、符号は保持されます
- 一部の GDA スタイル操作は exponent/quantum を意図的に保持します。canonical
  cohort が必要なら明示的に `normalized()` を使ってください

## 解析経路

`Decimal::from_string` は `@internal.split_decimal_string` を使って:

- 符号処理
- 小数点除去
- 科学表記指数の折り込み

を行ってから値を構築します。解析された coefficient が要求精度に収まる場合
は、末尾ゼロを先に削らず、元の exponent/quantum を保持します。`"-0"` も負の
ゼロとして保持されます。
