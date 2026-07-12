///|
fn usage() -> String {
  "usage: floating-conformance --backend <gda|testfloat|mpfr|itl> [backend options]"
}

///|
fn dispatch(arguments : Array[String]) -> Int {
  let forwarded : Array[String] = [arguments[0]]
  let mut backend = ""
  let mut index = 1
  while index < arguments.length() {
    let argument = arguments[index]
    if argument == "--backend" {
      guard index + 1 < arguments.length() else {
        println("--backend requires a value")
        println(usage())
        return 2
      }
      guard backend.length() == 0 else {
        println("--backend may only be specified once")
        return 2
      }
      index += 1
      backend = arguments[index]
    } else if argument.has_prefix("--backend=") {
      guard backend.length() == 0 else {
        println("--backend may only be specified once")
        return 2
      }
      backend = argument[10:].to_owned()
    } else if argument == "--help" || argument == "-h" {
      println(usage())
      return 0
    } else {
      forwarded.push(argument)
    }
    index += 1
  }
  match backend {
    "gda" => @gda_expr_cli.run(forwarded)
    "testfloat" => @testfloat_expr_cli.run(forwarded)
    "mpfr" => @mpfr_expr_cli.run(forwarded)
    "itl" => @itl_expr_cli.run(forwarded)
    "" => {
      println("--backend is required")
      println(usage())
      2
    }
    name => {
      println("unknown backend: " + name)
      println(usage())
      2
    }
  }
}

///|
fn main {
  @sys.exit(dispatch(@sys.get_cli_args()))
}
