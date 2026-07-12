# `frontend/mpfr_expr` 教程

通过共享工作流运行仓库内 fixture：

```sh
just conformance smoke binary
```

直接调用时应按语料语法选择 parser，执行 document 并检查 `summary.success()`；不要把 parser 诊断改写成不支持的数值运算。
