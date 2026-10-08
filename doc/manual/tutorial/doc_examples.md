# doc_examples tutorial

This page shows maintainers how to run and extend the executable examples in
`src/doc_examples/README.mbt.md`.

## Quick start

```sh
just docs
```

runs `tools/doc_quality.py` (links, snapshots, versions) and then
`moon test src/doc_examples --target native --deny-warn`, which compiles and
runs every `moonbit check` block of the README as a test.

## Everyday tasks

### Add an example

Append a block to `src/doc_examples/README.mbt.md`:

````text
```moonbit check
///|
test "a unique, descriptive name" {
  let x = @bin_float.BinFloat::from_int(3)
  inspect(x.to_string(), content="3p0")
}
```
````

Use packages listed in `src/doc_examples/moon.pkg` (add an import there if
needed), give the test a unique name, and show results with `inspect`.

### Run only this package

From a workspace that resolves the Luna-Flow dependencies:

```sh
moon test -p Luna-Flow/floating/doc_examples
```

## Going further

The manual pages carry their own detailed examples; `doc_examples` keeps only
a small set of cross-package workflows that must compile in every test run of
the module.

## Common pitfalls

- `--deny-warn` turns warnings (for example deprecated calls) into failures.
- Blocks fenced without `check` are not compiled.

## Next steps

- [doc_examples API](../api/doc_examples.md)
- [doc_examples design](../design/doc_examples.md)
