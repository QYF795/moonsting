///|
/// Two independent UTF-8 validators, judged by a differential oracle.
///
/// Writing one correct UTF-8 validator is easy; writing two *structurally
/// different* ones that agree on every input is the point. A counts how many
/// continuation bytes are still owed and tightens the bounds for the first one
/// (Höhrmann's trick); B decodes each code point and checks overlong forms,
/// surrogates and the maximum explicitly. Both return `ok:<chars>` or `err`, so
/// agreement is a string comparison and every disagreement is a real question.
///
/// Coverage ids for this target live in 800..819.

///|
/// A: "how many continuation bytes are still owed".
pub fn utf8_count_a(input : Bytes) -> String {
  let n = input.length()
  let mut i = 0
  let mut chars = 0
  let mut remaining = 0
  let mut lo = 0x80
  let mut hi = 0xbf
  while i < n {
    let b = input[i].to_int()
    if remaining > 0 {
      if b < lo || b > hi {
        @cov.hit(800)
        return "err"
      }
      remaining = remaining - 1
      lo = 0x80
      hi = 0xbf
      i = i + 1
    } else if b < 0x80 {
      @cov.hit(801)
      chars = chars + 1
      i = i + 1
    } else if b < 0xc2 {
      @cov.hit(802)
      return "err"
    } else if b <= 0xdf {
      @cov.hit(803)
      remaining = 1
      chars = chars + 1
      i = i + 1
    } else if b <= 0xef {
      @cov.hit(804)
      remaining = 2
      chars = chars + 1
      if b == 0xe0 {
        lo = 0xa0
        hi = 0xbf
      } else if b == 0xed {
        lo = 0x80
        hi = 0x9f
      }
      i = i + 1
    } else if b <= 0xf4 {
      @cov.hit(805)
      remaining = 3
      chars = chars + 1
      if b == 0xf0 {
        lo = 0x90
        hi = 0xbf
      } else if b == 0xf4 {
        lo = 0x80
        hi = 0x8f
      }
      i = i + 1
    } else {
      @cov.hit(806)
      return "err"
    }
  }
  if remaining > 0 {
    @cov.hit(807)
    return "err"
  }
  @cov.hit(808)
  "ok:" + chars.to_string()
}

///|
fn cont(b : Int32) -> Bool {
  b >= 0x80 && b <= 0xbf
}

///|
/// B: decode each code point, then check the ranges it must not fall into.
pub fn utf8_count_b(input : Bytes) -> String {
  let n = input.length()
  let mut i = 0
  let mut chars = 0
  while i < n {
    let b0 = input[i].to_int()
    if b0 < 0x80 {
      @cov.hit(810)
      chars = chars + 1
      i = i + 1
    } else if b0 < 0xc2 || b0 > 0xf4 {
      @cov.hit(811)
      return "err"
    } else if b0 <= 0xdf {
      if i + 1 >= n || !cont(input[i + 1].to_int()) {
        @cov.hit(812)
        return "err"
      }
      @cov.hit(813)
      chars = chars + 1
      i = i + 2
    } else if b0 <= 0xef {
      if i + 2 >= n {
        @cov.hit(814)
        return "err"
      }
      let b1 = input[i + 1].to_int()
      let b2 = input[i + 2].to_int()
      if !cont(b1) || !cont(b2) {
        @cov.hit(815)
        return "err"
      }
      // Overlong: E0 requires b1 >= A0. Surrogates: ED requires b1 <= 9F.
      if b0 == 0xe0 && b1 < 0xa0 {
        @cov.hit(816)
        return "err"
      }
      if b0 == 0xed && b1 > 0x9f {
        @cov.hit(817)
        return "err"
      }
      @cov.hit(818)
      chars = chars + 1
      i = i + 3
    } else {
      if i + 3 >= n {
        @cov.hit(819)
        return "err"
      }
      let b1 = input[i + 1].to_int()
      let b2 = input[i + 2].to_int()
      let b3 = input[i + 3].to_int()
      if !cont(b1) || !cont(b2) || !cont(b3) {
        @cov.hit(820)
        return "err"
      }
      if b0 == 0xf0 && b1 < 0x90 {
        @cov.hit(821)
        return "err"
      }
      if b0 == 0xf4 && b1 > 0x8f {
        @cov.hit(822)
        return "err"
      }
      @cov.hit(823)
      chars = chars + 1
      i = i + 4
    }
  }
  @cov.hit(824)
  "ok:" + chars.to_string()
}
