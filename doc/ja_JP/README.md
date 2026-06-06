# FLOATING

[![img](https://img.shields.io/badge/Maintainer-KCN--judu-violet)](https://github.com/KCN-judu) [![img](https://img.shields.io/badge/License-MIT-blue)](https://github.com/Luna-Flow/floating/blob/main/LICENSE) ![img](https://img.shields.io/badge/State-active-success)

## v0.1.0 - 初期パッケージ基準

このドキュメントは、現在のブランチにある **`v0.1.0`** の実装基準を説明します。

### パッケージの位置づけ

- **`def`**: 共有の浮動小数点分類、丸めモード、コア `Floating` trait。
- **`bin_float`**: 仮数、2 進指数、作業精度で表現される任意精度 2 進浮動小数点。
- **`decimal`**: 係数、10 進指数、作業精度で表現される任意精度 10 進浮動小数点。
- **`ball_float`**: `center +/- radius` として表現される、`bin_float` ベースの ball arithmetic 値。
- **`internal`**: 正規化、因子除去、丸め、10 進文字列解析の共有補助ロジック。
- **`consistency`**: 正規化、算術、変換、パッケージ間意味論を検証するリポジトリテスト。

### 現在の基準の特徴

- 最小限で安定した `Floating` trait 基盤を提供します。
- `bin_float` と `decimal` は構築、正規化、精度変更、四則、特殊値に加えて、共有 arithmetic trait による定数と超越関数を備えます。
- `ball_float` は正確な埋め込み、包含、重なり判定、分離判定、区間比較、`pow`、ball/interval 向け超越関数を備えます。
- `decimal` と `bin_float` の相互変換を提供します。
- `atan2` など分岐切替をまたぐ箇所では、必要に応じてより広いが安全な enclosure を返します。
- 正しさ優先の whitebox テストを含み、変換、超越関数の smoke case、区間境界を検証します。

### クイックスタート

```moonbit
let x = @bin_float.BinFloat::make(3N, -1, 32)
let y = @bin_float.BinFloat::make(5N, -1, 32)
let sum = x + y

let dec = @decimal.Decimal::from_string("12.34", precision=32).unwrap()
let as_bin = dec.to_bin_float(precision=32)
let ball = @ball_float.BallFloat::exact(as_bin)

inspect(sum.to_string(), content="1p2")
inspect(ball.contains(as_bin).to_string(), content="true")
```

### ドキュメント

多言語 README:

- 🇺🇸 [README.md](../../README.md)
- 🇨🇳 [README.md](../zh_CN/README.md)
- 🇯🇵 [README.md](./README.md)

パッケージ文書:

- [ドキュメント標準](./doc_standard.md)
- [正しさ監査台帳](./correctness_audit.md)
- [@def API](./def/api.md)
- [@bin_float API](./bin_float/api.md)
- [@decimal API](./decimal/api.md)
- [@ball_float API](./ball_float/api.md)

## 開発

よく使うコマンド:

```bash
moon fmt
moon check
moon test
moon test --enable-coverage
```

## リリースチェックリスト

1. `moon.mod` のバージョンを更新する。
2. `README.md` と多言語ドキュメントを現在の実装に合わせて更新する。
3. `moon check` と `moon test` を実行する。
4. `publish-package` workflow を起動する。

コントリビューション案内は [CONTRIBUTING.md](../../CONTRIBUTING.md) を参照してください。
