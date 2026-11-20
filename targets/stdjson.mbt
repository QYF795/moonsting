///|
/// Fuzz MoonBit's **own** JSON parser (`moonbitlang/core/json`).
///
/// Every other target here tests a hand-written parser. This one tests the
/// standard library the ecosystem actually ships, with a self-consistency oracle
/// instead of a second implementation:
///
///   - `@json.valid(s)` and `@json.parse(s)` must agree on every string;
///   - whatever `parse` accepts, `stringify` must re-emit as parseable JSON.
///
/// A disagreement is a real bug in the stdlib: either `valid` is too optimistic,
/// or `stringify` produces text its own parser rejects. A panic is even more
/// interesting, and is what `--isolate` exists for.
///
/// **Deliberately uninstrumented.** The interesting branches live in the stdlib,
/// where we cannot put `@cov.hit`, so a fingerprint built from our own few ids
/// would collapse every document into the same bucket. Instead the output
/// encodes what was parsed (kind, size class), which sends the engine down its
/// output-shape fallback and gives novelty something to work with.
///
/// Out of scope: bytes that are not valid UTF-8. A JSON document is text, so the
/// target decodes first and rejects anything that does not round trip.

///|
fn stdjson_kind(value : Json) -> String {
  match value {
    Object(_) => "object"
    Array(_) => "array"
    String(_) => "string"
    Number(_) => "number"
    True => "bool"
    False => "bool"
    Null => "null"
  }
}

///|
pub fn stdjson_check(input : Bytes) -> String {
  let text = @utf8.decode_lossy(input)
  if @utf8.encode(text) != input {
    return "err:utf8"
  }
  if !@json.valid(text) {
    return "err:invalid"
  }
  // Two stages: 0 = parse raised, 1 = re-emitted text did not parse, 2 = fine.
  let mut stage = 0
  let mut shape = ""
  try {
    let value = @json.parse(text)
    stage = 1
    let again = value.stringify()
    let _ = @json.parse(again)
    stage = 2
    // The size class is what makes identical-looking documents distinguishable
    // to the output-shape fallback.
    shape = stdjson_kind(value) +
      ":" +
      (again.length() / 8).to_string() +
      ":" +
      (again.length() % 8).to_string()
  } catch {
    _ => ()
  }
  if stage == 0 {
    "inconsistent:valid-but-parse-failed"
  } else if stage == 1 {
    "inconsistent:restringify-invalid"
  } else {
    "ok:" + shape
  }
}

///|
/// The oracle: both disagreement cases are failures, everything else passes.
pub fn stdjson_consistency(_input : Bytes, output : String) -> String {
  if output.has_prefix("inconsistent:") {
    output
  } else {
    ""
  }
}
