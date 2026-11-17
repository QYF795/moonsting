///|
test "report: regression test carries the input" {
  let finding = @core.Finding::new(
    @core.FindingKind::Mismatch,
    "varint.fast",
    b"\x80\x80\x80\x80\x80\x01",
    "expected v:1 got v:2",
    42,
  )
  let generated = @report.regression_test(finding)
  assert_true(generated.contains("test \"regress: varint.fast"))
  assert_true(generated.contains("808080808001"))
  assert_true(generated.contains("assert_eq"))
  assert_true(generated.contains("at exec 42"))
}

///|
test "report: json line is parseable by eye" {
  let finding = @core.Finding::new(
    @core.FindingKind::Violation,
    "json.lite",
    b"\"",
    "unterminated",
    7,
  )
  let line = @report.json_line(finding)
  assert_true(line.has_prefix("{"))
  assert_true(line.contains("\"kind\":\"violation\""))
  assert_true(line.contains("\"input\":\"22\""))
  assert_true(line.has_suffix("}\n"))
}
