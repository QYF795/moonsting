// TLV (type-length-value) record mutation.
//
// The `tlv` target's whole point is length arithmetic, and byte-level havoc
// almost never produces a *consistent* record that is wrong in an interesting
// way: it either breaks the first length byte or leaves the structure intact.
// Mutating at the record level is what makes the arithmetic reachable: bump a
// length by one, zero a type (which turns a record into a terminator), duplicate
// a record, truncate a payload, swap two types.
//
// Wire format (see targets/tlv_lite.mbt): repeated `[type:1][len:1][payload:len]`,
// optional `[0x00][0x00]` terminator that must end the message.

///|
pub(all) struct TlvField {
  kind : Int32
  len : Int32
  start : Int32
  end : Int32
}

///|
/// Parse the top-level records. `None` when the bytes are not a well-formed TLV
/// sequence (short header, length past the end, or a terminator that is not last).
pub fn tlv_fields(data : Bytes) -> Array[TlvField]? {
  let out : Array[TlvField] = []
  let n = data.length()
  let mut i = 0
  while i < n {
    if i + 2 > n {
      return None
    }
    let kind = data[i].to_int()
    let len = data[i + 1].to_int()
    if kind == 0 {
      if len != 0 || i + 2 != n {
        return None
      }
      return Some(out)
    }
    if i + 2 + len > n {
      return None
    }
    out.push({ kind, len, start: i, end: i + 2 + len, })
    i = i + 2 + len
  }
  if out.length() == 0 {
    None
  } else {
    Some(out)
  }
}

///|
/// True when the bytes look like TLV *and* at least two records are present.
/// One record is too weak: `[type][len][payload]` is a very common shape.
pub fn looks_tlv(data : Bytes) -> Bool {
  match tlv_fields(data) {
    None => false
    Some(fields) =>
      fields.length() >= 2 ||
      (
        fields.length() == 1 &&
        fields[0].end == data.length() &&
        data.length() >= 3
      )
  }
}

///|
fn tlv_copy(out : Array[Byte], data : Bytes, from : Int32, to : Int32) -> Unit {
  let mut i = from
  while i < to && i < data.length() {
    out.push(data[i])
    i = i + 1
  }
}

///|
pub fn tlv_mutate(rng : @core.Rng, data : Bytes) -> Bytes? {
  let fields = match tlv_fields(data) {
    None => return None
    Some(fields) => fields
  }
  if fields.length() == 0 {
    return None
  }
  let pick = fields[rng.below(fields.length())]
  let roll = rng.below(8)
  if roll == 0 {
    // Duplicate a record.
    let out : Array[Byte] = []
    tlv_copy(out, data, 0, pick.end)
    tlv_copy(out, data, pick.start, pick.end)
    tlv_copy(out, data, pick.end, data.length())
    Some(Bytes::from_array(out))
  } else if roll == 1 && fields.length() > 1 {
    // Drop a record.
    let out : Array[Byte] = []
    tlv_copy(out, data, 0, pick.start)
    tlv_copy(out, data, pick.end, data.length())
    Some(Bytes::from_array(out))
  } else if roll == 2 {
    // Off-by-one on the length: the classic bug this format invites.
    let out = @core.array_of(data)
    let at = pick.start + 1
    let bumped = (out[at].to_int() + 1) % 256
    out[at] = bumped.to_byte()
    Some(@core.bytes_of(out))
  } else if roll == 3 {
    // Truncate the payload by one byte, leaving the length prefix too large.
    if pick.len > 0 {
      let out : Array[Byte] = []
      tlv_copy(out, data, 0, pick.end - 1)
      tlv_copy(out, data, pick.end, data.length())
      Some(Bytes::from_array(out))
    } else {
      None
    }
  } else if roll == 4 {
    // Zero the type: a normal record becomes a terminator, which must be last.
    let out = @core.array_of(data)
    out[pick.start] = b'\x00'
    Some(@core.bytes_of(out))
  } else if roll == 5 {
    // Set the length to the maximum one-byte value.
    let out = @core.array_of(data)
    out[pick.start + 1] = b'\xff'
    Some(@core.bytes_of(out))
  } else if roll == 6 && fields.length() > 1 {
    // Swap the types of two records: the payloads no longer match their kind.
    let other = fields[rng.below(fields.length())]
    let out = @core.array_of(data)
    let a = out[pick.start]
    out[pick.start] = out[other.start]
    out[other.start] = a
    Some(@core.bytes_of(out))
  } else if roll == 7 {
    // Append a terminator, which is legal only at the very end.
    let out = @core.array_of(data)
    out.push(b'\x00')
    out.push(b'\x00')
    Some(@core.bytes_of(out))
  } else {
    None
  }
}
