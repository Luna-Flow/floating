# testfloat_expr_cli tutorial

This tutorial shows how to execute a Berkeley TestFloat vector file with the
binary runner. The runner is reached as
`floating-conformance --backend testfloat`; below, `testfloat` abbreviates that
command.

## Quick start

Generate vectors with TestFloat's `testfloat_gen` (installed by
`just conformance fetch binary`) and run them:

```sh
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

## Everyday tasks

### Match the generator options

Pass the same function, rounding and tininess as the generator, and `--exact`
when the vectors were generated with `-exact`:

```sh
testfloat_gen -rminMag -exact f32_roundToInt > r.tv
testfloat --function f32_roundToInt --rounding rminMag --exact r.tv
```

### Shard a large file

```sh
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

- [testfloat_expr_cli API](../../api/cli/testfloat_expr_cli.md)
- [testfloat_expr_cli design](../../design/cli/testfloat_expr_cli.md)
