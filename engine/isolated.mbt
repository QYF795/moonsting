///|
/// Isolated execution: the parent keeps the corpus and the scheduling, a child
/// process executes one batch of inputs and reports back. A panic in the target
/// kills the child, not the run.
///
/// Why not fork-per-input: process start dominates (~1-2 ms), so a batch of 512
/// amortizes it. Why not bisect on crash: the worker flushes one result line per
/// input, so `lines_written` *is* the index of the input that died. Bisection
/// would be a slower way to learn the same number.
pub fn run_isolated(
  case : @targets.Case,
  config : @core.Config,
  batch_size : Int32,
  jobs : Int32,
  exe : String,
  shrink : Bool,
  seeds : Array[Bytes],
) -> Session {
  if !@proc.supported() || exe.length() == 0 {
    // No OS access on this backend: fall back rather than pretending.
    return run_with(case, config, seeds)
  }
  let session = make(case, config)
  session.exe_ = exe
  session.shrink_ = shrink
  session.prime(seeds)
  session.drive_isolated(
    exe,
    if batch_size > 0 {
      batch_size
    } else {
      512
    },
    if jobs > 0 {
      jobs
    } else {
      1
    },
  )
  session
}

///|
fn Session::drive_isolated(
  self : Session,
  exe : String,
  batch_size : Int32,
  jobs : Int32,
) -> Unit {
  let started = @env.now()
  let budget = self.config_.time_budget_ms()
  let max_execs = self.config_.max_execs()
  let max_findings = self.config_.max_findings()
  let mut halt = false
  while !halt && self.stats_.execs() < max_execs {
    if budget > 0UL && @env.now() - started >= budget {
      halt = true
    } else {
      if jobs > 1 {
        self.run_round(exe, jobs, batch_size)
      } else {
        self.run_batch(exe, batch_size)
      }
      self.batch_ = self.batch_ + 1
      if self.findings_.length() >= max_findings {
        halt = true
      }
    }
  }
  self.stats_.set_elapsed_ms(@env.now() - started)
}

///|
/// Generate one batch, run it in a child, fold the results back in.
fn Session::run_batch(self : Session, exe : String, batch_size : Int32) -> Unit {
  // Empty inputs are skipped: a zero-length line cannot survive the hex batch
  // format, and a batch that reads back shorter than it was written looks
  // exactly like a crash.
  let room = self.config_.max_execs() - self.stats_.execs()
  let wanted = if batch_size < room { batch_size } else { room }
  let batch : Array[Bytes] = []
  let mut attempts = 0
  while batch.length() < wanted && attempts < wanted * 4 {
    let candidate = self.candidate()
    attempts = attempts + 1
    if candidate.length() > 0 {
      batch.push(candidate)
    }
  }
  if batch.length() == 0 {
    return
  }
  match self.execute_chunk(exe, batch) {
    None =>
      // No worker available for this batch: run it here instead of pretending.
      self.run_batch_inproc(batch)
    Some(chunk) => {
      let (results, code) = chunk
      self.absorb(batch, results, code)
    }
  }
}

///|
/// Run one chunk of inputs through a worker and return its result lines and
/// exit code, or `None` when spawning is impossible (no OS support, or a path
/// `cmd.exe` cannot carry).
fn Session::execute_chunk(
  self : Session,
  exe : String,
  inputs : Array[Bytes],
) -> (Array[String], Int32)? {
  let batch_path = @proc.temp_path("batch.txt")
  let out_path = @proc.temp_path("out.txt")
  let text = StringBuilder()
  let mut j = 0
  while j < inputs.length() {
    text.write_string(@core.hex_all(inputs[j]))
    text.write_string("\n")
    j = j + 1
  }
  if !@proc.write_file(batch_path, @utf8.encode(text.to_string())) {
    return None
  }
  let cmd_exe = spawn_path(exe)
  if !is_ascii(cmd_exe) {
    if !self.config_.quiet() {
      println(
        "warning: cannot spawn a worker from a non-ASCII path; running this batch in-process",
      )
    }
    @proc.remove_file(batch_path)
    @proc.remove_file(out_path)
    return None
  }
  let cmd = @proc.arg(cmd_exe) +
    " worker --target " +
    self.case_.name() +
    " --batch " +
    @proc.arg(batch_path) +
    " --out " +
    @proc.arg(out_path) +
    @proc.quiet_redirect()
  if @env.get_env_var("MOONSTING_DEBUG") is Some(_) && self.batch_ < 2 {
    println("spawn: " + cmd)
  }
  let code = @proc.run_command(cmd)
  let results = split_lines(@proc.read_file(out_path))
  @proc.remove_file(batch_path)
  @proc.remove_file(out_path)
  Some((results, code))
}

///|
/// Fold worker results back into the session. `results` may be shorter than
/// `batch` — that is exactly the crash signal.
fn Session::absorb(
  self : Session,
  batch : Array[Bytes],
  results : Array[String],
  exit_code : Int32,
) -> Unit {
  let mut k = 0
  while k < results.length() && k < batch.length() {
    let parts = split_tabs(results[k])
    if parts.length() >= 3 {
      let index = int_of(parts[0])
      if index >= 0 && index < batch.length() {
        let input = batch[index]
        let verdict = @utf8.decode_lossy(@core.parse_hex(parts[2]))
        let sig = int_of(parts[1])
        self.stats_.record_exec()
        if verdict == "" {
          self.stats_.record_accept()
          if self.buckets_.observe(sig) {
            self.stats_.record_novelty()
            if self.corpus_.add(input, 0) {
              self.stats_.record_corpus_add()
              self.pool_.push(input)
            }
          }
        } else {
          self.push_finding(self.oracle_kind(), self.shrunk(input, 1), verdict)
        }
      }
    }
    k = k + 1
  }
  if results.length() < batch.length() {
    // The child died on batch[results.length()]. The input is already minimal
    // in the sense that matters: we cannot shrink it without spawning per probe.
    let index = results.length()
    let input = batch[index]
    self.stats_.record_exec()
    self.push_finding(
      @core.FindingKind::Crash,
      self.shrunk(input, 2),
      "worker exited with code " +
      exit_code.to_string() +
      " on input " +
      index.to_string() +
      " of " +
      batch.length().to_string(),
    )
  }
}

///|
fn Session::oracle_kind(self : Session) -> @core.FindingKind {
  match self.case_.oracle() {
    @core.Oracle::Diff(_l, _r) => @core.FindingKind::Mismatch
    @core.Oracle::Custom(_n, _f) => @core.FindingKind::Violation
    @core.Oracle::Same => @core.FindingKind::Violation
  }
}

///|
fn Session::run_batch_inproc(self : Session, batch : Array[Bytes]) -> Unit {
  let mut i = 0
  while i < batch.length() {
    let input = batch[i]
    @cov.reset()
    let output = self.case_.target().run(input)
    self.stats_.record_exec()
    let verdict = self.case_.oracle().check(input, output)
    if verdict != "" {
      self.record(input, output, verdict)
    } else {
      self.stats_.record_accept()
      let novel = if @cov.observed() > 0 {
        self.buckets_.observe(@cov.fingerprint())
      } else {
        self.buckets_.observe(@cov.signature(output, input.length()))
      }
      if novel {
        self.stats_.record_novelty()
        if self.corpus_.add(input, 0) {
          self.stats_.record_corpus_add()
          self.pool_.push(input)
        }
      }
    }
    i = i + 1
  }
}
