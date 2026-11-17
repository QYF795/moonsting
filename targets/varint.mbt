///|
/// LEB128 decoders, deliberately paired.
///
/// Instrumented with `@cov.hit`: the ids encode *where* the decoder stopped and
/// *how many bytes* it consumed, which is exactly the structure a fuzzer needs
/// to keep exploring this function. `varint_ref` is the correct one;
/// `varint_fast` decodes into 32-bit `Int` and shifts without checking the
/// shift width, so any value that needs more than 32 bits is silently
/// truncated.
///
/// Coverage ids for this target live in 300..319.

///|
pub fn varint_ref(input : Bytes) -> String {
  let mut value : Int64 = 0
  let mut shift = 0
  let mut i = 0
  while i < input.length() {
    if i >= 10 {
      @cov.hit(300)
      return "err"
    }
    @cov.hit(301 + i)
    let b = input[i].to_int() & 0x7f
    value = value | (b.to_int64() << shift)
    if (input[i].to_int() & 0x80) == 0 {
      return "v:" + value.to_string()
    }
    shift = shift + 7
    i = i + 1
  }
  @cov.hit(312)
  "err"
}

///|
pub fn varint_fast(input : Bytes) -> String {
  let mut value = 0
  let mut shift = 0
  let mut i = 0
  while i < input.length() {
    if i >= 10 {
      @cov.hit(300)
      return "err"
    }
    @cov.hit(301 + i)
    let b = input[i].to_int() & 0x7f
    value = value | (b << shift)
    if (input[i].to_int() & 0x80) == 0 {
      return "v:" + value.to_string()
    }
    shift = shift + 7
    i = i + 1
  }
  @cov.hit(312)
  "err"
}
