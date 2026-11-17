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
  sb.write_string(
    "  moonsting worker --target NAME --batch FILE --out FILE\n\n",
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
      let loaded = if corpus_dir.length() > 0 {
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
  } else {
    println(help())
  }
}
