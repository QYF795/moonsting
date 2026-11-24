///|
test "cross: identical outputs produce no mismatch" {
  let inputs : Array[Bytes] = [b"a", b"b"]
  let result = cross_compare("t", inputs, ["x", "y"], ["x", "y"])
  assert_eq(result.compared, 2)
  assert_eq(result.mismatches.length(), 0)
  assert_eq(result.skipped, 0)
}

///|
test "cross: a disagreement is one mismatch, with both sides named" {
  let inputs : Array[Bytes] = [b"a", b"b"]
  let result = cross_compare("utf8", inputs, ["ok:1", "ok:2"], ["ok:1", "ok:3"])
  assert_eq(result.mismatches.length(), 1)
  let finding = result.mismatches[0]
  assert_eq(finding.exec(), 1)
  assert_true(finding.detail().contains("other=ok:3"))
  assert_true(finding.detail().contains("local=ok:2"))
  assert_eq(cross_lines(result).contains("input=62"), true)
}

///|
test "cross: an empty other-side output counts as skipped, not a bug" {
  let inputs : Array[Bytes] = [b"a", b"b"]
  let result = cross_compare("t", inputs, ["x", "y"], ["x", ""])
  assert_eq(result.mismatches.length(), 0)
  assert_eq(result.skipped, 1)
  assert_eq(result.compared, 1)
}
