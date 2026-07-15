# FLOATING 0.7.0 ドキュメント

このページはクイックインデックスです。公開名は各 package の `pkg.generated.mbti`
を正とし、Tutorial は推奨利用法、Design は標準整合・アルゴリズム・最適化・切替境界を説明します。

## クイックパス

- 初めて使う：[Getting Started](./getting_started.md)
- 共通数値語彙：[Numeric Semantics](./numeric_semantics.md)
- package/layer モデル：[Architecture](./architecture.md)
- 実際の検証範囲：[Verification](./verification.md)
- 文書規則：[Documentation Standard](./doc_standard.md)

## アプリケーション Package

| 要件 | Package | 最初に読む | 詳細 |
| --- | --- | --- | --- |
| dyadic / IEEE binary | `bin_float` | [Tutorial](./bin_float/tutorial.md) | [API](./bin_float/api.md) · [Design](./bin_float/design.md) · [Conformance](./bin_float/conformance.md) · [Performance](./bin_float/performance.md) |
| IEEE decimal / DPD / BID | `decimal` | [Tutorial](./decimal/tutorial.md) | [API](./decimal/api.md) · [Design](./decimal/design.md) · [Conformance](./decimal/conformance.md) · [Performance](./decimal/performance.md) |
| GDA sticky status / trap | `decimal_gda` | [Tutorial](./decimal_gda/tutorial.md) | [API](./decimal_gda/api.md) · [Design](./decimal_gda/design.md) · [Conformance](./decimal_gda/conformance.md) |
| certified interval / IEEE 1788 | `ball_float` | [Tutorial](./ball_float/tutorial.md) | [API](./ball_float/api.md) · [Design](./ball_float/design.md) · [Conformance](./ball_float/conformance.md) |
| first-error binary composition | `bin_float_checked` | [Tutorial](./bin_float_checked/tutorial.md) | [API](./bin_float_checked/api.md) · [Design](./bin_float_checked/design.md) |
| accumulated IEEE decimal flags | `decimal_checked` | [Tutorial](./decimal_checked/tutorial.md) | [API](./decimal_checked/api.md) · [Design](./decimal_checked/design.md) |
| sticky/trapping GDA composition | `decimal_gda_checked` | [Tutorial](./decimal_gda_checked/tutorial.md) | [API](./decimal_gda_checked/api.md) · [Design](./decimal_gda_checked/design.md) |
| first-error interval composition | `ball_float_checked` | [Tutorial](./ball_float_checked/tutorial.md) | [API](./ball_float_checked/api.md) · [Design](./ball_float_checked/design.md) |
| 共通語彙 | `def` | [Tutorial](./def/tutorial.md) | [API](./def/api.md) · [Design](./def/design.md) |
| 表現非依存の観測 | `semantic` | [Tutorial](./semantic/tutorial.md) | [API](./semantic/api.md) · [Design](./semantic/design.md) |

## Integration / Maintainer Package

- Expression IR：[`numeric_expr`](./numeric_expr/api.md)
- corpus frontend：[`frontend/gda_expr`](./frontend/gda_expr/api.md)、
  [`frontend/itl_expr`](./frontend/itl_expr/api.md)、
  [`frontend/mpfr_expr`](./frontend/mpfr_expr/api.md)、
  [`frontend/testfloat_expr`](./frontend/testfloat_expr/api.md)
- CLI adapter：[`cli`](./cli/api.md) と backend subpackage
- runtime/verification：[`internal`](./internal/api.md)、
  [`internal/conformance`](./internal/conformance/api.md)、
  [`internal/runner_cli`](./internal/runner_cli/api.md)、
  [`consistency`](./consistency/api.md)、[`bench`](./bench/api.md)

これらは repository tooling の合成用に interface を公開しますが、Design に記載する
stability boundary は application package より狭くなります。

## Evidence Snapshot

- 固定 GDA `official` corpus は **64,986/64,986 legal executable scalar rows**
  を全件 pass し、`official0` は 16,124/16,124 です。残る 141 の `#`
  placeholder/non-scalar row は diagnostic exclusion です。
- 固定 strict ITF1788 aggregate は selected interval 4,656/4,656 を pass します。
- Binary/IEEE decimal claim は operation/format matrix に限定され、固定 MPFR
  elementary-function evidence を含みます。

有限 corpus の pass は将来の directive、全標準 operation、全実数入力の対応を意味しません。
互換性を表明する前に該当 conformance page を確認してください。

## 読み方

呼出名は `api.md`、安全な workflow は `tutorial.md`、invariant と実装判断は
`design.md` を参照します。 prose と public inventory が衝突した場合は
`pkg.generated.mbti` を優先します。
