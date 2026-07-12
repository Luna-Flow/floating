# `cli` 设计

可执行包只解析 `--backend`，将其余参数原样转发到 `gda`、`testfloat`、`mpfr` 或 `itl` 适配器，并映射帮助/参数错误的退出码。它不解析语料、不实现算法、不做 shard 或 JSON schema。
