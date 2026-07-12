# `frontend/mpfr_expr` API

`parse_sqrt_data`/`execute_sqrt_data` は MPFR hex sqrt、`parse_pow_data`/`execute_pow_data` は固定 integer-power witness を扱います。document は source/case count、summary は total/passed/failed/results/success を公開します。

repository 固定の二つの文法だけを受け入れ、diagnostic は source、line、message を保持します。
