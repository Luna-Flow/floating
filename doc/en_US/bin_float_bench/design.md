# `bin_float_bench` Design

`bin_float_bench` is a test-only benchmark package that imports the public
`BinCoeff` surface. It measures representative construction and arithmetic
without becoming part of the shipped API. Algorithm-specific threshold tuning
also has skipped white-box benches inside `bin_float`; benchmark results guide
dispatch constants but never define correctness or stable performance promises.
