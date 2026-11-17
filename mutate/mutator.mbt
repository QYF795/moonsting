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
    self.structural(data)
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
