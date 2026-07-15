# `bench` Tutorial

## Quick Start

```sh
just bench all
just bench auto-tune
```

## Reading Results

Use `MAREMARK_JSONL` as the versioned raw artifact, `MAREMARK_HOTSPOT` for paired layer overhead, and `MAREMARK_TUNE` / `MAREMARK_CROSSOVER` for confirmed tuning decisions. Normal tests compile plans but skip timing.

- [`bench/bin_float`](./bin_float/tutorial.md)
- [`bench/decimal`](./decimal/tutorial.md)
- [`bench/decimal_gda`](./decimal_gda/tutorial.md)
- [`bench/ball_float`](./ball_float/tutorial.md)

## Next Reading

Read [API](./api.md) for the generated surface and [Design](./design.md) for ownership and invariants.

