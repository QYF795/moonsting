///|
test "fixed: a well-formed table round trips" {
  assert_eq(@targets.fixed_check(b"widths: 3\nabc\n"), "ok:1")
  assert_eq(
    @targets.fixed_check(b"widths: 6,4\nname  age \nalice 30  \n"),
    "ok:2",
  )
  // Padding is trimmed from cells and restored on emit, so a short cell is fine.
  assert_eq(@targets.fixed_check(b"widths: 4\nab  \n"), "ok:1")
}

///|
test "fixed: geometry errors are rejected" {
  // Row length does not match the width sum.
  assert_eq(@targets.fixed_check(b"widths: 3\nabcd\n"), "err")
  // No widths at all.
  assert_eq(@targets.fixed_check(b"widths:\nabc\n"), "err")
  // Zero width.
  assert_eq(@targets.fixed_check(b"widths: 0\n\n"), "err")
  // Non-numeric width.
  assert_eq(@targets.fixed_check(b"widths: 3,x\nabc\n"), "err")
  // Missing the widths line entirely.
  assert_eq(@targets.fixed_check(b"abc\n"), "err")
}

///|
test "ini: a sectioned document summarises" {
  let doc = b"[db]\nhost = localhost\nport = 5432\n"
  let summary = @targets.ini_summary(doc)
  assert_true(summary.has_prefix("ok:1x2:"))
}

///|
test "ini: comments do not change the summary anywhere" {
  let plain = b"[a]\nx=1\ny=2\n"
  let commented = b"; head\n[a]\nx=1\n# middle\ny=2\n; tail\n"
  assert_eq(@targets.ini_summary(plain), @targets.ini_summary(commented))
}

///|
test "ini: structural errors are errors" {
  // Key outside a section.
  assert_eq(@targets.ini_summary(b"x=1\n"), "err")
  // Unterminated section header.
  assert_eq(@targets.ini_summary(b"[abc\nx=1\n"), "err")
  // Empty section name.
  assert_eq(@targets.ini_summary(b"[]\nx=1\n"), "err")
  // Line that is neither a section, a comment nor a key.
  assert_eq(@targets.ini_summary(b"[a]\nnonsense\n"), "err")
}

///|
test "props: canonical entries round trip" {
  assert_eq(@targets.prop_check(b"a=1\n"), "ok:1")
  assert_eq(@targets.prop_check(b"a=1\nb=two\n"), "ok:2")
  // An escaped newline inside a value.
  assert_eq(@targets.prop_check(b"k=a\\nb\n"), "ok:1")
  // An escaped equals sign inside a key.
  assert_eq(@targets.prop_check(b"a\\=b=1\n"), "ok:1")
}

///|
test "props: non-canonical input is rejected outright" {
  // Spaces must be escaped, so an unescaped one is not canonical — rejected
  // rather than reported, because rejection is the cheaper signal here.
  assert_eq(@targets.prop_check(b"a= x\n"), "err")
  assert_eq(@targets.prop_check(b"a=\\ x\n"), "ok:1")
  assert_eq(@targets.prop_check(b"a\\ b=1\n"), "ok:1")
  // A blank line is not canonical.
  assert_eq(@targets.prop_check(b"a=1\n\nb=2\n"), "err")
  // Missing separator.
  assert_eq(@targets.prop_check(b"novalue\n"), "err")
  // Unknown escape.
  assert_eq(@targets.prop_check(b"a=\\q\n"), "err")
}
