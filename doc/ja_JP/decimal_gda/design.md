# `decimal_gda` 設計

`decimal_gda` は GDA Specification 1.70 の独立 engine で、固定 testcase suite 2.62 により
検証します。IEEE `decimal` に依存せず、value/coefficient/context/flags/interchange/finalization
を package 内に所有します。

## Design Objective

GDA operation は value に加え conditions、sticky status、optional trap と defined result を持つため、
pure state transition として表現します：operand/context → exact operation/finalization → value/raised/
next context → fixed-precedence trap → `Completed`/`Trapped`。Trap は value を消す exception ではありません。

## Value / Coefficient Representation

Finite `Decimal` は classification、sign、`GdaCoeff`、exponent、precision、sNaN state、payload。
`Small(UInt64)` は `10^18-1` まで、`Limbs(Array[UInt],digits)` は little-endian base-`10^9`。
Published value は mutable scratch を共有しません。Cohort、signed zero、NaN/payload を保持します。

## Context、Status、Trap Alignment

`GdaContext` は precision、8 rounding modes、exponent bounds、clamp、extended、sticky status、traps
を直接保存します。Operation は raised を next status に combine し、fixed GDA precedence で trap を
一つ選びます。Completed/Trapped はともに defined value、next context、raised を保持します。

## Arithmetic / Finalization

Finite arithmetic は exact signed coefficient と preferred exponent を作り、shared finalizer が rounding、
cohort、clamp、subnormal、underflow/overflow、signed zero、flags を決めます。FMA は一回 rounding。
1–18 digit parse/add/sub/mul/FMA fast path は finite/Small/in-range/unclamped/flag-free の全 predicate
成立時だけ使い、otherwise generic finalizer。Differential test が state 全体を比較します。

## Coefficient Algorithm Selection

Local engine は schoolbook/Comba、Karatsuba、Toom-3、dual-modulus NTT、Knuth D、BZ、Newton を持ち、
size/density/balance/square/transform/target で選びます。

| Target | Karatsuba mul/square | Toom-3 | first NTT mul/square | BZ | Newton |
| --- | ---: | ---: | ---: | ---: | ---: |
| native | 96 / 48 | 1,152 | 1,728 / 640 | adaptive 2,816+ | disabled |
| LLVM | 96 / 96 | 2,048 | 4,096 / 2,048 | 2,048 | 4,096 |
| Wasm / Wasm-GC / JS | 96 / 96 | 4,096 | 8,192 / 4,096 | 2,048 | 4,096 |

Native NTT/BZ boundary は 8,192/10,240 まで piecewise に変化します。NTT bounds/CRT、Toom exact
division、quotient/remainder identity を検査し exact fallback。IEEE decimal と数値 threshold が同じでも
code/test は独立し、semantic/dependency boundary を共有しません。

## Certified Elementary Functions

Sqrt は local integer-sqrt、integer power は exact/bounded exponentiation。Non-integer power と
`exp/ln/log10` は directed binary interval で decimal rounding cell を証明し、すべて GDA finalization
を通ります。Immutable single-entry `ln(10)` cache を使用。GDA surface は sqrt/power/exp/ln/log10
に限定し、trigonometric/hyperbolic/inverse/atan2/hypot/pi-scaled は公開しません。

## Non-Arithmetic / Interchange Operations

Comparison/total order、extrema、logB、same-quantum、adjacent、copy/class/predicate、logical digit、
shift/rotate、integral conversion、scientific/engineering formatting を実装します。Concrete interchange
は package-owned DPD。BID は IEEE package feature で意図的に非対応です。

## Optimization / Switching Boundary

Candidate は value/cohort/raised/next status/trap の完全一致と target benchmark benefit の両方が必要。
Boundary test は cutoff 前・点・後、sparse/square/unbalanced を覆います。Small fast path は semantic
predicate、large selector は performance policy です。

## Effect / Verification Boundary

`.decTest` parse、directive、shard、JSON、filesystem、process status は frontend/CLI/Python tooling。
Acceptance は property/all-target/dependency/IEEE isolation と corpus を組合せ、`official` 64,986/64,986、
`official0` 16,124/16,124 legal rows を pass。141 `#` placeholder/non-scalar は diagnostic exclusion です。

## 0.7.1 Semantic Preservation Proof

GDA coefficient remainder path は quotient/remainder division と同じ Euclidean remainder
`r = a - floor(a / d) * d`、`0 <= r < d` を計算します。従って GCD、exact division、half-power comparison が見る
canonical coefficient fact は不変です。Half-power predicate は leading decimal digit と残りの non-zero limb で
`5 * 10^(digits - 1)` と比較し、binary approximation には変換しません。

Small-value arithmetic path は finite、`Small`、context bounds、flag-free predicate がすべて成立した場合だけ許可し、
同じ GDA finalizer と trap precedence を使います。Semantic acceptance tuple は value/cohort、raised flags、next sticky context、
defined result、selected trap です。Package/frontend/boundary differential test と二つの decTest corpus が declared surface を検証し、
coefficient threshold は GDA rule ではなく performance policy です。

## Evidence Map

[API](./api.md)、[Tutorial](./tutorial.md)、[Conformance](./conformance.md)、および独立 IEEE model の
[`decimal` Design](../decimal/design.md) を参照してください。
