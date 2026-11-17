///|
test "decimal: parses the documented forms" {
  assert_eq(@targets.parse_decimal(b"1.23"), Some(123))
  assert_eq(@targets.parse_decimal(b"-1.23"), Some(-123))
  assert_eq(@targets.parse_decimal(b"12"), Some(1200))
  assert_eq(@targets.parse_decimal(b"12.5"), Some(1250))
  assert_eq(@targets.parse_decimal(b"0.01"), Some(1))
  assert_eq(@targets.parse_decimal(b"0"), Some(0))
}

///|
test "decimal: rejects malformed input" {
  assert_true(@targets.parse_decimal(b"") is None)
  assert_true(@targets.parse_decimal(b"-") is None)
  assert_true(@targets.parse_decimal(b"1.") is None)
  assert_true(@targets.parse_decimal(b".5") is None)
  assert_true(@targets.parse_decimal(b"1.234") is None)
  assert_true(@targets.parse_decimal(b"1,23") is None)
  assert_true(@targets.parse_decimal(b"1e5") is None)
}

///|
test "decimal: formats with two places" {
  assert_eq(@targets.format_decimal(123).to_string(), b"1.23".to_string())
  assert_eq(@targets.format_decimal(5).to_string(), b"0.05".to_string())
  assert_eq(@targets.format_decimal(-123).to_string(), b"-1.23".to_string())
  assert_eq(@targets.format_decimal(0).to_string(), b"0.00".to_string())
}

///|
test "decimal: the round-trip defect is visible" {
  // The parser refuses "-0.50" outright (negative with a zero integer part), so
  // the defect needs a value that *parses* and then lands below one unit after
  // formatting: 42949672 * 100 overflows Int, producing -96 cents, which
  // formats to "-0.96" and is then refused. The self-check reports exactly that.
  assert_eq(@targets.decimal_check(b"-0.50"), "err")
  assert_eq(@targets.decimal_check(b"42949672"), "roundtrip:rejected:-0.96")
  assert_true(@targets.decimal_check(b"-1.50").has_prefix("ok:"))
  assert_true(@targets.decimal_check(b"1.50").has_prefix("ok:"))
  assert_eq(@targets.decimal_check(b"nope"), "err")
}

///|
test "decimal: the oracle only rejects roundtrip diagnoses" {
  assert_eq(@targets.decimal_roundtrip_holds(b"x", "ok:1.23"), "")
  assert_eq(@targets.decimal_roundtrip_holds(b"x", "err"), "")
  assert_eq(
    @targets.decimal_roundtrip_holds(b"x", "roundtrip:rejected:-0.50"),
    "roundtrip:rejected:-0.50",
  )
}
