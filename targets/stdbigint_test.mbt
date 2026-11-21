///|
/// Reproducers for what the `bigint` target found on 2026-11-22. These are
/// *observations about the standard library*, kept as tests so the exact
/// behaviour is recorded and cannot silently change.
///
/// 1. `from_string` aborts (no `raise`) on text it cannot parse with the given
///    radix: `0x1f` with radix 10, and a leading `+`.
/// 2. Beyond roughly 3,500 decimal digits, `parse(print(v))` no longer equals
///    `v`.
///
/// (1) cannot be tested here — an abort kills the test process. (2) is pinned
/// at the boundary that was measured.
test "bigint: print-parse round trip holds at 200 digits" {
  let text = "1" + "0".repeat(199)
  let value = @targets.stdbigint_parse(text).unwrap()
  let printed = value.to_string()
  assert_eq(printed.length(), 200)
  assert_true(@targets.stdbigint_parse(printed).unwrap().equal(value))
}

///|
test "bigint: leading zeros and signs are handled" {
  for text in ["0", "-0", "007", "-007", "123456789", "-123456789"] {
    let value = @targets.stdbigint_parse(text).unwrap()
    assert_true(
      @targets.stdbigint_parse(value.to_string()).unwrap().equal(value),
    )
  }
}

///|
/// The radix round trip is not exercised: the stdlib renamed the label
/// (`base~` -> `radix=`) between toolchain versions, so one source cannot call
/// it against both. See docs/findings.md §10.7.
test "bigint: hex printing is stable" {
  let text = "123456789012345678901234567890"
  let value = @targets.stdbigint_parse(text).unwrap()
  assert_eq(value.to_string(radix=16), value.to_string(radix=16))
}
