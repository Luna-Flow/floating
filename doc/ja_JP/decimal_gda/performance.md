# `decimal_gda` Performance

## Measurement Boundary

`just bench decimal-gda --target native` は `src/bench/decimal_gda` の current Maremark
suite を実行し、`.tmp/bench/decimal-gda.jsonl` と analysis file を生成します。独立した
quick fixture は `python3 tools/run_gda_benchmark.py` で実行でき、`.tmp/bench/gda-quick-native.json`
に cell ごとの三つの native run を記録します。どちらの artifact も universal speed claim
ではなく、conformance gate の代替でもありません。

## Workload

Maremark suite は 1、9、18、34、128 decimal digits で add、subtract、multiply、divide、
FMA、parse を測定します。core `GdaContext` path と full checked path を比較し、layer
overhead を報告する前に core result と照合します。

## Reading Results

`MAREMARK_JSONL` は raw event stream、`MAREMARK_HOTSPOT` は core と checked の paired
overhead です。quick fixture は operation ごとの median と dispersion も記録します。
結果は記録された target、toolchain、fixture、workload に限定して解釈し、cross-target
threshold や固定 latency bound とはみなしません。

## Reproduction

```sh
just bench decimal-gda --target native
python3 tools/run_gda_benchmark.py
just bench all --target native
```

artifact を比較する場合は target と toolchain を固定します。通常の benchmark test は
plan を compile するだけで timing を skip するため、測定には明示的な benchmark command
が必要です。

## Semantic Gate

timing path は独立した GDA state model と pinned legal scalar corpus と合わせて受け入れます。
0.7.1 audit では current 64,986/64,986 row と legacy 16,124/16,124 row が通過しています。
[Conformance](./conformance.md)、[Design](./design.md)、[0.7.1 Performance And Semantic
Audit](../performance_audit.md)を参照してください。
