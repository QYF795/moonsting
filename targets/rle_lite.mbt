///|
/// Parquet's hybrid RLE / bit-packing run stream, at a fixed bit width of 5.
///
/// Wire format (a subset of the Parquet spec, fixed width so the arithmetic is
/// readable):
///
///   run    := header payload
///   header := varint
///             LSB 0 -> RLE:        count = header >> 1,  value byte, repeated
///             LSB 1 -> bit-packed: groups = header >> 1, groups * 5 bytes,
///                                  each byte-stream holds groups * 8 values of
///                                  5 bits, LSB first
///
/// Two properties are checked, and they are deliberately different:
///
///   1. **byte round trip** — `serialize(parse(x)) == x`. Catches non-minimal
///      headers, zero counts, truncated payloads, trailing bytes.
///   2. **width discipline** — an RLE value must fit in 5 bits, and a
///      bit-packed run must carry exactly `groups * 5` bytes. A parser that
///      preserved payloads verbatim would satisfy (1) and still accept garbage.
///
/// That second point is the reason this target exists: pure round-tripping can
/// be satisfied by a parser that validates nothing.
///
/// Coverage ids for this target live in 950..979.

///|
const RLE_WIDTH : Int32 = 5

///|
const RLE_VALUE_BYTES : Int32 = 1

///|
struct RleRun {
  packed : Bool
  count : Int32
  bytes : Array[Byte]
}

///|
/// Minimal-varint reader, same rule as the protobuf target: a multi-byte varint
/// must not end with a zero payload byte.
fn rle_varint(input : Bytes, start : Int32) -> (Int64, Int32)? {
  let mut value : Int64 = 0
  let mut shift = 0
  let mut i = start
  let mut bytes = 0
  while i < input.length() {
    if bytes >= 10 {
      @cov.hit(950)
      return None
    }
    let b = input[i].to_int()
    value = value | ((b & 0x7f).to_int64() << shift)
    bytes = bytes + 1
    i = i + 1
    if (b & 0x80) == 0 {
      if bytes > 1 && b == 0 {
        @cov.hit(951)
        return None
      }
      @cov.hit(952)
      return Some((value, i))
    }
    shift = shift + 7
  }
  @cov.hit(953)
  None
}

///|
pub fn rle_parse(input : Bytes) -> Array[RleRun]? {
  let runs : Array[RleRun] = []
  let n = input.length()
  let mut i = 0
  while i < n {
    let header = match rle_varint(input, i) {
      Some(pair) => pair
      None => return None
    }
    let (raw, after_header) = header
    let packed = (raw & 1L) == 1L
    let count = (raw >> 1).to_int()
    if count <= 0 {
      @cov.hit(954)
      return None
    }
    let bytes : Array[Byte] = []
    let mut next = after_header
    if packed {
      let need = count * RLE_WIDTH
      if after_header + need > n {
        @cov.hit(955)
        return None
      }
      let mut k = 0
      while k < need {
        bytes.push(input[after_header + k])
        k = k + 1
      }
      next = after_header + need
      @cov.hit(956)
    } else {
      if after_header + RLE_VALUE_BYTES > n {
        @cov.hit(957)
        return None
      }
      let value = input[after_header].to_int()
      // Canonical width: bits above 5 must be zero.
      if value >> RLE_WIDTH != 0 {
        @cov.hit(958)
        return None
      }
      bytes.push(input[after_header])
      next = after_header + RLE_VALUE_BYTES
      @cov.hit(959)
    }
    runs.push({ packed, count, bytes, })
    i = next
  }
  Some(runs)
}

///|
fn rle_push_varint(out : Array[Byte], value : Int64) -> Unit {
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
pub fn rle_serialize(runs : Array[RleRun]) -> Bytes {
  let out : Array[Byte] = []
  let mut i = 0
  while i < runs.length() {
    let run = runs[i]
    let header = if run.packed {
      (run.count.to_int64() << 1) | 1L
    } else {
      run.count.to_int64() << 1
    }
    rle_push_varint(out, header)
    let mut k = 0
    while k < run.bytes.length() {
      out.push(run.bytes[k])
      k = k + 1
    }
    i = i + 1
  }
  Bytes::from_array(out)
}

///|
/// Number of values the stream decodes to: RLE runs contribute `count`, packed
/// runs contribute `groups * 8`.
pub fn rle_values(runs : Array[RleRun]) -> Int32 {
  let mut total = 0
  let mut i = 0
  while i < runs.length() {
    if runs[i].packed {
      total = total + runs[i].count * 8
    } else {
      total = total + runs[i].count
    }
    i = i + 1
  }
  total
}

///|
/// Read `width` bits at `bit_offset`, LSB first, spanning bytes.
pub fn rle_read_bits(
  bytes : Array[Byte],
  bit_offset : Int32,
  width : Int32,
) -> Int32 {
  let mut value : Int32 = 0
  let mut got = 0
  let mut bit = bit_offset
  while got < width {
    let index = bit / 8
    let inside = bit % 8
    if index >= bytes.length() {
      return -1
    }
    let available = 8 - inside
    let take = if available < width - got { available } else { width - got }
    let chunk = (bytes[index].to_int() >> inside) & ((1 << take) - 1)
    value = value | (chunk << got)
    got = got + take
    bit = bit + take
  }
  value
}

///|
pub fn rle_check(input : Bytes) -> String {
  match rle_parse(input) {
    None => "err"
    Some(runs) => {
      let again = rle_serialize(runs)
      let m = input.length()
      if again.length() != m {
        @cov.hit(960)
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
          @cov.hit(961)
          "ok:" + rle_values(runs).to_string()
        } else {
          @cov.hit(962)
          "mismatch:" + @core.hex_all(again)
        }
      }
    }
  }
}

///|
pub fn rle_roundtrip_holds(_input : Bytes, output : String) -> String {
  if output.has_prefix("mismatch:") {
    output
  } else {
    ""
  }
}
