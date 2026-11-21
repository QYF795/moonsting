///|
/// The target caps input at 256 digits; this pins that the cap is comfortable.
///
/// Beyond a few hundred digits the standard library can *panic* on some values
/// instead of returning; that is recorded in docs/findings.md §5.7 rather than
/// run here, because a test that aborts the runner is not a test.
test "bigint: 256-digit round trip is comfortable" {
  let mut text = ""
  let mut i = 0
  while text.length() < 256 {
    let digit = (i * 7 + i / 10 + 3) % 10
    text = text + digit.to_string()
    i = i + 1
  }
  let parsed = @targets.stdbigint_parse(text)
  let value = match parsed {
    None => {
      // Say what failed instead of unwrapping: an unwrap panic here would look
      // like a stdlib crash and hide the real reason.
      assert_true(false, msg="parse_bigint rejected a plain digit string")
      abort("unreachable")
    }
    Some(v) => v
  }
  let printed = value.to_string()
  assert_eq(printed.length(), text.length())
  let again = @targets.stdbigint_parse(printed)
  assert_true(again is Some(_), msg="printed form did not parse")
  if again is Some(v) {
    assert_true(v.equal(value))
  }
}
