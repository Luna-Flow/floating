///|
/// A corpus of seeded random differential rows, split into the cases that the
/// harness validates together.
///
/// Two corpus formats exist: `mpfr-random-v1` (one row per case, produced by
/// `tools/generate_mpfr_random_oracle.c`) and `.decTest` (a context block and a
/// row per case, produced by `tools/generate_libmpdec_random.py`).
priv enum CorpusKind {
  MpfrRandom
  Decimal
}

///|
/// A group of consecutive cases. `texts[i]` is the complete source of case `i`
/// (the row, plus its context directives for `.decTest`), `ids[i]` its id.
priv struct Batch {
  kind : CorpusKind
  header : String
  label : String
  ids : Array[String]
  texts : Array[String]
}

///|
fn Batch::length(self : Batch) -> Int32 {
  self.ids.length()
}

///|
fn Batch::slice(self : Batch, start : Int32, end : Int32) -> Batch {
  {
    kind: self.kind,
    header: self.header,
    label: self.label,
    ids: self.ids[start:end].to_owned(),
    texts: self.texts[start:end].to_owned(),
  }
}

///|
/// The source text that the matching frontend parses.
fn Batch::source(self : Batch) -> String {
  let builder = StringBuilder()
  builder.write_string(self.header)
  for text in self.texts {
    builder.write_string(text)
    builder.write_char('\n')
  }
  builder.to_string()
}

///|
/// The cases as plain text, for failure artifacts.
fn Batch::text(self : Batch) -> String {
  let builder = StringBuilder()
  for index, text in self.texts {
    if index > 0 {
      builder.write_char('\n')
    }
    builder.write_string(text)
  }
  builder.to_string()
}

///|
fn first_token(line : String) -> String {
  let mut end = 0
  while end < line.length() && line[end] != ' ' && line[end] != '\t' {
    end += 1
  }
  line[:end].to_owned()
}

///|
fn is_directive(line : String) -> Bool {
  // A decTest directive is `keyword: value`; a test row never has a colon
  // right after its first word.
  let word = first_token(line)
  word.length() > 1 && word[word.length() - 1] == ':'
}

///|
fn corpus_label(text : String) -> String {
  for line in text.split("\n") {
    let line = line.to_owned()
    if line.has_prefix("# mpfr-random-v1") ||
      line.has_prefix("-- libmpdec-random-v1") {
      return line
    }
  }
  "corpus"
}

///|
/// Splits a corpus file into batches of at most `size` cases.
fn split_corpus(text : String, size : Int32) -> Result[Array[Batch], String] {
  let kind = if text.contains("mpfr-random-v1") {
    CorpusKind::MpfrRandom
  } else if text.contains("libmpdec-random-v1") {
    CorpusKind::Decimal
  } else {
    return Err("not a seeded random differential corpus")
  }
  let label = corpus_label(text)
  let header = match kind {
    MpfrRandom => "# mpfr-random-v1\n"
    Decimal => "version: 2.62\nextended: 1\n"
  }
  let ids : Array[String] = []
  let texts : Array[String] = []
  let pending : Array[String] = []
  for line_view in text.split("\n") {
    let line = line_view.to_owned().trim().to_owned()
    if line.length() == 0 || line.has_prefix("#") || line.has_prefix("--") {
      continue
    }
    match kind {
      MpfrRandom => {
        ids.push(first_token(line))
        texts.push(line)
      }
      Decimal =>
        if is_directive(line) {
          let word = first_token(line)
          // The preamble directives are in every batch header already.
          if word != "version:" && word != "extended:" {
            pending.push(line)
          }
        } else {
          pending.push(line)
          ids.push(first_token(line))
          texts.push(pending.join("\n"))
          pending.clear()
        }
    }
  }
  if size <= 0 {
    return Err("batch size must be positive")
  }
  let batches : Array[Batch] = []
  let mut start = 0
  while start < ids.length() {
    let end = Int32::min(start + size, ids.length())
    batches.push({
      kind,
      header,
      label,
      ids: ids[start:end].to_owned(),
      texts: texts[start:end].to_owned(),
    })
    start = end
  }
  Ok(batches)
}

///|
/// Runs every case of the batch through the library. The result has one entry
/// per case: the empty string when the case agrees with the oracle, otherwise
/// the frontend's description of the disagreement.
fn execute_batch(batch : Batch) -> Result[Array[String], String] {
  let source = batch.source()
  match batch.kind {
    MpfrRandom =>
      match @mpfr_expr.parse_random_data(batch.label, source) {
        Err(diagnostics) =>
          Err(
            "parse failure at line " +
            diagnostics[0].line().to_string() +
            ": " +
            diagnostics[0].message(),
          )
        Ok(document) => {
          let summary = @mpfr_expr.execute_random_data(document)
          let results = summary.results()
          if results.length() != batch.length() {
            return Err("frontend returned a different number of results")
          }
          Ok(
            results.map(result => {
              if result.passed() {
                ""
              } else {
                result.message()
              }
            }),
          )
        }
      }
    Decimal =>
      match @gda_expr.parse_dectest(batch.label, source) {
        Err(diagnostics) =>
          Err(
            "parse failure at line " +
            diagnostics[0].span().line().to_string() +
            ": " +
            diagnostics[0].message(),
          )
        Ok(document) => {
          let summary = @gda_expr.execute_documents([document])
          let results = summary.results()
          if results.length() != batch.length() {
            return Err("frontend returned a different number of results")
          }
          Ok(
            results.map(result => {
              match result.disposition() {
                Executable =>
                  if result.passed() {
                    ""
                  } else {
                    result.message()
                  }
                Diagnostic(reason) => "diagnostic: " + reason
                Legacy(reason) => "legacy: " + reason
                Unsupported(reason) => "unsupported: " + reason
              }
            }),
          )
        }
      }
  }
}

///|
/// The text of the first failures of a batch outcome, for the JSONL evidence.
fn failure_text(ids : Array[String], messages : Array[String]) -> String {
  let builder = StringBuilder()
  let mut shown = 0
  let mut total = 0
  for index, message in messages {
    if message.length() > 0 {
      total += 1
      if shown < 3 {
        if shown > 0 {
          builder.write_string(" | ")
        }
        builder.write_string(ids[index] + ": " + message)
        shown += 1
      }
    }
  }
  if total == 0 {
    "all cases agree"
  } else {
    total.to_string() +
    " of " +
    messages.length().to_string() +
    " cases differ; " +
    builder.to_string()
  }
}
