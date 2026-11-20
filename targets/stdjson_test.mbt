///|
test "stdjson: the stdlib parser agrees with itself" {
  // Shapes are reported so the output-shape fallback has something to bucket on.
  assert_true(@targets.stdjson_check(b"{\"a\":1}").has_prefix("ok:object:"))
  assert_true(@targets.stdjson_check(b"[1,2,3]").has_prefix("ok:array:"))
  assert_true(@targets.stdjson_check(b"\"x\"").has_prefix("ok:string:"))
  assert_true(@targets.stdjson_check(b"12.5e3").has_prefix("ok:number:"))
  assert_true(@targets.stdjson_check(b"true").has_prefix("ok:bool:"))
  assert_true(@targets.stdjson_check(b"null").has_prefix("ok:null:"))
}

///|
test "stdjson: invalid documents and invalid encoding are rejected" {
  assert_eq(@targets.stdjson_check(b"["), "err:invalid")
  assert_eq(@targets.stdjson_check(b"[1,]"), "err:invalid")
  assert_eq(@targets.stdjson_check(b"{'a':1}"), "err:invalid")
  // Not valid UTF-8: a JSON document is text.
  assert_eq(@targets.stdjson_check(b"\xff\xfe"), "err:utf8")
  assert_eq(@targets.stdjson_check(b""), "err:invalid")
}

///|
test "stdjson: the consistency oracle only flags disagreements" {
  assert_eq(@targets.stdjson_consistency(b"x", "ok:object:1:2"), "")
  assert_eq(@targets.stdjson_consistency(b"x", "err:invalid"), "")
  assert_eq(
    @targets.stdjson_consistency(b"x", "inconsistent:valid-but-parse-failed"),
    "inconsistent:valid-but-parse-failed",
  )
}
