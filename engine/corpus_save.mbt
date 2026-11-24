///|
/// Write a list of inputs to a corpus directory with the same numbered-file
/// convention as `save_corpus`, for callers that have inputs but no session
/// (the `cmin` command).
pub fn save_inputs(dir : String, inputs : Array[Bytes], limit : Int32) -> Int32 {
  ignore(@proc.make_dir(dir))
  let mut written = 0
  let mut i = 0
  while i < inputs.length() && written < limit {
    let path = corpus_file(dir, written + 1)
    if @proc.write_file(path, @utf8.encode(@core.hex_all(inputs[i]) + "\n")) {
      written = written + 1
    }
    i = i + 1
  }
  written
}
