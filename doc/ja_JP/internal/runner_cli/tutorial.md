# `internal/runner_cli` チュートリアル

## クイックスタート

native conformance command adapter が共有する effect boundary です。

## ワークフロー

dependency と target handling を CI と一致させるため、repository wrapper 経由で実行します。

```sh
sh tools/run_moon_clean_exec.sh test -p Luna-Flow/floating/internal/runner_cli --target native
```

failure は repository maintenance signal として扱います。この package は standalone end-user product ではありません。

## 失敗と範囲

filesystem read と rendering をここに閉じ込め、conformance model と numeric frontend を pure に保ちます。 この package を、支援対象 numeric package の代替として import しないでください。

## 次に読む文書

完全な生成 interface は [API](./api.md)、責務と trade-off は[設計](./design.md)を参照してください。
