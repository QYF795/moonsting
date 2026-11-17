///|
/// A small strict JSON validator, written against bytes on purpose.
///
/// It is strict (no trailing commas, no comments, control characters inside
/// strings rejected) so that fuzzing it is meaningful: every accepted input
/// should be valid JSON and every rejected one should carry a position, which
/// makes a mismatch report readable instead of "false vs true".
///
/// Byte codes used below: 9 tab, 10 lf, 13 cr, 32 space, 34 quote, 44 comma,
/// 45 minus, 58 colon, 91 `[`, 92 backslash, 93 `]`, 123 `{`, 125 `}`.

///|
fn jskip_ws(data : Bytes, pos : Int32) -> Int32 {
  let mut p = pos
  while p < data.length() {
    let v = data[p].to_int()
    if v == 32 || v == 9 || v == 10 || v == 13 {
      p = p + 1
    } else {
      break
    }
  }
  p
}

///|
fn jhex(data : Bytes, pos : Int32) -> Int32 raise {
  if pos >= data.length() {
    raise Failure::Failure("hex:eof")
  }
  let v = data[pos].to_int()
  if (v >= 48 && v <= 57) || (v >= 97 && v <= 102) || (v >= 65 && v <= 70) {
    v
  } else {
    raise Failure::Failure("hex:bad@" + pos.to_string())
  }
}

///|
fn jstring(data : Bytes, pos : Int32) -> Int32 raise {
  let mut p = pos + 1
  while p < data.length() {
    let v = data[p].to_int()
    if v == 34 {
      return p + 1
    } else if v == 92 {
      if p + 1 >= data.length() {
        raise Failure::Failure("escape:eof@" + p.to_string())
      }
      let e = data[p + 1].to_int()
      if e == 117 {
        ignore(jhex(data, p + 2))
        ignore(jhex(data, p + 3))
        ignore(jhex(data, p + 4))
        ignore(jhex(data, p + 5))
        p = p + 6
      } else {
        let known = e == 34 ||
          e == 92 ||
          e == 47 ||
          e == 98 ||
          e == 102 ||
          e == 110 ||
          e == 114 ||
          e == 116
        if !known {
          raise Failure::Failure("escape:bad@" + p.to_string())
        }
        p = p + 2
      }
    } else if v < 32 {
      raise Failure::Failure("ctrl@" + p.to_string())
    } else {
      p = p + 1
    }
  }
  raise Failure::Failure("string:eof@" + pos.to_string())
}

///|
fn jdigits(data : Bytes, pos : Int32) -> Int32 {
  let mut p = pos
  while p < data.length() {
    let v = data[p].to_int()
    if v >= 48 && v <= 57 {
      p = p + 1
    } else {
      break
    }
  }
  p
}

///|
fn jnumber(data : Bytes, pos : Int32) -> Int32 raise {
  let mut p = pos
  if p < data.length() && data[p].to_int() == 45 {
    p = p + 1
  }
  if p >= data.length() {
    raise Failure::Failure("number:eof@" + pos.to_string())
  }
  if data[p].to_int() == 48 {
    p = p + 1
  } else {
    let start = p
    p = jdigits(data, p)
    if p == start {
      raise Failure::Failure("number:digit@" + pos.to_string())
    }
  }
  if p < data.length() && data[p].to_int() == 46 {
    p = p + 1
    let start = p
    p = jdigits(data, p)
    if p == start {
      raise Failure::Failure("number:frac@" + pos.to_string())
    }
  }
  if p < data.length() && (data[p].to_int() == 101 || data[p].to_int() == 69) {
    p = p + 1
    if p < data.length() && (data[p].to_int() == 43 || data[p].to_int() == 45) {
      p = p + 1
    }
    let start = p
    p = jdigits(data, p)
    if p == start {
      raise Failure::Failure("number:exp@" + pos.to_string())
    }
  }
  p
}

///|
fn jliteral(data : Bytes, pos : Int32, word : Bytes) -> Int32 raise {
  if pos + word.length() > data.length() {
    raise Failure::Failure("literal:eof@" + pos.to_string())
  }
  let mut i = 0
  while i < word.length() {
    if data[pos + i] != word[i] {
      raise Failure::Failure("literal:bad@" + pos.to_string())
    }
    i = i + 1
  }
  pos + word.length()
}

///|
fn jvalue(data : Bytes, pos : Int32, depth : Int32) -> Int32 raise {
  if depth > 64 {
    raise Failure::Failure("depth@" + pos.to_string())
  }
  let p = jskip_ws(data, pos)
  if p >= data.length() {
    raise Failure::Failure("value:eof@" + p.to_string())
  }
  let v = data[p].to_int()
  if v == 123 {
    jobject(data, p, depth)
  } else if v == 91 {
    jarray(data, p, depth)
  } else if v == 34 {
    jstring(data, p)
  } else if v == 116 {
    jliteral(data, p, b"true")
  } else if v == 102 {
    jliteral(data, p, b"false")
  } else if v == 110 {
    jliteral(data, p, b"null")
  } else {
    jnumber(data, p)
  }
}

///|
fn jobject(data : Bytes, pos : Int32, depth : Int32) -> Int32 raise {
  let mut p = jskip_ws(data, pos + 1)
  if p < data.length() && data[p].to_int() == 125 {
    return p + 1
  }
  let mut first = true
  while true {
    if !first {
      if p >= data.length() || data[p].to_int() != 44 {
        raise Failure::Failure("object:comma@" + p.to_string())
      }
      p = jskip_ws(data, p + 1)
    }
    first = false
    if p >= data.length() || data[p].to_int() != 34 {
      raise Failure::Failure("object:key@" + p.to_string())
    }
    p = jskip_ws(data, jstring(data, p))
    if p >= data.length() || data[p].to_int() != 58 {
      raise Failure::Failure("object:colon@" + p.to_string())
    }
    p = jskip_ws(data, jvalue(data, p + 1, depth + 1))
    if p >= data.length() {
      raise Failure::Failure("object:eof@" + p.to_string())
    }
    let v = data[p].to_int()
    if v == 125 {
      return p + 1
    }
    if v != 44 {
      raise Failure::Failure("object:sep@" + p.to_string())
    }
  }
  p
}

///|
fn jarray(data : Bytes, pos : Int32, depth : Int32) -> Int32 raise {
  let mut p = jskip_ws(data, pos + 1)
  if p < data.length() && data[p].to_int() == 93 {
    return p + 1
  }
  let mut first = true
  while true {
    if !first {
      if p >= data.length() || data[p].to_int() != 44 {
        raise Failure::Failure("array:comma@" + p.to_string())
      }
      p = jskip_ws(data, p + 1)
    }
    first = false
    p = jskip_ws(data, jvalue(data, p, depth + 1))
    if p >= data.length() {
      raise Failure::Failure("array:eof@" + p.to_string())
    }
    let v = data[p].to_int()
    if v == 93 {
      return p + 1
    }
    if v != 44 {
      raise Failure::Failure("array:sep@" + p.to_string())
    }
  }
  p
}

///|
/// The target's canonical output: `ok:<end>` or `err:<reason>@<pos>`.
pub fn json_validate(input : Bytes) -> String {
  try {
    let end = jvalue(input, 0, 0)
    let p = jskip_ws(input, end)
    if p != input.length() {
      "err:trailing@" + p.to_string()
    } else {
      "ok:" + end.to_string()
    }
  } catch {
    e => "err:" + e.to_string()
  }
}
