# numeric_expr design

## Design goal

The conformance frontends of `floating` read four very different corpus
formats (GDA `.decTest`, IEEE 1788 `.itl`, MPFR data files, Berkeley TestFloat
vectors) and run them against four number types. `numeric_expr` gives them one
shared, typed intermediate form for "apply this operation to these operands"
and one evaluator, so that parsing, number semantics and error reporting are
separated:

- a frontend turns text into an `Expr` and keeps source positions;
- a backend, given as two callbacks, says what literals and operations mean;
- `evaluate` combines them and reports which node failed.

The package itself contains no arithmetic, no parsing of numbers, no IO and no
global state.

## Mathematical background

### Syntax

Let $L$ be the set of literals (raw text with a span) and $O$ the set of
operations (a name with a span). The public constructors generate exactly the
terms of the grammar

$$
e \;::=\; \mathsf{lit}(\ell) \;\mid\; \mathsf{op}(o)(e_1, \dots, e_n),
\qquad \ell \in L,\; o \in O,\; n \ge 0 .
$$

Internally a term is stored as a `@tt_syntax.Term[Atom]` of the
`Luna-Flow/type_theory` package, where `Atom` is a private enum with a literal
case and a primitive-operation case. `Expr::literal(ℓ)` is
`Value(LiteralAtom(ℓ))` and `Expr::invoke(o, args)` is
`Apply(Value(PrimitiveAtom(o)), args)`. The general `Term` type also has
`Variable` and `Bind` forms and allows any term in function position; the
public constructors never create those.

### Semantics

Fix a value set $V$, an error set $E$ and the two callbacks

$$
d : L \to V + E, \qquad i : O \times V^{*} \to V + E .
$$

Write $\mathrm{Err}$ for the error set
$L \times E \;+\; O \times E \;+\; \mathrm{Span}$ of `EvalError[E]`. The
meaning $[\![e]\!] \in V + \mathrm{Err}$ is defined by structural recursion:

$$
\begin{aligned}
[\![\mathsf{lit}(\ell)]\!] &=
  \begin{cases}
    v & \text{if } d(\ell) = v,\\
    \mathsf{LiteralFailure}(\ell, x) & \text{if } d(\ell) = \mathrm{err}\ x,
  \end{cases}\\[4pt]
[\![\mathsf{op}(o)(e_1, \dots, e_n)]\!] &=
  \begin{cases}
    [\![e_k]\!] & \text{if } [\![e_1]\!], \dots, [\![e_{k-1}]\!] \in V
                  \text{ and } [\![e_k]\!] \in \mathrm{Err},\\
    v & \text{if all } [\![e_j]\!] = v_j \in V \text{ and } i(o, v_1 \dots v_n) = v,\\
    \mathsf{OperationFailure}(o, x) & \text{if all } [\![e_j]\!] = v_j \in V
      \text{ and } i(o, v_1 \dots v_n) = \mathrm{err}\ x .
  \end{cases}
\end{aligned}
$$

This is the fold (catamorphism) of the syntax tree in the error monad
$V \mapsto V + \mathrm{Err}$, with the arguments sequenced from left to right.
The evaluator is a direct transcription: `evaluate_term` matches the three
shapes, evaluates the arguments in a `for` loop, and returns at the first
`Err`.

## Design decisions

### Callbacks instead of a number trait

**Problem.** The same row format is executed against several number types,
and each frontend needs its own value type: `gda_expr` evaluates to an enum
of decimals, integers, booleans and strings, each with thirteen GDA status
flags.

**Options.** A trait such as "`V` can parse literals and apply operations"; a
fixed value enum shared by all frontends; or two plain function arguments.

**Choice.** Two function arguments. MoonBit traits have only the `Self`
parameter, so a trait could not take the operation table as data, and one
value type could not have two interpretations (for example, the same `Decimal`
read under an IEEE context and under a GDA context). Functions also capture
per-row state: `gda_expr` closes over the row's `GdaContext`, so the same
literal text is read with the precision and rounding of the directive block it
appears in.

### Opaque `Expr` over `type_theory` syntax

**Problem.** Callers should be able to build and evaluate expressions without
depending on how trees are stored, and the package should be able to grow
variables and binders later.

**Choice.** `Expr` wraps a private `@tt_syntax.Term[Atom]`. `type_theory` owns
binding and substitution for the organisation's syntax trees, so variables and
`Bind` can be added later by reusing it, without a second tree type. Because
the field is private, adding constructors later does not break callers that
only use `Expr::literal`, `Expr::invoke` and `evaluate`.

### Left-to-right, fail-fast evaluation

**Problem.** When several operands are invalid, which error is reported, and
does work continue?

**Choice.** Arguments are evaluated from left to right and the first error is
returned without evaluating the rest. The reported error is therefore
deterministic (the leftmost failing leaf or node in post-order), and no
callback runs on values that will be discarded. A frontend that wants all
diagnostics of a document collects them while parsing, before evaluation, as
the frontends in this repository do.

### Errors keep the syntax node

`LiteralFailure` and `OperationFailure` carry the `Literal` or `Operation`
itself rather than only a message. The node has the raw text or name and the
span, which is what a corpus runner prints. The callback's error `E` is kept
unchanged, so a typed error survives evaluation.

## Correctness / invariants

**Proposition 1 (closed shape).** Every `Expr` built with the public API is
either `Value(LiteralAtom(ℓ))` or `Apply(Value(PrimitiveAtom(o)), args)` with
every element of `args` of the same two shapes. Consequently `evaluate` never
returns `UnsupportedExpression` for such trees.

*Proof.* By induction on construction. `Expr::literal` produces the first
shape. `Expr::invoke(o, args)` produces the second shape, and its arguments
are the terms of `Expr` values, which have the stated shapes by the induction
hypothesis. `evaluate_term` returns `UnsupportedExpression` only for
`Value(PrimitiveAtom(_))` at the root of a subterm, `Variable`, `Bind`, or an
`Apply` whose head is not `Value(PrimitiveAtom(_))`; none of these occurs.
$\square$

**Proposition 2 (post-order prefix).** Let $u_1, u_2, \dots, u_N$ be the nodes
of a tree in post-order (children left to right, then the parent). The
sequence of callback calls made by `evaluate` is $c(u_1), c(u_2), \dots,
c(u_m)$, where $c$ is `decode` for a literal and `invoke` for an operation
node, and

$$
m = \begin{cases}
N & \text{if evaluation succeeds,}\\
\min\{\, k : c(u_k) \text{ returns } \mathrm{Err} \,\} & \text{otherwise.}
\end{cases}
$$

*Proof sketch.* By induction on the tree. A leaf makes exactly one call. For
$\mathsf{op}(o)(e_1, \dots, e_n)$ the post-order is the concatenation of the
post-orders of $e_1, \dots, e_n$ followed by the node itself. The loop
evaluates $e_1, \dots, e_n$ in order; by the hypothesis each makes the calls
of its own post-order, stopping at its first failing call, and the loop returns
as soon as one child fails. If all children succeed, `invoke` is called once
for the node. Concatenating gives the claim. $\square$

Corollaries: on success `decode` runs once per literal and `invoke` once per
invocation node; no callback runs twice for the same node; the error returned
belongs to node $u_m$ and is wrapped exactly once (child errors are returned
unchanged, not re-wrapped by their ancestors).

**Proposition 3 (purity and determinism).** `evaluate` reads only the tree and
calls only the two callbacks. If the callbacks are deterministic functions,
so is `evaluate`.

**Complexity.** For a tree with $N$ nodes and height $h$, evaluation makes at
most $N$ callback calls, allocates one argument array per invocation node
(total size $N - 1$ at most), and uses recursion depth $h$. Construction with
`Expr::invoke` copies the argument array, $O(n)$ for $n$ arguments.

## Alternatives rejected

- **A public enum for `Expr`.** Callers could pattern-match the tree, but every
  new syntax form (variables, binders) would break them. The opaque struct
  keeps that freedom.
- **Collecting all errors during evaluation.** An applicative evaluator that
  continues after an error would have to invent values for failed operands or
  skip operations, which makes the meaning of later errors unclear. Frontends
  collect parse diagnostics before evaluation instead.
- **Arity in `Operation`.** A declared arity would only duplicate the check
  the backend has to do anyway (it must also check operand kinds), and would
  not work for variadic operations.
- **An explicit stack instead of recursion.** Corpus rows are shallow (one
  operation over literals), so the simpler recursive fold is kept.

## Boundaries

- No tokenizer, parser or pretty-printer: frontends turn text into `Expr`.
- No number type, rounding, precision, flags or contexts: callbacks own all
  numeric semantics.
- No arity or type checking of operations.
- No variables, binders, sharing or user-defined functions are exposed yet,
  although the internal representation can hold them.
- No IO, logging or global state; source spans are plain data.
- No equality or printing of whole expressions.
