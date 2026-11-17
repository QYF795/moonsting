///|
/// A finished run, packaged for a caller that wants the text, the page and the
/// machine-readable lines without touching the engine.
pub struct Run {
  session_ : @engine.Session
}

///|
/// Look up a target by name and fuzz it. `None` means "no such target", which
/// callers are expected to turn into a usage error rather than a crash.
pub fn fuzz(target : String, config : @core.Config) -> Run? {
  match @targets.find(target) {
    Some(case) => Some({ session_: @engine.run(case, config), })
    None => None
  }
}

///|
/// Fuzz a target that was registered programmatically (the CLI does not need
/// this, an embedding application does).
pub fn fuzz_case(case : @targets.Case, config : @core.Config) -> Run {
  { session_: @engine.run(case, config), }
}

///|
pub fn Run::summary(self : Run) -> String {
  @report.summary(self.session_)
}

///|
pub fn Run::html(self : Run) -> String {
  @report.html(self.session_)
}

///|
pub fn Run::jsonl(self : Run) -> String {
  @report.jsonl(self.session_)
}

///|
pub fn Run::findings(self : Run) -> Array[@core.Finding] {
  self.session_.findings()
}

///|
pub fn Run::regression_test(self : Run, index : Int32) -> String {
  let findings = self.session_.findings()
  if index < 0 || index >= findings.length() {
    ""
  } else {
    @report.regression_test(findings[index])
  }
}

///|
pub fn Run::corpus_size(self : Run) -> Int32 {
  self.session_.corpus_size()
}

///|
pub fn Run::stats(self : Run) -> @core.Stats {
  self.session_.stats()
}

///|
pub fn Run::replay(self : Run, input : Bytes) -> String {
  self.session_.replay(input)
}

///|
pub fn target_names() -> Array[String] {
  @targets.names()
}
