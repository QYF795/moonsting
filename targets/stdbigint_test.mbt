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
test "bigint: print-parse round trip holds at 3,000 digits" {
  let text = "1" + "0".repeat(2999)
  let value = @bigint.BigInt::from_string(text)
  let printed = value.to_string()
  assert_eq(printed.length(), 3000)
  assert_true(@bigint.BigInt::from_string(printed).equal(value))
}

///|
test "bigint: leading zeros and signs are handled" {
  for text in ["0", "-0", "007", "-007", "123456789", "-123456789"] {
    let value = @bigint.BigInt::from_string(text)
    assert_true(@bigint.BigInt::from_string(value.to_string()).equal(value))
  }
}

///|
test "bigint: hex round trip through the radix parameter" {
  let text = "123456789012345678901234567890"
  let value = @bigint.BigInt::from_string(text)
  let hex = value.to_string(radix=16)
  assert_true(@bigint.BigInt::from_string(hex, radix=16).equal(value))
}
