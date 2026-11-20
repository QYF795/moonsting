///|
test "tlv: records parse" {
  let fields = @mutate.tlv_fields(b"\x01\x02ab\x02\x01c").unwrap()
  assert_eq(fields.length(), 2)
  assert_eq(fields[0].kind, 1)
  assert_eq(fields[0].len, 2)
  assert_eq(fields[0].end, 4)
  assert_eq(fields[1].end, 7)
}

///|
test "tlv: a terminator must be empty and last" {
  assert_eq(@mutate.tlv_fields(b"\x01\x01a\x00\x00").unwrap().length(), 1)
  // Terminator with a payload.
  assert_true(@mutate.tlv_fields(b"\x00\x01a") is None)
  // Terminator not last.
  assert_true(@mutate.tlv_fields(b"\x00\x00\x01\x01a") is None)
  // Length past the end.
  assert_true(@mutate.tlv_fields(b"\x01\x05ab") is None)
  // Short header.
  assert_true(@mutate.tlv_fields(b"\x01") is None)
}

///|
test "tlv: mutations change bytes and mostly stay parseable" {
  let rng = @core.Rng::new(23)
  let seed = b"\x01\x03abc\x02\x02de"
  let mut changed = 0
  let mut parsed = 0
  let mut i = 0
  while i < 200 {
    match @mutate.tlv_mutate(rng, seed) {
      None => ()
      Some(out) => {
        if out != seed {
          changed = changed + 1
        }
        if @mutate.tlv_fields(out) is Some(_) {
          parsed = parsed + 1
        }
      }
    }
    i = i + 1
  }
  assert_true(changed >= 150)
  assert_true(parsed >= 40)
}

///|
test "tlv: the off-by-one and truncation classes are reachable" {
  let rng = @core.Rng::new(29)
  let seed = b"\x01\x03abc\x02\x02de"
  let mut saw_length_bump = false
  let mut saw_truncation = false
  let mut i = 0
  while i < 300 {
    match @mutate.tlv_mutate(rng, seed) {
      None => ()
      Some(out) => {
        if out.length() == seed.length() && out[1].to_int() != seed[1].to_int() {
          saw_length_bump = true
        }
        if out.length() == seed.length() - 1 {
          saw_truncation = true
        }
      }
    }
    i = i + 1
  }
  assert_true(saw_length_bump)
  assert_true(saw_truncation)
}
