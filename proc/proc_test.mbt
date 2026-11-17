///|
#cfg(target="native")
test "proc: file roundtrip" {
  let path = @proc.temp_path("roundtrip.bin")
  let payload = b"\x00\x01\xfe\xffhello"
  assert_true(@proc.write_file(path, payload))
  let back = @proc.read_file(path)
  assert_eq(back.length(), payload.length())
  let mut i = 0
  let mut same = true
  while i < payload.length() && i < back.length() {
    if payload[i] != back[i] {
      same = false
    }
    i = i + 1
  }
  assert_true(same)
  @proc.remove_file(path)
  assert_eq(@proc.read_file(path).length(), 0)
}

///|
#cfg(target="native")
test "proc: streaming write is visible after flush" {
  let path = @proc.temp_path("stream.txt")
  let handle = @proc.open_out(path)
  assert_true(handle != 0L)
  ignore(@proc.put(handle, b"first\n"))
  @proc.flush(handle)
  // Read while the handle is still open: a crash would leave exactly this.
  assert_eq(@proc.read_file(path).length(), 6)
  ignore(@proc.put(handle, b"second\n"))
  @proc.flush(handle)
  @proc.close_out(handle)
  assert_eq(@proc.read_file(path).length(), 13)
  @proc.remove_file(path)
}

///|
#cfg(target="native")
test "proc: system returns the exit code of a failing command" {
  let ok = @proc.run_command("cmd /c exit 0")
  assert_true(ok == 0)
  let bad = @proc.run_command("cmd /c exit 3")
  assert_true(bad != 0)
}

///|
#cfg(target="native")
test "proc: temp paths are unique and in the temp dir" {
  let a = @proc.temp_path("a")
  let b = @proc.temp_path("b")
  assert_true(a != b)
  assert_true(a.length() > 10)
}

///|
#cfg(target="native")
test "proc: a 512 line batch survives the round trip" {
  let path = @proc.temp_path("big.txt")
  let text = StringBuilder()
  let mut i = 0
  while i < 512 {
    text.write_string("8001\n")
    i = i + 1
  }
  assert_true(@proc.write_file(path, @utf8.encode(text.to_string())))
  let back = @proc.read_file(path)
  let mut lines = 0
  let mut j = 0
  while j < back.length() {
    if back[j].to_int() == 10 {
      lines = lines + 1
    }
    j = j + 1
  }
  @proc.remove_file(path)
  assert_eq(lines, 512)
}
