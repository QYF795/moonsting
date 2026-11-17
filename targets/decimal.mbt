///|
/// Fixed-point money: parse `123.45` into cents, format back, and check the
/// round trip.
///
/// This target demonstrates a third style: a **self-checking target**. Instead
/// of an external reference implementation, the body returns its own diagnosis
/// (`ok:` / `err` / `roundtrip:`), and the oracle is one line that rejects any
/// diagnosis starting with `roundtrip:`. That pattern is worth copying: the
/// invariant lives next to the code that can violate it.
///
/// A defect is left in on purpose (same as `varint`): `format_decimal` emits
/// `-0.50` for -50 cents, while `parse_decimal` refuses a negative number whose
/// integer part is zero. Both are individually reasonable-looking rules; the
/// round trip is what makes them contradict each other.

///|
pub fn parse_decimal(input : Bytes) -> Int32? {
  let n = input.length()
  if n == 0 {
    return None
  }
  let mut i = 0
  let mut negative = false
  if input[0].to_int() == 45 {
    negative = true
    i = 1
  }
  if i >= n {
    return None
  }
  let mut units = 0
  let mut digits = 0
  while i < n {
    let v = input[i].to_int()
    if v >= 48 && v <= 57 {
      units = units * 10 + (v - 48)
      digits = digits + 1
      if digits > 9 {
        return None
      }
      i = i + 1
    } else {
      break
    }
  }
  if digits == 0 {
    return None
  }
  // Deliberate strictness: a negative amount must have a non-zero integer part.
  if negative && units == 0 {
    return None
  }
  let mut frac = 0
  if i < n && input[i].to_int() == 46 {
    i = i + 1
    let mut places = 0
    while i < n && places < 2 {
      let v = input[i].to_int()
      if v < 48 || v > 57 {
        return None
      }
      frac = frac * 10 + (v - 48)
      places = places + 1
      i = i + 1
    }
    if places == 0 {
      return None
    }
    while places < 2 {
      frac = frac * 10
      places = places + 1
    }
  }
  if i != n {
    return None
  }
  let cents = units * 100 + frac
  if negative {
    Some(-cents)
  } else {
    Some(cents)
  }
}

///|
fn push_digits(out : Array[Byte], value : Int32) -> Unit {
  if value == 0 {
    out.push(b'0')
    return
  }
  let digits : Array[Byte] = []
  let mut v = value
  while v > 0 {
    digits.push((48 + v % 10).to_byte())
    v = v / 10
  }
  let mut i = digits.length()
  while i > 0 {
    out.push(digits[i - 1])
    i = i - 1
  }
}

///|
pub fn format_decimal(cents : Int32) -> Bytes {
  let out : Array[Byte] = []
  let negative = cents < 0
  let magnitude = if negative { -cents } else { cents }
  if negative {
    out.push(b'-')
  }
  push_digits(out, magnitude / 100)
  out.push(b'.')
  let frac = magnitude % 100
  if frac < 10 {
    out.push(b'0')
  }
  push_digits(out, frac)
  Bytes::from_array(out)
}

///|
/// `ok:<formatted>` when the round trip holds, `err` when the input is not a
/// decimal, and `roundtrip:<why>` when formatting produced something the
/// parser refuses (or that parses back to a different value).
pub fn decimal_check(input : Bytes) -> String {
  match parse_decimal(input) {
    None => "err"
    Some(cents) => {
      let text = format_decimal(cents)
      match parse_decimal(text) {
        None => "roundtrip:rejected:" + bytes_to_text(text)
        Some(again) =>
          if again == cents {
            "ok:" + bytes_to_text(text)
          } else {
            "roundtrip:changed:" + bytes_to_text(text)
          }
      }
    }
  }
}

///|
fn bytes_to_text(data : Bytes) -> String {
  let sb = StringBuilder()
  let mut i = 0
  while i < data.length() {
    sb.write_char(data[i].to_char())
    i = i + 1
  }
  sb.to_string()
}

///|
pub fn decimal_roundtrip_holds(_input : Bytes, output : String) -> String {
  if output.has_prefix("roundtrip:") {
    output
  } else {
    ""
  }
}
