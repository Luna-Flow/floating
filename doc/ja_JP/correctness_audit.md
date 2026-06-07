# 正しさ監査台帳

この台帳は現在の `0.2.0` 実装を明示的な意味論契約に対して API ごとに対応付けます。

状態ラベル:

- `Verified`
- `Verified with approximation boundary`
- `Known limitation`

## `@def`

| API | 契約 | 実装アンカー | 検証証拠 | 状態 |
| --- | --- | --- | --- | --- |
| `Sign` / `FpClass` / `RoundingMode` | 各数値パッケージで共有意味論列挙として一貫して使われる。 | `src/def/types.mbt` | `def predicates classify finite nan and enclosing zero consistently`; パッケージ単位のコード確認。 | Verified |
| `Floating` | 共有能力面は分類、符号、精度、精度再調整、正規化のみに限定される。 | `src/def/types.mbt` | パッケージ横断のコンパイル利用と helper predicate テスト。 | Verified |
| `is_finite` / `is_nan` / `is_infinite` / `is_zero` | class/sign に基づく述語であり、`is_zero` は NaN を拒否し、零をまたぐ包絡を受け入れる。 | `src/def/types.mbt` | `def predicates classify finite nan and enclosing zero consistently`; 既存 NaN 回帰テスト。 | Verified |

## `@internal`

| API | 契約 | 実装アンカー | 検証証拠 | 状態 |
| --- | --- | --- | --- | --- |
| `bigint_zero` / `bigint_one` / `abs_bigint` / `sign_of_bigint` | 標準的な整数補助関数。 | `src/internal/core.mbt` | 全数値パッケージから推移的に利用；符号挙動は predicate と正規化テストで間接確認。 | Verified |
| `pow2` / `pow5` / `pow10` / `digits10` | 正確な冪関数と 10 進桁数計算。 | `src/internal/core.mbt` | `bin_float` / `decimal` の構築・変換テスト；解析・正規化テスト。 | Verified |
| `remove_factor2` / `remove_factor10` | 取り除ける基数因子を剥がしつつ表現値を保存する。 | `src/internal/core.mbt` | `bin_float normalizes powers of two`; `decimal make and display normalize trailing zeros`。 | Verified |
| `round_positive_div` / `round_shift` / `compare_abs` | 非負 magnitude に対する方向付き・tie-aware 丸め；`compare_abs` は絶対値比較のみ。 | `src/internal/core.mbt` | `internal rounding helpers honor tie and directed modes`。 | Verified |
| `split_decimal_string` | 通常表記/科学表記の 10 進文字列を受理し、不正形式を拒否する。 | `src/internal/core.mbt` | `internal decimal parser accepts scientific notation and rejects malformed strings`; `decimal parses and normalizes`。 | Verified |

## `@bin_float`

| API | 契約 | 実装アンカー | 検証証拠 | 状態 |
| --- | --- | --- | --- | --- |
| `make` / `zero` / `one` / `from_int` / `from_bigint` | 有限値構築は正規化された標準 2 進形式へ落ちる。 | `src/bin_float/bin_float.mbt` | `bin_float normalizes powers of two`; `bin_float arithmetic stays exact on small dyadics`。 | Verified |
| `inf` / `nan` / `classify` / `sign` / `precision` | 特殊値は分類と格納精度の意味論を保つ。 | `src/bin_float/bin_float.mbt` | predicate テスト、compare テスト、特殊値算術のコード確認。 | Verified |
| `significand` / `exponent2` / `normalized` / `is_zero` | 正規化された有限表現と零判定を公開する。 | `src/bin_float/bin_float.mbt` | 正規化テスト、predicate テスト、コード監査。 | Verified |
| `with_precision` / `ulp` | 精度再調整は要求丸めに従い、`ulp` は表現局所の間隔を返す。 | `src/bin_float/bin_float.mbt` | `bin_float with_precision rounds and ulp tracks spacing`。 | Verified |
| `add` / `sub` / `mul` / `div` | 表現可能な小さな dyadic では正確で、特殊値は現在の実装規則で伝播する。 | `src/bin_float/bin_float.mbt` | `bin_float arithmetic stays exact on small dyadics`; 既存の変換・特殊値テスト。 | Verified with approximation boundary |
| `compare` | 順序付き値にのみ全順序を与え、NaN では拒否する。 | `src/bin_float/bin_float.mbt` | `bin_float compare orders finite and infinities`; NaN 分岐のコード確認。 | Verified |

## `@decimal`

| API | 契約 | 実装アンカー | 検証証拠 | 状態 |
| --- | --- | --- | --- | --- |
| `make` / `zero` / `one` / `from_int` / `from_bigint` / `from_string` | 10 進構築は末尾ゼロを正規化し、現在対応する文字列表現を受理する。 | `src/decimal/decimal.mbt` | `decimal parses and normalizes`; `decimal make and display normalize trailing zeros`; parser テスト。 | Verified |
| `inf` / `nan` / `classify` / `sign` / `precision` | 特殊値と符号の意味論はパッケージ契約に従う。 | `src/decimal/decimal.mbt` | predicate テストと特殊値算術のコード確認。 | Verified |
| `coefficient` / `exponent10` / `is_zero` / `normalized` / `with_precision` | 標準 10 進表現と精度再調整後の有限値を公開する。 | `src/decimal/decimal.mbt` | 正規化/表示テストとコード監査。 | Verified |
| `neg` / `abs` / `add` / `sub` / `mul` / `div` | 表現可能なら 10 進で正確、それ以外はパッケージ規則で丸める。 | `src/decimal/decimal.mbt` | `decimal arithmetic and display`; 変換起点の回帰確認。 | Verified with approximation boundary |
| `to_bin_float` / `from_bin_float` | 2 進変換は dyadic 互換方向では正確で、非 dyadic な 10 進→2 進では近似を含む。 | `src/decimal/decimal.mbt` | `decimal binary conversion preserves dyadics exactly`; `decimal to bin conversion handles non-dyadic values`; `bin to decimal conversion is exact for finite values`。 | Verified with approximation boundary |

## `@ball_float`

| API | 契約 | 実装アンカー | 検証証拠 | 状態 |
| --- | --- | --- | --- | --- |
| `new` | 中心量子化後も元の包絡を保持する。 | `src/ball_float/ball_float.mbt` | `ball_float new preserves an input endpoint after center rounding`。 | Verified |
| `exact` | 有限 `BinFloat` を ball へ埋め込み、精度低下後も元値を含み続ける。 | `src/ball_float/ball_float.mbt` | `ball_float exact widens when lowering precision`。 | Verified |
| `from_decimal` | 有限 10 進値から 2 進包絡を構築する。 | `src/ball_float/ball_float.mbt` | 既存の `ball_float from_decimal keeps low precision enclosure`。 | Verified with approximation boundary |
| `center` / `radius` / `precision` / `classify` / `sign` / `normalized` / `with_precision` | 格納包絡、有限分類、包絡由来の符号、包含関係を保つ正規化/精度再調整を提供する。 | `src/ball_float/ball_float.mbt` | `def predicates classify finite nan and enclosing zero consistently`; `ball_float sign and overlap relations remain enclosure based`; exact-widen 回帰。 | Verified |
| `contains` / `overlaps` / `separated_from` / `definitely_lt` / `definitely_gt` / `maybe_overlap` | 関係 API はスカラー全順序ではなく区間意味論に基づく。 | `src/ball_float/ball_float.mbt` | `ball_float overlap detects separated balls`; `ball_float sign and overlap relations remain enclosure based`; exact containment テスト。 | Verified |
| `add` / `sub` / `mul` / `div` | 算術は真の結果を包む ball を返し、出力丸め変位も半径へ加える。除算は分母 ball が零を含む場合を拒否する。 | `src/ball_float/ball_float.mbt` | `ball_float multiplication keeps exact scalar result inside zero-radius inputs`; `ball_float division keeps exact scalar result inside zero-radius inputs`; 零分母分岐のコード確認。 | Verified with approximation boundary |
