// Paths and quoting: pure logic, identical on every backend.
//
// Temporary files are created next to the current working directory, not in
// %TEMP%. Two reasons, both learned the hard way:
//   1. a sandboxed or AppContainer'd process may hold a write token that only
//      covers its working tree, and `fopen` on an absolute path outside it
//      fails with a NULL handle while a relative path succeeds;
//   2. parent and worker inherit the same cwd, so a relative name is the one
//      thing both sides are guaranteed to agree on.
// The names are prefixed `.moonsting-` and removed after every batch; a killed
// run can leave one behind, which is why the prefix is in .gitignore.

///|
/// UTF-8 bytes plus a trailing NUL, for passing to libc.
pub fn cstr(s : String) -> Bytes {
  @utf8.encode(s) + b"\x00"
}

///|
pub fn path_join(dir : String, name : String) -> String {
  if dir.length() == 0 {
    name
  } else {
    let last = dir.get_char(dir.length() - 1).unwrap()
    if last == '\\' || last == '/' {
      dir + name
    } else {
      dir + "/" + name
    }
  }
}

///|
/// A unique file name in the current working directory. pid + millisecond clock
/// keeps two concurrent runs apart without a random source.
pub fn temp_path(tag : String) -> String {
  ".moonsting-" + pid().to_string() + "-" + @env.now().to_string() + "-" + tag
}

///|
/// Quote an argument for `system`.
pub fn quote(arg : String) -> String {
  "\"" + arg + "\""
}

///|
/// Quote only when needed. `cmd.exe` mangles a line that starts with a quoted
/// token *and* carries further quoted tokens — the documented `/C` quote
/// stripping — so the safest command line is one with as few quotes as
/// possible. Paths we generate contain no spaces, so they stay bare.
pub fn arg(text : String) -> String {
  let mut i = 0
  while i < text.length() {
    if text.get_char(i).unwrap() == ' ' {
      return "\"" + text + "\""
    }
    i = i + 1
  }
  text
}

///|
/// Shell redirection that discards the child's output. The worker's exit code
/// and its result lines already carry everything the parent needs; letting a
/// deliberately crashing target print a panic trace into the fuzzer's own
/// report would make the report unreadable.
pub fn quiet_redirect() -> String {
  let windows = match @env.get_env_var("OS") {
    Some(os) => os == "Windows_NT"
    None => false
  }
  if windows {
    " > NUL 2>&1"
  } else {
    " > /dev/null 2>&1"
  }
}

///|
pub fn is_windows() -> Bool {
  match @env.get_env_var("OS") {
    Some(os) => os == "Windows_NT"
    None => false
  }
}

///|
/// Make a path acceptable to `cmd.exe`. Two traps, both observed:
/// a relative path must start with `.\`, and a forward slash inside it is read
/// as a switch separator, so `_build/native/cli.exe` fails while
/// `.\_build\native\cli.exe` works.
pub fn shell_path(path : String) -> String {
  if !is_windows() || path.length() == 0 {
    return path
  }
  let absolute = path.length() > 1 && path.get_char(1).unwrap() == ':'
  let rooted = path.get_char(0).unwrap() == '\\' ||
    path.get_char(0).unwrap() == '/'
  let sb = StringBuilder()
  if !absolute && !rooted {
    sb.write_string(".\\")
  }
  let mut i = 0
  while i < path.length() {
    let c = path.get_char(i).unwrap()
    if c == '/' {
      sb.write_char('\\')
    } else {
      sb.write_char(c)
    }
    i = i + 1
  }
  sb.to_string()
}

///|
/// Remove an empty directory. The redirection syntax differs per shell, and
/// getting it wrong leaves a file literally named `NUL` behind on POSIX.
pub fn rmdir_command(dir : String) -> String {
  if is_windows() {
    "rmdir \"" + dir + "\" > NUL 2>&1"
  } else {
    "rmdir \"" + dir + "\" 2>/dev/null"
  }
}
