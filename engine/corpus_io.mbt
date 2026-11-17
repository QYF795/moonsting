///|
/// Persistent corpus: a directory of numbered hex files.
///
/// Why numbered files instead of "one file per hash" or a directory listing:
/// MoonBit's stdlib has no `readdir`, so the loader cannot enumerate anything.
/// It can, however, open `corpus-0001.hex`, `corpus-0002.hex`, … until one is
/// missing — which is a listing, just spelled differently. The cost is one
/// failed `fopen` per load.
///
/// Layout:
///   <dir>/corpus-0001.hex   one input, lowercase hex, one line
///   <dir>/corpus-0002.hex
///   ...
///
/// Load stops at the first missing index, so a hole in the middle truncates the
/// corpus. That is deliberate: it makes the format recoverable by hand (delete
/// the tail, keep the prefix) instead of requiring a compaction pass.

///|
fn pad4(n : Int32) -> String {
  let digits = n.to_string()
  let sb = StringBuilder()
  let mut i = digits.length()
  while i < 4 {
    sb.write_char('0')
    i = i + 1
  }
  sb.write_string(digits)
  sb.to_string()
}

///|
pub fn corpus_file(dir : String, index : Int32) -> String {
  @proc.path_join(dir, "corpus-" + pad4(index) + ".hex")
}

///|
/// Read up to `limit` entries. Missing directory or missing first file yields an
/// empty array, which the caller treats as "start fresh".
pub fn load_corpus(dir : String, limit : Int32) -> Array[Bytes] {
  let out : Array[Bytes] = []
  let mut i = 1
  let mut stop = false
  while !stop && i <= limit {
    let raw = @proc.read_file(corpus_file(dir, i))
    if raw.length() == 0 {
      stop = true
    } else {
      let lines = split_lines(raw)
      if lines.length() > 0 {
        let input = @core.parse_hex(lines[0])
        if input.length() > 0 {
          out.push(input)
        }
      }
      i = i + 1
    }
  }
  out
}

///|
/// Write the session's corpus back. Returns how many files were written.
///
/// Existing files are overwritten from index 1; the sequence is never shrunk, so
/// a later run that happens to keep fewer entries leaves the tail intact and the
/// next load still sees everything.
pub fn save_corpus(session : Session, dir : String, limit : Int32) -> Int32 {
  ignore(@proc.make_dir(dir))
  let inputs = session.corpus_inputs()
  let total = if inputs.length() < limit { inputs.length() } else { limit }
  let mut i = 0
  while i < total {
    let path = corpus_file(dir, i + 1)
    ignore(
      @proc.write_file(path, @utf8.encode(@core.hex_all(inputs[i]) + "\n")),
    )
    i = i + 1
  }
  total
}

///|
/// Concatenate seed sources: a loaded corpus first, then seeds from the command
/// line, deduplicated by content so the same input is not paid for twice.
pub fn concat_seeds(a : Array[Bytes], b : Array[Bytes]) -> Array[Bytes] {
  let out : Array[Bytes] = []
  let mut i = 0
  while i < a.length() {
    out.push(a[i])
    i = i + 1
  }
  let mut j = 0
  while j < b.length() {
    let candidate = b[j]
    let mut seen = false
    let mut k = 0
    while k < out.length() {
      if out[k].length() == candidate.length() &&
        @core.bytes_equal(out[k], candidate) {
        seen = true
      }
      k = k + 1
    }
    if !seen {
      out.push(candidate)
    }
    j = j + 1
  }
  out
}
