///|
/// Verification for the upstream issue draft: does `parse_bigint -> to_string ->
/// parse_bigint` diverge at large digit counts on the CURRENT api?
///
/// Kept as a test so the answer is pinned and re-checked on every run. Sizes are
/// beyond the target's 256-digit cap on purpose; that cap exists for speed, not
/// because the library is known to be fine up there.
test "bigint: large-value round trip (issue verification)" {
  let sizes : Array[Int] = [300, 600, 1200, 2000, 3000]
  let mut failures = ""
  let mut s = 0
  while s < sizes.length() {
    let n = sizes[s]
    let mut text = ""
    let mut i = 0
    while text.length() < n {
      // Safe generator: small multiplier, no Int32 overflow.
      let digit = (i * 7 + i / 10 + 3) % 10
      text = text + digit.to_string()
      i = i + 1
    }
    let parsed = @targets.stdbigint_parse(text)
    if parsed is Some(value) {
      let printed = value.to_string()
      let again = @targets.stdbigint_parse(printed)
      if again is Some(back) {
        if !back.equal(value) {
          failures = failures + "len=" + n.to_string() + "(value differs) "
        }
      } else {
        failures = failures + "len=" + n.to_string() + "(reprint unparseable) "
      }
    } else {
      failures = failures + "len=" + n.to_string() + "(not parsed) "
    }
    s = s + 1
  }
  assert_eq(failures, "")
}
