// Corpus minimization ("cmin").
//
// A fuzz corpus grows monotonically: every input that reached a new id is kept,
// even after later inputs cover the same id. That is the right trade during a
// run — forgetting paths is worse than a large directory — but a 5,000-file
// corpus is painful to share, review, or check in.
//
// This is the set-cover pass: keep the smallest set of inputs that still reaches
// every id the full corpus reaches. Greedy is fine here; the exact problem is
// NP-hard and nobody needs an optimal answer.

///|
pub(all) struct CminResult {
  kept : Array[Int32]
  ids_total : Int32
  ids_covered : Int32
}

///|
/// The ids an input reaches. Instrumented targets hit real ids; uninstrumented
/// ones fall back to the output-shape bucket, so cmin still does something
/// sensible there (it keeps one representative per distinct output shape).
///
/// Ids are not necessarily small or positive — a shape signature is a hash — so
/// callers must compact them before using them as array indices.
pub fn coverage_of(case : @targets.Case, input : Bytes) -> Array[Int32] {
  @cov.reset()
  let output = case.target().run(input)
  if @cov.observed() > 0 {
    @cov.current_ids()
  } else {
    [@cov.signature(output, input.length())]
  }
}

///|
/// Index of `id` in `ids`, appending it when new. Linear scan: a target has tens
/// of ids, not thousands.
fn compact_index(ids : Array[Int32], id : Int32) -> Int32 {
  let mut i = 0
  while i < ids.length() {
    if ids[i] == id {
      return i
    }
    i = i + 1
  }
  ids.push(id)
  ids.length() - 1
}

///|
fn best_pick(
  keys : Array[Array[Int32]],
  covered : Array[Bool],
  used : Array[Bool],
  sizes : Array[Int32],
) -> Int32 {
  let mut best = -1
  let mut best_gain = 0
  let mut best_size = 0
  let mut i = 0
  while i < keys.length() {
    if !used[i] {
      let mut gain = 0
      let mut k = 0
      while k < keys[i].length() {
        let id = keys[i][k]
        if id >= 0 && id < covered.length() && !covered[id] {
          gain = gain + 1
        }
        k = k + 1
      }
      if gain > best_gain ||
        (gain == best_gain && gain > 0 && sizes[i] < best_size) {
        best = i
        best_gain = gain
        best_size = sizes[i]
      }
    }
    i = i + 1
  }
  best
}

///|
pub fn cmin(case : @targets.Case, inputs : Array[Bytes]) -> CminResult {
  // 1. Raw coverage per input, then compact the id space: a shape signature is a
  //    hash and would otherwise be used as an array index.
  let unique : Array[Int32] = []
  let keys : Array[Array[Int32]] = []
  let sizes : Array[Int32] = []
  let mut i = 0
  while i < inputs.length() {
    let ids = coverage_of(case, inputs[i])
    let compact : Array[Int32] = []
    let mut k = 0
    while k < ids.length() {
      compact.push(compact_index(unique, ids[k]))
      k = k + 1
    }
    keys.push(compact)
    sizes.push(inputs[i].length())
    i = i + 1
  }
  let total = unique.length()
  // 2. Greedy set cover over the compact ids.
  let reached : Array[Bool] = []
  let mut m = 0
  while m < total {
    reached.push(false)
    m = m + 1
  }
  let used : Array[Bool] = []
  let mut u = 0
  while u < inputs.length() {
    used.push(false)
    u = u + 1
  }
  let kept : Array[Int32] = []
  let mut got = 0
  while got < total {
    let pick = best_pick(keys, reached, used, sizes)
    if pick < 0 {
      break
    }
    used[pick] = true
    kept.push(pick)
    let mut k = 0
    while k < keys[pick].length() {
      let id = keys[pick][k]
      if id >= 0 && id < reached.length() && !reached[id] {
        reached[id] = true
        got = got + 1
      }
      k = k + 1
    }
  }
  { kept, ids_total: total, ids_covered: got, }
}
