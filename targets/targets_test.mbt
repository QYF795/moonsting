///|
test "json: accepts a minimal document" {
  assert_eq(@targets.json_validate(b"{}"), "ok:2")
  assert_eq(@targets.json_validate(b"[]"), "ok:2")
  assert_eq(@targets.json_validate(b"null"), "ok:4")
  assert_eq(@targets.json_validate(b"-1.5e3"), "ok:6")
  assert_eq(@targets.json_validate(b"{\"a\":[1,2]}"), "ok:11")
}

///|
test "json: rejects with a position" {
  assert_true(@targets.json_validate(b"{").has_prefix("err:"))
  assert_true(@targets.json_validate(b"{\"a\"}").has_prefix("err:"))
  assert_true(@targets.json_validate(b"[1,]").has_prefix("err:"))
  assert_true(@targets.json_validate(b"tru").has_prefix("err:"))
  assert_true(@targets.json_validate(b"01").has_prefix("err:"))
  assert_true(@targets.json_validate(b"\"\\u00G0\"").has_prefix("err:"))
  assert_true(@targets.json_validate(b"\"a\x01\"").has_prefix("err:"))
}

///|
test "json: whitespace does not change acceptance" {
  let inputs : Array[Bytes] = [
    b"{}", b" [1] ", b"{\"a\":1}", b"", b"{", b"[1,]",
  ]
  let mut i = 0
  while i < inputs.length() {
    let a = @targets.json_validate(inputs[i])
    let b = @targets.json_validate(inputs[i] + b" \n")
    assert_eq(a.has_prefix("ok:"), b.has_prefix("ok:"))
    i = i + 1
  }
}

///|
test "csv: counts rows, columns and the longest field" {
  assert_eq(@targets.csv_stats(b"a,b\n1,2\n"), "rows=2;cols=2;max=1")
  assert_eq(@targets.csv_stats(b"a\n"), "rows=1;cols=1;max=1")
  assert_eq(@targets.csv_stats(b""), "rows=0;cols=0;max=0")
  assert_eq(@targets.csv_stats(b"aaa,bb\n"), "rows=1;cols=2;max=3")
}

///|
test "csv: quoted separators stay inside a field" {
  assert_eq(@targets.csv_stats(b"\"a,b\",c\n"), "rows=1;cols=2;max=3")
  assert_true(@targets.csv_stats(b"\"a\"b,c\n").has_prefix("err:"))
  assert_true(@targets.csv_stats(b"\"ab,c\n").has_prefix("err:"))
}

///|
test "varint: the pair agrees on small values" {
  let cases : Array[Bytes] = [
    b"\x00", b"\x01", b"\x7f", b"\x80\x01", b"\xff\x01",
  ]
  let mut i = 0
  while i < cases.length() {
    assert_eq(@targets.varint_fast(cases[i]), @targets.varint_ref(cases[i]))
    i = i + 1
  }
}

///|
test "varint: the pair disagrees beyond 32 bits" {
  let wide = b"\x80\x80\x80\x80\x80\x01"
  assert_true(@targets.varint_fast(wide) != @targets.varint_ref(wide))
}

///|
test "catalog: names, lookup and seeds" {
  let names = @targets.names()
  assert_eq(names.length(), 5)
  assert_true(@targets.find("varint") is Some(_))
  assert_true(@targets.find("nope") is None)
  match @targets.find("json") {
    Some(c) => assert_true(c.seeds().length() > 5)
    None => abort("json case missing")
  }
}

///|
test "coverage: one target is instrumented, the other is not" {
  @cov.reset()
  ignore(@targets.varint_fast(b"\x80\x01"))
  assert_true(@cov.observed() > 0)
  @cov.reset()
  ignore(@targets.json_validate(b"{}"))
  assert_eq(@cov.observed(), 0)
}
