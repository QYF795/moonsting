///|
/// Fuzz MoonBit's **own** big-integer parser (`@string.parse_bigint`, backed by
/// `moonbitlang/core/bigint`).
///
/// Second standard-library target, after `stdjson`. The property is the same
/// shape: the library must agree with itself.
///
///   - parsing a decimal string must not trap, and must fail cleanly (`raise`)
///     rather than abort;
///   - `parse -> to_string -> parse` must give the same value;
///   - printing in another radix and parsing it back must give the same value.
///
/// Like `stdjson` this target is **deliberately uninstrumented** — the branches
/// live in the stdlib — so novelty comes from the output shape (sign, digit-count
/// class, radix class).
///
/// History worth keeping: the older `BigInt::from_string` (now deprecated)
/// *aborted* on unparseable text such as `0x1f` or `+5`, which killed the fuzz
/// loop. `@string.parse_bigint` raises instead, so those inputs are in scope and
/// are reported as `err:parse` rather than taking the process down.

///|
pub fn stdbigint_parse(text : StringView) -> @bigint.BigInt? {
  let mut out : @bigint.BigInt? = None
  try {
    out = Some(@string.parse_bigint(text))
  } catch {
    _ => ()
  }
  out
}

///|
fn stdbigint_class(value : Int32) -> String {
  // Coarse size classes: exact digit counts would make every input novel.
  if value < 2 {
    "s"
  } else if value < 5 {
    "m"
  } else if value < 20 {
    "l"
  } else {
    "xl"
  }
}

///|
pub fn stdbigint_check(input : Bytes) -> String {
  let text = @utf8.decode_lossy(input)
  if @utf8.encode(text) != input {
    return "err:utf8"
  }
  // Two reasons for the cap, both measured rather than guessed:
  //  - parsing cost is superlinear: a 4,000-digit input takes the loop from
  //    ~126k exec/s to ~400;
  //  - beyond a few hundred digits the stdlib can *panic* on some values instead
  //    of returning, and a panic takes the fuzz loop with it.
  // 256 digits (≈850 bits) still exercises multi-limb arithmetic. The panic is
  // recorded in docs/findings.md §5.7.
  if text.length() > 256 {
    return "err:too-long"
  }
  let parsed = stdbigint_parse(text)
  let value = match parsed {
    None => return "err:parse"
    Some(v) => v
  }
  let printed = value.to_string()
  // 1. Printing then parsing must give the same value back.
  let again = match stdbigint_parse(printed) {
    None => return "inconsistent:print-not-parseable"
    Some(v) => v
  }
  if !again.equal(value) {
    // Include both lengths: a shorter printed string means the printer lost
    // digits, an equal length means the parser mangled them.
    return "inconsistent:print-parse:" +
      printed.length().to_string() +
      ":" +
      text.length().to_string()
  }
  // 2. Another radix must survive the trip too.
  let hex = value.to_string(radix=16)
  let from_hex = match stdbigint_parse_radix(hex, 16) {
    None => return "inconsistent:hex-not-parseable"
    Some(v) => v
  }
  if !from_hex.equal(value) {
    return "inconsistent:radix-roundtrip"
  }
  let sign = if printed.has_prefix("-") { "n" } else { "p" }
  "ok:" +
  stdbigint_class(value.bit_length()) +
  ":" +
  stdbigint_class(text.length()) +
  ":" +
  sign
}

///|
pub fn stdbigint_parse_radix(
  text : StringView,
  base : Int32,
) -> @bigint.BigInt? {
  let mut out : @bigint.BigInt? = None
  try {
    out = Some(@string.parse_bigint(text, base~))
  } catch {
    _ => ()
  }
  out
}

///|
pub fn stdbigint_consistency(_input : Bytes, output : String) -> String {
  if output.has_prefix("inconsistent:") {
    output
  } else {
    ""
  }
}
