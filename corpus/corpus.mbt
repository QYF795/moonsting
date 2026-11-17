///|
/// One kept input. `hits` tracks how often it has been selected, which the
/// scheduler uses to avoid starving newer entries.
pub struct Entry {
  data_ : Bytes
  mut hits_ : Int32
  tag_ : Int32
}

///|
pub fn Entry::data(self : Entry) -> Bytes {
  self.data_
}

///|
pub fn Entry::hits(self : Entry) -> Int32 {
  self.hits_
}

///|
pub fn Entry::tag(self : Entry) -> Int32 {
  self.tag_
}

///|
/// Deduplicating corpus with tournament selection.
///
/// Selection is biased towards *smaller* entries: a 12-byte input that still
/// reaches an interesting state is worth more than a 4 KB one, because every
/// mutation of it is more likely to stay interesting. That single bias is why
/// minimized inputs get found at all.
pub struct Corpus {
  entries_ : Array[Entry]
  hashes_ : Array[Int32]
  mut picks_ : Int32
}

///|
pub fn Corpus::new() -> Corpus {
  { entries_: [], hashes_: [], picks_: 0, }
}

///|
pub fn Corpus::len(self : Corpus) -> Int32 {
  self.entries_.length()
}

///|
pub fn Corpus::is_empty(self : Corpus) -> Bool {
  self.entries_.length() == 0
}

///|
/// Returns `false` when the input was already present. Duplicates are checked
/// by hash first (cheap) and by bytes second (hash collisions must not lose an
/// input).
pub fn Corpus::add(self : Corpus, data : Bytes, tag : Int32) -> Bool {
  let h = @core.hash_bytes(data)
  let mut i = 0
  while i < self.hashes_.length() {
    if self.hashes_[i] == h {
      if @core.bytes_equal(self.entries_[i].data_, data) {
        return false
      }
    }
    i = i + 1
  }
  self.entries_.push({ data_: data, hits_: 0, tag_: tag, })
  self.hashes_.push(h)
  true
}

///|
/// Pick an entry by running a small tournament and preferring the shorter one.
pub fn Corpus::pick(self : Corpus) -> Bytes {
  let n = self.entries_.length()
  if n == 0 {
    b""
  } else {
    let mut best = self.picks_ % n
    let mut round = 0
    while round < 3 {
      let candidate = (self.picks_ + round * 7919 + 13) % n
      if self.entries_[candidate].data_.length() <
        self.entries_[best].data_.length() {
        best = candidate
      }
      round = round + 1
    }
    self.picks_ = self.picks_ + 1
    self.entries_[best].hits_ = self.entries_[best].hits_ + 1
    self.entries_[best].data_
  }
}

///|
pub fn Corpus::all(self : Corpus) -> Array[Bytes] {
  let out : Array[Bytes] = []
  let mut i = 0
  while i < self.entries_.length() {
    out.push(self.entries_[i].data_)
    i = i + 1
  }
  out
}

///|
/// Index of the shortest entry, or -1 for an empty corpus.
pub fn Corpus::shortest(self : Corpus) -> Int32 {
  let mut best = -1
  let mut i = 0
  while i < self.entries_.length() {
    if best < 0 ||
      self.entries_[i].data_.length() < self.entries_[best].data_.length() {
      best = i
    }
    i = i + 1
  }
  best
}

///|
/// Drop entries beyond `keep`, discarding the largest ones first. Long runs
/// would otherwise accumulate thousands of near-duplicates and slow every
/// subsequent mutation round.
pub fn Corpus::trim(self : Corpus, keep : Int32) -> Unit {
  while self.entries_.length() > keep && self.entries_.length() > 0 {
    let mut worst = 0
    let mut i = 1
    while i < self.entries_.length() {
      if self.entries_[i].data_.length() > self.entries_[worst].data_.length() {
        worst = i
      }
      i = i + 1
    }
    ignore(self.entries_.remove(worst))
    ignore(self.hashes_.remove(worst))
  }
}
