# `gda_expr` 设计

## 流水线

解析器把 directive 状态与 case 行转换成基于 `numeric_expr` 的 `GdaDocument`。执行器把 GDA context 转成 `DecimalContext`，按规范化操作名分派，并把结果分类到 `RunSummary`。

## 执行边界

库包不负责下载语料或调度进程。Python 工具负责固定语料、阶段分配、确定性 native shards、JSON 产物和聚合；`gda_expr_cli` 只提供进程边界。

## 未支持 case

未支持操作、解析诊断、legacy condition 与可执行结果错误分别记录。strict 模式可以让前两类导致门禁失败，但不会把它们伪装成错误数值答案。
