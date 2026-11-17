///|
test "rng: same seed, same stream" {
  let a = @core.Rng::new(42)
  let b = @core.Rng::new(42)
  let mut i = 0
  while i < 32 {
    assert_eq(a.next_int(), b.next_int())
    i = i + 1
  }
}

///|
test "rng: different seeds diverge" {
  let a = @core.Rng::new(1)
  let b = @core.Rng::new(2)
  let mut same = 0
  let mut i = 0
  while i < 32 {
    if a.next_int() == b.next_int() {
      same = same + 1
    }
    i = i + 1
  }
  assert_true(same < 32)
}

///|
test "rng: below stays in range" {
  let r = @core.Rng::new(7)
  let mut i = 0
  while i < 200 {
    let v = r.below(13)
    assert_true(v >= 0 && v < 13)
    i = i + 1
  }
  assert_eq(r.below(0), 0)
}

///|
test "hex: round trip" {
  let bytes = b"\x00\x01\x7f\x80\xff"
  let hex = @core.hex_all(bytes)
  assert_eq(hex, "00017f80ff")
  assert_true(@core.bytes_equal(@core.parse_hex(hex), bytes))
}

///|
test "hex: truncation and odd nibbles" {
  assert_eq(@core.hex_of(b"\xde\xad\xbe\xef", 2), "dead..")
  assert_eq(@core.hex_of(b"\xde\xad", 2), "dead")
  let odd = @core.parse_hex("abc")
  assert_eq(odd.length(), 2)
  assert_eq(@core.hex_all(odd), "ab0c")
}

///|
test "hash: stable and sensitive" {
  assert_eq(@core.hash_bytes(b"moonbit"), @core.hash_bytes(b"moonbit"))
  assert_true(@core.hash_bytes(b"moonbit") != @core.hash_bytes(b"moonbiu"))
  assert_true(@core.hash_bytes(b"") >= 0)
}

///|
test "shape: digits collapse" {
  assert_eq(@core.shape("v:123"), "v:#")
  assert_eq(@core.shape("v:12345"), "v:#")
  assert_eq(@core.shape("ok:12"), @core.shape("ok:3456"))
  assert_eq(@core.shape("no digits"), "no digits")
}

///|
test "ascii: non printable becomes dot" {
  assert_eq(@core.ascii_of(b"a\x00b\xffc", 5), "a.b.c")
}

///|
test "short: truncates with ellipsis" {
  assert_eq(@core.short("abcdef", 3), "abc...")
  assert_eq(@core.short("abc", 3), "abc")
}

///|
test "escape_json: quotes and control characters" {
  assert_eq(@core.escape_json("a\"b"), "a\\\"b")
  assert_eq(@core.escape_json("a\nb"), "a\\nb")
}
