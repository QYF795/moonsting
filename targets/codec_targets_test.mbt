///|
test "urlenc: canonical forms round trip" {
  assert_eq(@targets.url_check(b"abc"), "ok:3")
  assert_eq(@targets.url_check(b"a%20b"), "ok:3")
  assert_eq(@targets.url_check(b"%E4%B8%AD"), "ok:3")
  assert_eq(@targets.url_check(b"~-._"), "ok:4")
  assert_eq(@targets.url_check(b""), "ok:0")
}

///|
test "urlenc: non-canonical input is rejected, not silently fixed" {
  // %41 is 'A' — unreserved bytes must be literal.
  assert_eq(@targets.url_check(b"%41"), "err")
  // Lowercase hex is not the canonical form.
  assert_eq(@targets.url_check(b"%2f"), "err")
  // A reserved byte must be encoded.
  assert_eq(@targets.url_check(b"a/b"), "err")
  assert_eq(@targets.url_check(b"a b"), "err")
  // Truncated or bad escape.
  assert_eq(@targets.url_check(b"%2"), "err")
  assert_eq(@targets.url_check(b"%zz"), "err")
  assert_eq(@targets.url_check(b"%"), "err")
}

///|
test "protobuf: canonical wire data round trips" {
  assert_eq(@targets.pb_check(b"\x08\x01"), "ok:1")
  assert_eq(@targets.pb_check(b"\x12\x02hi"), "ok:1")
  assert_eq(@targets.pb_check(b"\x08\x96\x01"), "ok:1")
  assert_eq(@targets.pb_check(b"\x1d\x01\x02\x03\x04"), "ok:1")
  assert_eq(@targets.pb_check(b""), "ok:0")
}

///|
test "protobuf: non-minimal varints and bad keys are rejected" {
  // 0x80 0x00 is a two-byte encoding of zero: not minimal.
  assert_eq(@targets.pb_check(b"\x08\x80\x00"), "err")
  assert_eq(@targets.pb_check(b"\x80\x00"), "err")
  // Field number zero is illegal.
  assert_eq(@targets.pb_check(b"\x00\x01"), "err")
  // Wire type 3 (group) is not supported.
  assert_eq(@targets.pb_check(b"\x0b"), "err")
  // Truncated length-delimited payload.
  assert_eq(@targets.pb_check(b"\x12\x05hi"), "err")
  // Truncated key.
  assert_eq(@targets.pb_check(b"\x80"), "err")
}

///|
test "protobuf: varint decoding is exact at the boundaries" {
  assert_eq(@targets.pb_varint(b"\x00", 0).unwrap().0, 0L)
  assert_eq(@targets.pb_varint(b"\x7f", 0).unwrap().0, 127L)
  assert_eq(@targets.pb_varint(b"\x80\x01", 0).unwrap().0, 128L)
  assert_eq(
    @targets.pb_varint(b"\xff\xff\xff\xff\x0f", 0).unwrap().0,
    4294967295L,
  )
  assert_true(@targets.pb_varint(b"\x80", 0) is None)
}
