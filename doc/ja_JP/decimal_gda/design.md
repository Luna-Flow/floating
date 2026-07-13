# `decimal_gda` 設計

`decimal_gda` は General Decimal Arithmetic の state/control semantics を IEEE-oriented
`decimal` API から分離し、内部では同じ検証済み decimal kernel を再利用します。

## 責務と表現

Public `Decimal` wrapper は opaque です。`GdaContext` は internal decimal context、
GDA rounding、sticky status、trap configuration を持ちます。この package は GDA
naming、signal mapping、trap precedence、state threading を所有し、coefficient
arithmetic、transcendental algorithm、decimal32/64/128 encoding は複製しません。

分離により、一つの context type が二つの非互換な意味を持つことを防ぎます。
IEEE code は per-operation flags、GDA code は status/trap を thread します。Text または
interchange format が public value type 間の explicit boundary です。

## Outcome state machine

各 operation は次の順で処理します。

1. 対応する internal decimal context operation を実行する。
2. `DecimalFlags` を現在 step の raised `GdaFlags` に map する。
3. raised flags を input context の sticky status に combine する。
4. 固定 precedence で enabled trap を scan する。
5. value、next context、raised flags を保持した `Completed`/`Trapped` を返す。

Flow は deterministic かつ pure です。Context は immutable data で、status の
「更新」は新 context を返すことです。Caller が thread、clear、discard を選びます。

## Context 不変条件

Public precision は正で `e_min <= e_max` です。`try_new` は checked constructor、
`new` は正 precision invariant を直接 enforce します。Radix は 10 で、standard preset
は GDA decimal32/64/128 の precision、exponent、clamp を使います。

`clear_status` は trap を保持し、`reset` は status/trap の両方を消します。Trap-set
operation は新しい値を返し、別 calculation と共有する context を mutate しません。

## Capability 境界

Operation inventory は実装済み scalar GDA family、すなわち arithmetic、FMA、integer
division/remainder、quantize/rescale、integral conversion、elementary function、
adjacent value、logical digit、shift/rotate、numeric/total comparison を含みます。

Filesystem、`.decTest` parsing、case filter、sharding、JSON、process exit status は
`frontend/gda_expr`、`internal/runner_cli`、CLI、Python tooling の責務です。Effect を
numeric package 外に置き、operation/state transition を普通の値として test できます。

## Conformance 境界

Compatibility claim は parser token ではなく pinned legal scalar row で定義します。
`frontend/gda_expr` は `#` placeholder/non-scalar row を diagnostic とし、unknown future
operation/condition を別に報告します。Strict runner は denominator を silent に縮めず、
supported-case gap を failure にします。

IEEE decimal conformance は independent DPD/BID fixture の別 gate です。GDA decTest
pass だけで全 IEEE interchange property を証明せず、IEEE fixture pass も GDA sticky
status/trap を提供しません。

## 計算量と拡張

Decimal operation wrapper の追加コストは constant state combination と固定 13-signal
precedence scan です。Numeric complexity と allocation は delegated decimal operation
のものです。

Signal/operation 追加時は public enum/interface、flag/trap mapping、precedence、adapter、
`.decTest` frontend support、test、generated interface、全 localized docs を同時に更新します。
Explicit boundary conversion を避ける目的で internal decimal value を公開しません。

