///|
/// Fixed-width tables: `serialize(parse(x)) == x`.
///
/// A fixed-width table has no delimiters, so the interesting arithmetic is the
/// column geometry: the widths must sum to the declared line length, and every
/// row must be exactly that long. That is a different class of bug from CSV's
/// quoting rules, which is why it earns a target of its own.
///
/// Grammar:
///
///     widths: 6,4
///     name  age
///     alice 30
///
/// A cell is left-aligned and padded with spaces; a row must be exactly the sum
/// of the widths. The canonical form is the same text, so the round trip is
/// strict.
///
/// Coverage ids for this target live in 560..589.

///|
struct FixedTable {
  widths : Array[Int32]
  rows : Array[Array[Bytes]]
}

///|
fn fixed_parse_widths(line : Bytes) -> Array[Int32]? {
  let prefix = b"widths:"
  if line.length() <= prefix.length() {
    @cov.hit(560)
    return None
  }
  let mut i = 0
  while i < prefix.length() {
    if line[i] != prefix[i] {
      @cov.hit(561)
      return None
    }
    i = i + 1
  }
  // Canonical form is `widths: 6,4`: exactly one space after the colon and no
  // spaces anywhere else. Anything else is rejected, which is what lets the
  // round trip act as an oracle.
  if line[i].to_int() != 32 {
    @cov.hit(566)
    return None
  }
  i = i + 1
  let widths : Array[Int32] = []
  let mut start = i
  while start <= line.length() {
    if start >= line.length() {
      @cov.hit(566)
      return None
    }
    // One number, then either a comma or the end.
    let mut end = start
    while end < line.length() && line[end].to_int() != 44 {
      end = end + 1
    }
    if end == start {
      @cov.hit(562)
      return None
    }
    // `03` parses as 3 but re-emits as `3`, so it is not canonical.
    if end - start > 1 && line[start].to_int() == 48 {
      @cov.hit(571)
      return None
    }
    let mut value = 0
    let mut k = start
    while k < end {
      let v = line[k].to_int()
      if v < 48 || v > 57 {
        @cov.hit(563)
        return None
      }
      value = value * 10 + (v - 48)
      if value > 10000 {
        @cov.hit(564)
        return None
      }
      k = k + 1
    }
    if value == 0 {
      @cov.hit(565)
      return None
    }
    widths.push(value)
    if end >= line.length() {
      break
    }
    start = end + 1
  }
  if widths.length() == 0 {
    @cov.hit(566)
    return None
  }
  Some(widths)
}

///|
pub fn fixed_parse(input : Bytes) -> FixedTable? {
  let n = input.length()
  let mut i = 0
  // First line: widths.
  let line_end = match fixed_line_end(input, 0) {
    None => return None
    Some(v) => v
  }
  let widths = match fixed_parse_widths(@core.slice_bytes(input, 0, line_end)) {
    None => return None
    Some(w) => w
  }
  let mut total = 0
  let mut w = 0
  while w < widths.length() {
    total = total + widths[w]
    w = w + 1
  }
  if total <= 0 {
    @cov.hit(567)
    return None
  }
  i = line_end + 1
  let rows : Array[Array[Bytes]] = []
  while i < n {
    let end = match fixed_line_end(input, i) {
      None => return None
      Some(v) => v
    }
    let len = end - i
    if len != total {
      @cov.hit(568)
      return None
    }
    let cells : Array[Bytes] = []
    let mut at = i
    let mut col = 0
    while col < widths.length() {
      let width = widths[col]
      cells.push(fixed_trim_right(@core.slice_bytes(input, at, at + width)))
      at = at + width
      col = col + 1
    }
    rows.push(cells)
    @cov.hit(569)
    i = end + 1
  }
  Some({ widths, rows, })
}

///|
fn fixed_line_end(input : Bytes, from : Int32) -> Int32? {
  let mut i = from
  while i < input.length() {
    let v = input[i].to_int()
    if v == 10 {
      return Some(i)
    }
    // No control characters inside a table line.
    if v < 32 && v != 9 {
      @cov.hit(570)
      return None
    }
    i = i + 1
  }
  if i == from {
    None
  } else {
    Some(i)
  }
}

///|
pub fn fixed_serialize(table : FixedTable) -> Bytes {
  let out : Array[Byte] = []
  let mut i = 0
  while i < b"widths:".length() {
    out.push(b"widths:"[i])
    i = i + 1
  }
  out.push(b' ')
  let mut w = 0
  while w < table.widths.length() {
    if w > 0 {
      out.push(b',')
    }
    let digits = fixed_digits(table.widths[w])
    let mut k = 0
    while k < digits.length() {
      out.push(digits[k])
      k = k + 1
    }
    w = w + 1
  }
  out.push(b'\n')
  let mut r = 0
  while r < table.rows.length() {
    let cells = table.rows[r]
    let mut c = 0
    while c < cells.length() {
      let width = table.widths[c]
      let cell = cells[c]
      let mut k = 0
      while k < width {
        if k < cell.length() {
          out.push(cell[k])
        } else {
          out.push(b' ')
        }
        k = k + 1
      }
      c = c + 1
    }
    out.push(b'\n')
    r = r + 1
  }
  Bytes::from_array(out)
}

///|
pub fn fixed_check(input : Bytes) -> String {
  match fixed_parse(input) {
    None => "err"
    Some(table) => {
      let again = fixed_serialize(table)
      let m = input.length()
      let mut same = false
      if again.length() == m {
        same = fixed_same(input, again, m)
      } else if again.length() == m + 1 && again[m].to_int() == 10 {
        same = fixed_same(input, again, m)
      }
      if same {
        @cov.hit(580)
        "ok:" + table.rows.length().to_string()
      } else {
        @cov.hit(581)
        "roundtrip:" + @core.hex_all(again)
      }
    }
  }
}

///|
fn fixed_same(input : Bytes, canonical : Bytes, len : Int32) -> Bool {
  let mut i = 0
  while i < len {
    if input[i] != canonical[i] {
      return false
    }
    i = i + 1
  }
  true
}

///|
pub fn fixed_roundtrip_holds(_input : Bytes, output : String) -> String {
  if output.has_prefix("roundtrip:") {
    output
  } else {
    ""
  }
}

///|
fn fixed_trim_right(data : Bytes) -> Bytes {
  let mut end = data.length()
  while end > 0 && data[end - 1].to_int() == 32 {
    end = end - 1
  }
  @core.slice_bytes(data, 0, end)
}

///|
/// Decimal digits of a positive Int32, without going through String.
fn fixed_digits(value : Int32) -> Bytes {
  let reversed : Array[Byte] = []
  let mut v = value
  if v == 0 {
    reversed.push(b'0')
  }
  while v > 0 {
    reversed.push((48 + v % 10).to_byte())
    v = v / 10
  }
  let out : Array[Byte] = []
  let mut i = reversed.length()
  while i > 0 {
    out.push(reversed[i - 1])
    i = i - 1
  }
  Bytes::from_array(out)
}
