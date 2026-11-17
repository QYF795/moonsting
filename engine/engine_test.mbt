///|
test "engine: finds the varint truncation bug" {
  let case = @targets.find("varint").unwrap()
  let session = @engine.run(
    case,
    @core.Config::default().with_seed(1).with_max_execs(5000),
  )
  assert_true(session.findings().length() >= 1)
  let first = session.findings()[0]
  assert_eq(first.kind().label(), "mismatch")
  // Every reported input must reproduce through the replay path.
  assert_true(session.replay(first.input()) != "")
}

///|
test "engine: findings are minimized" {
  let case = @targets.find("varint").unwrap()
  let session = @engine.run(
    case,
    @core.Config::default().with_seed(2).with_max_execs(5000),
  )
  let findings = session.findings()
  let mut i = 0
  while i < findings.length() {
    assert_true(findings[i].input().length() <= 16)
    i = i + 1
  }
}

///|
test "engine: same seed reproduces the same first finding" {
  let case = @targets.find("varint").unwrap()
  let config = @core.Config::default().with_seed(9).with_max_execs(4000)
  let a = @engine.run(case, config)
  let b = @engine.run(case, config)
  assert_eq(a.findings().length(), b.findings().length())
  if a.findings().length() > 0 {
    assert_eq(
      @core.hex_all(a.findings()[0].input()),
      @core.hex_all(b.findings()[0].input()),
    )
  }
}

///|
test "engine: smoke oracle never reports and grows a corpus" {
  let case = @targets.find("csv").unwrap()
  let session = @engine.run(
    case,
    @core.Config::default().with_seed(3).with_max_execs(2000),
  )
  assert_eq(session.findings().length(), 0)
  assert_true(session.corpus_size() > 5)
}

///|
test "engine: a correct target yields no violation" {
  let case = @targets.find("json").unwrap()
  let session = @engine.run(
    case,
    @core.Config::default().with_seed(4).with_max_execs(8000),
  )
  assert_eq(session.findings().length(), 0)
  assert_true(session.stats().execs() >= 8000)
}
