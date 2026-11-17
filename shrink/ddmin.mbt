///|
/// Remove `len` bytes starting at `start`.
pub fn remove_span(data : Bytes, start : Int32, len : Int32) -> Bytes {
  let out : Array[Byte] = []
  let mut i = 0
  while i < data.length() {
    if i < start || i >= start + len {
      out.push(data[i])
    }
    i = i + 1
  }
  @core.bytes_of(out)
}

///|
/// Classic ddmin: repeatedly try to delete a chunk while `interesting` still
/// holds, halving the chunk size on success and doubling it on failure.
///
/// `max_probes` bounds how often the predicate may run, so a slow oracle
/// degrades into a smaller-but-still-correct reduction instead of hanging.
/// A finding is worth more when it is 8 bytes than when it is 4000, both for
/// the person reading the bug report and for the regression test that pins it.
pub fn ddmin(
  data : Bytes,
  interesting : (Bytes) -> Bool,
  max_probes : Int32,
) -> Bytes {
  if !interesting(data) {
    return data
  }
  let mut current = data
  let mut probes = 0
  let mut n = 2
  while current.length() >= 2 && probes < max_probes {
    let len = current.length()
    let chunk = (len + n - 1) / n
    let mut reduced = false
    let mut i = 0
    while i < n && !reduced && probes < max_probes {
      let start = i * chunk
      if start < len {
        let size = if chunk < len - start { chunk } else { len - start }
        let candidate = remove_span(current, start, size)
        probes = probes + 1
        if candidate.length() < current.length() && interesting(candidate) {
          current = candidate
          n = if n > 2 { n - 1 } else { 2 }
          reduced = true
        }
      }
      i = i + 1
    }
    if !reduced {
      if n >= current.length() {
        break
      }
      n = if n * 2 < current.length() { n * 2 } else { current.length() }
    }
  }
  // Final single-byte sweep: ddmin's chunking can stop at `n == len` with
  // individual removable bytes still present.
  let mut shrinking = true
  while shrinking && probes < max_probes {
    shrinking = false
    let mut i = 0
    while i < current.length() && probes < max_probes {
      let candidate = remove_span(current, i, 1)
      probes = probes + 1
      if interesting(candidate) {
        current = candidate
        shrinking = true
      } else {
        i = i + 1
      }
    }
  }
  current
}
