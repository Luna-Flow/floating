# `bench` Tutorial

## Quick Start

```sh
just bench all
just bench auto-tune
```

## Reading Results

Use `MAREMARK_JSONL` as the versioned raw artifact, `MAREMARK_HOTSPOT` for paired layer overhead, and `MAREMARK_TUNE` / `MAREMARK_CROSSOVER` for confirmed tuning decisions. Normal tests compile plans but skip timing.

- [`bench/bin_float`](./bench/bin_float.md)
- [`bench/decimal`](./bench/decimal.md)
- [`bench/decimal_gda`](./bench/decimal_gda.md)
- [`bench/ball_float`](./bench/ball_float.md)

## Next Reading

Read [API](../api/bench.md) for the generated surface and [Design](../design/bench.md) for ownership and invariants.

