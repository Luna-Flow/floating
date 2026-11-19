# `bench/external`

Maremark benchmarks of `floating` against MPFR (binary) and libmpdec
(`decimal_gda`) on the same operands. The package times `bin_float` and
`decimal_gda` on the cases of an operand file written by
`tools/external_baseline.py`, checks every result against the MPFR or libmpdec
result for the same operands, and streams versioned `mmka_1` JSONL. The C side
is `tools/external_baseline.c`; the runner alternates the two in seeded AB/BA
order and reduces both to ratios.

```sh
just bench external run
just bench external run --preset quick
```

The timed test is skipped during normal correctness runs; the plan and
parsing tests run everywhere. See `doc/manual/performance/bench/external.md`
for the method, the machine and the measured ratios.
