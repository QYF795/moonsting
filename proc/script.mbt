// Launching the worker in the background.
//
// `system()` blocks, so one worker at a time is all a blocking call can do. To
// run N at once each job gets a tiny launcher script:
//
//   Windows:  @echo off / "<exe>" worker ... / echo %ERRORLEVEL%> <done>
//   POSIX:    #!/bin/sh / "<exe>" worker ... / echo $? > <done>
//
// Two properties matter. The script always writes the done file, even when the
// worker aborts — that is the only way the parent can tell "finished" from
// "still running" without wait(). And the exit code lands in that file, so the
// parent never needs the shell's return value.

///|
pub fn script_for(
  exe : String,
  target : String,
  batch_path : String,
  out_path : String,
  done_path : String,
) -> String {
  let run = exe +
    " worker --target " +
    target +
    " --batch " +
    batch_path +
    " --out " +
    out_path
  if is_windows() {
    "@echo off\r\n" +
    run +
    " > NUL 2>&1\r\n" +
    "echo %ERRORLEVEL% > " +
    done_path +
    "\r\n"
  } else {
    "#!/bin/sh\n" +
    run +
    " > /dev/null 2>&1\n" +
    "echo $? > " +
    done_path +
    "\n"
  }
}

///|
/// Start a launcher script and return immediately (or return the spawn error).
pub fn launch(script_path : String) -> Int32 {
  if is_windows() {
    run_command("start /b \"\" cmd /c " + script_path)
  } else {
    run_command("sh " + script_path + " &")
  }
}

///|
/// Start every script with a single shell invocation.
///
/// Launching one `cmd.exe` per job costs ~57 ms each, which eats a third of a
/// 512-input round. Chaining the starts into one command line pays that cost
/// once: each `start /b` returns immediately, so the jobs still overlap.
pub fn launch_many(scripts : Array[String]) -> Int32 {
  if scripts.length() == 0 {
    return 0
  }
  let sb = StringBuilder()
  let mut i = 0
  while i < scripts.length() {
    if i > 0 {
      sb.write_string(" & ")
    }
    if is_windows() {
      sb.write_string("start /b \"\" cmd /c ")
    } else {
      sb.write_string("sh ")
    }
    sb.write_string(scripts[i])
    i = i + 1
  }
  if !is_windows() {
    sb.write_string(" &")
  }
  run_command(sb.to_string())
}
