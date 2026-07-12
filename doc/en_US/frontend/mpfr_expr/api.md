# `frontend/mpfr_expr` API

`parse_sqrt_data`/`execute_sqrt_data` handle MPFR hexadecimal sqrt rows.
`parse_pow_data`/`execute_pow_data` handle the pinned integer-power witness
format. Documents expose source and case count; summaries expose total, passed,
failed, individual results, and `success`.

Only these two repository-pinned grammars are accepted. Diagnostics preserve
source, line, and message.
