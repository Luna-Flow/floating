# `semantic` 设计

## 目的

语义层去除具体类型的存储与舍入细节，使精确值、无穷、NaN、区间和错误可以在不指定“主表示”的前提下比较。

## 限制

它是投影层，不是算术引擎，也不保留 Decimal context、precision、quantum、payload、flags 或区间 decoration。只有在不再需要这些信息时才投影。
