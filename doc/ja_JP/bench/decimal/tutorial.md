# `bench/decimal` チュートリアル

## クイックスタート

```sh
just bench decimal
```

## 結果の読み方

`MAREMARK_JSONL` は versioned raw artifact、`MAREMARK_HOTSPOT` はペア化したレイヤー overhead、`MAREMARK_TUNE` / `MAREMARK_CROSSOVER` は確認済み tuning decision です。通常テストは plan だけを compile して timing を skip します。

## 次に読むもの

生成インターフェースは [API](./api.md)、責務と不変条件は [設計](./design.md) を参照してください。

