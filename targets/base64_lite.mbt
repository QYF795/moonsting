///|
/// Base64 with a round-trip property.
///
/// The invariant: for any input the decoder accepts, re-encoding the decoded
/// bytes must reproduce the input exactly. That single sentence catches the
/// whole family of "accepted but not canonical" bugs — padding that is skipped,
/// trailing bits that are not zero, alphabets that are mixed — without needing a
/// second implementation to compare against.
///
/// Coverage ids for this target live in 600..619.

///|
fn b64_index(c : Int32) -> Int32 {
  if c >= 65 && c <= 90 {
    c - 65
  } else if c >= 97 && c <= 122 {
    c - 71
  } else if c >= 48 && c <= 57 {
    c + 4
  } else if c == 43 {
    62
  } else if c == 47 {
    63
  } else {
    -1
  }
}

///|
fn b64_char(v : Int32) -> Byte {
  if v < 26 {
    (65 + v).to_byte()
  } else if v < 52 {
    (97 + v - 26).to_byte()
  } else if v < 62 {
    (48 + v - 52).to_byte()
  } else if v == 62 {
    b'+'
  } else {
    b'/'
  }
}

///|
/// Strict RFC 4648 decode. Returns `None` for anything that is not a complete,
/// correctly padded quantum.
pub fn b64_decode(input : Bytes) -> Array[Byte]? {
  let n = input.length()
  if n == 0 || n % 4 != 0 {
    @cov.hit(600)
    return None
  }
  let mut pad = 0
  if input[n - 1].to_int() == 61 {
    pad = 1
    if n > 1 && input[n - 2].to_int() == 61 {
      pad = 2
    }
  }
  let data_len = n - pad
  let out : Array[Byte] = []
  let mut acc : Int32 = 0
  let mut bits : Int32 = 0
  let mut i = 0
  while i < data_len {
    let v = b64_index(input[i].to_int())
    if v < 0 {
      @cov.hit(601)
      return None
    }
    acc = ((acc << 6) | v) & 0xffffff
    bits = bits + 6
    if bits >= 8 {
      bits = bits - 8
      out.push(((acc >> bits) & 0xff).to_byte())
    }
    i = i + 1
  }
  // Anything left in `bits` that is not exactly zero means the encoding was not
  // canonical, and re-encoding would not reproduce the input.
  if bits > 0 && (acc & ((1 << bits) - 1)) != 0 {
    @cov.hit(602)
    return None
  }
  if out.length() != n / 4 * 3 - pad {
    @cov.hit(603)
    return None
  }
  Some(out)
}

///|
pub fn b64_encode(data : Array[Byte]) -> Bytes {
  let out : Array[Byte] = []
  let mut i = 0
  while i < data.length() {
    let b0 = data[i].to_int()
    let has1 = i + 1 < data.length()
    let has2 = i + 2 < data.length()
    let b1 = if has1 { data[i + 1].to_int() } else { 0 }
    let b2 = if has2 { data[i + 2].to_int() } else { 0 }
    out.push(b64_char(b0 >> 2))
    out.push(b64_char(((b0 & 0x03) << 4) | (b1 >> 4)))
    if has1 {
      out.push(b64_char(((b1 & 0x0f) << 2) | (b2 >> 6)))
    } else {
      out.push(b'=')
    }
    if has2 {
      out.push(b64_char(b2 & 0x3f))
    } else {
      out.push(b'=')
    }
    i = i + 3
  }
  Bytes::from_array(out)
}

///|
fn b64_text(data : Array[Byte]) -> String {
  let sb = StringBuilder()
  let mut i = 0
  while i < data.length() {
    sb.write_char(data[i].to_char())
    i = i + 1
  }
  sb.to_string()
}

///|
/// `ok:<canonical>` when the round trip holds, `err` when the input is not
/// base64, and `roundtrip:<re-encoding>` when the decoder accepted something it
/// should not have.
pub fn b64_check(input : Bytes) -> String {
  match b64_decode(input) {
    None => "err"
    Some(data) => {
      let again = b64_encode(data)
      if again.length() == input.length() {
        let mut same = true
        let mut i = 0
        while i < input.length() {
          if input[i] != again[i] {
            same = false
          }
          i = i + 1
        }
        if same {
          @cov.hit(610)
          "ok:" + b64_text(data)
        } else {
          @cov.hit(611)
          "roundtrip:" + b64_text(@core.array_of(again))
        }
      } else {
        @cov.hit(612)
        "roundtrip:" + b64_text(@core.array_of(again))
      }
    }
  }
}

///|
pub fn b64_roundtrip_holds(_input : Bytes, output : String) -> String {
  if output.has_prefix("roundtrip:") {
    output
  } else {
    ""
  }
}
