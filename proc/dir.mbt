// Directory creation, without a directory API.
//
// There is no `mkdir` in the standard library, and no `readdir` either — which
// is why the corpus on disk is a *numbered sequence* of files rather than a
// directory the loader can list. One shell call creates the directory; the
// numbered names are what makes listing unnecessary.

///|
pub fn make_dir(path : String) -> Bool {
  if is_windows() {
    run_command("mkdir " + path + " > NUL 2>&1") == 0
  } else {
    run_command("mkdir -p " + path + " > /dev/null 2>&1") == 0
  }
}

///|
/// A file counts as present when it has content. Corpus entries are hex lines,
/// so a zero-byte file is indistinguishable from a missing one — and that is
/// exactly the sentinel the loader needs.
pub fn file_present(path : String) -> Bool {
  read_file(path).length() > 0
}
