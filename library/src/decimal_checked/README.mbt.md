# `decimal_checked`

`DecimalChecked` is the IEEE decimal composition surface. It keeps one immutable
`DecimalContext`, the current defined result, flags raised by the latest
operation, and flags accumulated across the pipeline. IEEE exceptional results
remain values; they are not collapsed into `ArithmeticError`.
