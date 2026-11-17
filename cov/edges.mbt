///|
/// A set of edge identifiers extracted from an instrumented run.
///
/// Identifiers are hashes of the source location text, not raw counters: the
/// artifact format is internal to the toolchain, so the only thing this parser
/// promises is "same location, same id" -which is all a novelty check needs.
pub struct EdgeSet {
  ids_ : Array[Int32]
}

///|
pub fn EdgeSet::new() -> EdgeSet {
  { ids_: [], }
}

///|
pub fn EdgeSet::len(self : EdgeSet) -> Int32 {
  self.ids_.length()
}

///|
pub fn EdgeSet::contains(self : EdgeSet, id : Int32) -> Bool {
  let mut i = 0
  while i < self.ids_.length() {
    if self.ids_[i] == id {
      return true
    }
    i = i + 1
  }
  false
}

///|
/// Returns `true` when the edge was new.
pub fn EdgeSet::add(self : EdgeSet, id : Int32) -> Bool {
  if self.contains(id) {
    false
  } else {
    self.ids_.push(id)
    true
  }
}

///|
pub fn EdgeSet::merge(self : EdgeSet, other : EdgeSet) -> Int32 {
  let mut added = 0
  let mut i = 0
  while i < other.ids_.length() {
    if self.add(other.ids_[i]) {
      added = added + 1
    }
    i = i + 1
  }
  added
}

///|
fn trim_ascii_space(s : String) -> String {
  let sb = StringBuilder()
  let mut i = 0
  while i < s.length() {
    let c = s.get_char(i).unwrap()
    let v = c.to_int()
    if v > 32 {
      sb.write_char(c)
    }
    i = i + 1
  }
  sb.to_string()
}

///|
/// Split on newlines without relying on `String::split` (kept in one place so
/// line-ending differences between backends cannot change the parse).
fn split_lines(text : String) -> Array[String] {
  let out : Array[String] = []
  let sb = StringBuilder()
  let mut i = 0
  while i < text.length() {
    let c = text.get_char(i).unwrap()
    if c == '\n' {
      out.push(sb.to_string())
      sb.reset()
    } else if c != '\r' {
      sb.write_char(c)
    }
    i = i + 1
  }
  if sb.to_string().length() > 0 {
    out.push(sb.to_string())
  }
  out
}

///|
/// Parse the text of a `moonbit_coverage_*.txt` artifact.
///
/// Tolerated shapes (all real-world variants we have seen):
///   `path/to/file.mbt:12:5 3`
///   `path/to/file.mbt 12 5 3`
///   `3`
/// A line that yields no usable location is skipped. A line that is only a
/// number contributes nothing, because it carries no identity.
pub fn parse_artifact(text : String) -> EdgeSet {
  let set = EdgeSet::new()
  let lines = split_lines(text)
  let mut i = 0
  while i < lines.length() {
    let line = trim_ascii_space(lines[i])
    if line.length() > 0 {
      let key = location_key(line)
      if key.length() > 0 {
        ignore(set.add(@core.hash_bytes(@utf8.encode(key))))
      }
    }
    i = i + 1
  }
  set
}

///|
/// Keep everything before the trailing run of digits, so hit counts do not
/// create new edge ids when they change.
fn location_key(line : String) -> String {
  let mut end = line.length()
  while end > 0 {
    let c = line.get_char(end - 1).unwrap()
    let v = c.to_int()
    if v >= 48 && v <= 57 {
      end = end - 1
    } else {
      break
    }
  }
  if end == 0 {
    ""
  } else {
    let sb = StringBuilder()
    let mut i = 0
    while i < end {
      sb.write_char(line.get_char(i).unwrap())
      i = i + 1
    }
    trim_ascii_space(sb.to_string())
  }
}
