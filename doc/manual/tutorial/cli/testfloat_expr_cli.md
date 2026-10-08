# cli/testfloat_expr_cli tutorial

This tutorial shows how to execute a Berkeley TestFloat vector file with the
binary runner. The runner is reached as
`floating-conformance --backend testfloat`; below, `testfloat` abbreviates that
command.

| I want to | Use |
| --- | --- |
| run one generated vector file | [`testfloat --function … FILE`](#quick-start) |
| match `testfloat_gen` options | [`--rounding`, `--tininess`, `--exact`](#match-the-generator-options) |
| split a large file over processes | [`--shard-count`, `--shard-index`](#shard-a-large-file) |
| get machine-readable output | [`--json`](#json-for-scripts) |
| call the runner from MoonBit | [`@testfloat_expr_cli.run`](#from-moonbit-code) |
| run the whole TestFloat matrix | [`just conformance run binary`](#going-further) |

## Quick start

The executable is built from a checkout of the repository with
`just conformance build binary`.

Generate vectors with TestFloat's `testfloat_gen` and run them.
`just conformance fetch binary` downloads the pinned SoftFloat and TestFloat
sources; `just conformance run binary` builds `testfloat_gen` from them into
`.tmp/binfloat-conformance/vendor/TestFloat-3e/build/Linux-x86_64-GCC/`.

```bash
testfloat_gen -level 1 -rnear_even -tininessafter f64_mul > f64_mul.tv
testfloat --function f64_mul --rounding rnear_even --tininess after f64_mul.tv
```

```text
TestFloat execution summary
function: f64_mul
rounding: rnear_even
tininess: after
cases: …
selected cases: …
passed cases: …
failed cases: 0
```

### From MoonBit code

After `moon add Luna-Flow/floating@0.8.0`, import
`"Luna-Flow/floating/cli/testfloat_expr_cli"` in `moon.pkg` and call `run`
with the same arguments:

```moonbit nocheck
let status = @testfloat_expr_cli.run([
  "testfloat", "--function", "f64_mul", "--rounding", "rnear_even", "f64_mul.tv",
])
```

## Everyday tasks

### Match the generator options

Pass the same function, rounding and tininess as the generator, and `--exact`
when the vectors were generated with `-exact`:

```bash
testfloat_gen -rminMag -exact f32_roundToInt > r.tv
testfloat --function f32_roundToInt --rounding rminMag --exact r.tv
```

### Shard a large file

```bash
testfloat --function f128_mulAdd --shard-count 8 --shard-index 3 --json big.tv
```

Shard `i` runs the vectors whose index is `i` modulo the shard count.

### JSON for scripts

`--json` prints `function`, `rounding`, `tininess`, `exact`, `totalCases`,
`selectedCases`, `passedCases`, `failedCases` and `failedIds`
(`FUNCTION:LINE`).

## Going further

- `just conformance run binary --level 1 --tininess after --tininess before`
  plans the full matrix, streams `testfloat_gen` output in chunks into
  temporary files, runs this runner on each chunk, and remaps the line-based
  ids to global vector numbers.
- [testfloat_expr tutorial](../frontend/testfloat_expr.md) explains the pass
  rule.

## Common pitfalls

- **Exactly one file.** A second path is an error.
- **Rounding defaults to `rnear_even`.** Always pass the generator's mode.
- **Ids are line numbers of the file you pass.** When you split a stream into
  chunks, keep track of the offset yourself.

## Next steps

- [cli/testfloat_expr_cli API](../../api/cli/testfloat_expr_cli.md)
- [cli/testfloat_expr_cli design](../../design/cli/testfloat_expr_cli.md)
- [frontend/testfloat_expr tutorial](../frontend/testfloat_expr.md) for the
  pass rule.
