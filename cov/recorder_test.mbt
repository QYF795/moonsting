///|
/// The recorder is global state, so every test starts by clearing it.
#cfg(target="native")
test "recorder: hit dedupes within one execution" {
  @cov.reset()
  @cov.hit(1)
  @cov.hit(1)
  @cov.hit(2)
  assert_eq(@cov.observed(), 2)
}

///|
#cfg(target="native")
test "recorder: reset clears the current execution only" {
  @cov.reset()
  @cov.clear_seen()
  @cov.hit(1)
  ignore(@cov.commit())
  assert_eq(@cov.seen_count(), 1)
  @cov.reset()
  assert_eq(@cov.observed(), 0)
  assert_eq(@cov.seen_count(), 1)
}

///|
#cfg(target="native")
test "recorder: commit reports a new id exactly once" {
  @cov.reset()
  @cov.clear_seen()
  @cov.hit(7)
  assert_true(@cov.commit())
  @cov.reset()
  @cov.hit(7)
  assert_false(@cov.commit())
  @cov.reset()
  @cov.hit(7)
  @cov.hit(8)
  assert_true(@cov.commit())
}

///|
#cfg(target="native")
test "recorder: fingerprint ignores order, distinguishes sets" {
  @cov.reset()
  @cov.hit(1)
  @cov.hit(2)
  let a = @cov.fingerprint()
  @cov.reset()
  @cov.hit(2)
  @cov.hit(1)
  let b = @cov.fingerprint()
  assert_eq(a, b)
  @cov.reset()
  @cov.hit(1)
  let c = @cov.fingerprint()
  assert_true(a != c)
}
