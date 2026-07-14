# 验证

仓库将快速开发检查与有限、可复现的 conformance 声明分开。通过一个语料只证明
所声明的 format、operation、rounding mode、target 和固定 fixture revision。

## 验证层级

| 层 | 命令 | 用途 |
| --- | --- | --- |
| 文档 | `just docs` | locale/file/heading/link 检查与可执行文档示例 |
| 格式 | `just fmt` | MoonBit formatter |
| PR | `just pr [jobs]` | 生成接口、全 target check、native test、Python test、smoke corpus |
| IEEE decimal | `just gate decimal [jobs]` | 支持 target 上的 decimal32/64/128 DPD/BID fixture |
| GDA decimal | `just gate decimal_gda [jobs]` | 固定 `official` 与 `official0` `.decTest` 合法标量行 |
| Binary | `just gate binary [jobs]` | 固定 TestFloat level-1 matrix 与 MPFR 数据 |
| Interval | `just gate interval [jobs]` | 固定 ITF1788 strict supported phases |
| 完整 | `just ci [jobs]` | 全部生成接口、target、单元与 conformance gate |

先运行与改动最接近的窄检查，再在发布前逐步扩大范围。

## 统一 Conformance Runner

所有 suite 使用同一个 dispatcher：

```sh
just conformance <build|run|smoke|plan|fetch> \
  <decimal|decimal_gda|binary|interval> [options]
```

`decimal` 指独立 IEEE decimal corpus，`decimal_gda` 指 GDA `.decTest`；`binary`
组合 TestFloat 与 MPFR，`interval` 使用 ITL。

`smoke` 不下载外部语料，直接运行已提交 fixture；`plan` 显示确定性任务；`fetch`
验证固定 provenance 后把忽略数据装入 `.tmp/`；`run` 执行 suite。各 backend 的
filter、phase、target、strict mode、sharding 与 JSON 输出见 `testdata/*/README.md`。

## 已发布声明

- **GDA：** 144 文件 `official` corpus 的 64,986 条合法 executable scalar row
  全部通过，`official0` 的 16,124 条合法行全部通过；141 条 `#` placeholder/
  non-scalar 非法行是 diagnostic exclusion，不是未支持的合法行为。
- **Binary：** 7,461,360 条 TestFloat vector 覆盖 binary16/32/64/128 的 add、
  subtract、multiply、divide、sqrt，五种 rounding direction 与两种 tininess；
  固定 MPFR sqrt 数据另有 1,055 行。
- **IEEE decimal：** 已提交 decimal32/64/128 DPD/BID fixture 覆盖 encoding、
  special value、flags、核心算术与全部 1,024 个 DPD declet；运行于 native、Wasm、
  Wasm-GC、JavaScript，LLVM 不属于该 gate。
- **Interval：** strict ITF1788 phases 覆盖声明的 set、relation、observation、
  arithmetic、cancellation、elementary、power、trigonometric、FMA、integer-power
  与 extrema；reverse operations 仍未支持。

这些都是有限声明，不代表 IEEE 754/1788 的所有 operation、任意资源规模、所有
NaN payload policy 或未来未固定的 corpus revision。

## 可复现性

外部 artifact 的 revision 与 SHA-256 固定在 corpus manifest 中。构建使用按 backend
命名的输出和隔离 target 目录，并行 job 不会互相覆盖。Shard 按确定性 case index
选择，合并 summary 保留精确 total 与 failed ID。

MoonBit frontend 解析并执行数值行；Python 负责编排下载、task planning、subprocess、
target selection 和 aggregation。可选 oracle 缺失时不得静默换成较弱实现，必须
明确报告缺失条件。

性能证据与语义 conformance 分离。Benchmark manifest 固定 baseline source、依赖、
toolchain、target、schedule、sample count 与 dispersion limit。性能阈值不定义正确性。

## 失败排查

1. 用最小 case、ID filter、phase 或 shard 复现对应 backend；
2. 区分 parse diagnostic、unsupported、legacy、executable mismatch 与基础设施失败；
3. 记录 expected/actual value、flags、context、target、corpus revision 与命令；
4. 运行对应 white-box 包测试，定位 parser、arithmetic、interchange 或 aggregation；
5. 修复后依次运行 focused case、smoke fixture、backend gate，最后运行 `just pr` 或
   `just ci`。

不得通过降低 strict support、丢弃 flags 或改写分母让失败 gate 变绿。

## 发布 Gate

发布前：

1. 对齐 `moon.mod`、根 README、三语索引、文档标准与 changelog；
2. 运行 `just docs` 并检查生成接口差异；
3. 迭代期间运行 `just pr`；
4. 对 release candidate 运行 `just ci`；
5. 通过仓库 GitHub Actions workflow 发布。

Luna-Flow 不使用本地 `moon publish` 作为发布路径；组织凭据由 workflow 提供。
