///|
/// Worker mode: execute a batch of hex-encoded inputs and append one result line
/// per input to `out_path`.
///
/// Line format (tab separated): `index \t signature \t verdict-hex`.
///
/// The flush after every line is the whole design: the next input may abort the
/// process, and the parent must still be able to say *which* input did it. With
/// one line per execution and an fflush, the number of complete lines in the
/// output file *is* the index of the input that killed us — no bisection needed.
pub fn run_worker(
  case : @targets.Case,
  batch_path : String,
  out_path : String,
) -> Unit {
  let raw = @proc.read_file(batch_path)
  let inputs = split_lines(raw)
  let handle = @proc.open_out(out_path)
  let mut i = 0
  while i < inputs.length() {
    let input = @core.parse_hex(inputs[i])
    @cov.reset()
    let output = case.target().run(input)
    let verdict = case.oracle().check(input, output)
    let sig = if @cov.observed() > 0 {
      @cov.fingerprint()
    } else {
      @cov.signature(output, input.length())
    }
    let line = i.to_string() +
      "\t" +
      sig.to_string() +
      "\t" +
      @core.hex_all(@utf8.encode(verdict)) +
      "\n"
    ignore(@proc.put(handle, @utf8.encode(line)))
    @proc.flush(handle)
    i = i + 1
  }
  @proc.close_out(handle)
}
