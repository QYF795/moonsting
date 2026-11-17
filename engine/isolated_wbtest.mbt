///|
/// Whitebox tests for the parent side of isolation. They never spawn: the test
/// binary has no `worker` subcommand, so a spawn would fail and look like a
/// crash. What is worth testing here is the *interpretation* of a result list,
/// which is where the crash index comes from.
#cfg(target="native")
test "isolated: a short result list becomes a crash finding" {
  let session = make(@targets.boom_case(), @core.Config::default().with_seed(1))
  let batch : Array[Bytes] = [b"aa", b"bb", b"cc"]
  // Only the first input produced a line: the second one killed the worker.
  let results : Array[String] = ["0\t1\t"]
  session.absorb(batch, results, 3)
  let findings = session.findings()
  assert_eq(findings.length(), 1)
  assert_eq(findings[0].kind().label(), "crash")
  assert_eq(@core.hex_all(findings[0].input()), "6262")
  assert_true(findings[0].detail().contains("input 1 of 3"))
}

///|
#cfg(target="native")
test "isolated: a complete result list produces no crash" {
  let session = make(@targets.boom_case(), @core.Config::default().with_seed(1))
  let batch : Array[Bytes] = [b"aa", b"bb"]
  let results : Array[String] = ["0\t1\t", "1\t1\t"]
  session.absorb(batch, results, 0)
  assert_eq(session.findings().length(), 0)
  assert_eq(session.stats().execs(), 2)
}

///|
#cfg(target="native")
test "isolated: verdicts from the worker become findings" {
  let session = make(@targets.boom_case(), @core.Config::default().with_seed(1))
  let batch : Array[Bytes] = [b"aa"]
  // "err:boom" hex-encoded in the third column.
  let results : Array[String] = ["0\t7\t6572723a626f6f6d"]
  session.absorb(batch, results, 0)
  let findings = session.findings()
  assert_eq(findings.length(), 1)
  assert_eq(findings[0].kind().label(), "violation")
  assert_eq(findings[0].detail(), "err:boom")
}
