# `decimal_checked`

`DecimalResult` is the stable short-circuit wrapper for parse and scalar Decimal
pipelines. It preserves `ArithmeticError` without collapsing it into a special
value. It does not carry `DecimalContext` or accumulate `DecimalFlags`; use
`decimal` `*_ctx` methods whenever GDA status or cohort behavior is part of the
contract.
