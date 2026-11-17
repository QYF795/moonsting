///|
/// Cheap, compiler-free feedback signal.
///
/// A bucket is `(shape of the output, coarse length class)`. Two inputs that
/// produce the same shape are considered equivalent, which keeps the corpus
/// diverse instead of storing ten thousand variations of `"invalid input"`.
pub struct Buckets {
  seen_ : Array[Int32]
  mut observations_ : Int32
  mut novel_ : Int32
}

///|
pub fn Buckets::new() -> Buckets {
  { seen_: [], observations_: 0, novel_: 0, }
}

///|
pub fn Buckets::len(self : Buckets) -> Int32 {
  self.seen_.length()
}

///|
pub fn Buckets::novel(self : Buckets) -> Int32 {
  self.novel_
}

///|
pub fn Buckets::observations(self : Buckets) -> Int32 {
  self.observations_
}

///|
fn bucket_of_length(n : Int32) -> Int32 {
  // 0, 1, 2-3, 4-7, 8-15, ... -log2 buckets, capped.
  let mut step = 0
  let mut limit = 1
  while limit < n && step < 31 {
    limit = limit * 2
    step = step + 1
  }
  step
}

///|
/// Signature of one execution. `output` is the canonical string the target
/// returned; its first 64 bytes and its length class define the bucket.
pub fn signature(output : String, input_len : Int32) -> Int32 {
  let head = @core.short(@core.shape(output), 64)
  let h = @core.hash_bytes(@utf8.encode(head))
  (
    h * 131 +
    bucket_of_length(output.length()) * 17 +
    bucket_of_length(input_len)
  ) &
  0x3fffffff
}

///|
/// Record a signature; returns `true` when it had never been seen before.
pub fn Buckets::observe(self : Buckets, sig : Int32) -> Bool {
  self.observations_ = self.observations_ + 1
  let mut i = 0
  while i < self.seen_.length() {
    if self.seen_[i] == sig {
      return false
    }
    i = i + 1
  }
  self.seen_.push(sig)
  self.novel_ = self.novel_ + 1
  true
}
