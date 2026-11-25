# Rewrite report: doc/manual/tutorial/def.md

## Scope

Page `doc/manual/tutorial/def.md`, read from base `408e4c47`; 884 words before and 883 words after by `wc -w`. The prose scan is 482 words before and 481 words after. This pass rewrites the tutorial prose while preserving all runnable examples, headings, links, identifiers, formulas and numeric claims.

## Outline of questions

- Quick start: how do I import `def` and inspect a value?
- Write one function for every representation: how do I write generic code over the scalar types?
- Change precision generically: how do I round a value through `Floating`?
- Read an IEEE comparison: how do I handle the four comparison results?
- Normalize before comparing representations: how do I compare decimal cohorts by their printed forms?
- Use the re-exported arithmetic types: how do I handle checked errors through `def`?
- Common pitfalls: which sign, order, precision and context assumptions are unsafe?
- Next steps: where do I find the laws, full API and cross-representation tutorial?

## Scan before and after

Before (`manual_scan.py --examples 40`): 482 words; absolute 1, history 1, symbol-start 5, `decided:rounding mode` 1, `term:V08` 1, `term:V24` 1.

After: 481 words; absolute 1, negation 1, symbol-start 4; no `decided:` or `term:` hits. The remaining absolute, negation and symbol-start hits are intentional in the existing tutorial examples and statements about representational limits.

## Content check

`content_diff.py page.old.md page.new.md`: before 102 items, after 102 items, lost 0 distinct.

FORMULA: the `$2^{\\pm 2^{30}}$` bound is unchanged. All code blocks, inline identifiers, links, numbers and citations remain present. Added prose only restructures the goal, generic-method explanation, rounding explanation, comparison explanation, cohort explanation and context-limit pitfall; it adds no behavior or number.

## Ledger

Nothing left the text.

## Additions

- The opening states the learner's path as actions. Tutorial organization required by `references/tutorial.md`.
- The generic-method paragraph says qualified calls apply when the receiver has a type parameter. This restates the existing claim without the release-history aside.
- The rounding paragraph defines the radix-specific significant-digit count and names the rounding direction. `DECIDED.md` Q10 and the existing `Floating::with_precision` behavior in `doc/manual/api/def.md`.
- The comparison paragraph states that `Unordered` means at least one NaN operand. Existing page claim and `doc/manual/api/def.md`.
- The cohort paragraph says `normalized` returns the cohort's canonical member. Existing page claim and `doc/manual/api/def.md`.

## Statements that look wrong, stale or contradictory (listed, not changed)

| Old text (line) | The statement, as the old text has it | Checked against | The same statement in the new text | What was found |
| --- | --- | --- | --- | --- |
| 208 | `with_precision` ignores context exponent limits and `Binary` overflows near $2^{\\pm 2^{30}}$ | `doc/manual/api/def.md`; `.tmp/plan-0.12/align/checked-F2.md` | `with_precision` reports no flags and ignores context exponent limits; `Binary` still overflows at about $2^{\\pm 2^{30}}$ | Retained; no correction made. |
| 212 | `with_precision(x, 0)` aborts for `Binary` and `decimal.Decimal`, while `decimal_gda.Decimal` clamps to 1 | `.tmp/plan-0.12/align/checked-F2.md` and `doc/manual/api/def.md` | Same sentence | Retained; no correction made. |

## Corrections made in this pass

None.

## Terms and numbers wanted

None.

## Gates

`lunadoc update` ran and both catalogs report 100.0% coverage, 0 fuzzy and 0 untranslated entries. `report_check.py` passed. Pending final gates: `lunadoc check . --compile`, `just docs`, `moon fmt --check`, and `git diff --check`.
