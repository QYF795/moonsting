///|
/// A target whose coverage is a function of the first byte, so the setup is
/// obvious: three inputs covering three ids are enough, and a fourth input that
/// covers nothing must not be kept.
fn cmin_fixture() -> @targets.Case {
  let target = @core.Target::new("cmin.fixture", [b"a", b"b", b"c"], fn(input) {
    if input.length() > 0 {
      @cov.hit(1 + input[0].to_int() % 3)
    }
    "ok"
  })
  @targets.Case::new("cmin-fixture", target, @core.Oracle::Same)
}

///|
test "cmin keeps a minimal covering set" {
  let case = cmin_fixture()
  let inputs : Array[Bytes] = [b"a", b"b", b"c", b"d", b"a"]
  let result = cmin(case, inputs)
  // Three distinct ids, so at most three inputs can be needed.
  assert_true(result.kept.length() <= 3)
  assert_eq(result.ids_total, 3)
  assert_eq(result.ids_covered, 3)
}

///|
test "cmin prefers the shorter input on equal gain" {
  let case = cmin_fixture()
  // Both cover id 1; the first is shorter, so it should win.
  let inputs : Array[Bytes] = [b"a", b"a-longer-but-same-id"]
  let result = cmin(case, inputs)
  assert_eq(result.kept.length(), 1)
  assert_eq(result.kept[0], 0)
  assert_eq(result.ids_total, 1)
}

///|
test "cmin on an uninstrumented target falls back to output shape" {
  let target = @core.Target::new("cmin.shape", [b"x"], fn(input) {
    if input.length() > 2 {
      "long"
    } else {
      "short"
    }
  })
  let case = @targets.Case::new("cmin-shape", target, @core.Oracle::Same)
  // Equal-length inputs per group: the shape signature buckets by output *and*
  // input length (that is what the engine uses), so mixing lengths would look
  // like four shapes rather than two.
  let inputs : Array[Bytes] = [b"aa", b"bb", b"ccc", b"ddd"]
  let result = cmin(case, inputs)
  // Two observed shapes -> two representatives.
  assert_eq(result.kept.length(), 2)
  assert_eq(result.ids_covered, result.ids_total)
}
