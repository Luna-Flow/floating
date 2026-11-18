# `differential`

The seeded random differential harness: an executable that validates batches
of generated MPFR and libmpdec rows against `floating` through the
[mare_mark](https://lunaflow.cn/en/mare_mark/) runner and writes the append-only
JSONL record of the run.

## Contract

It reads a corpus produced by `tools/generate_mpfr_random_oracle.c`
(`mpfr-random-v1`) or `tools/generate_libmpdec_random.py` (`.decTest`), runs
every row through the matching frontend, and records one validation per batch,
a delta-debugged failure for every batch that disagrees with its oracle, and
the replay command. It does not implement or alter arithmetic.

## Maintainer Quick Start

```sh
just random-diff smoke
just random-diff run --family add --family dec-add --count 20000 --target native
```

## Detailed Documentation

The synchronized English, Simplified Chinese, and Japanese references live under
`doc/*/differential`. Read `api.md` for the command line, `tutorial.md` for the
shortest workflow, and `design.md` for invariants and trade-offs.
