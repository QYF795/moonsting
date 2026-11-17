///|
/// The worker's result file must end with a coverage line; without it the
/// parent can never report coverage for isolated runs.
#cfg(target="native")
test "worker: emits a coverage line with the ids it reached" {
  let case = @targets.find("csv").unwrap()
  let batch = @proc.temp_path("wbatch.txt")
  let out = @proc.temp_path("wout.txt")
  ignore(@proc.write_file(batch, @utf8.encode("612c620a0a\n22222c220a\n")))
  run_worker(case, batch, out)
  let text = @utf8.decode_lossy(@proc.read_file(out))
  @proc.remove_file(batch)
  @proc.remove_file(out)
  assert_true(text.contains("S\t"))
}
