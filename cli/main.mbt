// moonsting CLI.
//
// Argument parsing is hand-rolled on purpose: the tool has eight flags and no
// subcommand trees, and every dependency of a fuzzer is a dependency a user has
// to install before their first run.

///|
fn flag_value(args : Array[String], name : String) -> String? {
  let mut i = 0
  while i + 1 < args.length() {
    if args[i] == name {
      return Some(args[i + 1])
    }
    i = i + 1
  }
  None
}

///|
fn has_flag(args : Array[String], name : String) -> Bool {
  let mut i = 0
  while i < args.length() {
    if args[i] == name {
      return true
    }
    i = i + 1
  }
  false
}

///|
/// Decimal parser with a fallback. Hand-rolled so the CLI never depends on
/// error-returning stdlib helpers (and so `--max-execs abc` degrades to the
/// default instead of aborting the run).
fn parse_int_or(text : String, fallback : Int32) -> Int32 {
  if text.length() == 0 {
    return fallback
  }
  let mut value = 0
  let mut i = 0
  while i < text.length() {
    let c = text.get_char(i).unwrap()
    let v = c.to_int()
    if v < 48 || v > 57 {
      return fallback
    }
    value = value * 10 + (v - 48)
    i = i + 1
  }
  value
}

///|
fn int_flag(args : Array[String], name : String, fallback : Int32) -> Int32 {
  match flag_value(args, name) {
    Some(text) => parse_int_or(text, fallback)
    None => fallback
  }
}

///|
/// `--time 1500` (ms), `--time 1500ms`, `--time 3s`.
fn time_flag(args : Array[String]) -> UInt64 {
  match flag_value(args, "--time") {
    Some(text) => {
      let n = text.length()
      let mut end = 0
      while end < n {
        let c = text.get_char(end).unwrap()
        let v = c.to_int()
        if v >= 48 && v <= 57 {
          end = end + 1
        } else {
          break
        }
      }
      let digits = substring(text, 0, end)
      let value = parse_int_or(digits, 0)
      let mut multiplier = 1UL
      if end < n {
        if text.get_char(end).unwrap() == 's' {
          multiplier = 1000UL
        }
      }
      value.to_uint64() * multiplier
    }
    None => 0UL
  }
}

///|
fn substring(s : String, start : Int32, end : Int32) -> String {
  let sb = StringBuilder()
  let mut i = start
  while i < end && i < s.length() {
    sb.write_char(s.get_char(i).unwrap())
    i = i + 1
  }
  sb.to_string()
}

///|
fn help() -> String {
  let sb = StringBuilder()
  sb.write_string(
    "moonsting - coverage-guided, differential fuzzing for MoonBit\n\n",
  )
  sb.write_string("usage:\n")
  sb.write_string(
    "  moonsting run [--target NAME] [--seed N] [--max-execs N] [--time 5s]\n",
  )
  sb.write_string(
    "               [--max-input N] [--max-findings N] [--seed-input HEX]...\n",
  )
  sb.write_string(
    "               [--jobs N] [--corpus-dir DIR] [--corpus-max N]\n",
  )
  sb.write_string(
    "               [--json] [--html] [--emit-test] [--dump-corpus]\n",
  )
  sb.write_string(
    "               [--fail-on-finding] [--cov-report] [--no-shrink] [--batch-size N]\n",
  )
  sb.write_string("  moonsting list\n")
  sb.write_string("  moonsting replay --target NAME --hex HEX\n")
  sb.write_string("  moonsting minimize --target NAME --hex HEX\n")
  sb.write_string("  moonsting worker --target NAME --batch FILE --out FILE\n")
  sb.write_string(
    "  moonsting cmin --target NAME --corpus-dir DIR [--out DIR] [--dry-run]\n",
  )
  sb.write_string("  moonsting exec --target NAME --hex HEX\n")
  sb.write_string(
    "  moonsting cross --target NAME [--max-execs N] [--other WASM]\n\n",
  )
  sb.write_string(
    "run flags: --isolate runs each batch in a child process, so a\n",
  )
  sb.write_string(
    "panic is reported instead of killing the run; --batch-size N\n",
  )
  sb.write_string("sets how many inputs one child executes (default 512).\n\n")
  sb.write_string("targets:\n")
  let names = @targets.names()
  let mut i = 0
  while i < names.length() {
    sb.write_string("  " + names[i] + "\n")
    i = i + 1
  }
  sb.to_string()
}

///|
fn resolve_target(args : Array[String]) -> @targets.Case? {
  match flag_value(args, "--target") {
    Some(name) =>
      match @targets.find(name) {
        Some(c) => Some(c)
        None => {
          println("unknown target: " + name)
          println(help())
          None
        }
      }
    None =>
      match @targets.find("json") {
        Some(c) => Some(c)
        None => None
      }
  }
}

///|
/// Every value of a repeatable flag, in order. `--seed-input aa --seed-input bb`
/// yields both; that is how a corpus exported with `--dump-corpus` is fed back
/// into a later run.
fn flag_values(args : Array[String], name : String) -> Array[String] {
  let out : Array[String] = []
  let mut i = 0
  while i + 1 < args.length() {
    if args[i] == name {
      out.push(args[i + 1])
      i = i + 2
    } else {
      i = i + 1
    }
  }
  out
}

///|
fn hex_seeds(args : Array[String]) -> Array[Bytes] {
  let out : Array[Bytes] = []
  let raw = flag_values(args, "--seed-input")
  let mut i = 0
  while i < raw.length() {
    let bytes = @core.parse_hex(raw[i])
    if bytes.length() > 0 {
      out.push(bytes)
    }
    i = i + 1
  }
  out
}

///|
fn cmd_run(args : Array[String], exe : String) -> Unit {
  match resolve_target(args) {
    None => ()
    Some(case) => {
      let config = @core.Config::default()
        .with_seed(int_flag(args, "--seed", 0))
        .with_max_execs(int_flag(args, "--max-execs", 50000))
        .with_max_input_len(int_flag(args, "--max-input", 4096))
        .with_max_findings(int_flag(args, "--max-findings", 16))
        .with_time_budget_ms(time_flag(args))
        .with_quiet(has_flag(args, "--quiet"))
      let corpus_dir = match flag_value(args, "--corpus-dir") {
        Some(d) => d
        None => ""
      }
      if corpus_dir.length() > 0 && !@proc.supported() {
        println(
          "note     : --corpus-dir needs the native backend; ignored on this target",
        )
      }
      let loaded = if corpus_dir.length() > 0 && @proc.supported() {
        @engine.load_corpus(corpus_dir, int_flag(args, "--corpus-max", 4096))
      } else {
        []
      }
      let seeds = @engine.concat_seeds(loaded, hex_seeds(args))
      let session = if has_flag(args, "--isolate") {
        @engine.run_isolated(
          case,
          config,
          int_flag(args, "--batch-size", 512),
          int_flag(args, "--jobs", 1),
          exe,
          !has_flag(args, "--no-shrink"),
          seeds,
        )
      } else {
        @engine.run_with(case, config, seeds)
      }
      if has_flag(args, "--json") {
        println(@report.jsonl(session))
      } else if has_flag(args, "--html") {
        println(@report.html(session))
      } else {
        println(@core.trim_end(@report.summary(session)))
        if has_flag(args, "--emit-test") {
          let findings = session.findings()
          if findings.length() > 0 {
            println(@report.regression_test(findings[0]))
          }
        }
        if has_flag(args, "--dump-corpus") {
          println(@report.corpus_dump(session))
        }
        if has_flag(args, "--cov-report") {
          println(
            @core.trim_end(@report.coverage_report(session.coverage_ids())),
          )
        }
        if corpus_dir.length() > 0 {
          let written = @engine.save_corpus(
            session,
            corpus_dir,
            int_flag(args, "--corpus-max", 4096),
          )
          println(
            "corpus   -> " + corpus_dir + " (" + written.to_string() + " files)",
          )
        }
      }
      // CI hook: a fuzzer that always exits 0 is useless in a pipeline.
      if has_flag(args, "--fail-on-finding") && session.findings().length() > 0 {
        abort(
          "moonsting: " +
          session.findings().length().to_string() +
          " finding(s) on target " +
          case.name(),
        )
      }
    }
  }
}

///|
fn cmd_list(_args : Array[String]) -> Unit {
  println(help())
}

///|
fn cmd_replay(args : Array[String]) -> Unit {
  match resolve_target(args) {
    None => ()
    Some(case) =>
      match flag_value(args, "--hex") {
        None => println("replay needs --hex")
        Some(hex) => {
          let input = @core.parse_hex(hex)
          let output = case.target().run(input)
          let verdict = case.oracle().check(input, output)
          println("bytes   : " + input.length().to_string())
          println("output  : " + @core.short(output, 200))
          if verdict == "" {
            println("verdict : accepted")
          } else {
            println("verdict : " + verdict)
          }
        }
      }
  }
}

///|
fn cmd_minimize(args : Array[String]) -> Unit {
  match resolve_target(args) {
    None => ()
    Some(case) =>
      match flag_value(args, "--hex") {
        None => println("minimize needs --hex")
        Some(hex) => {
          let input = @core.parse_hex(hex)
          let target = case.target()
          let oracle = case.oracle()
          let small = @shrink.ddmin(
            input,
            fn(candidate) {
              oracle.check(candidate, target.run(candidate)) != ""
            },
            5000,
          )
          println(
            "from : " +
            input.length().to_string() +
            "B " +
            @core.hex_of(input, 32),
          )
          println(
            "to   : " + small.length().to_string() + "B " + @core.hex_all(small),
          )
        }
      }
  }
}

///|
/// `exec`: run one input and print the target output. Exists so that a build of
/// this CLI on another backend can act as the reference side of `cross`.
fn cmd_exec(args : Array[String]) -> Unit {
  match resolve_target(args) {
    None => ()
    Some(case) => {
      let hex = match flag_value(args, "--hex") {
        Some(h) => h
        None => ""
      }
      if hex.length() == 0 {
        println("exec needs --hex HEX")
        return
      }
      // `-` is the empty input: an empty argument would be dropped by the shell.
      let input = if hex == "-" { b"" } else { @core.parse_hex(hex) }
      println(case.target().run(input))
    }
  }
}

///|
/// The inputs `cross` feeds both sides: the target's seeds, then mutations of
/// them, so the comparison is not limited to hand-written cases.
fn cross_inputs(
  case : @targets.Case,
  count : Int32,
  seed : Int32,
) -> Array[Bytes] {
  let seeds = case.target().seeds()
  let out : Array[Bytes] = []
  if seeds.length() == 0 {
    return out
  }
  let mutator = @mutate.Mutator::new(seed, @mutate.Dictionary::generic(), 256)
  while out.length() < count {
    let index = out.length() % seeds.length()
    if out.length() < seeds.length() {
      out.push(seeds[index])
    } else {
      out.push(mutator.mutate(seeds[index], seeds))
    }
  }
  out
}

///|
/// Run one input through another build of this CLI and return its stdout.
fn run_other(wasm : String, name : String, input : Bytes) -> String {
  let out = @proc.temp_path("cross")
  let hex = if input.length() == 0 { "-" } else { @core.hex_all(input) }
  let script = "moonrun " +
    @proc.arg(wasm) +
    " exec --target " +
    name +
    " --hex " +
    hex +
    " > " +
    @proc.shell_path(out) +
    " 2>&1"
  ignore(@proc.run_command(script))
  let text = @utf8.decode_lossy(@proc.read_file(out))
  @proc.remove_file(out)
  @core.trim_end(text)
}

///|
/// `cross`: the same inputs through two backends; any disagreement is a bug.
fn cmd_cross(args : Array[String]) -> Unit {
  match resolve_target(args) {
    None => ()
    Some(case) => {
      if !@proc.supported() {
        println("cross needs the native backend: it spawns the other build")
        return
      }
      let other = match flag_value(args, "--other") {
        Some(p) => p
        None => "_build/wasm-gc/debug/build/cli/cli.wasm"
      }
      if !@proc.file_present(other) {
        println("other build not found: " + other)
        println("build it first: moon build --target wasm-gc")
        return
      }
      let count = int_flag(args, "--max-execs", 100)
      let inputs = cross_inputs(case, count, int_flag(args, "--seed", 0))
      let mine : Array[String] = []
      let theirs : Array[String] = []
      let mut i = 0
      while i < inputs.length() {
        mine.push(case.target().run(inputs[i]))
        theirs.push(run_other(other, case.name(), inputs[i]))
        i = i + 1
      }
      let result = @engine.cross_compare(case.name(), inputs, mine, theirs)
      println("target   : " + case.name())
      println(
        "compared : " + result.compared.to_string() + " inputs against " + other,
      )
      println("mismatch : " + result.mismatches.length().to_string())
      if result.skipped > 0 {
        println(
          "skipped  : " +
          result.skipped.to_string() +
          " (the other side produced nothing)",
        )
      }
      if result.mismatches.length() > 0 {
        println(@core.trim_end(@engine.cross_lines(result)))
      }
    }
  }
}

///|
/// `cmin`: keep the smallest subset of a corpus that still reaches every id.
fn cmd_cmin(args : Array[String]) -> Unit {
  match resolve_target(args) {
    None => ()
    Some(case) => {
      let dir = match flag_value(args, "--corpus-dir") {
        Some(d) => d
        None => ""
      }
      if dir.length() == 0 {
        println("cmin needs --corpus-dir DIR")
        return
      }
      if !@proc.supported() {
        println("cmin reads and writes files, which needs the native backend:")
        println(
          "  moon run cli --target native -- cmin --target ... --corpus-dir ...",
        )
        return
      }
      let inputs = @engine.load_corpus(
        dir,
        int_flag(args, "--corpus-max", 4096),
      )
      if inputs.length() == 0 {
        println("corpus   : 0 inputs in " + dir)
        return
      }
      let result = @engine.cmin(case, inputs)
      let kept : Array[Bytes] = []
      let mut i = 0
      while i < result.kept.length() {
        kept.push(inputs[result.kept[i]])
        i = i + 1
      }
      let out = match flag_value(args, "--out") {
        Some(o) => o
        None => ".corpus-min"
      }
      if has_flag(args, "--dry-run") {
        println("corpus   : " + inputs.length().to_string() + " inputs")
        println(
          "coverage : " +
          result.ids_covered.to_string() +
          " of " +
          result.ids_total.to_string() +
          " ids",
        )
        println(
          "kept     : " + result.kept.length().to_string() + " inputs (dry run)",
        )
        return
      }
      let written = @engine.save_inputs(
        out,
        kept,
        int_flag(args, "--corpus-max", 4096),
      )
      if has_flag(args, "--json") {
        println(
          @report.cmin_line(
            inputs.length(),
            result.kept.length(),
            result.ids_covered,
            result.ids_total,
            out,
          ),
        )
      } else {
        println("corpus   : " + inputs.length().to_string() + " inputs")
        println(
          "coverage : " +
          result.ids_covered.to_string() +
          " of " +
          result.ids_total.to_string() +
          " ids",
        )
        println(
          "kept     : " +
          result.kept.length().to_string() +
          " inputs (" +
          written.to_string() +
          " files written)",
        )
        println("out      : " + out)
      }
    }
  }
}

///|
/// Locate the subcommand. `moon run` hands the program its own path as argv[0]
/// on wasm-gc but as argv[0..1] under node (`node cli.js ...`), so the command
/// is found by name rather than by position.
fn is_command(a : String) -> Bool {
  if a == "run" {
    return true
  }
  if a == "list" {
    return true
  }
  if a == "replay" {
    return true
  }
  if a == "minimize" {
    return true
  }
  if a == "worker" {
    return true
  }
  if a == "cmin" {
    return true
  }
  if a == "exec" {
    return true
  }
  if a == "cross" {
    return true
  }
  if a == "help" {
    return true
  }
  if a == "--help" {
    return true
  }
  false
}

///|
/// Locate the subcommand. `moon run` hands the program its own path as argv[0]
/// on wasm-gc but as argv[0..1] under node (`node cli.js ...`), so the command
/// is found by name rather than by position.
fn command_index(args : Array[String]) -> Int32 {
  let mut i = 0
  while i < args.length() {
    if is_command(args[i]) {
      return i
    }
    i = i + 1
  }
  -1
}

///|
fn tail(args : Array[String], from : Int32) -> Array[String] {
  let out : Array[String] = []
  let mut i = from
  while i < args.length() {
    out.push(args[i])
    i = i + 1
  }
  out
}

///|
fn main {
  let args = @env.args()
  let at = command_index(args)
  if at < 0 {
    println(help())
    return
  }
  let cmd = args[at]
  let rest = tail(args, at + 1)
  if cmd == "run" {
    cmd_run(rest, self_exe(args))
  } else if cmd == "list" {
    cmd_list(rest)
  } else if cmd == "replay" {
    cmd_replay(rest)
  } else if cmd == "minimize" {
    cmd_minimize(rest)
  } else if cmd == "worker" {
    cmd_worker(rest)
  } else if cmd == "cmin" {
    cmd_cmin(rest)
  } else if cmd == "exec" {
    cmd_exec(rest)
  } else if cmd == "cross" {
    cmd_cross(rest)
  } else {
    println(help())
  }
}
