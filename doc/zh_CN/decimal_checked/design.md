# `decimal_checked` 设计

`DecimalResult` 为 Decimal 提供从左到右短路的 checked 流水线；parse 和 checked 操作可进入错误分支，后续操作不再执行。`bind` 可返回新错误，`map` 只能变换成功值。

wrapper 不携带 `DecimalContext`、不累计 `DecimalFlags`，因此不是 GDA status 流。涉及 cohort、clamp、指数界限或 flags 时必须使用 `decimal` 的 `*_ctx`。

组合本身除底层 Decimal 运算外是 `O(1)`。不携带 context/flags 是为了避免一个
类型同时拥有“首错短路”和“状态累计”两套互相冲突的数据流。
