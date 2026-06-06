# 正确性审计台账

这份台账把当前 `0.1.0` 实现与显式语义契约逐项对齐。

状态标签：

- `Verified`
- `Verified with approximation boundary`
- `Known limitation`

## `@def`

| API | 契约 | 实现锚点 | 校验证据 | 状态 |
| --- | --- | --- | --- | --- |
| `Sign` / `FpClass` / `RoundingMode` | 在各数值包中一致承担共享语义枚举角色。 | `src/def/types.mbt` | `def predicates classify finite nan and enclosing zero consistently`；包级代码审阅。 | Verified |
| `Floating` | 共享能力面只覆盖分类、符号、精度、重调精度与规范化。 | `src/def/types.mbt` | 跨包编译使用与 helper predicate 测试。 | Verified |
| `is_finite` / `is_nan` / `is_infinite` / `is_zero` | 基于 class/sign 判断；`is_zero` 拒绝 NaN，并接受跨零包络。 | `src/def/types.mbt` | `def predicates classify finite nan and enclosing zero consistently`；既有 NaN 回归测试。 | Verified |

## `@internal`

| API | 契约 | 实现锚点 | 校验证据 | 状态 |
| --- | --- | --- | --- | --- |
| `bigint_zero` / `bigint_one` / `abs_bigint` / `sign_of_bigint` | 规范的整数辅助函数。 | `src/internal/core.mbt` | 被全部数值包传递使用；符号行为由 predicate 与规范化测试间接覆盖。 | Verified |
| `pow2` / `pow5` / `pow10` / `digits10` | 精确幂函数与十进制位数计算。 | `src/internal/core.mbt` | `bin_float` / `decimal` 构造与转换测试；解析与规范化测试。 | Verified |
| `remove_factor2` / `remove_factor10` | 剥离可移除的基数因子且保持表示值不变。 | `src/internal/core.mbt` | `bin_float normalizes powers of two`；`decimal make and display normalize trailing zeros`。 | Verified |
| `round_positive_div` / `round_shift` / `compare_abs` | 对非负量级执行定向与 tie-aware 舍入；`compare_abs` 只比较绝对值。 | `src/internal/core.mbt` | `internal rounding helpers honor tie and directed modes`。 | Verified |
| `split_decimal_string` | 接受普通/科学计数十进制字符串并拒绝坏格式。 | `src/internal/core.mbt` | `internal decimal parser accepts scientific notation and rejects malformed strings`；`decimal parses and normalizes`。 | Verified |

## `@bin_float`

| API | 契约 | 实现锚点 | 校验证据 | 状态 |
| --- | --- | --- | --- | --- |
| `make` / `zero` / `one` / `from_int` / `from_bigint` | 有限值构造会规范化到标准二进制形式。 | `src/bin_float/bin_float.mbt` | `bin_float normalizes powers of two`；`bin_float arithmetic stays exact on small dyadics`。 | Verified |
| `inf` / `nan` / `classify` / `sign` / `precision` | 特殊值保持分类与存储精度语义。 | `src/bin_float/bin_float.mbt` | predicate 测试、compare 测试、特殊值算术代码审阅。 | Verified |
| `significand` / `exponent2` / `normalized` / `is_zero` | 暴露规范化有限表示与零判定。 | `src/bin_float/bin_float.mbt` | 规范化测试、predicate 测试、代码审计。 | Verified |
| `with_precision` / `ulp` | 精度重调遵守请求的舍入模式；`ulp` 返回表示局部的间距值。 | `src/bin_float/bin_float.mbt` | `bin_float with_precision rounds and ulp tracks spacing`。 | Verified |
| `add` / `sub` / `mul` / `div` | 在可表示的小 dyadic 上保持精确；特殊值按当前实现传播。 | `src/bin_float/bin_float.mbt` | `bin_float arithmetic stays exact on small dyadics`；既有转换与特殊值测试。 | Verified with approximation boundary |
| `compare` | 仅对有序值提供全序；遇到 NaN 拒绝。 | `src/bin_float/bin_float.mbt` | `bin_float compare orders finite and infinities`；NaN 分支代码审阅。 | Verified |

## `@decimal`

| API | 契约 | 实现锚点 | 校验证据 | 状态 |
| --- | --- | --- | --- | --- |
| `make` / `zero` / `one` / `from_int` / `from_bigint` / `from_string` | 十进制构造会去除尾随零，并接受当前支持的文本格式。 | `src/decimal/decimal.mbt` | `decimal parses and normalizes`；`decimal make and display normalize trailing zeros`；parser 测试。 | Verified |
| `inf` / `nan` / `classify` / `sign` / `precision` | 特殊值与符号语义符合包契约。 | `src/decimal/decimal.mbt` | predicate 测试与特殊值算术代码审阅。 | Verified |
| `coefficient` / `exponent10` / `is_zero` / `normalized` / `with_precision` | 暴露标准十进制表示与重调精度后的有限值。 | `src/decimal/decimal.mbt` | 规范化/显示测试与代码审计。 | Verified |
| `neg` / `abs` / `add` / `sub` / `mul` / `div` | 可表示时保持十进制精确；否则按包规则舍入。 | `src/decimal/decimal.mbt` | `decimal arithmetic and display`；转换驱动回归检查。 | Verified with approximation boundary |
| `to_bin_float` / `from_bin_float` | 二进制转换在 dyadic 兼容方向上精确，在非 dyadic 的十进制转二进制方向上近似。 | `src/decimal/decimal.mbt` | `decimal binary conversion preserves dyadics exactly`；`decimal to bin conversion handles non-dyadic values`；`bin to decimal conversion is exact for finite values`。 | Verified with approximation boundary |

## `@ball_float`

| API | 契约 | 实现锚点 | 校验证据 | 状态 |
| --- | --- | --- | --- | --- |
| `new` | 在中心量化后仍保持原始包络被包含。 | `src/ball_float/ball_float.mbt` | `ball_float new preserves an input endpoint after center rounding`。 | Verified |
| `exact` | 把有限 `BinFloat` 嵌入成球；即使降精度也仍包含源值。 | `src/ball_float/ball_float.mbt` | `ball_float exact widens when lowering precision`。 | Verified |
| `from_decimal` | 基于有限十进制源值构造二进制包络。 | `src/ball_float/ball_float.mbt` | 既有 `ball_float from_decimal keeps low precision enclosure`。 | Verified with approximation boundary |
| `center` / `radius` / `precision` / `classify` / `sign` / `normalized` / `with_precision` | 暴露存储包络、有限分类、按包络定义的符号，以及保持包含关系的规范化/重调精度。 | `src/ball_float/ball_float.mbt` | `def predicates classify finite nan and enclosing zero consistently`；`ball_float sign and overlap relations remain enclosure based`；exact-widen 回归。 | Verified |
| `contains` / `overlaps` / `separated_from` / `definitely_lt` / `definitely_gt` / `maybe_overlap` | 关系 API 基于区间语义，而不是标量全序。 | `src/ball_float/ball_float.mbt` | `ball_float overlap detects separated balls`；`ball_float sign and overlap relations remain enclosure based`；exact containment 测试。 | Verified |
| `add` / `sub` / `mul` / `div` | 算术返回的球会包住真实结果，并把输出舍入位移也并入半径；除法拒绝分母球包含零。 | `src/ball_float/ball_float.mbt` | `ball_float multiplication keeps exact scalar result inside zero-radius inputs`；`ball_float division keeps exact scalar result inside zero-radius inputs`；零分母分支代码审阅。 | Verified with approximation boundary |
