# consistency tutorial

This page shows maintainers how to run the cross-package consistency tests and
how to add a new law when a change touches more than one numeric package.

## Quick start

Run the suite from a workspace that contains the module (the repository
wrapper keeps the build directory clean):

```sh
sh tools/run_moon_clean_exec.sh test -p Luna-Flow/floating/consistency --target native
```

A passing run ends with `passed: N, failed: 0`. The suite is also part of
`just pr`.

## Everyday tasks

### Run one test

```sh
sh tools/run_moon_clean_exec.sh test -p Luna-Flow/floating/consistency \
  --filter "decimal quantize*"
```

### Add a cross-package law

Write a white-box test in `core_wbtest.mbt` (arithmetic laws) or
`api_audit_wbtest.mbt` (observable API behaviour). State the law against an
exact oracle whenever possible:

```moonbit
///|
test "bin_float addition of small dyadics is exact" {
  let a = @bin_float.BinFloat::from_int(3)
  let b = @bin_float.BinFloat::from_int(5)
  let sum = @semantic.SemanticScalar::from_bin_float(a + b)
  let exact = @semantic.SemanticScalar::from_bin_float(
    @bin_float.BinFloat::from_int(8),
  )
  assert_true(sum == exact)
}
```

Use official decTest rows as fixed witnesses when you test GDA cohort or
flag rules, and quote the row id in the test name.

### Decide where a test belongs

A law about one package goes into that package's own tests. A test belongs
here when it needs two or more packages, or `internal` helpers from outside
their package, or an oracle such as `semantic` exact rationals.

## Going further

- The conformance corpora ([verification](../verification.md)) check each
  core against external references; this suite checks the cores against each
  other and against exact arithmetic.
- [internal tutorial](internal.md) shows the helpers several tests exercise.

## Common pitfalls

- **Run from a workspace.** The package imports sibling Luna-Flow modules;
  use the repository wrapper or a workspace that resolves them.
- **Keep tests deterministic.** Use fixed seeds and explicit contexts; no
  test may depend on timing or the target's `Double` formatting.

## Next steps

- [consistency API](../api/consistency.md) for the file layout.
- [consistency design](../design/consistency.md) for what the suite proves.
