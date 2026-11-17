///|
/// The executable path to re-launch for `--isolate`. argv[0] is the binary on
/// native; under `moon run` on other backends it is a wasm/js path, which the
/// caller rejects by checking `@proc.supported()`.
fn self_exe(args : Array[String]) -> String {
  if args.length() == 0 {
    return ""
  }
  let a = args[0]
  if a.contains("\\") || a.contains("/") || a.has_suffix(".exe") {
    a
  } else {
    ""
  }
}

///|
fn cmd_worker(args : Array[String]) -> Unit {
  match flag_value(args, "--target") {
    None => abort("worker needs --target")
    Some(name) =>
      match @targets.find(name) {
        None => abort("worker: unknown target " + name)
        Some(case) => {
          let batch = match flag_value(args, "--batch") {
            Some(p) => p
            None => abort("worker needs --batch")
          }
          let out = match flag_value(args, "--out") {
            Some(p) => p
            None => abort("worker needs --out")
          }
          @engine.run_worker(case, batch, out)
        }
      }
  }
}
