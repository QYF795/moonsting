///|
test "shrink: reaches a single byte" {
  let data = b"AABBBCCCC"
  let predicate = fn(candidate : Bytes) { candidate.find(b"B") is Some(_) }
  let small = @shrink.ddmin(data, predicate, 500)
  assert_eq(small.length(), 1)
  assert_true(@core.bytes_equal(small, b"B"))
}

///|
test "shrink: keeps the original when it is not interesting" {
  let data = b"hello"
  let predicate = fn(_candidate) { false }
  let small = @shrink.ddmin(data, predicate, 100)
  assert_true(@core.bytes_equal(small, data))
}

///|
test "shrink: minimal example is preserved" {
  let data = b"xx42yy"
  let predicate = fn(candidate : Bytes) {
    @core.ascii_of(candidate, 64).contains("42")
  }
  let small = @shrink.ddmin(data, predicate, 500)
  assert_eq(@core.ascii_of(small, 16), "42")
}

///|
test "shrink: remove_span handles edges" {
  assert_eq(@core.hex_all(@shrink.remove_span(b"\x01\x02\x03", 0, 1)), "0203")
  assert_eq(@core.hex_all(@shrink.remove_span(b"\x01\x02\x03", 2, 9)), "0102")
  assert_eq(@core.hex_all(@shrink.remove_span(b"\x01\x02\x03", 5, 1)), "010203")
}
