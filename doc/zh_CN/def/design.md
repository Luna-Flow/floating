# `def` 设计

`def` 只提供共享数值词汇：重导出 arithmetic 的 context/error/rounding/classification 与 `BigInt`，定义 `Sign`、`PartialOrder` 和小型开放 `Floating` trait。trait 只要求 classify、sign、precision、with_precision、normalized。

算术、排序、解析、flags 和区间关系不放入 trait，因为各表示的定律不同。实现 `Floating` 不代表 field、全序、IEEE 格式或 checked 错误行为；调用方必须声明所需的更窄能力。

## 设计职责

该包只保存跨表示都成立的观察和能力命名；具体数值算法与副作用边界由实现包负责。

## 能力选择

泛型调用应按实际需要组合 arithmetic trait，而不是从 `Floating` 推断舍入、错误或区间语义。
