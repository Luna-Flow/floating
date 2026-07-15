# `bench/bin_float` 設計

## 責務

係数カーネル、`BinFloat`、checked wrapper、全初等関数、平方 crossover 候補を測定します。

## データフロー

決定的な正確係数を同じ Maremark case の係数、コア、checked 実装へ供給します。

## 不変条件

算術レイヤーは同じ正確値を返し、初等関数のコアと checked は計測前に一致し、調整は `mul(x, x)` と `square(x)` だけを比較します。

## 副作用

統一 runner が skipped test を明示的に含めた場合だけ `mmka_1` JSONL と hotspot/tuning 行を出力します。

