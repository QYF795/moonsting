///|
/// Fuzz MoonBit's **own** big-integer parser (`moonbitlang/core/bigint`).
///
/// Second standard-library target, after `stdjson`. The property is the same
/// shape: the library must agree with itself.
///
///   - `from_string(s)` must not trap on a plausible numeric string;
///   - `from_string(s).to_string()` must re-parse to the same value;
///   - printing in another radix and parsing it back must give the same value.
///
/// The input space is restricted to *plausible numbers* (optional sign, then
/// digits, with optional `0x`/`0o`/`0b` prefix). That is deliberate: the stdlib
/// does not document what `from_string` does with "hello", so feeding it
/// garbage would produce noise that says nothing about the library.
///
/// Like `stdjson` this target is **deliberately uninstrumented** — the branches
/// are in the stdlib — so novelty comes from the output shape (sign, digit
/// count class, radix class).
///
/// Scope note: `from_string` has no `raise` and aborts on text it cannot parse
/// with the given radix, so the input space here is "decimal digits with an
/// optional sign". Feeding it `0x1f` would test the stdlib's contract, not its
/// correctness — that path is a documented limitation (see docs/findings.md §5).

///|
fn stdbigint_is_number(text : StringView) -> Bool {
  let n = text.length()
  if n == 0 {
    return false
  }
  let mut i = 0
  let first = text.get_char(0).unwrap().to_int()
  if first == 43 || first == 45 {
    i = 1
  }
  if i >= n {
    return false
  }
  // Decimal only. `0x1f` and `0b1011` are *not* accepted here on purpose:
  // `BigInt::from_string` has no raise and aborts on input it cannot parse with
  // the given radix (observed at core/bigint/bigint_default.mbt:1289), so those
  // forms are the stdlib's contract, not a bug we should report.
  let mut digits = 0
  while i < n {
    let c = text.get_char(i).unwrap().to_int()
    if c < 48 || c > 57 {
      return false
    }
    digits = digits + 1
    i = i + 1
  }
  digits > 0
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
  // Decimal parsing is superlinear in the digit count: a 4,000-digit input costs
  // milliseconds per execution and takes the loop from ~150k exec/s to ~400.
  // 1,024 digits (≈3,400 bits) still exercises multi-limb arithmetic while
  // keeping the target fuzzable. The behaviour beyond that is recorded in
  // docs/findings.md §5.7 instead of being searched for.
  if text.length() > 1024 {
    return "err:too-long"
  }
  if !stdbigint_is_number(text) {
    return "err:notnumber"
  }
  // Observed on this toolchain: `from_string` aborts on a leading `+`
  // (`BigInt::from_string("+5")` -> abort at core/bigint/bigint_default.mbt:1289).
  // It also aborts on radix prefixes. Both are recorded in docs/findings.md §5.7;
  // filtering them here keeps an in-process run from being killed by a known,
  // documented limitation instead of an unknown bug.
  if text.has_prefix("+") {
    return "err:plus-sign"
  }
  let value = @bigint.BigInt::from_string(text)
  let printed = value.to_string()
  // 1. Printing then parsing must give the same value back.
  let again = @bigint.BigInt::from_string(printed)
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
  let from_hex = @bigint.BigInt::from_string(hex, radix=16)
  if !from_hex.equal(value) {
    return "inconsistent:radix-roundtrip"
  }
  // 3. And canonical decimal text must be invariant under reprinting.
  if printed != text && stdbigint_is_number(printed) && !printed.has_prefix("-") {
    let normalized = printed
    if @bigint.BigInt::from_string(normalized).to_string() != normalized {
      return "inconsistent:unstable-print"
    }
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
pub fn stdbigint_consistency(_input : Bytes, output : String) -> String {
  if output.has_prefix("inconsistent:") {
    output
  } else {
    ""
  }
}
