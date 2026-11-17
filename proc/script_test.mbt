///|
/// The launcher script is a pure string, so it can be tested without spawning.
/// What matters is that it runs the worker with exactly the paths the parent
/// wrote, and that it records the exit code even when the worker aborts.
#cfg(target="native")
test "script: launcher runs the worker and records the exit code" {
  let text = @proc.script_for(
    ".\\_build\\cli.exe", "varint", ".moonsting-1-batch.txt", ".moonsting-1-out.txt",
    ".moonsting-1-done.txt",
  )
  assert_true(text.contains("_build"))
  assert_true(text.contains("worker --target varint"))
  assert_true(text.contains(".moonsting-1-batch.txt"))
  assert_true(text.contains(".moonsting-1-out.txt"))
  assert_true(text.contains(".moonsting-1-done.txt"))
  if @proc.is_windows() {
    // `echo %ERRORLEVEL% > f`: the space before `>` matters. Without it
    // `0> f` is parsed as a redirect of file handle 0 and writes nothing —
    // which made every job look like it never finished.
    assert_true(text.contains("echo %ERRORLEVEL% > "))
  } else {
    assert_true(text.contains("echo $? > "))
  }
}

///|
#cfg(target="native")
test "script: launching nothing is a no-op" {
  assert_eq(@proc.launch_many([]).to_string(), "0")
}
