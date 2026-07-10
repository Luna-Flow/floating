# 正しさ監査

この監査は **`0.4.0`** の公開面を現在の実装・検証境界へ対応付けます。
生成 interface を API 一覧、source と test を挙動の根拠として扱います。

## 基本数値パッケージ

| 領域 | 契約 | 根拠 | 状態 |
| --- | --- | --- | --- |
| `def` | `Floating` は分類、符号、精度、精度変更、正規化だけを含み、算術 capability は分離する。 | 生成 interface、consistency tests | 検証済み |
| `bin_float` | 有限値は正規化 dyadic 表現を使い、精度変更は明示的に丸め、checked 演算は `ArithmeticError` を返す。 | `src/bin_float`、consistency tests | 丸め境界付きで検証済み |
| `decimal` 表現 | 符号、magnitude、exponent/quantum、precision、signed zero、qNaN/sNaN payload を保持する。 | `src/decimal`、white-box tests | 検証済み |
| `decimal` context | `*_ctx` は precision、rounding、指数、clamp、extended 設定を適用し、累積 `DecimalFlags` を返す。 | context source、conformance cases | operation ごとの corpus 境界付きで検証済み |
| `decimal` interchange | `DecimalInterchange` が decimal32/64/128 と canonicalization/status を公開する。 | interchange source、interchange phase | 適合性境界付きで検証済み |
| `ball_float` | bound は外向き丸めされ、算術は実数結果を包絡し、0 を含む除算は whole-real enclosure を返す。 | `src/ball_float`、consistency tests | 包絡境界付きで検証済み |

## 合成・意味パッケージ

| 領域 | 契約 | 根拠 | 状態 |
| --- | --- | --- | --- |
| `*_result` | 既存エラーは短絡し、値を返す checked 演算は `Self` 内で閉じる。 | 生成 interface と実装 | 検証済み |
| `semantic` | 具体値と算術失敗を表現非依存 variant へ投影する。 | `src/semantic`、consistency tests | 検証済み |
| `numeric_expr` | 式表現は非公開で、callback が literal/operation 意味論を所有する。 | package source/tests | 検証済み |
| `gda_expr` | diagnostic、legacy、unsupported、実行可能な不一致を分離する。 | parser/execution tests、smoke fixture | 検証済み |

## 検証ゲート

- `just smoke`: 追跡済み end-to-end fixture。
- `just ci`: 限定 white-box gate。
- `just pr`: all-target check、interface 更新、native interpreter build、official corpus 実行。

official corpus は外部 pinned input です。unsupported と diagnostic は summary
に残り、必要なら strict mode で失敗にします。詳細は[適合性手順](../../testdata/decimal/README.md)を参照してください。
