# FLOATING

[![img](https://img.shields.io/badge/Maintainer-KCN--judu-violet)](https://github.com/KCN-judu) [![img](https://img.shields.io/badge/License-Apache%202.0-blue)](https://github.com/Luna-Flow/floating/blob/main/LICENSE) ![img](https://img.shields.io/badge/State-active-success)

## v0.2.0 - arithmetic capability integration 基準

このドキュメントは、現在のブランチにある **`v0.2.0`** の実装基準を説明します。

### パッケージの位置づけ

- **`def`**: `Sign`、`PartialOrder`、狭い `Floating` trait、および arithmetic 境界型の互換 reexport を提供します。
- **`bin_float`**: 仮数、2 進指数、作業精度で表現される任意精度 2 進浮動小数点。
- **`decimal`**: 係数、10 進指数、作業精度で表現される任意精度 10 進浮動小数点。
- **`ball_float`**: 外向き丸めされた上下界で表現される、`bin_float` ベースの interval/ball 値。
- **`internal`**: 正規化、因子除去、丸め、10 進文字列解析の共有補助ロジック。
- **`consistency`**: 正規化、算術、変換、パッケージ間意味論を検証するリポジトリテスト。

### 現在の基準の特徴

- `Luna-Flow/arithmetic` の checked capability boundary に依存します。
- `bin_float` と `decimal` は checked scalar trait を実装します。
- `ball_float` は enclosure relation と checked division / checked integer power を実装します。
- `decimal` と `bin_float` の相互変換を提供します。
- 上位の超越関数レイヤー、微積分、行列、複素数、特殊関数はこのパスでは再導入しません。
- 正しさ優先の whitebox テストを含み、checked error path と enclosure 境界を検証します。

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
