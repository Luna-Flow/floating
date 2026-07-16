# `decimal` Performance

## Measurement Boundary

`just bench decimal --target native` は `src/bench/decimal` の current Maremark suite を
実行し、`.tmp/bench/decimal.jsonl` と analysis file を生成します。これは reproducible
measurement artifact であり、immutable release gate ではありません。0.7.1 には checked-in
decimal performance manifest と threshold workflow がないため、current instruction は下の
Maremark suite を使います。

## Workload

suite は 9、34、128、512 decimal digits の add、multiply、divide を測定します。各 cell
で coefficient kernel、core `Decimal` path、full checked path を exact `BigInt` reference
と照合します。input construction と expected-value construction は timed payload の外です。

## Reading Results

`MAREMARK_JSONL` は versioned raw event stream、`MAREMARK_HOTSPOT` は paired layer-overhead
analysis です。結果は current tree、toolchain、target に依存します。hotspot の発見には
使えますが、universal crossover や release-wide latency bound は示しません。

## Reproduction

```sh
just bench decimal --target native
just bench all --target native
```

all-suite run は binary、GDA、interval kernel も測定します。artifact を比較するには
target、toolchain、workload、benchmark protocol を固定してください。

## Semantic Gate

benchmark equivalence check だけでは十分ではありません。optimized decimal path は
coefficient differential test と pinned IEEE decimal/GDA conformance gate も通過してから
受け入れます。[Conformance](./conformance.md)、[Design](./design.md)、[0.7.1 Performance
And Semantic Audit](../performance_audit.md)を参照してください。
