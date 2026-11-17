///|
test "ddmin_batched: reaches a single byte" {
  let data = b"AABBBCCCC"
  let small = @shrink.ddmin_batched(
    data,
    fn(candidates) {
      let flags : Array[Bool] = []
      let mut i = 0
      while i < candidates.length() {
        flags.push(candidates[i].find(b"B") is Some(_))
        i = i + 1
      }
      flags
    },
    20,
  )
  assert_eq(small.length(), 1)
  assert_true(@core.bytes_equal(small, b"B"))
}

///|
test "ddmin_batched: respects a length property" {
  let data = b"0123456789"
  let small = @shrink.ddmin_batched(
    data,
    fn(candidates) {
      let flags : Array[Bool] = []
      let mut i = 0
      while i < candidates.length() {
        flags.push(candidates[i].length() >= 3)
        i = i + 1
      }
      flags
    },
    20,
  )
  assert_eq(small.length(), 3)
}

///|
test "ddmin_batched: nothing interesting leaves the input alone" {
  let data = b"abcdef"
  let small = @shrink.ddmin_batched(
    data,
    fn(candidates) {
      let flags : Array[Bool] = []
      let mut i = 0
      while i < candidates.length() {
        flags.push(false)
        i = i + 1
      }
      flags
    },
    20,
  )
  assert_true(@core.bytes_equal(small, data))
}

///|
test "ddmin_batched: short inputs are returned as-is" {
  assert_eq(@shrink.ddmin_batched(b"a", fn(_c) { [true] }, 5).length(), 1)
  assert_eq(@shrink.ddmin_batched(b"", fn(_c) { [true] }, 5).length(), 0)
}
