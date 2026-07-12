# `cli` Design

The executable package is a thin dispatcher. It parses only `--backend`,
forwards all remaining arguments unchanged to one backend CLI, and maps help or
argument errors to process exit codes. It owns no corpus parsing, numerical
algorithm, sharding, or JSON schema. Supported backend names are `gda`,
`testfloat`, `mpfr`, and `itl`.
