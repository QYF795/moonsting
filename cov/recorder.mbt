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

///|
/// Every id hit since the last `clear_seen`, unsorted.
pub fn seen_ids() -> Array[Int32] {
  let out : Array[Int32] = []
  let mut i = 0
  while i < seen_.length() {
    out.push(seen_[i])
    i = i + 1
  }
  out
}

///|
pub fn sorted_seen() -> Array[Int32] {
  let out = seen_ids()
  let mut i = 1
  while i < out.length() {
    let value = out[i]
    let mut j = i
    while j > 0 && out[j - 1] > value {
      out[j] = out[j - 1]
      j = j - 1
    }
    out[j] = value
    i = i + 1
  }
  out
}

///|
/// Compress a sorted id list into inclusive ranges of consecutive ids.
pub fn ranges(ids : Array[Int32]) -> Array[(Int32, Int32)] {
  let out : Array[(Int32, Int32)] = []
  let mut i = 0
  while i < ids.length() {
    let start = ids[i]
    let mut end = start
    while i + 1 < ids.length() && ids[i + 1] == end + 1 {
      end = ids[i + 1]
      i = i + 1
    }
    out.push((start, end))
    i = i + 1
  }
  out
}

///|
/// Ids that were *declared* (they fall inside the span of ids that were hit) but
/// never observed. This is the number that tells an instrumenter where the
/// unreachable code is: ids are allocated in dense per-target ranges by
/// convention, so a hole in the middle means a branch nobody reached.
pub fn gaps(ids : Array[Int32]) -> Array[(Int32, Int32)] {
  let compressed = ranges(ids)
  let out : Array[(Int32, Int32)] = []
  let mut i = 1
  while i < compressed.length() {
    let (_, prev_end) = compressed[i - 1]
    let (next_start, _) = compressed[i]
    if next_start > prev_end + 2 {
      out.push((prev_end + 1, next_start - 1))
    }
    i = i + 1
  }
  out
}

///|
/// Sort an arbitrary id array (the helper `sorted_seen` uses internally, exposed
/// so range formatting can be tested without touching global state).
pub fn sorted_seen_from(ids : Array[Int32]) -> Array[Int32] {
  let out : Array[Int32] = []
  let mut i = 0
  while i < ids.length() {
    out.push(ids[i])
    i = i + 1
  }
  let mut a = 1
  while a < out.length() {
    let value = out[a]
    let mut j = a
    while j > 0 && out[j - 1] > value {
      out[j] = out[j - 1]
      j = j - 1
    }
    out[j] = value
    a = a + 1
  }
  out
}

///|
/// "600-601, 603" — the human form of a range list.
pub fn format_ranges(ranges : Array[(Int32, Int32)]) -> String {
  let sb = StringBuilder()
  let mut i = 0
  while i < ranges.length() {
    if i > 0 {
      sb.write_string(", ")
    }
    let (from, to) = ranges[i]
    sb.write_string(from.to_string())
    if to > from {
      sb.write_string("-")
      sb.write_string(to.to_string())
    }
    i = i + 1
  }
  sb.to_string()
}

///|
/// Merge ids observed in another process into this process's set. The isolated
/// runner uses this to rebuild coverage in the parent from what each worker
/// reports.
pub fn merge_seen(ids : Array[Int32]) -> Unit {
  let mut i = 0
  while i < ids.length() {
    let id = ids[i]
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
    }
    i = i + 1
  }
}

///|
/// "600,601,605" — the wire form used to carry ids out of a worker.
pub fn encode_ids(ids : Array[Int32]) -> String {
  let sb = StringBuilder()
  let mut i = 0
  while i < ids.length() {
    if i > 0 {
      sb.write_char(',')
    }
    sb.write_string(ids[i].to_string())
    i = i + 1
  }
  sb.to_string()
}

///|
pub fn decode_ids(text : String) -> Array[Int32] {
  let out : Array[Int32] = []
  let sb = StringBuilder()
  let mut i = 0
  while i <= text.length() {
    if i == text.length() || text.get_char(i).unwrap() == ',' {
      let piece = sb.to_string()
      if piece.length() > 0 {
        out.push(int_of_str(piece))
      }
      sb.reset()
    } else {
      sb.write_char(text.get_char(i).unwrap())
    }
    i = i + 1
  }
  out
}

///|
fn int_of_str(text : String) -> Int32 {
  let mut value = 0
  let mut i = 0
  while i < text.length() {
    let v = text.get_char(i).unwrap().to_int()
    if v < 48 || v > 57 {
      return value
    }
    value = value * 10 + (v - 48)
    i = i + 1
  }
  value
}
