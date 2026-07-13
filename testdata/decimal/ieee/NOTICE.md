These fixtures are maintained as repository test data. DPD and BID values are
generated from the IEEE 754-2019 interchange encoding formulas; arithmetic rows
are checked with exact integer/rational reference calculations.

`dectest_ieee_excerpt.json` contains 42 deliberately selected decimal64 and
decimal128 rows from the pinned Cowlishaw `dectest.zip` concrete-format files.
The General Decimal Arithmetic project labels those files beta, non-exhaustive,
and not sufficient to establish compliance with any Standard. They therefore
serve as supplementary differential diagnostics only; the clause-derived
fixtures and independent encoding checks remain the authoritative oracle.

`vector_plan.json` is the reproducible expansion contract: ten oracle families
each target 100,000 generated rows spanning the declared IEEE boundary and
coefficient-size classes. Generated rows are descriptors until their selected
RDFP, Arb, or MPFR adapter is installed and its result/flags pair is recorded.
