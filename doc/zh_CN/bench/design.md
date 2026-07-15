# `bench` 设计

## 职责

构建不可变 Maremark 计划并归约版本化 observation，避免数值包依赖 benchmark 代码。

## 数据流

数据类型 fixture 生成输入，Maremark 校验参考等价性，平衡计时块产生 observation，纯函数归约得到热点与调优 winner。

## 不变量

setup 必须位于计时 payload 外；成对比较必须匹配 dataset 与 block；auto-tune 只能比较语义等价候选。

## 副作用

公共层除显式 async runner 边界外保持纯函数；JSONL 输出与文件写入留在测试和 `tools/benchmark.py`。

