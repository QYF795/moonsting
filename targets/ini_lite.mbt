///|
/// INI files, with a metamorphic property instead of a round trip.
///
/// INI has no canonical form: whitespace around `=`, section separators and
/// comment markers are all free. Byte round-tripping would be a fake goal. What
/// must hold is that a comment changes nothing:
///
///     summary(x) == summary(x + "\n; anything\n")
///
/// This catches the classic comment bugs: comments only recognised at the start
/// of a line, a value that swallows the rest of the file, section state leaking
/// across a comment.
///
/// Coverage ids for this target live in 620..648.

///|
struct IniDoc {
  sections : Int32
  keys : Int32
  hash : Int32
}

///|
fn ini_trim(data : Bytes, start : Int32, end : Int32) -> Bytes {
  let mut lo = start
  let mut hi = end
  while lo < hi {
    let v = data[lo].to_int()
    if v == 32 || v == 9 {
      lo = lo + 1
    } else {
      break
    }
  }
  while hi > lo {
    let v = data[hi - 1].to_int()
    if v == 32 || v == 9 || v == 13 {
      hi = hi - 1
    } else {
      break
    }
  }
  @core.slice_bytes(data, lo, hi)
}

///|
fn ini_mix(seed : Int32, data : Bytes) -> Int32 {
  let mut h = seed
  let mut i = 0
  while i < data.length() {
    h = (h * 31 + data[i].to_int()) % 1000003
    i = i + 1
  }
  h
}

///|
/// Parse the document into a summary. `None` on a structural error: a key/value
/// line outside any section, an empty key, or a section header that is never
/// closed.
pub fn ini_parse(input : Bytes) -> IniDoc? {
  let n = input.length()
  let mut i = 0
  let mut sections = 0
  let mut keys = 0
  let mut hash = 7
  let mut in_section = false
  while i < n {
    let start = i
    while i < n && input[i].to_int() != 10 {
      i = i + 1
    }
    let line = ini_trim(input, start, i)
    if i < n {
      i = i + 1
    }
    if line.length() == 0 {
      continue
    }
    let first = line[0].to_int()
    if first == 59 || first == 35 {
      // `;` or `#`
      @cov.hit(620)
      continue
    }
    if first == 91 {
      // `[section]`
      if line[line.length() - 1].to_int() != 93 {
        @cov.hit(621)
        return None
      }
      let name = ini_trim(line, 1, line.length() - 1)
      if name.length() == 0 {
        @cov.hit(622)
        return None
      }
      sections = sections + 1
      in_section = true
      hash = ini_mix(hash ^ 0x11, name)
      @cov.hit(623)
      continue
    }
    // `key = value`
    let mut eq = -1
    let mut k = 0
    while k < line.length() {
      if line[k].to_int() == 61 {
        eq = k
        break
      }
      k = k + 1
    }
    if eq <= 0 {
      @cov.hit(624)
      return None
    }
    if !in_section {
      @cov.hit(625)
      return None
    }
    let key = ini_trim(line, 0, eq)
    let value = ini_trim(line, eq + 1, line.length())
    if key.length() == 0 {
      @cov.hit(626)
      return None
    }
    keys = keys + 1
    hash = ini_mix(hash ^ 0x22, key)
    hash = ini_mix(hash, value)
    @cov.hit(627)
  }
  Some({ sections, keys, hash, })
}

///|
pub fn ini_summary(input : Bytes) -> String {
  match ini_parse(input) {
    None => "err"
    Some(doc) => {
      @cov.hit(640)
      "ok:" +
      doc.sections.to_string() +
      "x" +
      doc.keys.to_string() +
      ":" +
      doc.hash.to_string()
    }
  }
}

///|
/// A comment must not change the summary. The appended text always starts on a
/// fresh line, so the only way it can alter anything is a parsing bug.
pub fn ini_comment_invariant(input : Bytes, output : String) -> String {
  let padded = input + b"\n; moonsting comment\n"
  let after = ini_summary(padded)
  if after == output {
    ""
  } else {
    "comment changed the summary: " + output + " -> " + after
  }
}
