# ドキュメント標準

リポジトリ文書は**現在のブランチに存在する実装**だけを説明します。
`2026-07-14` の release 基準は **`0.7.0`** です。

## 文書種別と責務

1. **API リファレンス（`api.md`）**: 公開型、関数、メソッド、エラー、観測可能な意味論を規定します。
2. **チュートリアル（`tutorial.md`）**: 小さく実行可能な利用手順を示します。
3. **設計文書（`design.md`）**: 表現、不変条件、責務境界、実装上の選択を説明します。
4. **Conformance（`conformance.md`）**: numeric core の固定された有限 evidence と対象外を定義します。
5. **Performance（`performance.md`）**: 再現可能な measurement と target-specific dispatch evidence を記録し、API promise にはしません。
6. **README**: 現在の基準、パッケージ入口、読者向け経路だけを扱います。
7. **CHANGELOG**: 過去のリリース情報と移行履歴を扱います。

各 locale root には package 横断の四つの guide も置きます。`getting_started.md`
は package 選択、`numeric_semantics.md` は共通語彙、`architecture.md` は責務境界、
`verification.md` は conformance 範囲と再現可能な command を説明します。

## 構造とローカライズ

- 各 `moon.pkg` のパスを文書ツリーに反映します。ファイル名はモジュールを作らず、
  パッケージ境界は `moon.pkg` が決めます。
- `en_US`、`zh_CN`、`ja_JP` で Markdown ファイル集合と主要節の責務を揃えます。
- locale-only research page は残しません。耐久的な結論を三言語の design、conformance、performance に昇格し、置き換えられた履歴は `CHANGELOG.md` に移します。
- 英語を構造上の基準とし、各言語で自然に記述します。識別子、パッケージ名、
  パス、コマンド、バージョン文字列は翻訳しません。
- README は現在の基準に限定し、古いリリース説明は `CHANGELOG.md` に移します。
- 未実装 API を現行機能として記述しません。`pkg.generated.mbti` を公開面の一覧、
  ソースとテストを挙動の根拠として扱います。
- 全 package に `api.md`、`tutorial.md`、`design.md` を置きます。application API を持たない package も生成 interface、maintainer workflow、stability boundary を公開します。

## 数値文書の規則

- `precision`、`rounding`、`classify`、`sign`、`normalized`、`quantum`、
  `context`、`flags` の用語を統一します。
- 保存表現、厳密値、丸め結果、状態フラグ、checked エラー、区間包絡を区別します。
- 解析が quantum を保持する場合と、正規化が数学的値を変えず cohort だけを変える場合を明記します。
- NaN を含むスカラーや区間値に通常の全順序があるように記述しません。
- `*_ctx` API では値と累積 flags の両方を説明します。
- `*_checked` API では domain-specific state transition、すなわち result error、
  IEEE flags の蓄積、または GDA trap の short-circuit/recovery を説明します。
- `decimal` と `decimal_gda` は別 contract として説明します。IEEE operation は
  per-operation flags を返し、GDA operation は `GdaOutcome` で sticky status と
  trap を thread します。
- 例は小さく検証可能にします。MoonBit import では `Luna-Flow/luna-generic` を
  `@lf_alg`、`Luna-Flow/arithmetic` を `@lf_arith` として扱います。

## レビューチェック

- `moon info` 後の `pkg.generated.mbti` とパッケージ文書を照合します。
- リンクと三言語のファイル集合を確認します。
- 変更範囲に応じて `moon fmt`、`moon check --target all`、関連テスト、文書例、または `just pr` を実行します。
- リリース時は基準日、バージョン、changelog を同時に更新します。
