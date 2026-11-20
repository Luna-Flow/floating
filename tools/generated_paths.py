"""The throwaway sources that gate stages write into the source trees.

One list, shared by every tool that has to tell them from a real change
(#417, #431):

- `tools/check_package_contents.py` rejects them in a package;
- `tools/run_python_tests.py` ignores them when it compares the tree around the
  Python tests, because the stage that writes them runs in another lane of the
  quick gate, concurrently with the tests.

Writers: `tools/run_ieee_decimal.py` (`ieee_corpus_generated_NN_wbtest.mbt` next to
the decimal tests, for the length of one run), `tools/check_doc_examples.py`
(`_generated_doc_examples` packages in both modules) and the retired decTest
generator (`.generated_dectest*`, `_generated_dectest_wbtest.mbt`). A new
writer adds its marker here and nowhere else.
"""

GENERATED_MARKERS = (
    "ieee_corpus_generated_",
    "_generated_doc_examples",
    ".generated_dectest",
    "_generated_dectest",
)


def is_generated_path(path: str) -> bool:
    """Whether `path` is a throwaway source written by a gate stage."""
    return any(marker in path for marker in GENERATED_MARKERS)
