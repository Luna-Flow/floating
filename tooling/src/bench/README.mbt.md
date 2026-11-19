# `bench`

Shared Maremark infrastructure for repository performance experiments. It
builds immutable benchmark specifications, records explicit environment and
protocol data, compares paired kernel/core/full-path observations, and reduces
confirmed samples into deterministic auto-tune decisions.

The package keeps experiment description and statistical reduction pure.
Timing, JSONL streaming, process execution, and artifact writes stay in the
datatype benchmark packages and `tools/benchmark.py`.

The runner stores versioned observations in `.jsonl` and paired hotspot,
tuning, crossover, and deployment-policy lines in a matching `.analysis.txt`
sidecar.

```sh
just bench all
just bench auto-tune
```
