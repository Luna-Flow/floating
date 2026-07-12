///|
pub struct CommonOptions {
  priv json : Bool
  priv shard : @conformance.ShardSpec
  priv remaining : Array[String]
}

///|
pub fn parse_int(name : String, source : String) -> Result[Int, String] {
  try @string.parse_int(source) catch {
    _ => Err("invalid " + name + ": " + source)
  } noraise {
    value => Ok(value)
  }
}

///|
pub fn parse_common_options(
  arguments : Array[String],
  allow_shard? : Bool = true,
) -> Result[CommonOptions, String] {
  let mut json = false
  let mut shard_count = 1
  let mut shard_index = 0
  let remaining : Array[String] = []
  let mut index = 1
  while index < arguments.length() {
    let argument = arguments[index]
    if argument == "--json" {
      json = true
    } else if allow_shard &&
      (argument == "--shard-count" || argument == "--shard-index") {
      guard index + 1 < arguments.length() else {
        return Err(argument + " requires a value")
      }
      index += 1
      let name = if argument == "--shard-count" {
        "shard count"
      } else {
        "shard index"
      }
      match parse_int(name, arguments[index]) {
        Ok(value) =>
          if argument == "--shard-count" {
            shard_count = value
          } else {
            shard_index = value
          }
        Err(message) => return Err(message)
      }
    } else if allow_shard && argument.has_prefix("--shard-count=") {
      match parse_int("shard count", argument[14:].to_owned()) {
        Ok(value) => shard_count = value
        Err(message) => return Err(message)
      }
    } else if allow_shard && argument.has_prefix("--shard-index=") {
      match parse_int("shard index", argument[14:].to_owned()) {
        Ok(value) => shard_index = value
        Err(message) => return Err(message)
      }
    } else {
      remaining.push(argument)
    }
    index += 1
  }
  match @conformance.ShardSpec::try_new(shard_count, shard_index) {
    Ok(shard) => Ok({ json, shard, remaining })
    Err(message) => Err(message)
  }
}

///|
pub fn CommonOptions::json(self : CommonOptions) -> Bool {
  self.json
}

///|
pub fn CommonOptions::shard_count(self : CommonOptions) -> Int {
  self.shard.count()
}

///|
pub fn CommonOptions::shard_index(self : CommonOptions) -> Int {
  self.shard.index()
}

///|
pub fn CommonOptions::remaining(self : CommonOptions) -> Array[String] {
  self.remaining.copy()
}

///|
pub fn read_source(
  path : String,
  label? : String = "file",
) -> Result[String, String] {
  try @fs.read_file_to_string(path) catch {
    _ => Err("cannot read " + label + ": " + path)
  } noraise {
    source => Ok(source)
  }
}

///|
pub fn collect_files(
  paths : Array[String],
  suffix : String,
) -> Result[Array[String], String] {
  let files : Array[String] = []
  for path in paths {
    if !@fs.path_exists(path) {
      return Err("path does not exist: " + path)
    }
    let is_directory = @fs.is_dir(path) catch {
      _ => return Err("cannot inspect path: " + path)
    }
    if is_directory {
      let entries = @fs.read_dir(path) catch {
        _ => return Err("cannot read directory: " + path)
      }
      for entry in entries {
        if entry.has_suffix(suffix) {
          files.push(path + "/" + entry)
        }
      }
    } else if path.has_suffix(suffix) {
      files.push(path)
    }
  }
  files.sort()
  Ok(files)
}

///|
pub fn format_diagnostic(
  location : @conformance.SourceLocation,
  message : String,
) -> String {
  location.source() +
  ":" +
  location.line().to_string() +
  ":" +
  location.column().to_string() +
  ": " +
  message
}

///|
pub fn format_diagnostic_at(
  source : String,
  line : Int,
  message : String,
  column? : Int = 1,
) -> String {
  format_diagnostic(
    @conformance.SourceLocation::new(source, line, column~),
    message,
  )
}

///|
pub fn json_int(value : Int) -> Json {
  Json::number(value.to_double(), repr=value.to_string())
}

///|
pub fn json_string(value : String) -> Json {
  Json::string(value)
}

///|
pub fn json_bool(value : Bool) -> Json {
  Json::boolean(value)
}

///|
pub fn json_strings(values : Array[String]) -> Json {
  Json::array(values.map(fn(value) { Json::string(value) }))
}

///|
pub fn json_object(fields : Array[(String, Json)]) -> Json {
  let object : Map[String, Json] = {}
  for field in fields {
    let (key, value) = field
    object[key] = value
  }
  Json::object(object)
}

///|
pub fn json_stringify(value : Json) -> String {
  value.stringify()
}
