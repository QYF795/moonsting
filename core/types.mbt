///|
/// A fuzz target: a named entry point plus a seed corpus.
///
/// `body` must not raise. Wrap fallible parsers in `try`/`catch` inside the
/// target so that "rejected the input" stays distinguishable from "crashed":
/// the engine can only reason about values it receives.
pub struct Target {
  name_ : String
  seeds_ : Array[Bytes]
  body_ : (Bytes) -> String
}

///|
pub fn Target::new(
  name : String,
  seeds : Array[Bytes],
  body : (Bytes) -> String,
) -> Target {
  { name_: name, seeds_: seeds, body_: body, }
}

///|
pub fn Target::name(self : Target) -> String {
  self.name_
}

///|
pub fn Target::seeds(self : Target) -> Array[Bytes] {
  self.seeds_
}

///|
pub fn Target::run(self : Target, input : Bytes) -> String {
  (self.body_)(input)
}

///|
/// How a result is judged.
pub(all) enum Oracle {
  /// Smoke mode: every completed execution is accepted. Useful for growing a
  /// corpus for a target whose correctness oracle does not exist yet.
  Same
  /// Differential mode: two implementations of the same contract must agree.
  Diff(Target, Target)
  /// User-supplied invariant. Returns "" when the input is fine, or a short
  /// human-readable reason when it is not.
  Custom(String, (Bytes, String) -> String)
}

///|
pub fn Oracle::label(self : Oracle) -> String {
  match self {
    Oracle::Same => "same"
    Oracle::Diff(left, right) =>
      "diff(" + left.name() + "," + right.name() + ")"
    Oracle::Custom(name, _f) => name
  }
}

///|
/// `""` means "accepted". Anything else is the reason the input was rejected.
pub fn Oracle::check(self : Oracle, input : Bytes, output : String) -> String {
  match self {
    Oracle::Same => ""
    Oracle::Diff(left, right) => {
      let a = left.run(input)
      let b = right.run(input)
      if a == b {
        ""
      } else {
        "expected " + short(b, 120) + " got " + short(a, 120)
      }
    }
    Oracle::Custom(_name, f) => f(input, output)
  }
}

///|
/// Tunables for one fuzzing session.
pub struct Config {
  mut seed_ : Int32
  mut max_execs_ : Int32
  /// 0 means "no wall-clock limit".
  mut time_budget_ms_ : UInt64
  mut max_input_len_ : Int32
  mut max_findings_ : Int32
  mut quiet_ : Bool
}

///|
pub fn Config::default() -> Config {
  {
    seed_: 0,
    max_execs_: 100000,
    time_budget_ms_: 0,
    max_input_len_: 4096,
    max_findings_: 32,
    quiet_: false,
  }
}

///|
pub fn Config::with_seed(self : Config, seed : Int32) -> Config {
  self.seed_ = seed
  self
}

///|
pub fn Config::with_max_execs(self : Config, n : Int32) -> Config {
  self.max_execs_ = n
  self
}

///|
pub fn Config::with_time_budget_ms(self : Config, ms : UInt64) -> Config {
  self.time_budget_ms_ = ms
  self
}

///|
pub fn Config::with_max_input_len(self : Config, n : Int32) -> Config {
  self.max_input_len_ = n
  self
}

///|
pub fn Config::with_max_findings(self : Config, n : Int32) -> Config {
  self.max_findings_ = n
  self
}

///|
pub fn Config::with_quiet(self : Config, quiet : Bool) -> Config {
  self.quiet_ = quiet
  self
}

///|
pub fn Config::seed(self : Config) -> Int32 {
  self.seed_
}

///|
pub fn Config::max_execs(self : Config) -> Int32 {
  self.max_execs_
}

///|
pub fn Config::time_budget_ms(self : Config) -> UInt64 {
  self.time_budget_ms_
}

///|
pub fn Config::max_input_len(self : Config) -> Int32 {
  self.max_input_len_
}

///|
pub fn Config::max_findings(self : Config) -> Int32 {
  self.max_findings_
}

///|
pub fn Config::quiet(self : Config) -> Bool {
  self.quiet_
}

///|
pub(all) enum FindingKind {
  Mismatch
  Violation
  /// The target died (panic / abort) in a worker process. Only the isolated
  /// runner can report this: in-process, the crash takes the fuzzer with it.
  Crash
}

///|
pub fn FindingKind::label(self : FindingKind) -> String {
  match self {
    FindingKind::Mismatch => "mismatch"
    FindingKind::Violation => "violation"
    FindingKind::Crash => "crash"
  }
}

///|
/// One rejected input, already minimized by the time it reaches a report.
pub struct Finding {
  kind_ : FindingKind
  target_ : String
  input_ : Bytes
  detail_ : String
  exec_ : Int32
}

///|
pub fn Finding::new(
  kind : FindingKind,
  target : String,
  input : Bytes,
  detail : String,
  exec : Int32,
) -> Finding {
  { kind_: kind, target_: target, input_: input, detail_: detail, exec_: exec, }
}

///|
pub fn Finding::kind(self : Finding) -> FindingKind {
  self.kind_
}

///|
pub fn Finding::target(self : Finding) -> String {
  self.target_
}

///|
pub fn Finding::input(self : Finding) -> Bytes {
  self.input_
}

///|
pub fn Finding::detail(self : Finding) -> String {
  self.detail_
}

///|
pub fn Finding::exec(self : Finding) -> Int32 {
  self.exec_
}

///|
/// Counters for the run summary. Deliberately plain data: the engine owns it,
/// the reporters read it, and nothing else needs to know it exists.
pub struct Stats {
  mut execs_ : Int32
  mut accepted_ : Int32
  mut novelty_ : Int32
  mut corpus_adds_ : Int32
  mut findings_ : Int32
  mut elapsed_ms_ : UInt64
}

///|
pub fn Stats::new() -> Stats {
  {
    execs_: 0,
    accepted_: 0,
    novelty_: 0,
    corpus_adds_: 0,
    findings_: 0,
    elapsed_ms_: 0,
  }
}

///|
pub fn Stats::execs(self : Stats) -> Int32 {
  self.execs_
}

///|
pub fn Stats::record_exec(self : Stats) -> Unit {
  self.execs_ = self.execs_ + 1
}

///|
pub fn Stats::accepted(self : Stats) -> Int32 {
  self.accepted_
}

///|
pub fn Stats::record_accept(self : Stats) -> Unit {
  self.accepted_ = self.accepted_ + 1
}

///|
pub fn Stats::novelty(self : Stats) -> Int32 {
  self.novelty_
}

///|
pub fn Stats::record_novelty(self : Stats) -> Unit {
  self.novelty_ = self.novelty_ + 1
}

///|
pub fn Stats::corpus_adds(self : Stats) -> Int32 {
  self.corpus_adds_
}

///|
pub fn Stats::record_corpus_add(self : Stats) -> Unit {
  self.corpus_adds_ = self.corpus_adds_ + 1
}

///|
pub fn Stats::findings(self : Stats) -> Int32 {
  self.findings_
}

///|
pub fn Stats::record_finding(self : Stats) -> Unit {
  self.findings_ = self.findings_ + 1
}

///|
pub fn Stats::elapsed_ms(self : Stats) -> UInt64 {
  self.elapsed_ms_
}

///|
pub fn Stats::set_elapsed_ms(self : Stats, ms : UInt64) -> Unit {
  self.elapsed_ms_ = ms
}

///|
/// Truncate for one-line output.
pub fn short(s : String, max : Int32) -> String {
  if s.length() <= max {
    s
  } else {
    let sb = StringBuilder()
    let mut i = 0
    while i < max {
      sb.write_char(s.get_char(i).unwrap())
      i = i + 1
    }
    sb.to_string() + "..."
  }
}
