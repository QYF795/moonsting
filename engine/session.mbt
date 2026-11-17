///|
/// One fuzzing session. Holds the corpus, the coverage signal and the findings
/// so that a caller can run once and then report, replay or minimize without
/// re-running the loop.
pub struct Session {
  case_ : @targets.Case
  config_ : @core.Config
  mutator_ : @mutate.Mutator
  corpus_ : @corpus.Corpus
  buckets_ : @cov.Buckets
  stats_ : @core.Stats
  findings_ : Array[@core.Finding]
  verdicts_ : Array[Int32]
  pool_ : Array[Bytes]
  mut batch_ : Int32
  /// Set by the isolated runner: the worker executable and whether findings are
  /// minimized (minimizing costs one process per probe round).
  mut exe_ : String
  mut shrink_ : Bool
}

///|
/// The one place a session is constructed, so the in-process and isolated
/// runners cannot drift apart.
fn make(case : @targets.Case, config : @core.Config) -> Session {
  {
    case_: case,
    config_: config,
    mutator_: @mutate.Mutator::new(
      config.seed(),
      @mutate.Dictionary::generic(),
      config.max_input_len(),
    ),
    corpus_: @corpus.Corpus::new(),
    buckets_: @cov.Buckets::new(),
    stats_: @core.Stats::new(),
    findings_: [],
    verdicts_: [],
    pool_: [],
    batch_: 0,
    exe_: "",
    shrink_: false,
  }
}

///|
pub fn run(case : @targets.Case, config : @core.Config) -> Session {
  run_with(case, config, [])
}

///|
/// Same as `run`, plus extra seed inputs (hex strings passed on the command
/// line, or a corpus exported by a previous run). Seeds are loaded before the
/// loop, so they participate in mutation from the very first execution.
pub fn run_with(
  case : @targets.Case,
  config : @core.Config,
  extra_seeds : Array[Bytes],
) -> Session {
  let session = make(case, config)
  session.prime(extra_seeds)
  session.drive()
  session
}

///|
pub fn Session::stats(self : Session) -> @core.Stats {
  self.stats_
}

///|
pub fn Session::case(self : Session) -> @targets.Case {
  self.case_
}

///|
pub fn Session::findings(self : Session) -> Array[@core.Finding] {
  self.findings_
}

///|
pub fn Session::corpus_size(self : Session) -> Int32 {
  self.corpus_.len()
}

///|
pub fn Session::bucket_count(self : Session) -> Int32 {
  self.buckets_.len()
}

///|
pub fn Session::replay(self : Session, input : Bytes) -> String {
  let output = self.case_.target().run(input)
  self.case_.oracle().check(input, output)
}

///|
fn Session::prime(self : Session, extra_seeds : Array[Bytes]) -> Unit {
  let seeds = self.case_.seeds()
  let mut i = 0
  while i < seeds.length() {
    let seed = seeds[i]
    @cov.reset()
    let output = self.case_.target().run(seed)
    self.stats_.record_exec()
    if @cov.observed() > 0 {
      ignore(self.buckets_.observe(@cov.fingerprint()))
    } else {
      ignore(self.buckets_.observe(@cov.signature(output, seed.length())))
    }
    if self.corpus_.add(seed, 0) {
      self.pool_.push(seed)
    }
    i = i + 1
  }
  let mut j = 0
  while j < extra_seeds.length() {
    let seed = extra_seeds[j]
    @cov.reset()
    let output = self.case_.target().run(seed)
    self.stats_.record_exec()
    if @cov.observed() > 0 {
      ignore(self.buckets_.observe(@cov.fingerprint()))
    } else {
      ignore(self.buckets_.observe(@cov.signature(output, seed.length())))
    }
    if self.corpus_.add(seed, 0) {
      self.pool_.push(seed)
    }
    j = j + 1
  }
}

///|
/// The final corpus, in insertion order. Exposed so the CLI can print it as
/// hex lines (`--dump-corpus`), which is how a run is resumed without needing
/// a filesystem API: redirect it to a file, feed it back with `--seed-input`.
pub fn Session::corpus_inputs(self : Session) -> Array[Bytes] {
  self.corpus_.all()
}

///|
fn Session::drive(self : Session) -> Unit {
  let started = @env.now()
  let budget = self.config_.time_budget_ms()
  let max_execs = self.config_.max_execs()
  let max_findings = self.config_.max_findings()
  let mut halt = false
  while !halt && self.stats_.execs() < max_execs {
    if budget > 0UL && @env.now() - started >= budget {
      halt = true
    } else {
      self.step()
      self.batch_ = self.batch_ + 1
      if self.batch_ % 512 == 0 && self.corpus_.len() > 2048 {
        self.corpus_.trim(1024)
      }
      if self.findings_.length() >= max_findings {
        halt = true
      }
    }
  }
  self.stats_.set_elapsed_ms(@env.now() - started)
}

///|
fn Session::step(self : Session) -> Unit {
  let candidate = self.candidate()
  @cov.reset()
  let output = self.case_.target().run(candidate)
  self.stats_.record_exec()
  let verdict = self.case_.oracle().check(candidate, output)
  if verdict != "" {
    self.record(candidate, output, verdict)
  } else {
    self.stats_.record_accept()
    // An instrumented target reports the branches it took; an uninstrumented
    // one reports nothing and gets the weaker shape-based signal instead. The
    // engine does not need to be told which kind it is looking at.
    let novel = if @cov.observed() > 0 {
      self.buckets_.observe(@cov.fingerprint())
    } else {
      self.buckets_.observe(@cov.signature(output, candidate.length()))
    }
    if novel {
      self.stats_.record_novelty()
      if self.corpus_.add(candidate, 0) {
        self.stats_.record_corpus_add()
        self.pool_.push(candidate)
      }
    }
  }
}

///|
fn Session::record(
  self : Session,
  input : Bytes,
  _output : String,
  verdict : String,
) -> Unit {
  let kind = match self.case_.oracle() {
    @core.Oracle::Diff(_l, _r) => @core.FindingKind::Mismatch
    @core.Oracle::Custom(_n, _f) => @core.FindingKind::Violation
    @core.Oracle::Same => @core.FindingKind::Violation
  }
  let small = self.shrink(input)
  self.push_finding(kind, small, verdict)
}

///|
/// Add a finding, deduplicated by the *shape* of its detail text: `v:4294967186`
/// and `v:12348032000` are the same bug (a 32-bit truncation), and a report with
/// sixteen copies of it is worse than a report with one. The isolated runner
/// uses this directly, because it cannot minimize a crash without spawning.
fn Session::push_finding(
  self : Session,
  kind : @core.FindingKind,
  input : Bytes,
  detail : String,
) -> Unit {
  let key = @core.hash_bytes(@utf8.encode(@core.shape(detail)))
  let mut i = 0
  while i < self.verdicts_.length() {
    if self.verdicts_[i] == key {
      return
    }
    i = i + 1
  }
  self.verdicts_.push(key)
  self.findings_.push(
    @core.Finding::new(
      kind,
      self.case_.name(),
      input,
      detail,
      self.stats_.execs(),
    ),
  )
  self.stats_.record_finding()
}

///|
/// One candidate input: pick from the corpus, mutate. Shared by the in-process
/// loop and the isolated one so both explore the same way.
fn Session::candidate(self : Session) -> Bytes {
  let base = self.corpus_.pick()
  self.mutator_.mutate(base, self.pool_)
}

///|
/// Shrink with the oracle as the predicate: "still produces this class of bad
/// result". The predicate is re-evaluated, not memoized, because minimization
/// must remain valid under a nondeterministic target.
fn Session::shrink(self : Session, input : Bytes) -> Bytes {
  let target = self.case_.target()
  let oracle = self.case_.oracle()
  @shrink.ddmin(
    input,
    fn(candidate) { oracle.check(candidate, target.run(candidate)) != "" },
    2000,
  )
}
