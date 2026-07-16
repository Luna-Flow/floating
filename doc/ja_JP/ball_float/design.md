# `ball_float` 設計

`ball_float` は 0.7.1 の certified real enclosure domain です。`BinFloat` endpoint 上に bare/decorated
interval を構築し declared IEEE 1788-2015 boundary に整合します。Correctness は tightness より先に
set inclusion で定義します。

## Design Contract

Pipeline は input interval → Empty/Entire/domain classification → monotone/critical/full-product rule →
lower downward / upper upward → `BallContext` → optional decoration。`bin_float` は endpoint rounding/
certificate、`ball_float` は set image の endpoint combination/domain fallback を所有します。

## Representation / Invariant

Non-empty interval は NaN でない `lo_ <= hi_` と precision を保持し、Empty/Entire は explicit。
`new(center,radius)` は constructor view に過ぎません。Precision conversion は outward のみ。
`exact(x)` は supplied dyadic `BinFloat` を exact に埋め込み、以前の decimal approximation を元の
decimal real に戻しません。Decorated value は decoration と distinct NaI を追加します。

## IEEE 1788 Alignment

Bare operation は set enclosure、decorated は operand/domain/continuity に応じ grade を下げ、NaI は
Empty と分離します。Relations は set semantics、reverse operations は boundary 外。Pinned strict
ITF1788 selected 4,656/4,656 を pass（general power、trig、hyperbolic、inverse、375 atan2）。
Rootn/extensions は corpus coverage と分けて報告します。

## Basic Arithmetic Selection

| Operation | Enclosure rule | Boundary |
| --- | --- | --- |
| add | `[a.lo+b.lo,a.hi+b.hi]` directed | Empty propagation |
| sub | `[a.lo-b.hi,a.hi-b.lo]` | subtrahend order reversal |
| mul | four endpoint products の min/max | sign shortcut は candidate を落とさない |
| reciprocal/div | zero exclusion 時 endpoint reciprocal | interior zero→Entire、one-sided zero→half-infinite |
| square/root | monotone pieces + domain | negative-only sqrt→Empty |
| intersection/hull | endpoint max/min | disjoint intersection→Empty |

`BallContext` は endpoint precision/exponent と flags を適用し、Entire は valid success です。

## Certified Elementary Functions

Directed dyadic certificate と analytic remainder bound を使います。Exp range reduction、ln power-of-two
reduction、certified log、Machin pi、quadrant reduction、alternating series、critical/pole detection、
inverse/hyperbolic monotonic endpoints、guarded power を実装。最大 12 refinement、growth
`max(32,work/2)`。`try_*` は failure detail、total API は contract が許す場合 sin/cos `[-1,1]`、
tan Entire などの safe fallback を返します。

## Critical Point、Pole、Switching Boundary

Periodic function は certified index range に extremum/pole が含まれるか判定し、heuristic epsilon を
使いません。Unbounded または adjusted exponent が `max(65,536,4×precision)` を超える場合、total
path は safe range、`try_*` は resource detail。これは proof-resource boundary です。

## Decoration / Relation

Decoration は最弱 grade へ伝播。`contains`、`subset/interior/set_equal`、`overlap_state`、
`definitely_lt/gt`、`maybe_eq` はそれぞれ set semantics を持ちます。Interval に scalar total order
はなく、`Sign::Zero` は zero crossing の場合もあります。

## Optimization / Trade-off

Basic cost は constant endpoint operations で `O(M(p))`。Elementary は range reduction、bounded series、
refinement を追加します。Constant/special case/monotonicity/shared trig reduction は最適化しますが、
endpoint candidate を捨てたり nearest rounding に置換しません。Resource と tightness が衝突すれば
total API は widen、checked API は理由を返します。

## 0.7.1 Semantic Preservation Proof

各 finite endpoint candidate `y` について、downward rounding は lower certificate、upward rounding は upper certificate です。
実装はまず monotonicity と sign structure から mathematical extremum を選び、その役割に合う direction を適用します。
`quantize_interval` は stored precision でも outward relation を保ちます。

Integer-power の obligation は明示的です。Positive odd は increasing、positive even は negative half-axis で decreasing、
negative odd は zero から離れると decreasing、negative even は negative half-axis で increasing です。Zero-containing negative
power は pole/whole-real branch を使います。Negative-half-axis regression、directed endpoint test、strict ITF1788 aggregate が
declared forward interval surface の ordered set inclusion を検証します。Wider fallback は有効ですが、reversed または inward-rounded endpoint は無効です。

## Evidence Map

[API](./api.md)、[Tutorial](./tutorial.md)、[Conformance](./conformance.md)、endpoint kernel/crossover の
[`bin_float` Design](../bin_float/design.md) / [Performance](../bin_float/performance.md) を参照してください。
