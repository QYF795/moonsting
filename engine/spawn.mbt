///|
/// Path handling for re-launching the worker.
///
/// Windows `system()` hands the command line to cmd.exe, which decodes it with
/// the ANSI code page. A project living under a non-ASCII directory (very
/// common: `文档`, `项目`, any Chinese user name) therefore makes the spawn fail
/// with exit code 1 even though the same command works by hand. `_wsystem`
/// would fix it properly, but it does not exist off Windows and we cannot gate
/// on the OS at compile time here.
///
/// The workaround that costs nothing: pass a path *relative to the working
/// directory*, which the child inherits. `_build/native/.../cli.exe` has no
/// non-ASCII bytes even when every parent directory does.
fn is_ascii(s : String) -> Bool {
  let mut i = 0
  while i < s.length() {
    if s.get_char(i).unwrap().to_int() >= 128 {
      return false
    }
    i = i + 1
  }
  true
}

///|
/// Best path to hand to `system()`: the original when it is ASCII, otherwise a
/// path relative to the current directory when that is ASCII.
pub fn spawn_path(exe : String) -> String {
  if is_ascii(exe) {
    return @proc.shell_path(exe)
  }
  match @env.current_dir() {
    Some(cwd) =>
      if exe.length() > cwd.length() + 1 && exe.has_prefix(cwd) {
        let rel = @core.slice_str(exe, cwd.length() + 1, exe.length())
        if is_ascii(rel) {
          @proc.shell_path(rel)
        } else {
          exe
        }
      } else {
        exe
      }
    None => exe
  }
}
