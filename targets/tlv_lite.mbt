///|
/// Length-prefixed records, with a serialize(parse(x)) == x property.
///
/// Wire format: repeated `[type:1][len:1][payload:len]`, optionally terminated
/// by a `type = 0x00` record whose length must be 0 and which must be the last
/// byte. Every rejection is a defined error, everything accepted must survive a
/// round trip byte for byte — which is what makes truncation and length
/// arithmetic bugs visible.
///
/// Coverage ids for this target live in 700..719.

///|
struct Tlv {
  kind : Int32
  payload : Array[Byte]
}

///|
pub fn tlv_parse(input : Bytes) -> Array[Tlv]? {
  let records : Array[Tlv] = []
  let n = input.length()
  let mut i = 0
  if n == 0 {
    @cov.hit(700)
    return None
  }
  while i < n {
    if i + 2 > n {
      @cov.hit(701)
      return None
    }
    let kind = input[i].to_int()
    let len = input[i + 1].to_int()
    @cov.hit(702)
    if kind == 0 {
      // Terminator: must be empty and must end the message.
      if len != 0 || i + 2 != n {
        @cov.hit(703)
        return None
      }
      @cov.hit(704)
      return Some(records)
    }
    if i + 2 + len > n {
      @cov.hit(705)
      return None
    }
    let payload : Array[Byte] = []
    let mut j = 0
    while j < len {
      payload.push(input[i + 2 + j])
      j = j + 1
    }
    records.push({ kind, payload, })
    @cov.hit(706)
    i = i + 2 + len
  }
  Some(records)
}

///|
pub fn tlv_serialize(records : Array[Tlv]) -> Bytes {
  let out : Array[Byte] = []
  let mut i = 0
  while i < records.length() {
    let record = records[i]
    out.push(record.kind.to_byte())
    out.push(record.payload.length().to_byte())
    let mut j = 0
    while j < record.payload.length() {
      out.push(record.payload[j])
      j = j + 1
    }
    i = i + 1
  }
  Bytes::from_array(out)
}

///|
pub fn tlv_check(input : Bytes) -> String {
  match tlv_parse(input) {
    None => "err"
    Some(records) => {
      let again = tlv_serialize(records)
      let n = again.length()
      let m = input.length()
      // A terminator is dropped by serialize: compare against the prefix.
      let compared = if m == n + 2 { n } else { m }
      if compared != n {
        @cov.hit(710)
        "mismatch:" + @core.hex_all(again)
      } else {
        let mut same = true
        let mut i = 0
        while i < compared {
          if input[i] != again[i] {
            same = false
          }
          i = i + 1
        }
        if same {
          @cov.hit(711)
          "ok:" + records.length().to_string()
        } else {
          @cov.hit(712)
          "mismatch:" + @core.hex_all(again)
        }
      }
    }
  }
}

///|
pub fn tlv_roundtrip_holds(_input : Bytes, output : String) -> String {
  if output.has_prefix("mismatch:") {
    output
  } else {
    ""
  }
}
