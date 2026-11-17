///|
test "buckets: shape-based signature groups number-only changes" {
  let a = @cov.signature("v:123", 4)
  let b = @cov.signature("v:999999", 4)
  assert_eq(a, b)
}

///|
test "buckets: different shapes are different signatures" {
  let a = @cov.signature("ok:4", 4)
  let b = @cov.signature("err:boom", 4)
  assert_true(a != b)
}

///|
test "buckets: novelty is counted once per signature" {
  let b = @cov.Buckets::new()
  assert_true(b.observe(7))
  assert_false(b.observe(7))
  assert_true(b.observe(8))
  assert_eq(b.len(), 2)
  assert_eq(b.novel(), 2)
  assert_eq(b.observations(), 3)
}

///|
test "edges: artifact lines become stable ids" {
  let text = "src/json.mbt:12:5 3\nsrc/json.mbt:12:5 9\nsrc/csv.mbt 4 2 1\n42\n"
  let set = @cov.parse_artifact(text)
  // Two distinct locations; the bare counter line and the hit counts must not
  // create identities of their own.
  assert_eq(set.len(), 2)
  let again = @cov.parse_artifact(text)
  assert_eq(set.merge(again), 0)
}

///|
test "edges: merge counts new ids" {
  let a = @cov.parse_artifact("a.mbt:1:1 1\n")
  let b = @cov.parse_artifact("a.mbt:1:1 1\nb.mbt:2:2 1\n")
  assert_eq(a.merge(b), 1)
  assert_eq(a.len(), 2)
}
