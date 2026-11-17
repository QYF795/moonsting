///|
/// Known-interesting tokens. Written as `Array[Byte]` literals so nothing in
/// the mutation path depends on UTF-8 decoding.
pub struct Dictionary {
  tokens_ : Array[Bytes]
}

///|
pub fn Dictionary::new(tokens : Array[Bytes]) -> Dictionary {
  { tokens_: tokens, }
}

///|
pub fn Dictionary::empty() -> Dictionary {
  { tokens_: [], }
}

///|
pub fn Dictionary::add(self : Dictionary, token : Bytes) -> Unit {
  self.tokens_.push(token)
}

///|
pub fn Dictionary::tokens(self : Dictionary) -> Array[Bytes] {
  self.tokens_
}

///|
pub fn Dictionary::size(self : Dictionary) -> Int32 {
  self.tokens_.length()
}

///|
/// Tokens that tend to break text parsers: nesting, escapes, numeric edges,
/// encoding oddities, and the classic `-0` / `NaN` / huge-exponent family.
pub fn Dictionary::generic() -> Dictionary {
  Dictionary::new([
    b"0", b"-0", b"1", b"-1", b"2147483647", b"-2147483648", b"4294967295", b"9223372036854775807",
    b"18446744073709551615", b"1e308", b"1e-308", b"NaN", b"inf", b"-inf", b"null",
    b"true", b"false", b"\"\"", b"{}", b"[]", b"\x00", b"\xff", b"\xfe\xff", b"\xef\xbb\xbf",
    b"\x80", b"\xc0\x80", b"\r\n", b"\r", b"\n", b"\t", b" ", b"\\", b"\\\\", b"\\u0000",
    b"\\ud800", b"%s", b"%d", b"%n", b"${", b"'", b"\"", b";", b"--", b"<!--", b"]]>",
    b"{\"a\":1}", b"[[]]", b"[[[[[[[[", b"}}}}}}}}", b"................",
  ])
}

///|
/// Tokens for JSON-shaped inputs.
pub fn Dictionary::json() -> Dictionary {
  Dictionary::new([
    b"{", b"}", b"[", b"]", b",", b":", b"\"", b"\\", b"\\\"", b"\\u0000", b"\\uD800",
    b"\\uDC00", b"null", b"true", b"false", b"0", b"-0", b"1e999", b"1e-999", b"2147483648",
    b"9223372036854775808", b"\"\"", b"{}", b"[]", b"\x00", b"\xff", b"\n", b"\r",
    b"\t",
  ])
}

///|
/// Tokens for CSV-shaped inputs: quoting, separators, record ends.
pub fn Dictionary::csv() -> Dictionary {
  Dictionary::new([
    b",", b"\"", b"\"\"", b"\n", b"\r\n", b"\r", b";", b"\t", b" ", b"\x00", b"\"\"\"",
    b"\"\"\"\"", b"\"a,b\"", b"\"a\"\"b\"", b"0", b"-0", b"1e309", b"", b"NULL",
    b"\xff",
  ])
}
