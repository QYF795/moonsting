///|
/// Java-style properties: `serialize(parse(x)) == x` with a canonical form.
///
/// The format is small but the escaping is not: a key may not contain `=`, and
/// both `\n` and the escape character itself have to survive a round trip. That
/// makes it a good counterweight to CSV — the same property, a completely
/// different failure mode.
///
/// Canonical form (strict, so the round trip is meaningful):
///
///     key=value\n
///
/// Escapes: `\\`, `\n`, `\=`, `\ `. Leading and trailing spaces in a value are
/// escaped rather than trimmed.
///
/// Coverage ids for this target live in 650..678.

///|
struct PropEntry {
  key : Bytes
  value : Bytes
}

///|
fn prop_unescape(data : Bytes, start : Int32, end : Int32) -> Bytes? {
  let out : Array[Byte] = []
  let mut i = start
  while i < end {
    let v = data[i].to_int()
    if v == 92 {
      if i + 1 >= end {
        @cov.hit(650)
        return None
      }
      let next = data[i + 1].to_int()
      if next == 92 {
        out.push(b'\\')
      } else if next == 110 {
        out.push(b'\n')
      } else if next == 61 {
        out.push(b'=')
      } else if next == 32 {
        out.push(b' ')
      } else {
        @cov.hit(651)
        return None
      }
      i = i + 2
    } else {
      out.push(data[i])
      i = i + 1
    }
  }
  Some(Bytes::from_array(out))
}

///|
pub fn prop_parse(input : Bytes) -> Array[PropEntry]? {
  let entries : Array[PropEntry] = []
  let n = input.length()
  let mut i = 0
  while i < n {
    let start = i
    while i < n && input[i].to_int() != 10 {
      i = i + 1
    }
    let end = i
    if i < n {
      i = i + 1
    }
    if end == start {
      // Blank line: not canonical.
      @cov.hit(652)
      return None
    }
    // The separator is the first unescaped `=`.
    let mut eq = -1
    let mut k = start
    while k < end {
      let v = input[k].to_int()
      if v == 92 {
        k = k + 2
      } else if v == 61 {
        eq = k
        break
      } else {
        k = k + 1
      }
    }
    if eq <= start {
      @cov.hit(653)
      return None
    }
    // Spaces must be escaped everywhere, otherwise the canonical form would
    // differ from the input.
    let mut sp = start
    while sp < eq {
      let v = input[sp].to_int()
      if v == 92 {
        sp = sp + 2
      } else if v == 32 {
        @cov.hit(657)
        return None
      } else {
        sp = sp + 1
      }
    }
    let key = match prop_unescape(input, start, eq) {
      None => return None
      Some(v) => v
    }
    if key.length() == 0 {
      @cov.hit(654)
      return None
    }
    // An unescaped `=` in the value would be re-emitted as `\=`, so reject it.
    let mut p = eq + 1
    while p < end {
      let v = input[p].to_int()
      if v == 92 {
        p = p + 2
      } else if v == 61 {
        @cov.hit(656)
        return None
      } else if v == 32 {
        @cov.hit(658)
        return None
      } else {
        p = p + 1
      }
    }
    let value = match prop_unescape(input, eq + 1, end) {
      None => return None
      Some(v) => v
    }
    entries.push({ key, value, })
    @cov.hit(655)
  }
  Some(entries)
}

///|
fn prop_escape(out : Array[Byte], data : Bytes, _is_key : Bool) -> Unit {
  let mut i = 0
  while i < data.length() {
    let v = data[i].to_int()
    if v == 92 {
      out.push(b'\\')
      out.push(b'\\')
    } else if v == 10 {
      out.push(b'\\')
      out.push(b'n')
    } else if v == 61 {
      out.push(b'\\')
      out.push(b'=')
    } else if v == 32 {
      out.push(b'\\')
      out.push(b' ')
    } else {
      out.push(data[i])
    }
    i = i + 1
  }
}

///|
pub fn prop_serialize(entries : Array[PropEntry]) -> Bytes {
  let out : Array[Byte] = []
  let mut i = 0
  while i < entries.length() {
    prop_escape(out, entries[i].key, true)
    out.push(b'=')
    prop_escape(out, entries[i].value, false)
    out.push(b'\n')
    i = i + 1
  }
  Bytes::from_array(out)
}

///|
fn prop_same(input : Bytes, canonical : Bytes, len : Int32) -> Bool {
  let mut i = 0
  while i < len {
    if input[i] != canonical[i] {
      return false
    }
    i = i + 1
  }
  true
}

///|
pub fn prop_check(input : Bytes) -> String {
  match prop_parse(input) {
    None => "err"
    Some(entries) => {
      let again = prop_serialize(entries)
      let m = input.length()
      let mut same = false
      if again.length() == m {
        same = prop_same(input, again, m)
      } else if again.length() == m + 1 && again[m].to_int() == 10 {
        same = prop_same(input, again, m)
      }
      if same {
        @cov.hit(670)
        "ok:" + entries.length().to_string()
      } else {
        @cov.hit(671)
        "roundtrip:" + @core.hex_all(again)
      }
    }
  }
}

///|
pub fn prop_roundtrip_holds(_input : Bytes, output : String) -> String {
  if output.has_prefix("roundtrip:") {
    output
  } else {
    ""
  }
}
