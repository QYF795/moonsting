///|
/// Strict CSV with `serialize(parse(x)) == x`.
///
/// The existing `csv` target is a smoke target: it counts rows and columns but
/// judges nothing. This one is its oracle-backed counterpart. Strictness is what
/// makes the round trip meaningful:
///
///   - LF only (a CR is an error, not whitespace),
///   - a field is quoted **only** when it must be (contains `,`, `"` or LF),
///     so `"a"` is rejected while `"a,b"` is fine,
///   - inside quotes, `"` is doubled; a quote may only be followed by `,`, LF or
///     the end of input,
///   - a trailing LF after the last row is optional but a trailing empty row is
///     not.
///
/// Every rule exists because a looser parser would accept documents whose
/// canonical form differs — and those are exactly the bugs a round trip finds.
/// Here the parser rejects them instead, so a clean run is this target's success
/// criterion.
///
/// Coverage ids for this target live in 500..529.

///|
struct CsvRow {
  cells : Array[Bytes]
}

///|
fn field_needs_quotes(cell : Bytes) -> Bool {
  let mut i = 0
  while i < cell.length() {
    let v = cell[i].to_int()
    if v == 44 || v == 34 || v == 10 || v == 13 {
      return true
    }
    i = i + 1
  }
  false
}

///|
pub fn csv_parse_strict(input : Bytes) -> Array[CsvRow]? {
  let rows : Array[CsvRow] = []
  let n = input.length()
  if n == 0 {
    @cov.hit(500)
    return Some(rows)
  }
  let mut i = 0
  let mut cells : Array[Bytes] = []
  let mut cell : Array[Byte] = []
  let mut row_start = true
  // A quoted field is committed when its closing quote is seen; the following
  // separator must not push an empty cell for it.
  let mut committed = false
  while i < n {
    let v = input[i].to_int()
    if v == 13 {
      @cov.hit(501)
      return None
    }
    if v == 34 {
      if cell.length() > 0 {
        @cov.hit(502)
        return None
      }
      // Quoted field.
      i = i + 1
      let mut closed = false
      while i < n && !closed {
        let b = input[i].to_int()
        if b == 34 {
          if i + 1 < n && input[i + 1].to_int() == 34 {
            cell.push(b'"')
            i = i + 2
          } else {
            closed = true
            i = i + 1
          }
        } else {
          cell.push(input[i])
          i = i + 1
        }
      }
      if !closed {
        @cov.hit(503)
        return None
      }
      // A quote must not have been necessary — or rather, it must have been:
      // `"a"` is non-canonical, `"a,b"` is the only way to write that cell.
      let content = Bytes::from_array(cell)
      if !field_needs_quotes(content) {
        @cov.hit(504)
        return None
      }
      if i < n && input[i].to_int() != 44 && input[i].to_int() != 10 {
        @cov.hit(505)
        return None
      }
      cells.push(content)
      cell = []
      row_start = false
      committed = true
      @cov.hit(506)
    } else if v == 44 {
      if !committed {
        cells.push(Bytes::from_array(cell))
      }
      cell = []
      committed = false
      row_start = false
      @cov.hit(507)
      i = i + 1
    } else if v == 10 {
      if !committed {
        cells.push(Bytes::from_array(cell))
      }
      cell = []
      committed = false
      if cells.length() == 1 && cells[0].length() == 0 && row_start {
        @cov.hit(508)
        return None
      }
      rows.push({ cells, })
      cells = []
      row_start = true
      @cov.hit(509)
      i = i + 1
    } else {
      cell.push(input[i])
      row_start = false
      i = i + 1
    }
  }
  // The last row may end without a newline.
  if committed {
    // The last field was a quoted one: its row still needs to be pushed.
    rows.push({ cells, })
    @cov.hit(510)
  } else if cell.length() > 0 || cells.length() > 0 {
    cells.push(Bytes::from_array(cell))
    rows.push({ cells, })
    @cov.hit(510)
  }
  Some(rows)
}

///|
fn csv_push_quoted(out : Array[Byte], cell : Bytes) -> Unit {
  out.push(b'"')
  let mut i = 0
  while i < cell.length() {
    if cell[i].to_int() == 34 {
      out.push(b'"')
    }
    out.push(cell[i])
    i = i + 1
  }
  out.push(b'"')
}

///|
pub fn csv_serialize_strict(rows : Array[CsvRow]) -> Bytes {
  let out : Array[Byte] = []
  let mut r = 0
  while r < rows.length() {
    let cells = rows[r].cells
    let mut c = 0
    while c < cells.length() {
      if c > 0 {
        out.push(b',')
      }
      let cell = cells[c]
      if field_needs_quotes(cell) {
        csv_push_quoted(out, cell)
      } else {
        let mut k = 0
        while k < cell.length() {
          out.push(cell[k])
          k = k + 1
        }
      }
      c = c + 1
    }
    out.push(b'\n')
    r = r + 1
  }
  Bytes::from_array(out)
}

///|
pub fn csv_strict_check(input : Bytes) -> String {
  match csv_parse_strict(input) {
    None => "err"
    Some(rows) => {
      let again = csv_serialize_strict(rows)
      let m = input.length()
      // The canonical form either equals the input, or is the input plus the
      // one newline the serializer always writes.
      let mut same = false
      if again.length() == m {
        same = csv_same(input, again, m)
      } else if again.length() == m + 1 && again[m].to_int() == 10 {
        same = csv_same(input, again, m)
      }
      if same {
        @cov.hit(521)
        "ok:" + rows.length().to_string()
      } else {
        @cov.hit(522)
        "roundtrip:" + @core.hex_all(again)
      }
    }
  }
}

///|
fn csv_same(input : Bytes, canonical : Bytes, len : Int32) -> Bool {
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
pub fn csv_strict_roundtrip_holds(_input : Bytes, output : String) -> String {
  if output.has_prefix("roundtrip:") {
    output
  } else {
    ""
  }
}
