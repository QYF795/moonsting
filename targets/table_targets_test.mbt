///|
test "csv strict: canonical documents round trip" {
  assert_eq(@targets.csv_strict_check(b"a,b\n1,2\n"), "ok:2")
  assert_eq(@targets.csv_strict_check(b"\"a,b\",c\n"), "ok:1")
  assert_eq(@targets.csv_strict_check(b"a\n"), "ok:1")
  // A single quote inside a quoted field.
  assert_eq(@targets.csv_strict_check(b"\"\"\"\"\n"), "ok:1")
}

///|
test "csv strict: non-canonical input is rejected" {
  // Quotes that were not needed.
  assert_eq(@targets.csv_strict_check(b"\"a\"\n"), "err")
  // CR is not whitespace, it is an error.
  assert_eq(@targets.csv_strict_check(b"a\r\n"), "err")
  // A trailing empty row is not a row.
  assert_eq(@targets.csv_strict_check(b"a\n\n"), "err")
  // Stray quote inside an unquoted field.
  assert_eq(@targets.csv_strict_check(b"a\"b\n"), "err")
  // Unterminated quote.
  assert_eq(@targets.csv_strict_check(b"\"ab\n"), "err")
}

///|
test "arff: a well-formed document summarises" {
  let doc = b"@relation r\n@attribute a numeric\n@data\n1\n2\n"
  assert_eq(@targets.arff_summary(doc), "ok:72:1x2")
}

///|
test "arff: comments are ignored wherever they appear" {
  let with_comment = b"% leading\n@relation r\n@attribute a numeric\n@data\n1\n% middle\n2\n"
  assert_eq(@targets.arff_summary(with_comment), "ok:72:1x2")
}

///|
test "arff: structural errors are errors" {
  assert_eq(@targets.arff_summary(b""), "err")
  assert_eq(@targets.arff_summary(b"@relation r\n1\n"), "err")
  assert_eq(@targets.arff_summary(b"@data\n1\n"), "err")
  assert_eq(
    @targets.arff_summary(b"@relation r\n@attribute a numeric\n@data\n1,2\n"),
    "err",
  )
}

///|
test "arff: appending a comment cannot change the summary" {
  let doc = b"@relation r\n@attribute a numeric\n@data\n1\n2\n"
  assert_eq(
    @targets.arff_comment_invariant(doc, @targets.arff_summary(doc)),
    "",
  )
  let broken = b"@relation r\n@data\n1\n"
  assert_eq(
    @targets.arff_comment_invariant(broken, @targets.arff_summary(broken)),
    "",
  )
}
