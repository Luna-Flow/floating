# FLOATING ドキュメント

このディレクトリは現在の **`0.4.1`** 実装を説明します。過去のリリース
情報は [CHANGELOG.md](../../CHANGELOG.md) に集約し、README は現在の基準だけを扱います。

## 読み進め方

- 具体的な数値型には `bin_float`、`decimal`、`ball_float` を使います。
- checked 演算を閉じたパイプラインとして組み立てる場合は、対応する
  `*_result` パッケージを使います。
- 複数の表現に共通する厳密な境界が必要な場合は `semantic` を参照します。
- 数値式フロントエンドには `numeric_expr`、GDA `.decTest` と Decimal
  適合性処理には `gda_expr` を参照します。
- `internal` と `consistency` は実装・検証層であり、安定したアプリ API ではありません。

## 基本文書

- [ドキュメント標準](./doc_standard.md)
- [正しさ監査](./correctness_audit.md)
- [リリース履歴](../../CHANGELOG.md)
- [適合性テスト手順](../../testdata/decimal/README.md)

## パッケージ文書

- [`def`](./def/api.md): [API](./def/api.md)、[チュートリアル](./def/tutorial.md)、[設計](./def/design.md)
- [`bin_float`](./bin_float/api.md): [API](./bin_float/api.md)、[チュートリアル](./bin_float/tutorial.md)、[設計](./bin_float/design.md)
- [`decimal`](./decimal/api.md): [API](./decimal/api.md)、[チュートリアル](./decimal/tutorial.md)、[設計](./decimal/design.md)、[アーキテクチャ調査](../en_US/decimal/architecture_research.md)
- [`ball_float`](./ball_float/api.md): [API](./ball_float/api.md)、[チュートリアル](./ball_float/tutorial.md)、[設計](./ball_float/design.md)
- [`bin_float_result`](./bin_float_result/api.md): [API](./bin_float_result/api.md)、[チュートリアル](./bin_float_result/tutorial.md)、[設計](./bin_float_result/design.md)
- [`decimal_result`](./decimal_result/api.md): [API](./decimal_result/api.md)、[チュートリアル](./decimal_result/tutorial.md)、[設計](./decimal_result/design.md)
- [`ball_float_result`](./ball_float_result/api.md): [API](./ball_float_result/api.md)、[チュートリアル](./ball_float_result/tutorial.md)、[設計](./ball_float_result/design.md)
- [`semantic`](./semantic/api.md): [API](./semantic/api.md)、[チュートリアル](./semantic/tutorial.md)、[設計](./semantic/design.md)
- [`numeric_expr`](./numeric_expr/api.md): [API](./numeric_expr/api.md)、[チュートリアル](./numeric_expr/tutorial.md)、[設計](./numeric_expr/design.md)
- [`gda_expr`](./gda_expr/api.md): [API](./gda_expr/api.md)、[チュートリアル](./gda_expr/tutorial.md)、[設計](./gda_expr/design.md)
- [`internal`](./internal/api.md): [API](./internal/api.md)、[チュートリアル](./internal/tutorial.md)、[設計](./internal/design.md)

英語ツリーを構造上の基準とし、中国語・日本語でも同じ Markdown ファイル集合と文書責務を保ちます。
