# `frontend/itl_expr` チュートリアル

まず end-to-end smoke を実行します。

```sh
just conformance smoke interval
```

library では parse、各 case の execute、summarize の順です。Unsupported と executable failure を分離し、strict 化は CLI/tooling で行います。
