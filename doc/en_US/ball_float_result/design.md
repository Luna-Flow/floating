# `ball_float_result` Design

## Responsibility

The wrapper distinguishes construction or checked-operation failure from a
valid but wide enclosure. Whole-real fallback is valid interval information,
not an arithmetic error.

## Boundaries

Only value-producing operations are lifted. Relations naturally return `Bool`
and remain on `BallFloat`. Existing errors short-circuit `map`, `bind`, and all
numeric methods.
