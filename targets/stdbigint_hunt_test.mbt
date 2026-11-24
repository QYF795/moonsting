///|
/// Mini-fuzz for the upstream issue: look for a large decimal value whose
/// `parse -> to_string -> parse` round trip diverges, on the current api.
/// Prints the first counterexample it finds.
test "bigint: hunt for a large-value divergence" {
  let mut seed = 987654321
  let mut found = ""
  let mut trial = 0
  while trial < 60 && found == "" {
    // 3,000-4,000 digits, generated without Int32 overflow.
    let target_len = 3000 + (seed % 1000)
    let mut text = ""
    while text.length() < target_len {
      seed = (seed * 16807) % 2147483647
      let digit = seed % 10
      // A digit string may not start with 0 for the comparison to be meaningful.
      if !(text.length() == 0 && digit == 0) {
        text = text + digit.to_string()
      }
    }
    let parsed = @targets.stdbigint_parse(text)
    if parsed is Some(value) {
      let printed = value.to_string()
      if printed.length() != text.length() {
        found = "len " + text.length().to_string() + " printed " + printed.length().to_string()
      } else if @targets.stdbigint_parse(printed) is Some(back) {
        if !back.equal(value) {
          found = "diverge at len " + text.length().to_string()
        }
      } else {
        found = "reprint unparseable at len " + text.length().to_string()
      }
    }
    trial = trial + 1
  }
  assert_eq(found, "")
}
