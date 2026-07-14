# FLOATING ドキュメント

`0.6.1` release 基準を説明します。公開名の根拠は各 package の `pkg.generated.mbti` です。

最初に[はじめに](./getting_started.md)、[数値意味論](./numeric_semantics.md)、
[Architecture](./architecture.md)、[検証](./verification.md)を読み、その後に
package reference を開いてください。

## Package 入口

- Core: [`def`](./def/api.md)、[`bin_float`](./bin_float/api.md)、[`decimal`](./decimal/api.md)、[`decimal_gda`](./decimal_gda/api.md)、[`ball_float`](./ball_float/api.md)
- Checked: [`bin_float_checked`](./bin_float_checked/api.md)、[`decimal_checked`](./decimal_checked/api.md)、[`decimal_gda_checked`](./decimal_gda_checked/api.md)、[`ball_float_checked`](./ball_float_checked/api.md)
- Semantic/IR: [`semantic`](./semantic/api.md)、[`numeric_expr`](./numeric_expr/api.md)
- Frontend: [`frontend/gda_expr`](./frontend/gda_expr/api.md)、[`frontend/itl_expr`](./frontend/itl_expr/api.md)、[`frontend/mpfr_expr`](./frontend/mpfr_expr/api.md)、[`frontend/testfloat_expr`](./frontend/testfloat_expr/api.md)
- Runtime/verification: [`internal`](./internal/api.md)、[`internal/conformance`](./internal/conformance/api.md)、[`internal/runner_cli`](./internal/runner_cli/api.md)、[`consistency`](./consistency/api.md)、[`bin_float_bench`](./bin_float_bench/api.md)
- CLI: [`cli`](./cli/api.md)、[`cli/gda_expr_cli`](./cli/gda_expr_cli/api.md)、[`cli/itl_expr_cli`](./cli/itl_expr_cli/api.md)、[`cli/mpfr_expr_cli`](./cli/mpfr_expr_cli/api.md)、[`cli/testfloat_expr_cli`](./cli/testfloat_expr_cli/api.md)

全 package に `api.md`、`tutorial.md`、`design.md` を置きます。infrastructure、CLI、benchmark、test package は maintainer entry point と、stable application API ではない境界を明示します。

## 公開面と安定性

`0.6.1` は 1.0 前の release です。「安定」は本 release で意図した application
surface を指し、将来版の ABI 不変を約束しません。

| Package | 利用できる公開面 | 状態 | 含まれないもの |
| --- | --- | --- | --- |
| `bin_float` | `BinFloat`、`BinCoeff`、context/flags、interchange | 安定 release 面 | IEEE 754 全 operation |
| `decimal` | `Decimal`、IEEE context/flags、interchange | 安定 release 面 | IEEE 754 全 operation |
| `decimal_gda` | GDA `Decimal`、context、sticky flags、trap、outcome | 安定 GDA 面 | 未固定の future directive と non-scalar placeholder |
| `ball_float` | bare/decorated interval、relation、directed arithmetic | 安定 release 面 | reverse operation、tightness 保証 |
| `bin_float_checked`、`ball_float_checked` | `Result[..., ArithmeticError]` short-circuit pipeline | 安定 composition 面 | context flags と decoration |
| `decimal_checked` | IEEE context、defined result、latest/accumulated flags | 安定 IEEE composition 面 | GDA sticky status と trap |
| `decimal_gda_checked` | sticky context、trap short-circuit、explicit recovery | 安定 GDA composition 面 | IEEE per-operation context model |
| `semantic` | exact rational/infinity/NaN/interval projection | provisional integration 面 | 表現 metadata と arithmetic |
| `numeric_expr` | syntax node と callback evaluation | provisional integration 面 | text parser と concrete semantics |
| `frontend/*`、`cli/*` | conformance parser、runner、command | 検証 infrastructure | 一般 file/format compatibility |
| `internal/*`、`consistency`、`*_bench` | 実装・検証 helper | application API ではない | compatibility 保証 |

callable 名は `api.md`、不変条件と algorithm の選択は `design.md`、最短の利用例は
`tutorial.md` を参照してください。prose と inventory が違う場合は
`pkg.generated.mbti` を正とします。

## 数値的な証拠

- [`bin_float` conformance](./bin_float/conformance.md) と [performance](./bin_float/performance.md)
- [`decimal` IEEE conformance](./decimal/conformance.md) と [performance](./decimal/performance.md)
- [`decimal_gda` conformance](./decimal_gda/conformance.md)
- [`ball_float` conformance](./ball_float/conformance.md)

performance threshold は実装 evidence であり public guarantee ではありません。conformance page は有限 claim と除外範囲を明記します。

## GDA の結論

公式 144 ファイル corpus は合法な executable scalar 64,986/64,986 を通過し、
unsupported と legacy はゼロです。残る 141 行はすべて `#` placeholder/non-scalar
の不正入力で、合法な意味論の分母から除外します。official0 の合法 16,124 行も
全件通過します。

## 検証

`just conformance smoke <backend>` は同梱 fixture を使います。full corpus と対応範囲は `testdata/*/README.md` を参照し、pass を IEEE 754、GDA、ITF1788 全体の保証とは解釈しません。
