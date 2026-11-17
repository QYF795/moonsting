///|
test "e2e: a run exposes text, html and jsonl views of the same data" {
  let run = @api.fuzz(
    "varint",
    @core.Config::default().with_seed(1).with_max_execs(2000),
  ).unwrap()
  let text = run.summary()
  assert_true(text.contains("varint"))
  assert_true(text.contains("exec/s"))
  assert_true(text.contains("mismatch"))
  let page = run.html()
  assert_true(page.has_prefix("<!doctype html>"))
  assert_true(page.contains("moonsting report"))
  assert_true(run.jsonl().contains("\"kind\":\"mismatch\""))
}

///|
test "e2e: a clean target reports nothing but still explores" {
  let run = @api.fuzz(
    "json",
    @core.Config::default().with_seed(7).with_max_execs(6000),
  ).unwrap()
  assert_eq(run.findings().length(), 0)
  assert_true(run.corpus_size() > 20)
  assert_true(run.stats().novelty() > 20)
}

///|
test "e2e: every finding reproduces through replay" {
  let run = @api.fuzz(
    "varint",
    @core.Config::default().with_seed(5).with_max_execs(3000),
  ).unwrap()
  let findings = run.findings()
  assert_true(findings.length() > 0)
  let mut i = 0
  while i < findings.length() {
    assert_true(run.replay(findings[i].input()) != "")
    i = i + 1
  }
}

///|
test "e2e: emitted regression test is valid MoonBit scaffolding" {
  let run = @api.fuzz(
    "varint",
    @core.Config::default().with_seed(1).with_max_execs(2000),
  ).unwrap()
  let generated = run.regression_test(0)
  assert_true(generated.contains("test \"regress:"))
  assert_true(generated.contains("parse_hex("))
  assert_eq(run.regression_test(99), "")
}

///|
test "api: unknown target is a clean None" {
  assert_true(@api.fuzz("nope", @core.Config::default()) is None)
  assert_eq(@api.target_names().length(), 3)
}
