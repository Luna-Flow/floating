# `semantic` Design

## Purpose

Concrete types have different storage and rounding behavior. The semantic layer
removes those details so exact values, infinities, NaN, intervals, and errors can
be compared without treating one representation as canonical.

## Limits

The model is a projection, not an arithmetic engine. It intentionally does not
carry Decimal context, precision, quantum, payload, rounding flags, or interval
decoration. Project only when those representation details are no longer needed.
