# `semantic` 设计

该包把具体值投影到精确 `ExactRational`、有符号无穷、NaN、闭区间和语义错误。二进制按 2 的幂、十进制按 10 的幂转换，区间端点独立投影；checked 错误映射为 `SemanticError`。

投影有意丢弃 precision、quantum/cohort、负零、NaN payload/signaling、装饰和 context flags。它是比较/序列化边界，不负责舍入、解析、互换或区间收紧。

## 投影复杂度

标量投影按系数位数执行有理数归约；区间只独立处理两个端点。投影是纯函数，不分配 context、不改变输入，也不替代 concrete arithmetic。

## 稳定边界

该包是跨表示诊断与测试的 provisional boundary。精度、cohort、payload 和 flags 需要保留时必须继续使用原始数值包。
