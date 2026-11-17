///|
/// The built-in catalog. Every case demonstrates a different oracle kind, so
/// `--target` is also a tour of what the tool can judge:
///
///   json    metamorphic — appending insignificant whitespace must not change
///           the verdict. No reference implementation required.
///   csv     smoke       — accepts everything, grows a corpus. This is what you
///           run when you have no oracle yet: it still finds crashes.
///   varint  differential — two decoders must agree. This is the mode that
///           finds silently wrong results, not just exceptions.

///|
fn json_case() -> Case {
  let seeds : Array[Bytes] = [
    b"{}", b"[]", b"null", b"true", b"0", b"-1.5e3", b"\"a\"", b"{\"a\":[1,2]}",
    b"{\"a\":{\"b\":null}}", b"[1,2,3]", b"\"\\u0041\"",
  ]
  let target = @core.Target::new("json.lite", seeds, json_validate)
  let oracle = @core.Oracle::Custom("json.ws-invariance", fn(input, output) {
    // Insignificant whitespace must never flip acceptance. Error *text* is
    // allowed to change (positions move), so only the verdict is compared —
    // an oracle that compares error messages finds nothing but its own
    // wording.
    let accepted = output.has_prefix("ok:")
    let trailing = json_validate(input + b" \n\t ")
    let leading = json_validate(b" \r\n" + input)
    if trailing.has_prefix("ok:") != accepted {
      "trailing whitespace flipped the verdict: " + output + " -> " + trailing
    } else if leading.has_prefix("ok:") != accepted {
      "leading whitespace flipped the verdict: " + output + " -> " + leading
    } else {
      ""
    }
  })
  Case::new("json", target, oracle)
}

///|
fn csv_case() -> Case {
  let seeds : Array[Bytes] = [
    b"a,b\n1,2\n", b"a\n", b"\"a,b\",c\n", b"\n", b"a,b,c\n1,2,3\n4,5,6\n", b"\"\"\"\"\n",
  ]
  let target = @core.Target::new("csv.lite", seeds, csv_stats)
  Case::new("csv", target, @core.Oracle::Same)
}

///|
fn varint_case() -> Case {
  let fast = @core.Target::new(
    "varint.fast",
    [
      b"\x00", b"\x7f", b"\x80\x01", b"\xff\x01", b"\x80\x80\x01", b"\xff\xff\xff\xff\x0f",
    ],
    varint_fast,
  )
  let reference = @core.Target::new(
    "varint.ref",
    [b"\x00", b"\x7f", b"\x80\x01", b"\xff\x01", b"\x80\x80\x01"],
    varint_ref,
  )
  Case::new("varint", fast, @core.Oracle::Diff(fast, reference))
}

///|
fn decimal_case() -> Case {
  let seeds : Array[Bytes] = [
    b"-1.23", b"1.23", b"0.00", b"12.5", b"0.01", b"-99.99", b"1234.56",
  ]
  let target = @core.Target::new("decimal.money", seeds, decimal_check)
  Case::new(
    "decimal",
    target,
    @core.Oracle::Custom("decimal.roundtrip", decimal_roundtrip_holds),
  )
}

///|
pub fn catalog() -> Array[Case] {
  [json_case(), csv_case(), varint_case(), decimal_case()]
}

///|
pub fn names() -> Array[String] {
  let out : Array[String] = []
  let cases = catalog()
  let mut i = 0
  while i < cases.length() {
    out.push(cases[i].name())
    i = i + 1
  }
  out
}

///|
pub fn find(name : String) -> Case? {
  let cases = catalog()
  let mut i = 0
  while i < cases.length() {
    if cases[i].name() == name {
      return Some(cases[i])
    }
    i = i + 1
  }
  None
}
