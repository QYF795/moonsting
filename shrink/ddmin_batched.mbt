///|
fn first_true(flags : Array[Bool]) -> Int32 {
  let mut i = 0
  while i < flags.length() {
    if flags[i] {
      return i
    }
    i = i + 1
  }
  -1
}

///|
fn chunk_candidates(current : Bytes, n : Int32) -> Array[Bytes] {
  let out : Array[Bytes] = []
  let len = current.length()
  let chunk = (len + n - 1) / n
  let mut i = 0
  while i < n {
    let start = i * chunk
    if start < len {
      let size = if chunk < len - start { chunk } else { len - start }
      out.push(remove_span(current, start, size))
    }
    i = i + 1
  }
  out
}

///|
fn byte_candidates(current : Bytes) -> Array[Bytes] {
  let out : Array[Bytes] = []
  let mut i = 0
  while i < current.length() {
    out.push(remove_span(current, i, 1))
    i = i + 1
  }
  out
}

///|
/// Delta debugging where the predicate judges a batch.
///
/// `probe` receives every candidate of one round and must return one flag per
/// candidate (missing flags are treated as `false`). `max_rounds` bounds the
/// number of *rounds*, not probes: each round costs one worker invocation, so
/// twenty rounds is twenty process starts, not a thousand.
pub fn ddmin_batched(
  data : Bytes,
  probe : (Array[Bytes]) -> Array[Bool],
  max_rounds : Int32,
) -> Bytes {
  if data.length() < 2 {
    return data
  }
  let mut current = data
  let mut n = 2
  let mut rounds = 0
  while current.length() >= 2 && rounds < max_rounds {
    rounds = rounds + 1
    let candidates = chunk_candidates(current, n)
    let flags = probe(candidates)
    let hit = first_true(flags)
    if hit >= 0 && hit < candidates.length() {
      current = candidates[hit]
      n = if n > 2 { n - 1 } else { 2 }
    } else if n >= current.length() {
      break
    } else {
      n = if n * 2 < current.length() { n * 2 } else { current.length() }
    }
  }
  // Single-byte sweep: chunking can stop with removable bytes still present.
  let mut sweeping = true
  while sweeping && rounds < max_rounds {
    rounds = rounds + 1
    let candidates = byte_candidates(current)
    let flags = probe(candidates)
    let hit = first_true(flags)
    if hit >= 0 && hit < candidates.length() {
      current = candidates[hit]
    } else {
      sweeping = false
    }
  }
  current
}
