# `ball_float_checked` 设计

`BallFloatResult` 封闭 checked 区间构造与算术。非法端点、非有限 exact 来源和 checked 运算失败进入错误分支并短路。

它不存 decoration 或 `BallFlags`，也不新增区间算法；bare set、decorated operation 与 context status 均由 `ball_float` 负责。Entire 等保守包络是合法成功值，不是 wrapper error。

wrapper 附加成本是 `O(1)`。Entire 仍为成功，是因为 tightness 降低不等于包含
失败；把安全包络当错误会破坏区间域本身的语义。
