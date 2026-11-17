///|
/// Deterministic 32-bit LCG.
///
/// A fuzzer is only useful if a finding can be replayed, so the PRNG must be
/// (a) seedable, (b) identical on every backend, and (c) immune to the
/// signed/unsigned differences between wasm and native. A wrapping LCG over
/// `Int` with a 30-bit mask gives all three; low bits of an LCG are weak, so
/// `next_int` exposes the *high* bits and `below` uses modulo of those.
pub struct Rng {
  mut state : Int32
}

///|
pub fn Rng::new(seed : Int32) -> Rng {
  // Seed 0 would lock the LCG at a fixed point; force a non-zero state.
  { state: (seed & 0x3fffffff) + 1, }
}

///|
/// Advance the state and return 30 high-quality bits.
pub fn Rng::next_int(self : Rng) -> Int32 {
  let next = (self.state * 1103515245 + 12345) & 0x3fffffff
  self.state = next
  (next >> 14) & 0xffff
}

///|
/// Uniform-ish integer in `[0, n)`. Returns 0 for non-positive `n`.
pub fn Rng::below(self : Rng, n : Int32) -> Int32 {
  if n <= 0 {
    0
  } else {
    self.next_int() % n
  }
}

///|
pub fn Rng::next_bool(self : Rng) -> Bool {
  self.next_int() % 2 == 0
}

///|
/// A byte that is *not* uniform: interesting bytes (NUL, quotes, braces,
/// 0xFF, newline) show up far more often than in a uniform draw, because
/// parsers tend to break at boundaries rather than in the middle of a word.
pub fn Rng::next_interesting_byte(self : Rng) -> Byte {
  let interesting : Array[Byte] = [
    b'\x00', b'\x01', b'\x02', b'\x7f', b'\x80', b'\xff', b'"', b'\'', b'{', b'}',
    b'[', b']', b',', b':', b';', b'\n', b'\r', b'\t', b' ', b'\\', b'/', b'%', b'=',
    b'&', b'#', b'<', b'>',
  ]
  if self.next_bool() {
    interesting[self.below(interesting.length())]
  } else {
    self.next_int().to_byte()
  }
}

///|
/// Pick an index in `[0, n)`; `n` must be positive.
pub fn Rng::index(self : Rng, n : Int32) -> Int32 {
  self.below(n)
}
