# `decimal` 设计说明

`Decimal` 是当前仓库里的十进制优先表示。

## 核心不变式

- 有限值保存为 `coefficient * 10^exponent10`
- `coefficient` 会剥离所有可移除的 10 因子
- 零值使用唯一规范表示

## 解析路径

`Decimal::from_string` 会先调用 `@internal.split_decimal_string`：

- 处理符号
- 去掉小数点
- 合并科学计数法指数

然后再构造规范化的十进制值。

## 与 `bin_float` 的关系

- `bin_float -> decimal`：精确保留当前有限二进制表示
- `decimal -> bin_float`：对非 dyadic 值可能产生近似
