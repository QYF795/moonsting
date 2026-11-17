///|
/// Canonical URI component encoding (the `encodeURIComponent` contract).
///
/// The property: decoding then re-encoding must reproduce the input byte for
/// byte. That only holds if the decoder is *strict about canonical form*, which
/// means rejecting three things a permissive decoder would happily accept:
///
///   - lowercase hex in `%xx` (the canonical form is uppercase),
///   - `%XX` whose byte is unreserved (`%41` is 'A', which must be literal),
///   - literal reserved bytes (`/`, `?`, `&`, …) that must be percent-encoded.
///
/// Being strict is what makes the round trip a real oracle instead of a
/// tautology: a loose decoder would pass "it decodes", and this one is asked to
/// pass "it decodes to something canonical".
///
/// Coverage ids for this target live in 900..919.

///|
fn url_unreserved(b : Int32) -> Bool {
  (b >= 65 && b <= 90) ||
  (b >= 97 && b <= 122) ||
  (b >= 48 && b <= 57) ||
  b == 45 ||
  b == 46 ||
  b == 95 ||
  b == 126
}

///|
fn url_hex_upper(c : Int32) -> Int32 {
  if c >= 48 && c <= 57 {
    c - 48
  } else if c >= 65 && c <= 70 {
    c - 55
  } else {
    -1
  }
}

///|
fn url_hex_char(v : Int32) -> Byte {
  if v < 10 {
    (48 + v).to_byte()
  } else {
    (55 + v).to_byte()
  }
}

///|
pub fn url_decode(input : Bytes) -> Array[Byte]? {
  let out : Array[Byte] = []
  let n = input.length()
  let mut i = 0
  while i < n {
    let b = input[i].to_int()
    if b == 37 {
      if i + 2 >= n {
        @cov.hit(900)
        return None
      }
      let hi = url_hex_upper(input[i + 1].to_int())
      let lo = url_hex_upper(input[i + 2].to_int())
      if hi < 0 || lo < 0 {
        @cov.hit(901)
        return None
      }
      let value = hi * 16 + lo
      if url_unreserved(value) {
        // `%41` is a non-canonical encoding of 'A'.
        @cov.hit(902)
        return None
      }
      @cov.hit(903)
      out.push(value.to_byte())
      i = i + 3
    } else if url_unreserved(b) {
      @cov.hit(904)
      out.push(b.to_byte())
      i = i + 1
    } else {
      // Reserved bytes, spaces and control characters must be percent-encoded.
      @cov.hit(905)
      return None
    }
  }
  @cov.hit(906)
  Some(out)
}

///|
pub fn url_encode(data : Array[Byte]) -> Bytes {
  let out : Array[Byte] = []
  let mut i = 0
  while i < data.length() {
    let b = data[i].to_int()
    if url_unreserved(b) {
      out.push(b.to_byte())
    } else {
      out.push(b'%')
      out.push(url_hex_char(b / 16))
      out.push(url_hex_char(b % 16))
    }
    i = i + 1
  }
  Bytes::from_array(out)
}

///|
pub fn url_check(input : Bytes) -> String {
  match url_decode(input) {
    None => "err"
    Some(data) => {
      let again = url_encode(data)
      let m = input.length()
      if again.length() != m {
        @cov.hit(910)
        "roundtrip:" + @core.hex_all(again)
      } else {
        let mut same = true
        let mut i = 0
        while i < m {
          if input[i] != again[i] {
            same = false
          }
          i = i + 1
        }
        if same {
          @cov.hit(911)
          "ok:" + data.length().to_string()
        } else {
          @cov.hit(912)
          "roundtrip:" + @core.hex_all(again)
        }
      }
    }
  }
}

///|
pub fn url_roundtrip_holds(_input : Bytes, output : String) -> String {
  if output.has_prefix("roundtrip:") {
    output
  } else {
    ""
  }
}
