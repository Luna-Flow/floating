# `ball_float` Conformance

## Claim

The current strict ITF1788 gate executes 4,113/4,113 selected cases with no failed, unsupported, or diagnostic rows. This is a claim about the pinned corpus revision, selected operation phases, and runner precision—not a claim of complete IEEE 1788 implementation.

## Semantic Oracle

Expected results are compared by set meaning: endpoint containment, set relations, boolean relations, overlap states, numeric observations, and decorations use operation-specific comparators. A conservative interval may be valid when the contract permits widening; an enclosure that excludes an exact result is never valid.

## Supported Phases

The strict matrix covers sets, relations, observations, cancellation, add/subtract/multiply/divide, elementary core, exponential/logarithmic functions, general power, trigonometric functions, FMA, integer power, and extrema. Phase operation sets are disjoint so a row is never counted twice.

## Decorations And Fallbacks

Empty, Entire, and decorated NaI are separate states. Elementary kernels use directed dyadic certificates. When range reduction cannot be certified, `sin`/`cos` return `[-1,1]` and `tan` returns Entire; that preserves inclusion but does not promise tightness.

## Exclusions

Reverse interval operations, every decoration rule outside the selected phases, arbitrary endpoint formats, and unpinned upstream revisions remain outside the claim.

## Reproduction

```sh
just conformance smoke interval
just conformance fetch interval itf1788
just interval-ci 8
```

See [the interval data guide](../../../testdata/interval/README.md) for provenance, phase counts, strict-mode behavior, and failure triage.
