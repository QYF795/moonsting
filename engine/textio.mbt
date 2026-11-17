// Small text helpers shared by the worker (writes lines) and the parent
// (reads them back). Kept byte-oriented so a non-UTF-8 byte in a verdict can
// never panic the parser; verdicts are ASCII by construction.

///|
pub fn split_lines(data : Bytes) -> Array[String] {
  let out : Array[String] = []
  let sb = StringBuilder()
  let mut i = 0
  while i < data.length() {
    let v = data[i].to_int()
    if v == 10 {
      if sb.to_string().length() > 0 {
        out.push(sb.to_string())
      }
      sb.reset()
    } else if v != 13 {
      sb.write_char(v.to_byte().to_char())
    }
    i = i + 1
  }
  if sb.to_string().length() > 0 {
    out.push(sb.to_string())
  }
  out
}

///|
pub fn split_tabs(s : String) -> Array[String] {
  let out : Array[String] = []
  let sb = StringBuilder()
  let mut i = 0
  while i < s.length() {
    let c = s.get_char(i).unwrap()
    if c == '\t' {
      out.push(sb.to_string())
      sb.reset()
    } else {
      sb.write_char(c)
    }
    i = i + 1
  }
  out.push(sb.to_string())
  out
}

///|
pub fn int_of(s : String) -> Int32 {
  let mut value = 0
  let mut i = 0
  while i < s.length() {
    let v = s.get_char(i).unwrap().to_int()
    if v < 48 || v > 57 {
      return value
    }
    value = value * 10 + (v - 48)
    i = i + 1
  }
  value
}
