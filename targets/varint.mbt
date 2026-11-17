///|
/// LEB128 decoders, deliberately paired.
///
/// `varint_ref` decodes into `Int64` and is correct for any 10-byte varint.
/// `varint_fast` decodes into 32-bit `Int` and shifts without checking the
/// shift width, so any value that needs more than 32 bits (5+ continuation
/// bytes) is silently truncated. This is a *realistic* bug shape: it is the
/// kind of code that passes every hand-written test and fails on input byte
/// 6. The differential oracle finds it without knowing what "correct" means.
pub fn varint_ref(input : Bytes) -> String {
  let mut value : Int64 = 0
  let mut shift = 0
  let mut i = 0
  while i < input.length() {
    if i >= 10 {
      return "err"
    }
    let b = input[i].to_int() & 0x7f
    value = value | (b.to_int64() << shift)
    if (input[i].to_int() & 0x80) == 0 {
      return "v:" + value.to_string()
    }
    shift = shift + 7
    i = i + 1
  }
  "err"
}

///|
pub fn varint_fast(input : Bytes) -> String {
  let mut value = 0
  let mut shift = 0
  let mut i = 0
  while i < input.length() {
    if i >= 10 {
      return "err"
    }
    let b = input[i].to_int() & 0x7f
    value = value | (b << shift)
    if (input[i].to_int() & 0x80) == 0 {
      return "v:" + value.to_string()
    }
    shift = shift + 7
    i = i + 1
  }
  "err"
}
