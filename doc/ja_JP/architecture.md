# アーキテクチャ

`floating` 0.7.1 は、明示的な数値 domain と薄い composition/parsing/verification layer
で構成されます。数値意味論を pure かつ明示的に保ち、filesystem・process・corpus・
benchmark effect を repository edge に置くことが中心原則です。

## Layer Map

| Layer | Package | 責務 |
| --- | --- | --- |
| 共通語彙 | `def` | classification、sign、partial order、arithmetic type reexport、最小 `Floating` trait |
| scalar domain | `bin_float`、`decimal`、`decimal_gda` | binary、IEEE decimal、GDA decimal の value/context semantics |
| interval domain | `ball_float` | bare/decorated outward-rounded real enclosure |
| checked composition | `*_checked` | 各 domain の error/flag/trap state を closed pipeline に保持 |
| semantic projection | `semantic` | 表現非依存の exact observation |
| syntax | `numeric_expr` | source span、literal、primitive call、callback evaluation |
| format frontend | `frontend/*` | 単一 corpus grammar の parse と typed case 実行 |
| runtime adapter | `internal/conformance`、`internal/runner_cli`、`cli/*` | summary、shard、file、JSON/text、exit status |
| evidence | `consistency`、`doc_examples`、`bench/*`、`tools/`、`testdata/` | law、docs、conformance、performance、orchestration |

Package boundary は `moon.pkg` が定義し、同一 package 内の file 名は namespace を作りません。

## 標準境界

すべてを一つの「floating value」に平坦化せず、標準ごとの観測可能 state を保持します。

| Domain | 0.7.1 が表現する規範モデル | Operation result |
| --- | --- | --- |
| `bin_float` | declared IEEE 754-2019 binary | value + `BinaryFlags` |
| `decimal` | declared IEEE 754-2019 decimal/interchange | value + `DecimalFlags` |
| `decimal_gda` | GDA 1.70 scalar operation model | raised、sticky next context、optional trap を持つ `GdaOutcome` |
| `ball_float` | declared IEEE 1788-2015 bare/decorated interval | enclosure、decoration/NaI、optional `BallFlags` |

この分離により GDA trap を IEEE flag に、IEEE defined infinity を generic error に、
Entire/Empty/NaI を同一 failure に変換しません。

## Numeric Core Pipeline

各 scalar core は次の分解を共有します。

```text
public immutable value(s) + explicit context
  -> special-state/domain classification
  -> exact coefficient or certified interval computation
  -> one domain-owned finalization
  -> public value + explicit effect data
```

`BinFloat` は sign、non-negative binary coefficient、exponent、precision、special state、
二つの Decimal は独立した package-owned base-`10^9` coefficient と quantum、
`BallFloat` は outward endpoint と Empty/Entire を保持します。Finalization が semantic
firewall であり、kernel は flags、cohort、trap、decoration、endpoint direction を決めません。

## Algorithm Selection Architecture

Large integer kernel は size/shape/target/proof precondition から inline/schoolbook/Comba、
Karatsuba、Toom-3、NTT+exact CRT を段階選択し、precondition failure では exact fallback
へ戻ります。Division は word/Knuth D から Burnikel-Ziegler/Newton へ進み、sparse、square、
unbalanced shape は専用経路を持ちます。

Boundary は target-specific private policy です。Maremark が dense/sparse/square/balanced/
unbalanced を測定し、cutoff の直前・点・直後で exact differential test を行います。
Native/LLVM/Wasm/Wasm-GC/JS が異なる path を選んでも public result は同一です。

## Certified Elementary Architecture

共通 proof contract は、directed lower/upper enclosure を作り、両 endpoint を target domain
へ丸め、value と flags が一致した時だけ採用し、otherwise `max(32, work/2)` で精度を増し、
12 refinement 後に structured detail を返します。

`bin_float` が scalar dyadic certificate、`ball_float` が endpoint/critical point/pole/domain、
decimal 二包が exact decimal↔dyadic conversion を担当します。Total interval API は安全に
`[-1,1]`/Entire へ広げられ、`try_*` は proof/resource failure を公開します。

## Context / Effect Flow

Ambient rounding state は使いません。Binary/IEEE decimal context は immutable input、flags
は output、GDA は sticky next context と fixed-precedence trap、`BallContext` は endpoint
limits を扱います。Binary/interval wrapper は first `ArithmeticError`、`DecimalChecked` は
IEEE flags、`GdaDecimalChecked` は一つの outcome と trap short-circuit を保持します。

Wrapper は既存 semantics を合成するだけで、新しい arithmetic algorithm や不正な effect
merge を導入しません。

## Parsing / Execution

`numeric_expr` は syntax data と post-order callback evaluation のみです。各 frontend が
GDA/TestFloat/MPFR/ITL grammar を所有し typed summary を返します。CLI は files/filter/
shard/render/exit code、Python tooling は checksum-pinned data、isolated target/process、
aggregation を担当し、MoonBit 数値実装を置き換えません。

## Stable / Internal Boundary

Application surface は `def`、concrete numeric package、checked wrapper です。`semantic` と
`numeric_expr` は provisional、frontend compatibility は declared corpus/interface に限定。
`internal/*`、CLI、`bench/*`、`consistency`、`doc_examples` は implementation/verification
infrastructure です。`pkg.generated.mbti` への掲載だけで長期 application contract にはなりません。

## Invariant

- sign と non-negative coefficient は分離する；
- binary normalization は 2 の factor のみ除く；
- decimal parse は explicit normalization/reduction まで quantum を保持する；
- context finalization が唯一の bounded rounding/status decision point；
- interval lower は downward、upper は upward；
- Empty/Entire/NaI/NaN/signed zero/infinity は明示 state；
- fast path/fallback は public value/effect data を変えない；
- conformance count は selected case を partition し sharding は deterministic；
- IO/download/process/parallel scheduling は tooling edge に置く。

## Extension Rule

Semantics を所有する package に機能を追加し、umbrella trait より既存 capability composition
を優先します。Kernel は private、context/effect は explicit、external format parse は stable
interchange contract でない限り numeric value 外に置きます。

Conformance surface 拡張では parser、executor、support classification、CLI schema、manifest、
test、generated interface、三言語文書を同時更新します。Parse できるだけでは support ではなく、
strict execution に定義済み比較と再現可能 evidence が必要です。
