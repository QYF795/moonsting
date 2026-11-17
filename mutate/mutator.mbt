///|
/// A stateful mutator. The PRNG lives here so a whole session is reproducible
/// from `--seed`: replays must produce the same sequence of candidate inputs.
pub struct Mutator {
  rng_ : @core.Rng
  dict_ : Dictionary
  max_len_ : Int32
}

///|
pub fn Mutator::new(
  seed : Int32,
  dict : Dictionary,
  max_len : Int32,
) -> Mutator {
  { rng_: @core.Rng::new(seed), dict_: dict, max_len_: max_len, }
}

///|
pub fn Mutator::rng(self : Mutator) -> @core.Rng {
  self.rng_
}

///|
/// Apply between one and four mutation rounds to `base`.
pub fn Mutator::mutate(
  self : Mutator,
  base : Bytes,
  corpus : Array[Bytes],
) -> Bytes {
  let data = @core.array_of(base)
  let rounds = 1 + self.rng_.below(4)
  let mut i = 0
  while i < rounds {
    self.round(data, corpus)
    i = i + 1
  }
  @core.bytes_of(data)
}

///|
fn Mutator::round(
  self : Mutator,
  data : Array[Byte],
  corpus : Array[Bytes],
) -> Unit {
  let roll = self.rng_.below(100)
  if roll < 40 {
    self.havoc(data)
  } else if roll < 62 {
    self.structured(data)
  } else if roll < 78 {
    self.dict_insert(data)
  } else if roll < 90 {
    self.splice(data, corpus)
  } else {
    self.boundary(data)
  }
}

///|
fn pop(data : Array[Byte]) -> Unit {
  if data.length() > 0 {
    ignore(data.pop())
  }
}

///|
fn Mutator::take_token(self : Mutator) -> Bytes {
  let tokens = self.dict_.tokens()
  if tokens.length() == 0 {
    b""
  } else {
    tokens[self.rng_.below(tokens.length())]
  }
}

///|
/// Dispatch on the *shape* of the current input, not on the target. A mutator
/// has no idea what it is feeding, so it looks at the bytes: JSON documents get
/// token-level edits, base64 gets alphabet/padding edits, percent-encoded text
/// gets escape edits, CSV keeps its existing quoting edits, and everything else
/// gets the length-poke that length-prefixed formats hate.
fn Mutator::structured(self : Mutator, data : Array[Byte]) -> Unit {
  let current = @core.bytes_of(data)
  match detect(current) {
    Shape::Csv => self.csv_edit(data)
    Shape::Json =>
      self.apply(
        data,
        json_mutate(self.rng_, current, self.dict_, self.max_len_),
      )
    Shape::Base64 => self.apply(data, base64_mutate(self.rng_, current))
    Shape::Urlenc => self.apply(data, urlenc_mutate(self.rng_, current))
    Shape::Binary => self.apply(data, length_mutate(self.rng_, current))
  }
}

///|
/// Replace the buffer contents, respecting the length cap.
fn Mutator::apply(self : Mutator, data : Array[Byte], next : Bytes) -> Unit {
  truncate_to(data, 0)
  let mut i = 0
  while i < next.length() && data.length() < self.max_len_ {
    data.push(next[i])
    i = i + 1
  }
}
