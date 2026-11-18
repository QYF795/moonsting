// Protobuf wire-format mutation.
//
// Byte-level havoc on protobuf bytes mostly produces "invalid tag" within the
// first few bytes, so the decoder's interesting paths (length arithmetic, nested
// messages, repeated field handling) are never reached. This module parses the
// top-level field structure and mutates *fields*: duplicate one, drop one, make a
// varint non-minimal, flip a wire type, zero a field number, or damage the last
// byte of a payload.
//
// The parser only walks the top level. Nested messages stay opaque payloads,
// which is enough to exercise length handling without writing a full descriptor
// system.

///|
pub(all) struct ProtoField {
  no : Int32
  wire : Int32
  start : Int32
  end : Int32
}

///|
/// Read a base-128 varint at `pos`. Returns the low 32 bits and the next
/// position; `None` when the input ends or the encoding is longer than 10 bytes.
fn proto_varint(data : Bytes, pos : Int32) -> (Int32, Int32)? {
  let mut value = 0
  let mut shift = 0
  let mut i = pos
  while i < data.length() && shift < 70 {
    let b = data[i].to_int()
    value = value | ((b & 127) << shift)
    i = i + 1
    if b < 128 {
      return Some((value, i))
    }
    shift = shift + 7
  }
  None
}

///|
/// Parse the top-level fields of a protobuf message. `None` when the bytes are
/// not a valid sequence of fields (field number 0, bad wire type, truncated).
pub fn proto_fields(data : Bytes) -> Array[ProtoField]? {
  let out : Array[ProtoField] = []
  let n = data.length()
  let mut i = 0
  while i < n {
    let start = i
    let tag = match proto_varint(data, i) {
      None => return None
      Some(pair) => pair
    }
    let (tag_value, after_tag) = tag
    let field_no = tag_value >> 3
    let wire = tag_value & 7
    if field_no <= 0 {
      return None
    }
    let mut j = after_tag
    if wire == 0 {
      let next = match proto_varint(data, j) {
        None => return None
        Some(pair) => pair
      }
      j = next.1
    } else if wire == 1 {
      j = j + 8
      if j > n {
        return None
      }
    } else if wire == 2 {
      let len = match proto_varint(data, j) {
        None => return None
        Some(pair) => pair
      }
      // Compare before adding: a huge length would overflow `j` to a negative
      // number, and the next parse would index from before the buffer.
      if len.0 < 0 || len.0 > n - len.1 {
        return None
      }
      j = len.1 + len.0
    } else if wire == 5 {
      j = j + 4
      if j > n {
        return None
      }
    } else {
      // Wire types 3/4 (groups) and 6/7 are not supported: treat as not-protobuf.
      return None
    }
    out.push({ no: field_no, wire, start, end: j, })
    i = j
  }
  if out.length() == 0 {
    None
  } else {
    Some(out)
  }
}

///|
/// True when the bytes parse as protobuf with at least two fields. A single
/// field is too weak a signal: plenty of random bytes look like one.
pub fn looks_protobuf(data : Bytes) -> Bool {
  match proto_fields(data) {
    None => false
    Some(fields) =>
      fields.length() >= 2 && fields[fields.length() - 1].end == data.length()
  }
}

///|
fn proto_slice(
  out : Array[Byte],
  data : Bytes,
  from : Int32,
  to : Int32,
) -> Unit {
  let mut i = from
  while i < to && i < data.length() {
    out.push(data[i])
    i = i + 1
  }
}

///|
fn proto_tag_is_single_byte(data : Bytes, pos : Int32) -> Bool {
  match proto_varint(data, pos) {
    None => false
    Some(pair) => pair.1 == pos + 1
  }
}

///|
/// Mutate one field. Returns `None` when the input is not protobuf, so the
/// caller can fall back to generic havoc.
pub fn proto_mutate(rng : @core.Rng, data : Bytes) -> Bytes? {
  let fields = match proto_fields(data) {
    None => return None
    Some(fields) => fields
  }
  if fields.length() == 0 {
    return None
  }
  let pick = fields[rng.below(fields.length())]
  let roll = rng.below(6)
  if roll == 0 {
    // Duplicate a field: repeated-field handling and duplicate-key handling.
    let out : Array[Byte] = []
    proto_slice(out, data, 0, pick.end)
    proto_slice(out, data, pick.start, pick.end)
    proto_slice(out, data, pick.end, data.length())
    Some(Bytes::from_array(out))
  } else if roll == 1 && fields.length() > 1 {
    // Delete a field, which can leave a required field missing.
    let out : Array[Byte] = []
    proto_slice(out, data, 0, pick.start)
    proto_slice(out, data, pick.end, data.length())
    Some(Bytes::from_array(out))
  } else if roll == 2 && pick.wire == 0 {
    // Append `\x80\x00` to a varint payload: same value, non-minimal encoding.
    let out : Array[Byte] = []
    proto_slice(out, data, 0, pick.end)
    out.push(b'\x80')
    out.push(b'\x00')
    proto_slice(out, data, pick.end, data.length())
    Some(Bytes::from_array(out))
  } else if roll == 3 && pick.wire == 2 && pick.end > pick.start + 2 {
    // Damage the last payload byte: contents become invalid for nested readers.
    let out = @core.array_of(data)
    let at = pick.end - 1
    out[at] = (out[at].to_int() ^ 0xff).to_byte()
    Some(@core.bytes_of(out))
  } else if roll == 4 && proto_tag_is_single_byte(data, pick.start) {
    // Flip the wire type in a one-byte tag: structure no longer matches content.
    let out = @core.array_of(data)
    let tag = out[pick.start].to_int()
    let field_bits = tag & 0xf8
    let new_wire = if pick.wire == 0 { 2 } else { 0 }
    out[pick.start] = (field_bits | new_wire).to_byte()
    Some(@core.bytes_of(out))
  } else if roll == 5 &&
    proto_tag_is_single_byte(data, pick.start) &&
    pick.no < 15 {
    // Bump the field number: the decoder sees a field the schema does not have.
    let out = @core.array_of(data)
    let tag = out[pick.start].to_int()
    out[pick.start] = ((tag & 0x07) | (((pick.no + 1) & 0x1f) << 3)).to_byte()
    Some(@core.bytes_of(out))
  } else {
    None
  }
}
