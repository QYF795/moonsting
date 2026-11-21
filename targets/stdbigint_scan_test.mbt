///|
/// Scan for the smallest decimal string whose print/parse round trip breaks.
/// Temporary diagnostic: the assertion message names the case.
test "bigint: scan families for a print-parse failure" {
  let families : Array[String] = ["2", "3", "7", "9", "20", "002", "1234567"]
  let mut found = ""
  let mut i = 0
  while i < families.length() && found == "" {
    let pattern = families[i]
    let mut n = 1
    while n <= 400 {
      let mut text = ""
      let mut k = 0
      while k < n {
        text = text + pattern
        k = k + 1
      }
      let value = @targets.stdbigint_parse(text).unwrap()
      let printed = value.to_string()
      if !@targets.stdbigint_parse(printed).unwrap().equal(value) {
        found = pattern +
          " x" +
          n.to_string() +
          " (len " +
          text.length().to_string() +
          ")"
        break
      }
      n = n + 1
    }
    i = i + 1
  }
  assert_eq(found, "")
}
