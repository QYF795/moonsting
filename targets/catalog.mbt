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

///|
fn base64_case() -> Case {
  let seeds : Array[Bytes] = [
    b"AA==", b"AAA=", b"AAAA", b"Zm9v", b"+/==", b"", b"AAAAAA==", b"////",
  ]
  let target = @core.Target::new("base64.check", seeds, b64_check)
  Case::new(
    "base64",
    target,
    @core.Oracle::Custom("base64.roundtrip", b64_roundtrip_holds),
  )
}

///|
fn tlv_case() -> Case {
  let seeds : Array[Bytes] = [
    b"\x01\x00", b"\x01\x01A", b"\x01\x01A\x00\x00", b"\x00\x00", b"\x02\x03abc",
  ]
  let target = @core.Target::new("tlv.check", seeds, tlv_check)
  Case::new(
    "tlv",
    target,
    @core.Oracle::Custom("tlv.roundtrip", tlv_roundtrip_holds),
  )
}

///|
fn utf8_case() -> Case {
  let seeds : Array[Bytes] = [
    b"a", b"\xc3\xa9", b"\xe4\xb8\xad", b"\xf0\x9f\x98\x80", b"\x00", b"\xff",
  ]
  let a = @core.Target::new("utf8.a", seeds, utf8_count_a)
  let b = @core.Target::new("utf8.b", seeds, utf8_count_b)
  Case::new("utf8", a, @core.Oracle::Diff(a, b))
}

///|
fn urlenc_case() -> Case {
  let seeds : Array[Bytes] = [
    b"abc", b"a%20b", b"%E4%B8%AD", b"~-._", b"", b"a%2Fb",
  ]
  let target = @core.Target::new("urlenc.check", seeds, url_check)
  Case::new(
    "urlenc",
    target,
    @core.Oracle::Custom("urlenc.roundtrip", url_roundtrip_holds),
  )
}

///|
fn protobuf_case() -> Case {
  let seeds : Array[Bytes] = [
    b"\x08\x01", b"\x12\x02hi", b"", b"\x08\x96\x01", b"\x1d\x01\x02\x03\x04",
  ]
  let target = @core.Target::new("protobuf.check", seeds, pb_check)
  Case::new(
    "protobuf",
    target,
    @core.Oracle::Custom("protobuf.roundtrip", pb_roundtrip_holds),
  )
}

///|
fn rle_case() -> Case {
  let seeds : Array[Bytes] = [
    b"\x02\x03", b"\x06\x07", b"\x03\x01\x02\x03\x04\x05", b"", b"\x02\x1f",
  ]
  let target = @core.Target::new("rle.check", seeds, rle_check)
  Case::new(
    "rle",
    target,
    @core.Oracle::Custom("rle.roundtrip", rle_roundtrip_holds),
  )
}

///|
fn csv_strict_case() -> Case {
  let seeds : Array[Bytes] = [
    b"a,b\n1,2\n", b"\"a,b\",c\n", b"a\n", b"\"\"\"\"\n", b"x\n",
  ]
  let target = @core.Target::new("csv.strict", seeds, csv_strict_check)
  Case::new(
    "csvstrict",
    target,
    @core.Oracle::Custom("csv.strict.roundtrip", csv_strict_roundtrip_holds),
  )
}

///|
fn arff_case() -> Case {
  let seeds : Array[Bytes] = [
    b"@relation r\n@attribute a numeric\n@data\n1\n2\n", b"@relation r\n@attribute a {x,y}\n@data\nx\ny\n",
    b"% c\n@relation r\n@attribute a numeric\n@data\n1\n",
  ]
  let target = @core.Target::new("arff.summary", seeds, arff_summary)
  Case::new(
    "arff",
    target,
    @core.Oracle::Custom("arff.comment-invariant", arff_comment_invariant),
  )
}

///|
fn fixed_case() -> Case {
  let seeds : Array[Bytes] = [
    b"widths: 6,4\nname  age \nalice 30  \n", b"widths: 3\nabc\ndef\n",
  ]
  let target = @core.Target::new("fixed.check", seeds, fixed_check)
  Case::new(
    "fixed",
    target,
    @core.Oracle::Custom("fixed.roundtrip", fixed_roundtrip_holds),
  )
}

///|
fn ini_case() -> Case {
  let seeds : Array[Bytes] = [
    b"[db]\nhost = localhost\nport = 5432\n", b"; comment\n[a]\nx=1\n",
  ]
  let target = @core.Target::new("ini.summary", seeds, ini_summary)
  Case::new(
    "ini",
    target,
    @core.Oracle::Custom("ini.comment-invariant", ini_comment_invariant),
  )
}

///|
fn props_case() -> Case {
  let seeds : Array[Bytes] = [b"a=1\nb=two\n", b"path=C:\\\\tmp\n"]
  let target = @core.Target::new("props.check", seeds, prop_check)
  Case::new(
    "props",
    target,
    @core.Oracle::Custom("props.roundtrip", prop_roundtrip_holds),
  )
}

///|
fn stdjson_case() -> Case {
  // Rich, valid documents: the fuzzer needs structures worth mutating, and the
  // stdlib parser's interesting paths (nesting, unicode escapes, number corners)
  // are only reachable from documents that already parse.
  let seeds : Array[Bytes] = [
    b"{\"a\":1,\"b\":[1,2,3],\"c\":{\"d\":null}}", b"[1,2,3,4,5,6,7,8,9,10]", b"{\"n\":1e999,\"m\":-0.0,\"k\":12345678901234567890}",
    b"\"\\u0041\\u00e9\\ud83d\\ude00\"", b"[[[[[1]]]]]", b"{\"empty\":{},\"arr\":[],\"bool\":[true,false]}",
    b"\"x\"", b"{\"s\":\"a\\nb\\t\\\"c\\\"\"}",
  ]
  let target = @core.Target::new("stdjson.check", seeds, stdjson_check)
  Case::new(
    "stdjson",
    target,
    @core.Oracle::Custom("stdjson.consistency", stdjson_consistency),
  )
}

///|
pub fn catalog() -> Array[Case] {
  [
    json_case(),
    csv_case(),
    varint_case(),
    decimal_case(),
    base64_case(),
    tlv_case(),
    utf8_case(),
    urlenc_case(),
    protobuf_case(),
    rle_case(),
    csv_strict_case(),
    arff_case(),
    fixed_case(),
    ini_case(),
    props_case(),
    stdjson_case(),
    boom_case(),
  ]
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

///|
/// The instrumentation ids this case actually assigns, by case name.
///
/// Kept next to the catalog rather than inside each constructor so that adding a
/// target means touching one table, and so the session can scope the declaration
/// to the case it is about to run (declarations are global state).
pub fn declared_for(name : String) -> Array[Int32] {
  if name == "csv" {
    [200, 202, 203, 204, 205, 206, 207, 208, 209, 210]
  } else if name == "varint" {
    [300, 312]
  } else if name == "csvstrict" {
    [500, 501, 502, 503, 504, 505, 506, 507, 508, 509, 510, 521, 522]
  } else if name == "arff" {
    [530, 531, 532, 533, 534, 535, 536, 537, 538, 539, 540, 550]
  } else if name == "base64" {
    [600, 601, 602, 603, 610, 611, 612]
  } else if name == "tlv" {
    [700, 701, 702, 703, 704, 705, 706, 710, 711, 712]
  } else if name == "utf8" {
    [
      800, 801, 802, 803, 804, 805, 806, 807, 808, 810, 811, 812, 813, 814, 815,
      816, 817, 818, 819, 820, 821, 822, 823, 824,
    ]
  } else if name == "urlenc" {
    [900, 901, 902, 903, 904, 905, 906, 910, 911, 912]
  } else if name == "protobuf" {
    [
      920, 921, 922, 923, 924, 925, 926, 927, 928, 929, 930, 931, 932, 933, 934,
      940, 941, 942,
    ]
  } else if name == "rle" {
    [950, 951, 952, 953, 954, 955, 956, 957, 958, 959, 960, 961, 962]
  } else if name == "fixed" {
    [560, 561, 562, 563, 564, 565, 566, 567, 568, 569, 570, 571, 580, 581]
  } else if name == "ini" {
    [620, 621, 622, 623, 624, 625, 626, 627, 640]
  } else if name == "props" {
    [650, 651, 652, 653, 654, 655, 656, 657, 658, 670, 671]
  } else {
    []
  }
}
