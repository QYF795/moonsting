///|
test "rle: a single RLE run decodes to its count" {
  assert_eq(@targets.rle_check(b"\x02\x03"), "ok:1")
  assert_eq(@targets.rle_check(b"\x06\x07"), "ok:3")
  assert_eq(@targets.rle_check(b""), "ok:0")
}

///|
test "rle: a bit-packed run carries groups * 8 values" {
  // header 3 = packed, 1 group; 5 bytes hold 8 values of 5 bits.
  assert_eq(@targets.rle_check(b"\x03\x01\x02\x03\x04\x05"), "ok:8")
}

///|
test "rle: 5-bit unpacking is LSB first and spans bytes" {
  // One group: value 0 = 1, then zeros.
  assert_eq(
    @targets.rle_read_bits(@core.array_of(b"\x01\x00\x00\x00\x00"), 0, 5),
    1,
  )
  assert_eq(
    @targets.rle_read_bits(@core.array_of(b"\x01\x00\x00\x00\x00"), 5, 5),
    0,
  )
  // 0x1f is five ones.
  assert_eq(
    @targets.rle_read_bits(@core.array_of(b"\x1f\x00\x00\x00\x00"), 0, 5),
    31,
  )
  // Value crossing the byte boundary: bits 5..9 of [0xE0, 0x03] = 0b11111.
  assert_eq(
    @targets.rle_read_bits(@core.array_of(b"\xe0\x03\x00\x00\x00"), 5, 5),
    31,
  )
}

///|
test "rle: width discipline is enforced, not just the bytes" {
  // RLE value 0x20 has bits above width 5 set.
  assert_eq(@targets.rle_check(b"\x02\x20"), "err")
  // Packed run claiming one group but carrying two bytes.
  assert_eq(@targets.rle_check(b"\x03\x01\x02"), "err")
  // Count zero is not a run.
  assert_eq(@targets.rle_check(b"\x00\x03"), "err")
  // Non-minimal header varint.
  assert_eq(@targets.rle_check(b"\x80\x00\x03"), "err")
  // Truncated RLE value.
  assert_eq(@targets.rle_check(b"\x02"), "err")
}

///|
test "rle: a run stream can mix both encodings" {
  // RLE(1, value 3) then packed(1 group).
  assert_eq(@targets.rle_check(b"\x02\x03\x03\x01\x02\x03\x04\x05"), "ok:9")
}

///|
/// Found by moonsting itself on 2026-11-18: `count * RLE_WIDTH` overflowed to a
/// negative number, which made the next header offset negative and indexed
/// before the buffer. Isolated mode reported it as `[crash] input=021eefbbffbf256e`.
test "rle: overflow in the run count is rejected, not a crash" {
  let evil = @core.parse_hex("021eefbbffbf256e")
  assert_eq(@targets.rle_check(evil), "err")
  // A count that does not fit the remaining bytes, without overflow.
  let huge = @core.parse_hex("feffffff0f00")
  assert_eq(@targets.rle_check(huge), "err")
  // A well-formed single run still parses.
  assert_true(@targets.rle_check(@core.parse_hex("021e")) != "err")
}
