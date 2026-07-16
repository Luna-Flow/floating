# `ball_float` Performance

## Measurement Boundary

`just bench ball-float --target native` は `src/bench/ball_float` の current Maremark suite
を実行し、`.tmp/bench/ball-float.jsonl` と analysis file を生成します。artifact は current
target の layer cost を測定しますが、IEEE 1788 completeness claim や release-wide latency
guarantee ではありません。

## Workload

suite は 53、128、512、2,048 bit で add、multiply、divide を測定します。各 cell で binary
kernel、core `BallFloat`、full checked path を比較します。expected value は exact binary
result で、timing observation を受け入れる前に ball と checked output が singleton enclosure
として一致する必要があります。

## Reading Results

`MAREMARK_JSONL` は raw event stream、`MAREMARK_HOTSPOT` は kernel-to-core と core-to-checked
の paired overhead です。layer cost が低くても enclosure が tight とは限りません。directed
rounding、decoration、pole、conservative fallback は core path の semantic responsibility です。

## Reproduction

```sh
just bench ball-float --target native
just bench all --target native
```

artifact を比較する場合は target、toolchain、workload、benchmark protocol を固定します。
通常の benchmark test は plan を compile するだけで timing を skip します。

## Semantic Gate

performance evidence は enclosure correctness に従属します。0.7.1 interval gate は pinned
strict ITF1788 case 4,656/4,656 を通過し、integer-power regression boundary も含みます。
[Conformance](./conformance.md)、[Design](./design.md)、[0.7.1 Performance And Semantic
Audit](../performance_audit.md)を参照してください。
