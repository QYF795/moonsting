///|
/// Pure logic: numbering and seed merging.
test "corpus: file names are zero padded" {
  assert_eq(@engine.corpus_file("c", 1), "c/corpus-0001.hex")
  assert_eq(@engine.corpus_file("c", 42), "c/corpus-0042.hex")
  assert_eq(@engine.corpus_file("c", 12345), "c/corpus-12345.hex")
}

///|
test "corpus: seed sources merge without duplicates" {
  let a : Array[Bytes] = [b"aa", b"bb"]
  let b : Array[Bytes] = [b"bb", b"cc"]
  let merged = @engine.concat_seeds(a, b)
  assert_eq(merged.length(), 3)
  assert_eq(@core.hex_all(merged[0]), "6161")
  assert_eq(@core.hex_all(merged[2]), "6363")
}

///|
/// File-backed behaviour. The directory is created and removed by the test so a
/// failed assertion does not leave anything behind.
#cfg(target="native")
test "corpus: save then load round trips" {
  let dir = @proc.temp_path("corpus-test")
  ignore(@proc.make_dir(dir))
  let base = @proc.temp_path("seed")
  let inputs : Array[Bytes] = [b"\x80\x01", b"\xff\x01", b"abc"]
  let mut i = 0
  while i < inputs.length() {
    ignore(
      @proc.write_file(
        @engine.corpus_file(dir, i + 1),
        @utf8.encode(@core.hex_all(inputs[i]) + "\n"),
      ),
    )
    i = i + 1
  }
  let loaded = @engine.load_corpus(dir, 100)
  assert_eq(loaded.length(), 3)
  assert_eq(@core.hex_all(loaded[0]), "8001")
  assert_eq(@core.hex_all(loaded[2]), "616263")
  // Clean up: remove the entries, then the directory.
  let mut k = 1
  while k <= 3 {
    @proc.remove_file(@engine.corpus_file(dir, k))
    k = k + 1
  }
  @proc.remove_file(base)
  ignore(@proc.run_command("rmdir \"" + dir + "\" > NUL 2>&1"))
}

///|
#cfg(target="native")
test "corpus: a gap truncates the load" {
  let dir = @proc.temp_path("corpus-gap")
  ignore(@proc.make_dir(dir))
  ignore(@proc.write_file(@engine.corpus_file(dir, 1), @utf8.encode("8001\n")))
  ignore(@proc.write_file(@engine.corpus_file(dir, 3), @utf8.encode("ff01\n")))
  let loaded = @engine.load_corpus(dir, 100)
  assert_eq(loaded.length(), 1)
  @proc.remove_file(@engine.corpus_file(dir, 1))
  @proc.remove_file(@engine.corpus_file(dir, 3))
  ignore(@proc.run_command("rmdir \"" + dir + "\" > NUL 2>&1"))
}

///|
#cfg(target="native")
test "corpus: a missing directory loads as empty" {
  let loaded = @engine.load_corpus(@proc.temp_path("corpus-missing"), 100)
  assert_eq(loaded.length(), 0)
}
