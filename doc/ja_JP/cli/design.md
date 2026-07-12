# `cli` 設計

実行可能 package は `--backend` だけを解析し、残りを `gda`/`testfloat`/`mpfr`/`itl` に転送します。corpus parser、数値アルゴリズム、shard、JSON schema は所有しません。
