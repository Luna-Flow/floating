# `bench/decimal`

Maremark benchmarks for decimal arithmetic. Exact integer workloads compare
the coefficient baseline, contextual `Decimal` core, and `DecimalChecked`
full path at representative decimal precisions.

```sh
just bench decimal
```

Fixture construction and reference validation stay outside timed payloads.
