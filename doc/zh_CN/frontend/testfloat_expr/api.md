# `frontend/testfloat_expr` API

`TestFloatSpec::parse(function, rounding, tininess?)` 校验格式、operation、rounding 和 tininess；`parse_testfloat` 返回 typed document；`execute_document` 执行稳定 shard 并返回逐行结果与计数。

操作限于 binary16/32/64/128 上的 Add/Subtract/Multiply/Divide/SquareRoot。summary success 只代表所选行的值和 flags 匹配。
