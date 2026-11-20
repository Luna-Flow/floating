# differential/harness tutorial

The harness is run through the `just random-diff` tooling, which builds the
`differential` executable around it. This tutorial says where its code lives, how
to test it and how to extend it; the campaign workflow is in the
[differential tutorial](../differential.md).

| I want to | Use |
| --- | --- |
| run a campaign | [the `differential` tutorial](../differential.md) |
| test the harness | [quick start](#quick-start) |
| change the batching or the record | [everyday tasks](#everyday-tasks) |
| add a family of rows | [going further](#going-further) |

## Quick start

The package ships inside the tools module `Luna-Flow/floating-tools` (directory
`tooling/` of the repository); there is nothing to install. Test it from the
repository (native only, because `moonbitlang/async` has no wasm-gc runtime):

```bash
moon test tooling/src/differential/harness --target native
```

Run the committed fixtures through the whole stack:

```bash
just random-diff smoke
```

`run` is the only public function; the `differential` executable calls it with
`@env.args()`.

## Everyday tasks

### Find the code

`batch.mbt` splits a corpus into batches and executes one (`split_corpus`,
`execute_batch`); `harness.mbt` holds the command-line options, the experiment
specification and `run`; `differential_wbtest.mbt` tests the batching and the
failure text with inline corpora.

### Change how a corpus is split

`split_corpus(text, size)` recognises the corpus kind from its header line and,
for decimal corpora, repeats the directives (precision, rounding, exponent
range) in front of the cases they govern, so a batch is always self-contained. Add a case to `differential_wbtest.mbt` with
a small inline corpus before changing it, then run the command above.

## Going further

A new family of rows needs three things: an oracle program that writes the rows
(outside MoonBit, see `tools/generate_*`), a frontend that executes one row, and
a `CorpusKind` that `split_corpus` recognises from the header line and
`execute_batch` maps to that frontend. The
manifest and the replay command of `tools/random_differential.py` pick it up by
family name.

## Common pitfalls

- **No wasm-gc build.** `moonbitlang/async` has no wasm-gc runtime, so the
  package declares `supported_targets = "all-wasm-gc"`.
- **Exit status.** `run` exits the process (`2` for a bad command line or corpus,
  `1` for a disagreement): do not call it from a test.

## Next steps

- [differential/harness API](../../api/differential/harness.md).
- [differential/harness design](../../design/differential/harness.md).
- [differential tutorial](../differential.md) for the workflow.
