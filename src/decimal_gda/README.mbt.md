# `decimal_gda`

`decimal_gda` is the General Decimal Arithmetic surface. Its opaque `Decimal`,
`GdaContext`, `GdaFlags`, and `GdaTrapSet` are distinct from the IEEE package.
Every operation returns `GdaOutcome`, including sticky status, the signals
raised by that operation, and the GDA-defined result when a trap is enabled.

New IEEE 754 code should import `decimal`. GDA decTest integrations should
import this package and cross the IEEE/GDA boundary only through text or
interchange formats.
