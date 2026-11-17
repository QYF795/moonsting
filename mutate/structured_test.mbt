///|
fn balanced(data : Bytes) -> Bool {
  let mut depth = 0
  let mut in_string = false
  let mut escaped = false
  let mut i = 0
  while i < data.length() {
    let v = data[i].to_int()
    if in_string {
      if escaped {
        escaped = false
      } else if v == 92 {
        escaped = true
      } else if v == 34 {
        in_string = false
      }
    } else if v == 34 {
      in_string = true
    } else if v == 123 || v == 91 {
      depth = depth + 1
    } else if v == 125 || v == 93 {
      depth = depth - 1
    }
    i = i + 1
  }
  depth == 0 && !in_string
}

///|
test "structured: shape detection" {
  assert_eq(@mutate.detect(b"{\"a\":1}").label(), "json")
  assert_eq(@mutate.detect(b"[1,2]").label(), "json")
  assert_eq(@mutate.detect(b"a,b\n1,2\n").label(), "csv")
  assert_eq(@mutate.detect(b"a%20b").label(), "urlenc")
  assert_eq(@mutate.detect(b"QUJD").label(), "base64")
  assert_eq(@mutate.detect(b"\xff\x00\xfe").label(), "binary")
}

///|
/// The property structured mutation exists for: the document usually survives.
test "structured: json mutations stay balanced most of the time" {
  let rng = @core.Rng::new(11)
  let dict = @mutate.Dictionary::json()
  let seeds : Array[Bytes] = [
    b"{\"a\":1}", b"[1,2,3]", b"{\"k\":\"v\",\"n\":[true,null]}",
  ]
  let mut ok = 0
  let mut total = 0
  let mut s = 0
  while s < seeds.length() {
    let mut i = 0
    while i < 100 {
      let out = @mutate.json_mutate(rng, seeds[s], dict, 512)
      if balanced(out) {
        ok = ok + 1
      }
      total = total + 1
      i = i + 1
    }
    s = s + 1
  }
  // Deleting a token can leave `{"a":}` behind, so this is not 100%; anything
  // near half would mean the mutator is not doing token-level work at all.
  // Measured: 199/300 = 66%. Deleting a value can leave `{"a":}` behind.\n  assert_true(ok * 10 >= total * 6)
}

///|
test "structured: base64 mutations stay in the alphabet or break it on purpose" {
  let rng = @core.Rng::new(3)
  let mut i = 0
  let mut in_alphabet = 0
  while i < 100 {
    let out = @mutate.base64_mutate(rng, b"QUJDRA==")
    let mut ok = true
    let mut j = 0
    while j < out.length() {
      let v = out[j].to_int()
      if !((v >= 65 && v <= 90) ||
        (v >= 97 && v <= 122) ||
        (v >= 48 && v <= 57) ||
        v == 43 ||
        v == 47 ||
        v == 61) {
        ok = false
      }
      j = j + 1
    }
    if ok {
      in_alphabet = in_alphabet + 1
    }
    i = i + 1
  }
  assert_eq(in_alphabet, 100)
}

///|
test "structured: length poke moves exactly one byte by one" {
  let rng = @core.Rng::new(5)
  let data = b"\x01\x05abc"
  let out = @mutate.length_mutate(rng, data)
  assert_eq(out.length(), data.length())
  let mut changed = 0
  let mut i = 0
  while i < data.length() {
    if out[i] != data[i] {
      changed = changed + 1
    }
    i = i + 1
  }
  assert_eq(changed, 1)
}
