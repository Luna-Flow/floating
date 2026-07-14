# `decimal_gda_checked`

`GdaDecimalChecked` is the closed General Decimal Arithmetic composition
surface. It threads the sticky `GdaContext` through completed operations,
short-circuits when a configured trap fires, and retains the trapped signal,
defined result, next context, and raised flags. Continuing from a trapped
defined result always requires an explicit `resume_defined()` call.
