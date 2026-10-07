# `frontend/testfloat_expr` Tutorial

Use the checked-in vectors first:

```sh
just conformance smoke binary
```

Library callers build a `TestFloatSpec`, parse one vector source, construct
`RunOptions` for an optional shard, then execute the document. Keep function
metadata explicit rather than inferring it from a path.
