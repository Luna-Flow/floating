# `decimal_gda` 设计

`decimal_gda` 将 General Decimal Arithmetic 的状态与控制语义从面向 IEEE 的
`decimal` API 中隔离出来，同时在内部复用同一套已验证 Decimal 内核。

## 职责与表示

公开 `Decimal` wrapper 不透明。`GdaContext` 包含内部 decimal context、GDA rounding、
sticky status 与 trap 配置。该包拥有 GDA 命名、signal mapping、trap precedence 与
状态传递，不复制 coefficient arithmetic、transcendental algorithm 或
decimal32/64/128 encoding。

拆分可以避免一个 context 同时拥有两种不兼容含义：IEEE 代码观察逐 operation
flags，GDA 代码传递 status 与 traps。文本或 interchange format 是两个公开值类型
之间的显式边界。

## Outcome 状态机

每次运算依次：

1. 执行对应内部 decimal context operation；
2. 把 `DecimalFlags` 映射成本步 raised `GdaFlags`；
3. 把 raised flags 合并进输入 context 的 sticky status；
4. 按固定优先级扫描已启用 traps；
5. 返回 `Completed` 或 `Trapped`，始终保留 value、next context 与 raised flags。

整个流程确定且纯。Context 是不可变数据，“更新”status 的含义是返回一个新 context；
调用方决定继续传递、清除或丢弃。

## Context 不变量

公开 precision 必须为正，且 `e_min <= e_max`。`try_new` 是 checked constructor；
`new` 直接强制正 precision 不变量。Radix 固定为 10。标准 preset 使用 GDA
decimal32/64/128 的 precision、指数与 clamp。

`clear_status` 保留 traps，`reset` 同时清除 status 与 traps。Trap-set 操作返回新值，
不会修改其他计算共享的 context。

## 能力边界

operation inventory 覆盖已实现标量 GDA family：arithmetic、FMA、integer division/
remainder、quantize/rescale、integral conversion、elementary functions、adjacent
values、logical digits、shift/rotate 与 numeric/total comparison。

文件系统、`.decTest` parsing、case filter、sharding、JSON 与进程退出状态属于
`frontend/gda_expr`、`internal/runner_cli`、CLI 与 Python tooling。副作用留在数值包
之外，使 operation 与状态转移能作为普通值测试。

## Conformance 边界

兼容声明由固定合法 scalar row 定义，而不是由 parser 能识别某个 token 定义。
`frontend/gda_expr` 把 `#` placeholder/non-scalar 行分类为 diagnostic，并单独报告
未来未知 operation 或 condition。Strict runner 对 supported-case gap 失败，而不是
静默缩小分母。

IEEE decimal conformance 是使用独立 DPD/BID fixture 的另一 gate。通过 GDA decTest
本身不证明所有 IEEE interchange 属性；通过 IEEE fixture 也不会提供 GDA sticky
status 或 traps。

## 复杂度与扩展

每个 decimal operation 的 wrapper 只增加常量级状态合并和固定 13-signal 优先级
扫描。数值复杂度与分配仍由被委托的 decimal operation 决定。

新增 signal 或 operation 时，应同步更新公开 enum/interface、flag/trap mapping、
precedence policy、operation adapter、`.decTest` frontend support、测试、生成接口与
全部本地化文档。不要为了省略显式边界转换而暴露内部 decimal 值。

