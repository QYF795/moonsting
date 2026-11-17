///|
test "base64: accepts canonical encodings" {
  assert_true(@targets.b64_check(b"AA==").has_prefix("ok:"))
  assert_true(@targets.b64_check(b"AAA=").has_prefix("ok:"))
  assert_true(@targets.b64_check(b"AAAA").has_prefix("ok:"))
  assert_true(@targets.b64_check(b"Zm9v").has_prefix("ok:"))
  assert_eq(@targets.b64_check(b""), "err")
}

///|
test "base64: rejects non-canonical input instead of silently fixing it" {
  // Wrong length, padding in the middle, non-zero trailing bits, bad alphabet.
  assert_eq(@targets.b64_check(b"A"), "err")
  assert_eq(@targets.b64_check(b"AA=A"), "err")
  assert_eq(@targets.b64_check(b"AB=="), "err")
  assert_eq(@targets.b64_check(b"AA==="), "err")
  assert_eq(@targets.b64_check(b"AA==AAAA"), "err")
  assert_eq(@targets.b64_check(b"AAAAA==="), "err")
  assert_eq(@targets.b64_check(b"-___"), "err")
}

///|
test "tlv: round trips complete messages" {
  assert_eq(@targets.tlv_check(b"\x01\x00"), "ok:1")
  assert_eq(@targets.tlv_check(b"\x01\x01A"), "ok:1")
  assert_eq(@targets.tlv_check(b"\x01\x01A\x00\x00"), "ok:1")
  assert_eq(@targets.tlv_check(b"\x02\x03abc"), "ok:1")
}

///|
test "tlv: rejects truncation and stray terminators" {
  assert_eq(@targets.tlv_check(b""), "err")
  assert_eq(@targets.tlv_check(b"\x01"), "err")
  assert_eq(@targets.tlv_check(b"\x01\x05ab"), "err")
  assert_eq(@targets.tlv_check(b"\x00\x01A"), "err")
  assert_eq(@targets.tlv_check(b"\x00\x00\x01\x00"), "err")
}

///|
test "utf8: the two validators agree on valid input" {
  let valid : Array[Bytes] = [
    b"", b"a", b"abc", b"\x00", b"\xc3\xa9", b"\xe4\xb8\xad", b"\xf0\x9f\x98\x80",
    b"a\xc3\xa9b",
  ]
  let mut i = 0
  while i < valid.length() {
    let a = @targets.utf8_count_a(valid[i])
    let b = @targets.utf8_count_b(valid[i])
    assert_eq(a, b)
    assert_true(a.has_prefix("ok:"))
    i = i + 1
  }
}

///|
test "utf8: the two validators agree on invalid input" {
  let invalid : Array[Bytes] = [
    b"\x80", b"\xc0\x80", b"\xe0\x80\x80", b"\xed\xa0\x80", b"\xf4\x90\x80\x80",
    b"\xf5\x80\x80\x80", b"\xe4\xb8", b"\xc3", b"\xfe",
  ]
  let mut i = 0
  while i < invalid.length() {
    let a = @targets.utf8_count_a(invalid[i])
    let b = @targets.utf8_count_b(invalid[i])
    assert_eq(a, b)
    assert_eq(a, "err")
    i = i + 1
  }
}

///|
test "utf8: char counting matches for multibyte text" {
  assert_eq(@targets.utf8_count_a(b"a\xc3\xa9"), "ok:2")
  assert_eq(@targets.utf8_count_b(b"a\xc3\xa9"), "ok:2")
  assert_eq(@targets.utf8_count_a(b"\xf0\x9f\x98\x80\xf0\x9f\x98\x80"), "ok:2")
}
