///|
test "corpus: deduplicates by content" {
  let c = @corpus.Corpus::new()
  assert_true(c.add(b"a", 0))
  assert_false(c.add(b"a", 0))
  assert_true(c.add(b"b", 0))
  assert_eq(c.len(), 2)
}

///|
test "corpus: pick returns a stored input" {
  let c = @corpus.Corpus::new()
  ignore(c.add(b"aaa", 0))
  ignore(c.add(b"bbbb", 0))
  ignore(c.add(b"ccccc", 0))
  let mut i = 0
  while i < 50 {
    let picked = c.pick()
    assert_true(
      @core.bytes_equal(picked, b"aaa") ||
      @core.bytes_equal(picked, b"bbbb") ||
      @core.bytes_equal(picked, b"ccccc"),
    )
    i = i + 1
  }
}

///|
test "corpus: empty pick is empty" {
  let c = @corpus.Corpus::new()
  assert_eq(c.pick().length(), 0)
  assert_eq(c.shortest(), -1)
}

///|
test "corpus: trim drops the largest entries" {
  let c = @corpus.Corpus::new()
  ignore(c.add(b"1", 0))
  ignore(c.add(b"22", 0))
  ignore(c.add(b"333333", 0))
  ignore(c.add(b"4444", 0))
  c.trim(2)
  assert_eq(c.len(), 2)
  let all = c.all()
  let mut i = 0
  while i < all.length() {
    assert_true(all[i].length() <= 4)
    i = i + 1
  }
}
