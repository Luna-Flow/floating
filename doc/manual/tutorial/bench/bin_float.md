# `bench/bin_float` Tutorial

## Quick Start

```sh
just bench bin-float
just bench elementary
just bench auto-tune
```

## Reading Results

Use `MAREMARK_JSONL` as the versioned raw artifact, `MAREMARK_HOTSPOT` for paired layer overhead, and `MAREMARK_TUNE` / `MAREMARK_CROSSOVER` for confirmed tuning decisions. Normal tests compile plans but skip timing.

## Next Reading

Read [API](../../api/bench/bin_float.md) for the generated surface and [Design](../../design/bench/bin_float.md) for ownership and invariants.

