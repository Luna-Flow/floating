# Architecture

`floating` は明示的な数値 domain と、薄い composition、parsing、verification layer
で構成されます。純粋な数値変換を filesystem、process、corpus の effect から分離します。

## Layer map

| Layer | Package | 責務 |
| --- | --- | --- |
| 共有語彙 | `def` | classification、sign、partial order、arithmetic type の reexport、最小 `Floating` trait |
| Scalar domain | `bin_float`、`decimal`、`decimal_gda` | binary、IEEE decimal、GDA decimal の意味論 |
| Interval domain | `ball_float` | bare/decorated outward-rounded enclosure |
| Checked composition | `bin_float_checked`、`ball_float_checked`、`decimal_checked`、`decimal_gda_checked` | error、IEEE flags、GDA outcome を保つ domain-specific pipeline |
| Semantic projection | `semantic` | 表現に依存しない exact observation |
| Syntax | `numeric_expr` | source span、literal、primitive call、callback evaluation |
| Format frontend | `frontend/*` | corpus format を parse し typed case を実行 |
| Runtime adapter | `internal/conformance`、`internal/runner_cli`、`cli/*` | summary、sharding、file、JSON、exit code |
| Verification | `consistency`、`doc_examples`、`*_bench`、`tools/`、`testdata/` | law、executable docs、performance、corpus orchestration |

Package 境界は `moon.pkg` が決めます。Package 内 file 名は実装を整理するだけで、
namespace を作りません。

## 数値 core

`BinFloat` は独立 sign、非負 `BinCoeff`、binary exponent、precision、特殊値 state
を保持します。non-JS target は private inline/limb kernel、JS は同じ public
contract を持つ hidden host-`bigint` adapter を使います。

`Decimal` は sign、private decimal coefficient、base-10 exponent、precision、
cohort、特殊値 state を保持します。Coefficient kernel は target ごとに調整した
multiplication/division dispatch を使いますが、public behavior は limb layout ではなく
decimal value、quantum、context、flags で定義されます。

`BallFloat` は binary lower/upper endpoint と Empty/Entire state を保持します。
Directed rounding が enclosure を作り、`BallFloatDecorated` は bare representation
を変えずに IEEE 1788 decoration と NaI を追加します。

## Context と effect flow

通常 arithmetic は pure value transformation です。Contextual arithmetic も pure
であり、context は explicit input、result と flags は explicit output です。Ambient
rounding state は使いません。

```text
value(s) + immutable context
          -> classify special states
          -> exact or guarded finite computation
          -> one bounded-format finalization
          -> rounded value + operation flags
```

`decimal_gda` は immutable state threading を追加します。各 operation は新しい
raised flags を sticky status に combine し、固定 precedence で enabled trap を
選びます。Status を蓄積するには返された context を次の operation に渡します。

Checked wrapper は各 numerical domain の effect channel を保ちます。Binary と
interval wrapper は最初の `ArithmeticError` を保持します。`decimal_checked` は
IEEE context を固定して flags を蓄積し、defined exceptional result を保持します。
`decimal_gda_checked` は next sticky context を渡し、`Trapped` で停止し、defined
result から続行するには explicit recovery を要求します。

## Parsing と execution

`numeric_expr` は syntax data と post-order callback evaluation だけを持ち、IO も
numeric backend の選択も行いません。

各 `frontend/*` package は一つの外部 grammar を所有します。

- `gda_expr` は `.decTest` directive/case を parse して GDA row を実行します。
- `testfloat_expr` は TestFloat vector と function/rounding/tininess を扱います。
- `mpfr_expr` は pinned MPFR sqrt と integer-power data を扱います。
- `itl_expr` は interval test language row を parse して support を分類します。

Frontend は typed summary を返します。CLI は file、shard/filter、JSON/text、process
status を扱います。Python tool は pinned data の fetch、task plan、複数 process/
target、aggregation を担当し、MoonBit numerical implementation を置換しません。

## Stable と internal の境界

Application-facing release surface は `def`、concrete numeric package、checked wrapper
です。`semantic` と `numeric_expr` は provisional integration surface です。Frontend
は repository runner の composition のため public ですが、compatibility は宣言済み
corpus と generated interface の範囲です。

`internal/*`、CLI、benchmark、`consistency`、`doc_examples` は implementation/
verification infrastructure です。`pkg.generated.mbti` に symbol があっても stable
application contract とは限らないため、package design を確認します。

## 不変条件

- Coefficient sign と非負 magnitude は独立です。
- Finite normalized form は表現上の冗長性だけを除き、数学的値を保ちます。
- Decimal parser は explicit normalization まで cohort/quantum を保持できます。
- Bounded precision、exponent、clamp、status policy は context finalization で適用します。
- Interval lower bound は downward、upper bound は upward に round します。
- Empty、Entire、NaI、NaN、infinity は explicit state のままです。
- Summary count は selected case を分割し、sharding は deterministic です。
- IO、process state、download、parallel scheduling は tooling edge に置きます。

## 拡張規則

Behavior は意味論を所有する package に追加します。新しい umbrella trait を作る前に
既存 arithmetic capability trait を composition します。Numeric kernel は private、
context と flags は explicit に保ち、stable interchange contract でない format parser
は concrete value type の外に置きます。

Conformance surface を拡張するときは parser model、executor、support classification、
CLI schema、corpus manifest、test、localized docs を同時に更新します。Token を parse
できるだけでは support ではなく、strict execution の定義済み比較と再現可能な証拠が必要です。
