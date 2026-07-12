# `frontend/testfloat_expr` 教程

先运行仓库内向量：

```sh
just conformance smoke binary
```

库调用方构造 `TestFloatSpec`、解析一个向量源、可选设置 `RunOptions` shard，再执行 document。function 元数据必须显式提供，不能从路径猜测。
