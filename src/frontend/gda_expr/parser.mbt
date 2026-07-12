///|
fn ascii_lower(src : String) -> String {
  let builder = StringBuilder::new()
  for index in 0..<src.length() {
    let ch = src[index]
    if ch >= 'A' && ch <= 'Z' {
      builder.write_char(Int::unsafe_to_char(ch.to_int() + 32))
    } else {
      builder.write_char(Int::unsafe_to_char(ch.to_int()))
    }
  }
  builder.to_string()
}

///|
fn normalized_word(src : String) -> String {
  let builder = StringBuilder::new()
  let lower = ascii_lower(src)
  for index in 0..<lower.length() {
    let ch = lower[index]
    if ch != '-' && ch != '_' && ch != ' ' && ch != '\t' {
      builder.write_char(Int::unsafe_to_char(ch.to_int()))
    }
  }
  builder.to_string()
}

///|
fn find_unquoted(src : String, target : UInt16) -> Int {
  let mut quote : UInt16? = None
  for index in 0..<src.length() {
    let ch = src[index]
    match quote {
      Some(active) => if ch == active { quote = None }
      None =>
        if ch == '\'' || ch == '"' {
          quote = Some(ch)
        } else if ch == target {
          return index
        }
    }
  }
  -1
}

///|
fn strip_comment(src : String) -> String {
  let mut quote : UInt16? = None
  let mut index = 0
  while index + 1 < src.length() {
    let ch = src[index]
    match quote {
      Some(active) => if ch == active { quote = None }
      None =>
        if ch == '\'' || ch == '"' {
          quote = Some(ch)
        } else if ch == '-' && src[index + 1] == '-' {
          return src[:index].to_owned()
        }
    }
    index += 1
  }
  src
}

///|
fn find_arrow(src : String) -> Int {
  let mut quote : UInt16? = None
  let mut index = 0
  while index + 1 < src.length() {
    let ch = src[index]
    match quote {
      Some(active) => if ch == active { quote = None }
      None =>
        if ch == '\'' || ch == '"' {
          quote = Some(ch)
        } else if ch == '-' && src[index + 1] == '>' {
          return index
        }
    }
    index += 1
  }
  -1
}

///|
fn tokenize(src : String) -> Result[Array[String], String] {
  let tokens : Array[String] = []
  let builder = StringBuilder::new()
  let mut quote : UInt16? = None
  let mut has_content = false
  for index in 0..<src.length() {
    let ch = src[index]
    match quote {
      Some(active) =>
        if ch == active {
          tokens.push(builder.to_string())
          builder.reset()
          has_content = false
          quote = None
        } else {
          builder.write_char(Int::unsafe_to_char(ch.to_int()))
          has_content = true
        }
      None =>
        if ch == '\'' || ch == '"' {
          if has_content {
            tokens.push(builder.to_string())
            builder.reset()
            has_content = false
          }
          quote = Some(ch)
        } else if ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n' {
          if has_content {
            tokens.push(builder.to_string())
            builder.reset()
            has_content = false
          }
        } else {
          builder.write_char(Int::unsafe_to_char(ch.to_int()))
          has_content = true
        }
    }
  }
  if quote is Some(_) {
    Err("unterminated quoted token")
  } else {
    if has_content {
      tokens.push(builder.to_string())
    }
    Ok(tokens)
  }
}

///|
fn parse_int_value(src : String) -> Int? {
  try @string.parse_int(src) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn update_context(
  context : GdaContext,
  name : String,
  value : String,
) -> Result[GdaContext, String] {
  match normalized_word(name) {
    "precision" =>
      match parse_int_value(value) {
        Some(number) => Ok({ ..context, precision: number })
        None => Err("invalid precision directive")
      }
    "rounding" => Ok({ ..context, rounding: value })
    "minexponent" =>
      match parse_int_value(value) {
        Some(number) => Ok({ ..context, min_exponent: number })
        None => Err("invalid minexponent directive")
      }
    "maxexponent" =>
      match parse_int_value(value) {
        Some(number) => Ok({ ..context, max_exponent: number })
        None => Err("invalid maxexponent directive")
      }
    "clamp" => Ok({ ..context, clamp: value.trim().to_owned() == "1" })
    "extended" => Ok({ ..context, extended: value.trim().to_owned() != "0" })
    "dectest" => Ok({ ..context, dectest: value })
    "version" => Ok(context)
    _ => Ok(context)
  }
}

///|
pub fn parse_dectest(
  source : String,
  text : String,
) -> Result[GdaDocument, Array[ParseDiagnostic]] {
  let cases : Array[GdaCase] = []
  let diagnostics : Array[ParseDiagnostic] = []
  let mut context = GdaContext::default()
  let lines = text.split("\n").to_array()
  for line_index, line_view in lines {
    let line_number = line_index + 1
    let span = @numeric_expr.SourceSpan::new(source, line=line_number, column=1)
    let line = strip_comment(line_view.to_owned()).trim().to_owned()
    if line.length() == 0 {
      continue
    }
    let arrow = find_arrow(line)
    if arrow < 0 {
      let colon = find_unquoted(line, ':')
      if colon > 0 {
        let name = line[:colon].to_owned().trim().to_owned()
        let value = line[colon + 1:].to_owned().trim().to_owned()
        match update_context(context, name, value) {
          Ok(next) => context = next
          Err(message) => diagnostics.push({ span, message })
        }
      } else {
        diagnostics.push({ span, message: "expected directive or testcase row" })
      }
      continue
    }
    let lhs = tokenize(line[:arrow].to_owned())
    let rhs = tokenize(line[arrow + 2:].to_owned())
    match (lhs, rhs) {
      (Ok(left), Ok(right)) if left.length() >= 2 && right.length() >= 1 => {
        let id = left[0]
        let operation = left[1]
        let operands = left[2:].to_owned()
        let expected = right[0]
        let conditions = right[1:].to_owned()
        let arguments = operands.map(fn(raw) {
          @numeric_expr.Expr::literal(@numeric_expr.Literal::new(raw, span~))
        })
        let expression = @numeric_expr.Expr::invoke(
          @numeric_expr.Operation::new(normalized_word(operation), span~),
          arguments,
        )
        cases.push({
          id,
          operation,
          normalized_operation: normalized_word(operation),
          operands,
          expected,
          conditions,
          context,
          expression,
          span,
        })
      }
      (Err(message), _) | (_, Err(message)) =>
        diagnostics.push({ span, message })
      _ => diagnostics.push({ span, message: "malformed testcase row" })
    }
  }
  if diagnostics.length() == 0 {
    Ok({ source, cases })
  } else {
    Err(diagnostics)
  }
}
