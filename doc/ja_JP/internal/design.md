# `internal` 設計

2/5/10 の冪、十進文字列分割、因子除去、桁数、正商/シフト丸め、`ExactRat`、Result lift を共有する純粋な補助層です。context、flags、公開表現、IO を所有しません。

モジュール内部の実装境界であり、安定したアプリ API ではありません。

## Pure function と計算量

helper は外部 state を読まず、power cache と rounding は局所 allocation だけを使います。桁数・因子除去・文字列分割は入力長に対して線形で、算術コストは呼び出し側の `BigInt` が決めます。

## Compatibility 境界

これらの名前は現実装と white-box test のためで、安定契約ではありません。公開利用は concrete numeric package 経由にします。
