# `bench/decimal` 設計

## 責務

係数コスト、contextual `Decimal` コスト、`DecimalChecked` wrapper コストを分離します。

## データフロー

決定的な十進係数を計測前に生成し、9、34、128、512 桁を評価します。

## 不変条件

作業精度は正確演算に十分で、全レイヤーを同じ整数参照値で検証します。

## 副作用

明示的に含めた skipped test だけが時間を測定して artifact を出力します。

