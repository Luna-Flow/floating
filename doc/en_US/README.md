# FLOATING Documentation

This directory documents the current **`0.4.1`** implementation. Historical
release notes belong in [CHANGELOG.md](../../CHANGELOG.md).

## Reader Guide

- Start with `bin_float`, `decimal`, or `ball_float` for concrete values.
- Use the matching `*_result` package for closed checked-arithmetic pipelines.
- Read `semantic` when values from several representations need a common exact
  comparison or serialization boundary.
- Read `numeric_expr` to build a numeric expression frontend; read `gda_expr`
  for the General Decimal Arithmetic `.decTest` frontend and Decimal backend.
- Treat `internal` and `consistency` as implementation and verification layers,
  not as stable application APIs.

## Core Documents

- [Documentation Standard](./doc_standard.md)
- [Correctness Audit](./correctness_audit.md)
- [Release History](../../CHANGELOG.md)
- [Conformance Workflow](../../testdata/decimal/README.md)

## Package Documentation

- [`def`](./def/api.md): [API](./def/api.md), [Tutorial](./def/tutorial.md), [Design](./def/design.md)
- [`bin_float`](./bin_float/api.md): [API](./bin_float/api.md), [Tutorial](./bin_float/tutorial.md), [Design](./bin_float/design.md)
- [`decimal`](./decimal/api.md): [API](./decimal/api.md), [Tutorial](./decimal/tutorial.md), [Design](./decimal/design.md), [Architecture Research](./decimal/architecture_research.md)
- [`ball_float`](./ball_float/api.md): [API](./ball_float/api.md), [Tutorial](./ball_float/tutorial.md), [Design](./ball_float/design.md)
- [`bin_float_result`](./bin_float_result/api.md): [API](./bin_float_result/api.md), [Tutorial](./bin_float_result/tutorial.md), [Design](./bin_float_result/design.md)
- [`decimal_result`](./decimal_result/api.md): [API](./decimal_result/api.md), [Tutorial](./decimal_result/tutorial.md), [Design](./decimal_result/design.md)
- [`ball_float_result`](./ball_float_result/api.md): [API](./ball_float_result/api.md), [Tutorial](./ball_float_result/tutorial.md), [Design](./ball_float_result/design.md)
- [`semantic`](./semantic/api.md): [API](./semantic/api.md), [Tutorial](./semantic/tutorial.md), [Design](./semantic/design.md)
- [`numeric_expr`](./numeric_expr/api.md): [API](./numeric_expr/api.md), [Tutorial](./numeric_expr/tutorial.md), [Design](./numeric_expr/design.md)
- [`gda_expr`](./gda_expr/api.md): [API](./gda_expr/api.md), [Tutorial](./gda_expr/tutorial.md), [Design](./gda_expr/design.md)
- [`internal`](./internal/api.md): [API](./internal/api.md), [Tutorial](./internal/tutorial.md), [Design](./internal/design.md)

The English tree is the structural source of truth. Chinese and Japanese docs
keep the same Markdown file set and section responsibilities.
