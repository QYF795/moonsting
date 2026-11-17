// A manual coverage recorder.
//
// MoonBit's own coverage instrumentation is a *test-run* feature: an
// instrumented binary does not leave an artifact behind (`moon test
// --enable-coverage` does, a plain run does not), so a fuzzer cannot read it
// per execution. The honest alternative is manual instrumentation — the same
// thing AFL calls `__afl_manual` and libFuzzer calls a user-defined counter:
// the target calls `hit(id)` at each branch it cares about, and the engine
// compares the hit set before and after every execution.
//
// The ids are ours, chosen at the instrumentation sites. Granularity is
// whatever the instrumenter writes, which for a parser is usually better than
// compiled-in block coverage: the interesting branches are exactly the ones a
// human would name.
//
// Globals, because an instrumented function must be able to record without
// threading a context parameter through every call site. MoonBit allows a
// top-level `let` bound to an array, which is all this needs.

///|
/// ids hit during the current execution (deduplicated on insert)
let hits_ : Array[Int32] = []

///|
/// ids ever hit since the last `clear_seen`
let seen_ : Array[Int32] = []

///|
/// Record a branch. Called by instrumented targets; cheap and idempotent
/// within one execution.
pub fn hit(id : Int32) -> Unit {
  let n = hits_.length()
  let mut i = 0
  while i < n {
    if hits_[i] == id {
      return
    }
    i = i + 1
  }
  hits_.push(id)
}

///|
/// Start a new execution.
pub fn reset() -> Unit {
  while hits_.length() > 0 {
    ignore(hits_.pop())
  }
}

///|
/// How many distinct ids the current execution hit. Zero means "this target is
/// not instrumented", which is the signal for the engine to fall back to its
/// shape-based feedback.
pub fn observed() -> Int32 {
  hits_.length()
}

///|
/// Merge the current execution into the global set; `true` when it contained
/// at least one id never hit before.
pub fn commit() -> Bool {
  let mut fresh = false
  let mut i = 0
  while i < hits_.length() {
    let id = hits_[i]
    let mut known = false
    let mut j = 0
    while j < seen_.length() {
      if seen_[j] == id {
        known = true
      }
      j = j + 1
    }
    if !known {
      seen_.push(id)
      fresh = true
    }
    i = i + 1
  }
  fresh
}

///|
pub fn seen_count() -> Int32 {
  seen_.length()
}

///|
/// Drop the accumulated set (tests, and a fresh run in the same process).
pub fn clear_seen() -> Unit {
  while seen_.length() > 0 {
    ignore(seen_.pop())
  }
}

///|
/// Order-insensitive fingerprint of the current execution. Used by the worker
/// as its result signature: two inputs with the same fingerprint took the same
/// branches, whatever order they took them in.
pub fn fingerprint() -> Int32 {
  // XOR of per-id hashes: commutative, so the order in which a target took its
  // branches cannot change the signature. The avalanche runs once at the end,
  // after the order-sensitive part would have mattered.
  let mut acc : UInt32 = 0U
  let mut i = 0
  while i < hits_.length() {
    let v = hits_[i].reinterpret_as_uint()
    let mut h = v * 2654435761U
    h = h ^ (h >> 15)
    acc = acc ^ h
    i = i + 1
  }
  acc = acc ^ (acc >> 16)
  acc = acc * 2246822519U
  acc = acc ^ (acc >> 13)
  (acc & 0x3fffffffU).reinterpret_as_int()
}
