# doc_examples tutorial

The goal of this page is to show maintainers how to run and extend the
executable examples in `src/doc_examples/README.mbt.md`.

| I want to | Use |
| --- | --- |
| run the whole documentation gate | [`just docs`](#quick-start) |
| run only these examples | [`moon test`](#run-only-this-package) |
| add a workflow example | [a `moonbit check` block](#add-an-example) |
| decide between this package and a manual page | [Going further](#going-further) |

## Quick start

```bash
just docs
```

runs `tools/run_docs.py`, which performs three steps and stops at the first
failure: `tools/doc_quality.py` (links, snapshots, versions),
`tools/check_doc_examples.py` (the runnable examples of every manual page),
and `moon test src/doc_examples --target native --deny-warn`, which compiles
and runs every `moonbit check` block of the README as a test.

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

From the repository root:

```bash
sh tools/run_moon_clean_exec.sh test src/doc_examples --target native --deny-warn
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
