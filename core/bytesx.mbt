///|
/// Byte-level helpers shared by the corpus, the mutators and the reporters.
///
/// Everything is expressed on `Bytes` / `Array[Byte]` rather than `String`,
/// because the inputs we care about are *not* valid text: a fuzz input is an
/// arbitrary byte string, and any `String` round trip would silently replace
/// the bytes we are trying to preserve.
pub fn bytes_of(arr : Array[Byte]) -> Bytes {
  Bytes::from_array(arr)
}

///|
pub fn array_of(bytes : Bytes) -> Array[Byte] {
  let out : Array[Byte] = []
  let mut i = 0
  while i < bytes.length() {
    out.push(bytes[i])
    i = i + 1
  }
  out
}

///|
pub fn concat_bytes(a : Bytes, b : Bytes) -> Bytes {
  a + b
}

///|
pub fn slice_bytes(bytes : Bytes, start : Int32, end : Int32) -> Bytes {
  let lo = if start < 0 {
    0
  } else if start > bytes.length() {
    bytes.length()
  } else {
    start
  }
  let hi = if end < lo {
    lo
  } else if end > bytes.length() {
    bytes.length()
  } else {
    end
  }
  let out : Array[Byte] = []
  let mut i = lo
  while i < hi {
    out.push(bytes[i])
    i = i + 1
  }
  bytes_of(out)
}

///|
/// A stable, backend-independent hash (FNV-1a, folded into 30 bits so it stays
/// positive on every backend).
pub fn hash_bytes(bytes : Bytes) -> Int32 {
  let mut h : UInt32 = 2166136261U
  let mut i = 0
  while i < bytes.length() {
    h = h ^ bytes[i].to_uint()
    h = h * 16777619U
    i = i + 1
  }
  (h & 0x3fffffffU).reinterpret_as_int()
}

///|
pub fn bytes_equal(a : Bytes, b : Bytes) -> Bool {
  if a.length() != b.length() {
    false
  } else {
    let mut i = 0
    let mut same = true
    while same && i < a.length() {
      if a[i] != b[i] {
        same = false
      }
      i = i + 1
    }
    same
  }
}

///|
/// Lowercase hex, at most `max` bytes, with `..` when truncated.
pub fn hex_of(bytes : Bytes, max : Int32) -> String {
  let sb = StringBuilder()
  let n = if bytes.length() < max { bytes.length() } else { max }
  let mut i = 0
  while i < n {
    sb.write_string(bytes[i].to_hex())
    i = i + 1
  }
  if n < bytes.length() {
    sb.write_string("..")
  }
  sb.to_string()
}

///|
pub fn hex_all(bytes : Bytes) -> String {
  hex_of(bytes, bytes.length())
}

///|
/// Printable ASCII view: non-printable bytes become `.`, so a report stays
/// one line per input. Never used for correctness, only for humans.
pub fn ascii_of(bytes : Bytes, max : Int32) -> String {
  let sb = StringBuilder()
  let n = if bytes.length() < max { bytes.length() } else { max }
  let mut i = 0
  while i < n {
    let v = bytes[i].to_int()
    if v >= 32 && v < 127 {
      sb.write_char(v.to_char().unwrap())
    } else {
      sb.write_char('.')
    }
    i = i + 1
  }
  sb.to_string()
}

///|
fn hex_value(c : Char) -> Int32 {
  let v = c.to_int()
  if v >= 48 && v <= 57 {
    v - 48
  } else if v >= 97 && v <= 102 {
    v - 87
  } else if v >= 65 && v <= 70 {
    v - 55
  } else {
    0
  }
}

///|
/// Parse a hex string into bytes. Non-hex characters are treated as `0` so a
/// hand-edited crash file never panics the replay path.
pub fn parse_hex(s : String) -> Bytes {
  let digits = s.length()
  let out : Array[Byte] = []
  let mut i = 0
  while i + 1 < digits {
    let hi = hex_value(s.get_char(i).unwrap())
    let lo = hex_value(s.get_char(i + 1).unwrap())
    out.push((hi * 16 + lo).to_byte())
    i = i + 2
  }
  if i < digits {
    out.push(hex_value(s.get_char(i).unwrap()).to_byte())
  }
  bytes_of(out)
}

///|
/// Replace digit runs with a single `#`, so that `v:123` and `v:456` share a
/// shape. This is what makes the bucket-based feedback signal meaningful: a
/// target that prints a number must not look "novel" on every execution.
pub fn shape(s : String) -> String {
  let sb = StringBuilder()
  let mut i = 0
  let mut in_digits = false
  while i < s.length() {
    let c = s.get_char(i).unwrap()
    let v = c.to_int()
    if v >= 48 && v <= 57 {
      if !in_digits {
        sb.write_char('#')
        in_digits = true
      }
    } else {
      in_digits = false
      sb.write_char(c)
    }
    i = i + 1
  }
  sb.to_string()
}

///|
/// Drop trailing whitespace (including newlines). Reporters build strings with
/// a trailing newline so they compose when piped; `println` adds its own, so
/// the CLI trims once at the print site instead of every reporter guessing.
pub fn trim_end(s : String) -> String {
  let mut end = s.length()
  while end > 0 {
    let c = s.get_char(end - 1).unwrap()
    let v = c.to_int()
    if v == 32 || v == 9 || v == 10 || v == 13 {
      end = end - 1
    } else {
      break
    }
  }
  let sb = StringBuilder()
  let mut i = 0
  while i < end {
    sb.write_char(s.get_char(i).unwrap())
    i = i + 1
  }
  sb.to_string()
}

///|
/// JSON-escape a string for the machine-readable report. Deliberately minimal:
/// control characters become `\u00XX`, the rest is passed through.
pub fn escape_json(s : String) -> String {
  let sb = StringBuilder()
  let mut i = 0
  while i < s.length() {
    let c = s.get_char(i).unwrap()
    let v = c.to_int()
    if c == '"' {
      sb.write_string("\\\"")
    } else if c == '\\' {
      sb.write_string("\\\\")
    } else if c == '\n' {
      sb.write_string("\\n")
    } else if c == '\r' {
      sb.write_string("\\r")
    } else if c == '\t' {
      sb.write_string("\\t")
    } else if v < 32 {
      sb.write_string("\\u00")
      let hex = v.to_byte().to_hex()
      sb.write_string(hex)
    } else {
      sb.write_char(c)
    }
    i = i + 1
  }
  sb.to_string()
}

///|
/// Substring by code-unit index, clamped. Used by path handling, where slicing
/// an ASCII path must not depend on grapheme boundaries.
pub fn slice_str(s : String, start : Int32, end : Int32) -> String {
  let sb = StringBuilder()
  let mut i = if start < 0 { 0 } else { start }
  let hi = if end > s.length() { s.length() } else { end }
  while i < hi {
    sb.write_char(s.get_char(i).unwrap())
    i = i + 1
  }
  sb.to_string()
}
