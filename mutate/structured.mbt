// Structure-aware mutation.
//
// Byte-level havoc is undirected: it finds a `{` and breaks the document, and
// everything past that is a syntax-error test. Structure-aware mutation keeps
// the document legal and moves the fight into the semantic layer — which is
// where the bugs that matter live (wrong values, wrong counts, wrong lengths).
//
// The dispatch is by *shape of the input*, not by target name: a mutator has no
// idea which target it is feeding. Sniffing is cheap and deliberately naive;
// guessing wrong costs one round of ordinary havoc.

///|
pub(all) enum Shape {
  Json
  Base64
  Urlenc
  Protobuf
  Csv
  Binary
}

///|
/// First significant byte decides JSON; otherwise the alphabet decides.
pub fn detect(data : Bytes) -> Shape {
  let start = first_non_ws(data)
  if start < data.length() {
    let v = data[start].to_int()
    if v == 123 || v == 91 || v == 34 || v == 45 || (v >= 48 && v <= 57) {
      return Shape::Json
    }
  }
  let mut b64_only = data.length() > 0
  let mut has_pct = false
  let mut i = 0
  while i < data.length() {
    let v = data[i].to_int()
    if v == 37 {
      has_pct = true
    }
    if !(is_b64_char(v) || v == 61) {
      b64_only = false
    }
    i = i + 1
  }
  if has_pct && url_ok(data) {
    Shape::Urlenc
  } else if b64_only {
    Shape::Base64
  } else if looks_protobuf(data) {
    Shape::Protobuf
  } else if looks_like_csv(data) {
    Shape::Csv
  } else {
    Shape::Binary
  }
}

///|
fn looks_like_csv(data : Bytes) -> Bool {
  let mut saw_separator = false
  let mut i = 0
  while i < data.length() {
    let v = data[i].to_int()
    if v == 44 || v == 10 {
      saw_separator = true
    } else if v < 32 && v != 13 && v != 9 {
      return false
    }
    i = i + 1
  }
  saw_separator
}

///|
fn take_from(rng : @core.Rng, dict : Dictionary) -> Bytes {
  let tokens = dict.tokens()
  if tokens.length() == 0 {
    b"x"
  } else {
    tokens[rng.below(tokens.length())]
  }
}

///|
pub fn Shape::label(self : Shape) -> String {
  match self {
    Shape::Json => "json"
    Shape::Base64 => "base64"
    Shape::Urlenc => "urlenc"
    Shape::Protobuf => "protobuf"
    Shape::Csv => "csv"
    Shape::Binary => "binary"
  }
}

///|
fn first_non_ws(data : Bytes) -> Int32 {
  let mut i = 0
  while i < data.length() {
    let v = data[i].to_int()
    if v != 32 && v != 9 && v != 10 && v != 13 {
      return i
    }
    i = i + 1
  }
  data.length()
}

///|
fn is_b64_char(v : Int32) -> Bool {
  (v >= 65 && v <= 90) ||
  (v >= 97 && v <= 122) ||
  (v >= 48 && v <= 57) ||
  v == 43 ||
  v == 47
}

///|
fn url_ok(data : Bytes) -> Bool {
  let mut i = 0
  while i < data.length() {
    let v = data[i].to_int()
    if v == 37 {
      if i + 2 >= data.length() {
        return false
      }
      i = i + 3
    } else if (v >= 65 && v <= 90) ||
      (v >= 97 && v <= 122) ||
      (v >= 48 && v <= 57) ||
      v == 45 ||
      v == 46 ||
      v == 95 ||
      v == 126 {
      i = i + 1
    } else {
      return false
    }
  }
  true
}

///|
/// A token of a JSON document, by byte range. `kind`: 0 string, 1 number,
/// 2 literal, 3 punctuation.
priv struct Token {
  start : Int32
  end : Int32
  kind : Int32
}

///|
fn json_tokens(data : Bytes) -> Array[Token] {
  let out : Array[Token] = []
  let mut i = 0
  while i < data.length() {
    let v = data[i].to_int()
    if v == 32 || v == 9 || v == 10 || v == 13 {
      i = i + 1
    } else if v == 34 {
      let start = i
      i = i + 1
      let mut closed = false
      while i < data.length() && !closed {
        let b = data[i].to_int()
        if b == 92 {
          i = i + 2
        } else if b == 34 {
          closed = true
          i = i + 1
        } else {
          i = i + 1
        }
      }
      out.push({ start, end: i, kind: 0, })
    } else if v == 45 || (v >= 48 && v <= 57) {
      let start = i
      while i < data.length() {
        let b = data[i].to_int()
        if (b >= 48 && b <= 57) ||
          b == 45 ||
          b == 43 ||
          b == 46 ||
          b == 101 ||
          b == 69 {
          i = i + 1
        } else {
          break
        }
      }
      out.push({ start, end: i, kind: 1, })
    } else if (v >= 97 && v <= 122) || (v >= 65 && v <= 90) {
      let start = i
      while i < data.length() {
        let b = data[i].to_int()
        if (b >= 97 && b <= 122) || (b >= 65 && b <= 90) {
          i = i + 1
        } else {
          break
        }
      }
      out.push({ start, end: i, kind: 2, })
    } else {
      out.push({ start: i, end: i + 1, kind: 3, })
      i = i + 1
    }
  }
  out
}

///|
fn splice(out : Array[Byte], from : Bytes, start : Int32, end : Int32) -> Unit {
  let mut i = start
  while i < end && i < from.length() {
    out.push(from[i])
    i = i + 1
  }
}

///|
fn replace_range(
  data : Bytes,
  start : Int32,
  end : Int32,
  with_ : Bytes,
) -> Bytes {
  let out : Array[Byte] = []
  splice(out, data, 0, start)
  splice(out, with_, 0, with_.length())
  splice(out, data, end, data.length())
  Bytes::from_array(out)
}

///|
fn number_replacement(rng : @core.Rng) -> Bytes {
  let options : Array[Bytes] = [
    b"0", b"-0", b"1", b"-1", b"2147483647", b"-2147483648", b"4294967295", b"9223372036854775807",
    b"1e308", b"1e-308", b"0.0", b"1e999", b"-1e999",
  ]
  options[rng.below(options.length())]
}

///|
/// Mutate a JSON document while keeping it parseable in most cases:
/// replace a number, rewrite a string body, duplicate a token, or delete one.
pub fn json_mutate(
  rng : @core.Rng,
  data : Bytes,
  dict : Dictionary,
  max_len : Int32,
) -> Bytes {
  let tokens = json_tokens(data)
  if tokens.length() == 0 {
    return b"{}"
  }
  let pick = tokens[rng.below(tokens.length())]
  let roll = rng.below(10)
  if roll < 4 && pick.kind == 1 {
    replace_range(data, pick.start, pick.end, number_replacement(rng))
  } else if roll < 6 && pick.kind == 0 {
    // Rewrite the string body, keeping the quotes and escaping what needs it.
    let token = take_from(rng, dict)
    let escaped = escape_into_quotes(token)
    replace_range(data, pick.start + 1, pick.end - 1, escaped)
  } else if roll < 8 {
    // Duplicate a whole member or element, not a bare token: `{"a":1}` becomes
    // `{"a":1,"a":1}`, never `{"a":1,1}`.
    match member_span(data, tokens, pick) {
      None => data
      Some(span) => {
        let (from, to) = span
        if data.length() + (to - from) + 1 < max_len {
          let out : Array[Byte] = []
          splice(out, data, 0, to)
          out.push(b',')
          splice(out, data, from, to)
          splice(out, data, to, data.length())
          Bytes::from_array(out)
        } else {
          data
        }
      }
    }
    // Delete a member: a value together with its key and one separator, so the
    // document stays legal. Deleting only the value leaves `{"a":}` behind.
  } else if tokens.length() <= 1 || pick.kind == 3 {
    data
  } else {
    let mut k = 0
    while k < tokens.length() {
      if tokens[k].start == pick.start && tokens[k].end == pick.end {
        break
      }
      k = k + 1
    }
    let mut start = pick.start
    let mut end = pick.end
    // `"key": value` — if the picked token is the value, include its key.
    if k >= 2 && is_punct(data, tokens[k - 1], 58) && tokens[k - 2].kind == 0 {
      start = tokens[k - 2].start
    } else if k + 2 < tokens.length() && is_punct(data, tokens[k + 1], 58) {
      // The picked token is the key: include the colon and the value.
      end = tokens[k + 2].end
    }
    // Prefer eating the following comma.
    let mut next = end
    while next < data.length() && data[next].to_int() == 44 {
      next = next + 1
    }
    if next > end {
      end = next
    } else {
      // Last member: eat the preceding comma instead.
      let mut back = start
      while back > 0 && is_space(data[back - 1].to_int()) {
        back = back - 1
      }
      if back > 0 && data[back - 1].to_int() == 44 {
        start = back - 1
      }
    }
    replace_range(data, start, end, b"")
  }
}

///|
fn is_punct(data : Bytes, token : Token, ch : Int32) -> Bool {
  token.kind == 3 &&
  token.end == token.start + 1 &&
  data[token.start].to_int() == ch
}

///|
fn is_space(v : Int32) -> Bool {
  v == 32 || v == 10 || v == 9 || v == 13
}

///|
fn escape_into_quotes(token : Bytes) -> Bytes {
  let out : Array[Byte] = []
  let mut i = 0
  while i < token.length() {
    let v = token[i].to_int()
    if v == 34 || v == 92 || v < 32 {
      out.push(b'\\')
      out.push(if v == 34 || v == 92 { v.to_byte() } else { b'n' })
    } else {
      out.push(token[i])
    }
    i = i + 1
  }
  Bytes::from_array(out)
}

///|
/// Rewrite one base64 character, flip its case, or touch the padding. Case and
/// padding are exactly where "decodes fine, re-encodes differently" lives.
pub fn base64_mutate(rng : @core.Rng, data : Bytes) -> Bytes {
  if data.length() == 0 {
    return b"AAAA"
  }
  let out = @core.array_of(data)
  let at = rng.below(out.length())
  let v = out[at].to_int()
  let roll = rng.below(10)
  if roll < 5 {
    let alphabet : Array[Byte] = [
      b'A', b'B', b'C', b'Z', b'a', b'b', b'z', b'0', b'9', b'+', b'/', b'=',
    ]
    out[at] = alphabet[rng.below(alphabet.length())]
  } else if roll < 8 && ((v >= 65 && v <= 90) || (v >= 97 && v <= 122)) {
    out[at] = if v >= 97 { (v - 32).to_byte() } else { (v + 32).to_byte() }
  } else if v == 61 {
    ignore(out.remove(at))
  } else {
    out.insert(at, b'=')
  }
  @core.bytes_of(out)
}

///|
/// Percent-encoding mutations that matter: lowercase a hex digit, decode an
/// escape back into a literal, or add an escape for an unreserved byte.
pub fn urlenc_mutate(rng : @core.Rng, data : Bytes) -> Bytes {
  if data.length() == 0 {
    return b"%41"
  }
  let out = @core.array_of(data)
  let at = rng.below(out.length())
  let v = out[at].to_int()
  let roll = rng.below(10)
  if roll < 4 && v == 37 && at + 2 < out.length() {
    let hex = out[at + 1].to_int()
    if hex >= 65 && hex <= 70 {
      out[at + 1] = (hex + 32).to_byte()
    } else {
      out[at + 1] = b'G'
    }
  } else if roll < 7 {
    out.insert(at, b'%')
    out.insert(at + 1, b'4')
    out.insert(at + 2, b'1')
  } else {
    out.insert(at, b'%')
  }
  @core.bytes_of(out)
}

///|
/// The generic length poke: change one byte by ±1. This is the classic
/// off-by-one trigger for length-prefixed formats (TLV, RLE, protobuf), and it
/// needs no parser.
pub fn length_mutate(rng : @core.Rng, data : Bytes) -> Bytes {
  if data.length() == 0 {
    return b"\x01\x00"
  }
  let out = @core.array_of(data)
  let at = rng.below(out.length())
  let v = out[at].to_int()
  if rng.next_bool() {
    out[at] = ((v + 1) % 256).to_byte()
  } else {
    out[at] = ((v + 255) % 256).to_byte()
  }
  @core.bytes_of(out)
}

///|
/// The byte range to duplicate for `pick`: the whole `"key": value` pair when
/// the token is an object value or key, or the bare value when it is an array
/// element. `None` when the token is punctuation or we cannot tell.
fn member_span(
  data : Bytes,
  tokens : Array[Token],
  pick : Token,
) -> (Int32, Int32)? {
  let mut k = 0
  while k < tokens.length() {
    if tokens[k].start == pick.start && tokens[k].end == pick.end {
      break
    }
    k = k + 1
  }
  if k >= tokens.length() || pick.kind == 3 {
    return None
  }
  if k >= 2 && is_punct(data, tokens[k - 1], 58) && tokens[k - 2].kind == 0 {
    return Some((tokens[k - 2].start, pick.end))
  }
  if k + 2 < tokens.length() && is_punct(data, tokens[k + 1], 58) {
    return Some((pick.start, tokens[k + 2].end))
  }
  Some((pick.start, pick.end))
}
