# `frontend/testfloat_expr`

Parser and executor for the verified Berkeley TestFloat matrix.

## Contract

It covers binary16/32/64/128 add, subtract, multiply, divide, sqrt, mulAdd, rem, roundToInt (plain and exact), conversions to signed/unsigned 32/64-bit integers (plain and exact), and the six comparison predicates under explicit rounding and tininess policies.

## Maintainer Quick Start

```sh
sh tools/run_moon_clean_exec.sh test -p Luna-Flow/floating/frontend/testfloat_expr --target native
```

## Detailed Documentation

The synchronized English, Simplified Chinese, and Japanese references live under
`doc/*/frontend/testfloat_expr`. Read `api.md` for the generated surface, `tutorial.md` for the
shortest workflow, and `design.md` for invariants and trade-offs.
