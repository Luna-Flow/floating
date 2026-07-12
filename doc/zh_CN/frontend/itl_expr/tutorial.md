# `frontend/itl_expr` 教程

先运行端到端 smoke：

```sh
just conformance smoke interval
```

库调用方先 parse，再逐 case 执行并 summarize。Unsupported 不应与 executable failure 混为一谈；需要严格模式时由 CLI/tooling 提升为失败。
