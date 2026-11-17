///|
/// Minimization for the isolated runner.
///
/// The problem: ddmin needs to ask "is this reduced input still broken?" a few
/// hundred times, and every question costs a process. The solution is not to
/// make questions cheaper but to ask them in batches: each round generates all
/// candidates of one ddmin step, one worker judges the whole round, and a crash
/// in the middle only means the parent resubmits the tail.
///
/// `want` is the status a candidate must reach to count: 1 for "rejected by the
/// oracle", 2 for "killed the worker". Keeping them apart matters — otherwise a
/// mismatch finding could be minimized onto an unrelated crash.

///|
/// Drop the first `n` elements; used to resubmit the tail after a crash.
fn drop_first(inputs : Array[Bytes], n : Int32) -> Array[Bytes] {
  let out : Array[Bytes] = []
  let mut i = n
  while i < inputs.length() {
    out.push(inputs[i])
    i = i + 1
  }
  out
}

///|
/// Classify every input: 0 accepted, 1 rejected, 2 crashed.
///
/// Two things make this less trivial than it looks:
///   - a crash ends the worker, so the tail is resubmitted (bounded, so a
///     pathological target cannot make one round cost unbounded spawns);
///   - empty inputs never enter the batch. A zero-length line cannot survive the
///     hex format, and a shorter-than-expected result list is indistinguishable
///     from a crash — that mistake once turned every minimize round into 32
///     wasted spawns.
fn Session::probe(
  self : Session,
  exe : String,
  inputs : Array[Bytes],
) -> Array[Int32] {
  let statuses : Array[Int32] = []
  let mut i = 0
  while i < inputs.length() {
    statuses.push(0)
    i = i + 1
  }
  let payload : Array[Bytes] = []
  let origin : Array[Int32] = []
  let mut j = 0
  while j < inputs.length() {
    if inputs[j].length() > 0 {
      payload.push(inputs[j])
      origin.push(j)
    }
    j = j + 1
  }
  let mut start = 0
  let mut spawns = 0
  while start < payload.length() && spawns < 16 {
    spawns = spawns + 1
    let tail = drop_first(payload, start)
    match self.execute_chunk(exe, tail) {
      None =>
        // No worker: nothing can be classified, and pretending otherwise would
        // silently "minimize" to a wrong answer.
        start = payload.length()
      Some(chunk) => {
        let (results, _code) = chunk
        let mut k = 0
        while k < results.length() {
          let parts = split_tabs(results[k])
          let verdict = if parts.length() >= 3 {
            @utf8.decode_lossy(@core.parse_hex(parts[2]))
          } else {
            ""
          }
          if k < tail.length() {
            statuses[origin[start + k]] = if verdict == "" { 0 } else { 1 }
          }
          k = k + 1
        }
        if k < tail.length() {
          // The worker died on tail[k]: that input is the crash.
          statuses[origin[start + k]] = 2
          start = start + k + 1
        } else {
          start = payload.length()
        }
      }
    }
  }
  statuses
}

///|
/// Shrink `input` while it still reaches status `want`, or return it unchanged
/// when shrinking is disabled or no worker can be started.
fn Session::shrunk(self : Session, input : Bytes, want : Int32) -> Bytes {
  if !self.shrink_ || self.exe_.length() == 0 || input.length() < 2 {
    return input
  }
  // Bound the work: the first few findings are worth a careful reduction, and
  // after that the run is better spent exploring.
  if self.findings_.length() >= 8 {
    return input
  }
  @shrink.ddmin_batched(
    input,
    fn(candidates) {
      let statuses = self.probe(self.exe_, candidates)
      let flags : Array[Bool] = []
      let mut i = 0
      while i < candidates.length() {
        flags.push(i < statuses.length() && statuses[i] == want)
        i = i + 1
      }
      flags
    },
    20,
  )
}
