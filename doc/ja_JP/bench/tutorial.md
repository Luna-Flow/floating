# `bench` チュートリアル

## クイックスタート

```sh
just bench all
just bench auto-tune
```

## 結果の読み方

`MAREMARK_JSONL` は versioned raw artifact、`MAREMARK_HOTSPOT` はペア化したレイヤー overhead、`MAREMARK_TUNE` / `MAREMARK_CROSSOVER` は確認済み tuning decision です。通常テストは plan だけを compile して timing を skip します。

- [`bench/bin_float`](./bin_float/tutorial.md)
- [`bench/decimal`](./decimal/tutorial.md)
- [`bench/decimal_gda`](./decimal_gda/tutorial.md)
- [`bench/ball_float`](./ball_float/tutorial.md)

## 次に読むもの

生成インターフェースは [API](./api.md)、責務と不変条件は [設計](./design.md) を参照してください。

