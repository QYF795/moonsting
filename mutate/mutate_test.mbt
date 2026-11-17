///|
test "mutate: deterministic per seed" {
  let a = @mutate.Mutator::new(11, @mutate.Dictionary::generic(), 256)
  let b = @mutate.Mutator::new(11, @mutate.Dictionary::generic(), 256)
  let corpus : Array[Bytes] = [b"abc", b"{}"]
  let mut i = 0
  while i < 50 {
    let x = a.mutate(b"{\"k\":[1,2,3]}", corpus)
    let y = b.mutate(b"{\"k\":[1,2,3]}", corpus)
    assert_true(@core.bytes_equal(x, y))
    i = i + 1
  }
}

///|
test "mutate: respects the length cap" {
  let m = @mutate.Mutator::new(5, @mutate.Dictionary::generic(), 64)
  let mut i = 0
  while i < 500 {
    let out = m.mutate(b"0123456789", [])
    assert_true(out.length() <= 64)
    i = i + 1
  }
}

///|
test "mutate: usually changes the input" {
  let m = @mutate.Mutator::new(99, @mutate.Dictionary::generic(), 512)
  let base = b"{\"a\":1,\"b\":[1,2,3]}"
  let mut changed = 0
  let mut i = 0
  while i < 200 {
    let out = m.mutate(base, [])
    if !@core.bytes_equal(out, base) {
      changed = changed + 1
    }
    i = i + 1
  }
  // The mutator is allowed to be a no-op occasionally, but not usually.
  assert_true(changed > 150)
}

///|
test "dictionary: json tokens are available" {
  let d = @mutate.Dictionary::json()
  assert_true(d.size() > 10)
}

///|
test "mutate: empty input is safe" {
  let m = @mutate.Mutator::new(3, @mutate.Dictionary::generic(), 32)
  let mut i = 0
  while i < 100 {
    let out = m.mutate(b"", [])
    assert_true(out.length() <= 32)
    i = i + 1
  }
}
