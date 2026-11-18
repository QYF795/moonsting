///|
test "proto: top-level fields parse" {
  // field 1, varint 150
  let fields = @mutate.proto_fields(b"\x08\x96\x01").unwrap()
  assert_eq(fields.length(), 1)
  assert_eq(fields[0].no, 1)
  assert_eq(fields[0].wire, 0)
  assert_eq(fields[0].start, 0)
  assert_eq(fields[0].end, 3)
}

///|
test "proto: a len-delimited field parses" {
  // field 2 (0x12), length 3, "abc"
  let fields = @mutate.proto_fields(b"\x12\x03abc").unwrap()
  assert_eq(fields.length(), 1)
  assert_eq(fields[0].wire, 2)
  assert_eq(fields[0].end, 5)
}

///|
test "proto: invalid structures are rejected" {
  // field number 0
  assert_true(@mutate.proto_fields(b"\x00\x01") is None)
  // truncated length
  assert_true(@mutate.proto_fields(b"\x12\x05ab") is None)
  // wire type 3 (group) is not supported
  assert_true(@mutate.proto_fields(b"\x0b\x00") is None)
  // empty input
  assert_true(@mutate.proto_fields(b"") is None)
}

///|
test "proto: detection needs more than one field" {
  assert_true(@mutate.looks_protobuf(b"\x08\x01\x10\x02"))
  assert_true(!@mutate.looks_protobuf(b"\x08\x01"))
  assert_true(!@mutate.looks_protobuf(b"ab"))
  assert_eq(@mutate.detect(b"\x08\x01\x10\x02").label(), "protobuf")
}

///|
test "proto: mutations stay in the field language most of the time" {
  let rng = @core.Rng::new(17)
  let seed = b"\x08\x96\x01\x12\x03abc\x1d\x01\x00\x00\x00"
  let mut parsed = 0
  let mut changed = 0
  let mut i = 0
  while i < 200 {
    match @mutate.proto_mutate(rng, seed) {
      None => ()
      Some(out) => {
        if out != seed {
          changed = changed + 1
        }
        if @mutate.proto_fields(out) is Some(_) {
          parsed = parsed + 1
        }
      }
    }
    i = i + 1
  }
  // Every mutation must change the bytes; most should still be field-shaped,
  // which is the point of mutating at the field level rather than the byte level.
  assert_true(changed >= 150)
  assert_true(parsed * 2 >= changed)
}

///|
test "proto: a non-minimal varint is produced sometimes" {
  let rng = @core.Rng::new(5)
  let seed = b"\x08\x96\x01\x10\x02"
  let mut saw = false
  let mut i = 0
  while i < 200 {
    match @mutate.proto_mutate(rng, seed) {
      None => ()
      Some(out) =>
        if out.length() == seed.length() + 2 && out[3].to_int() == 0x80 {
          saw = true
        }
    }
    i = i + 1
  }
  assert_true(saw)
}
