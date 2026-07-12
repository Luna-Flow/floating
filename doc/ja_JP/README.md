# FLOATING ドキュメント

`0.5.0` release 基準を説明します。公開名の根拠は各 package の `pkg.generated.mbti` です。

## Package 入口

- Core: [`def`](./def)、[`bin_float`](./bin_float)、[`decimal`](./decimal)、[`ball_float`](./ball_float)
- Checked: [`bin_float_checked`](./bin_float_checked)、[`decimal_checked`](./decimal_checked)、[`ball_float_checked`](./ball_float_checked)
- Semantic/IR: [`semantic`](./semantic)、[`numeric_expr`](./numeric_expr)
- Frontend: [`frontend/gda_expr`](./frontend/gda_expr)、[`frontend/itl_expr`](./frontend/itl_expr)、[`frontend/mpfr_expr`](./frontend/mpfr_expr)、[`frontend/testfloat_expr`](./frontend/testfloat_expr)
- Runtime/verification: [`internal`](./internal)、[`internal/conformance`](./internal/conformance)、[`internal/runner_cli`](./internal/runner_cli)、[`consistency`](./consistency)、[`bin_float_bench`](./bin_float_bench)
- CLI: [`cli`](./cli)、[`cli/gda_expr_cli`](./cli/gda_expr_cli)、[`cli/itl_expr_cli`](./cli/itl_expr_cli)、[`cli/mpfr_expr_cli`](./cli/mpfr_expr_cli)、[`cli/testfloat_expr_cli`](./cli/testfloat_expr_cli)

各 package に `design.md` を置き、library には API/tutorial、internal・CLI・test には設計境界を記録します。

## 公開面と安定性

`0.5.0` は 1.0 前の release です。「安定」は本 release で意図した application
surface を指し、将来版の ABI 不変を約束しません。

| Package | 利用できる公開面 | 状態 | 含まれないもの |
| --- | --- | --- | --- |
| `bin_float` | `BinFloat`、`BinCoeff`、context/flags、interchange | 安定 release 面 | IEEE 754 全 operation |
| `decimal` | `Decimal`、context/flags、GDA operation、interchange | 安定 release 面 | `#` placeholder/non-scalar の不正入力だけ除外 |
| `ball_float` | bare/decorated interval、relation、directed arithmetic | 安定 release 面 | reverse operation、tightness 保証 |
| `*_checked` | `Result[..., ArithmeticError]` short-circuit pipeline | 安定 composition 面 | context flags、decoration、recovery policy |
| `semantic` | exact rational/infinity/NaN/interval projection | provisional integration 面 | 表現 metadata と arithmetic |
| `numeric_expr` | syntax node と callback evaluation | provisional integration 面 | text parser と concrete semantics |
| `frontend/*`、`cli/*` | conformance parser、runner、command | 検証 infrastructure | 一般 file/format compatibility |
| `internal/*`、`consistency`、`*_bench` | 実装・検証 helper | application API ではない | compatibility 保証 |

callable 名は `api.md`、不変条件と algorithm の選択は `design.md`、最短の利用例は
`tutorial.md` を参照してください。prose と inventory が違う場合は
`pkg.generated.mbti` を正とします。

## GDA の結論

公式 144 ファイル corpus は合法な executable scalar 64,986/64,986 を通過し、
unsupported と legacy はゼロです。残る 141 行はすべて `#` placeholder/non-scalar
の不正入力で、合法な意味論の分母から除外します。official0 の合法 16,124 行も
全件通過します。

## 検証

`just smoke` または `just conformance smoke <backend>` は同梱 fixture を使います。full corpus と対応範囲は `testdata/*/README.md` を参照し、pass を IEEE 754、GDA、ITF1788 全体の保証とは解釈しません。
