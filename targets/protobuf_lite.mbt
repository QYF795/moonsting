///|
/// Protobuf wire format, with `serialize(parse(x)) == x`.
///
/// The parser is deliberately canonical: it rejects varints that are not
/// minimally encoded, a field number of zero, group wire types (3/4), and any
/// wire type outside {0,1,2,5}. Those rules are exactly what makes the round
/// trip meaningful — a parser that accepts `0x80 0x00` for zero would "parse
/// fine" and then re-emit `0x00`, and the mismatch is the finding.
///
/// The output keeps fields in wire order and preserves each payload verbatim,
/// so the comparison is byte equality and not a semantic one. That is on
/// purpose: canonical-form bugs are what round trips are for.
///
/// Coverage ids for this target live in 920..949.

///|
struct PbField {
  number : Int32
  wire : Int32
  payload : Array[Byte]
}

///|
/// Read a varint, rejecting non-minimal encodings. Returns `(value, next)` or
/// `None` on a malformed one.
pub fn pb_varint(input : Bytes, start : Int32) -> (Int64, Int32)? {
  let mut value : Int64 = 0
  let mut shift = 0
  let mut i = start
  let mut bytes = 0
  while i < input.length() {
    if bytes >= 10 {
      @cov.hit(920)
      return None
    }
    let b = input[i].to_int()
    value = value | ((b & 0x7f).to_int64() << shift)
    bytes = bytes + 1
    i = i + 1
    if (b & 0x80) == 0 {
      // Minimality: a multi-byte varint must not end with a zero payload byte.
      if bytes > 1 && b == 0 {
        @cov.hit(921)
        return None
      }
      @cov.hit(922)
      return Some((value, i))
    }
    shift = shift + 7
  }
  @cov.hit(923)
  None
}

///|
pub fn pb_parse(input : Bytes) -> Array[PbField]? {
  let fields : Array[PbField] = []
  let n = input.length()
  let mut i = 0
  while i < n {
    let key = match pb_varint(input, i) {
      Some(pair) => pair
      None => return None
    }
    let (key_value, after_key) = key
    let number = (key_value >> 3).to_int()
    let wire = (key_value & 7L).to_int()
    if number < 1 || number > 536870911 {
      @cov.hit(924)
      return None
    }
    if wire != 0 && wire != 1 && wire != 2 && wire != 5 {
      @cov.hit(925)
      return None
    }
    @cov.hit(926)
    let payload : Array[Byte] = []
    let mut next = after_key
    if wire == 0 {
      let value = match pb_varint(input, next) {
        Some(pair) => pair
        None => return None
      }
      let (_v, after) = value
      let mut k = next
      while k < after {
        payload.push(input[k])
        k = k + 1
      }
      next = after
      @cov.hit(927)
    } else if wire == 1 {
      if next + 8 > n {
        @cov.hit(928)
        return None
      }
      let mut k = 0
      while k < 8 {
        payload.push(input[next + k])
        k = k + 1
      }
      next = next + 8
      @cov.hit(929)
    } else if wire == 5 {
      if next + 4 > n {
        @cov.hit(930)
        return None
      }
      let mut k = 0
      while k < 4 {
        payload.push(input[next + k])
        k = k + 1
      }
      next = next + 4
      @cov.hit(931)
    } else {
      let length = match pb_varint(input, next) {
        Some(pair) => pair
        None => return None
      }
      let (length_value, after_length) = length
      if length_value < 0L || length_value > 2147483647L {
        @cov.hit(932)
        return None
      }
      let len = length_value.to_int()
      if after_length + len > n {
        @cov.hit(933)
        return None
      }
      let mut k = 0
      while k < len {
        payload.push(input[after_length + k])
        k = k + 1
      }
      next = after_length + len
      @cov.hit(934)
    }
    fields.push({ number, wire, payload, })
    i = next
  }
  Some(fields)
}

///|
fn pb_push_varint(out : Array[Byte], value : Int64) -> Unit {
  let mut v = value
  let mut more = true
  while more {
    let low = (v & 0x7fL).to_int()
    v = v >> 7
    if v == 0L {
      out.push(low.to_byte())
      more = false
    } else {
      out.push((low | 0x80).to_byte())
    }
  }
}

///|
pub fn pb_serialize(fields : Array[PbField]) -> Bytes {
  let out : Array[Byte] = []
  let mut i = 0
  while i < fields.length() {
    let field = fields[i]
    let key = (field.number.to_int64() << 3) | field.wire.to_int64()
    pb_push_varint(out, key)
    if field.wire == 2 {
      pb_push_varint(out, field.payload.length().to_int64())
    }
    let mut k = 0
    while k < field.payload.length() {
      out.push(field.payload[k])
      k = k + 1
    }
    i = i + 1
  }
  Bytes::from_array(out)
}

///|
pub fn pb_check(input : Bytes) -> String {
  match pb_parse(input) {
    None => "err"
    Some(fields) => {
      let again = pb_serialize(fields)
      let m = input.length()
      if again.length() != m {
        @cov.hit(940)
        "mismatch:" + @core.hex_all(again)
      } else {
        let mut same = true
        let mut i = 0
        while i < m {
          if input[i] != again[i] {
            same = false
          }
          i = i + 1
        }
        if same {
          @cov.hit(941)
          "ok:" + fields.length().to_string()
        } else {
          @cov.hit(942)
          "mismatch:" + @core.hex_all(again)
        }
      }
    }
  }
}

///|
pub fn pb_roundtrip_holds(_input : Bytes, output : String) -> String {
  if output.has_prefix("mismatch:") {
    output
  } else {
    ""
  }
}
