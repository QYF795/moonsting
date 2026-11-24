// Cross-backend differential.
//
// The project's first premise is that the same source compiled to wasm-gc, js
// and native must behave the same, so "the two backends disagree" is a bug
// class a MoonBit-only fuzzer can find and a C-world fuzzer cannot.
//
// This module holds the part that is worth testing without spawning anything:
// turning a list of inputs plus the outputs each side produced into findings.
// The CLI does the spawning.

///|
pub(all) struct CrossResult {
  compared : Int32
  mismatches : Array[@core.Finding]
  skipped : Int32
}

///|
/// Compare two output strings for the same input.
///
/// `mine` is the local (in-process) output, `theirs` the one reported by the
/// other backend. An empty `theirs` means the other side failed to produce
/// anything (missing build, crashed process), which is counted as skipped rather
/// than as a mismatch: a broken harness is not a library bug.
pub fn cross_compare(
  target : String,
  inputs : Array[Bytes],
  mine : Array[String],
  theirs : Array[String],
) -> CrossResult {
  let mismatches : Array[@core.Finding] = []
  let mut compared = 0
  let mut skipped = 0
  let mut i = 0
  while i < inputs.length() && i < mine.length() && i < theirs.length() {
    if theirs[i].length() == 0 {
      skipped = skipped + 1
    } else if theirs[i] != mine[i] {
      mismatches.push(
        @core.Finding::new(
          @core.FindingKind::Mismatch,
          target,
          inputs[i],
          "backends disagree: other=" + theirs[i] + " local=" + mine[i],
          i,
        ),
      )
      compared = compared + 1
    } else {
      compared = compared + 1
    }
    i = i + 1
  }
  { compared, mismatches, skipped, }
}

///|
/// One line per mismatch, shaped like the rest of the tool's finding output.
pub fn cross_lines(result : CrossResult) -> String {
  let sb = StringBuilder()
  let mut i = 0
  while i < result.mismatches.length() {
    let f = result.mismatches[i]
    sb.write_string(
      "  [mismatch] " +
      f.target() +
      "  input=" +
      @core.hex_all(f.input()) +
      " (" +
      f.input().length().to_string() +
      "B)\n        " +
      f.detail() +
      "\n",
    )
    i = i + 1
  }
  sb.to_string()
}
