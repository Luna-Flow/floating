# `gda_expr` 設計

## パイプライン

parser は directive 状態と case 行を `numeric_expr` ベースの `GdaDocument` にします。executor は GDA context を `DecimalContext` に変換し、正規化操作名を dispatch して結果を `RunSummary` に分類します。

## 実行境界

ライブラリは corpus download や process scheduling を所有しません。Python tooling が pinned corpus、段階割当、決定的 native shards、JSON、集約を担当し、`gda_expr_cli` は process 境界だけを提供します。

## 未対応 case

未対応操作、解析診断、legacy condition、実行可能な数値不一致は別々に記録します。strict mode は未対応・legacy を gate failure にできますが、誤った数値答としては報告しません。
