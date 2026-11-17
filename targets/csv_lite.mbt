///|
/// CSV shape analysis: record count, column count and the longest field.
///
/// The point is not to be a full RFC 4180 implementation but to have a target
/// whose output is *composite* (three numbers derived from one pass), so a
/// single wrong byte changes the summary in a readable way instead of just
/// flipping ok/err.
pub fn csv_stats(input : Bytes) -> String {
  let n = input.length()
  let mut i = 0
  let mut rows = 0
  let mut cols_here = 0
  let mut max_cols = 0
  let mut field = 0
  let mut max_field = 0
  let mut in_quotes = false
  let mut closed = false
  let mut any = false
  while i < n {
    let v = input[i].to_int()
    any = true
    if closed {
      // RFC 4180: after a closing quote only a separator, a record end or EOF
      // is allowed. Being strict here is what makes the fuzzer's rejections
      // meaningful instead of "anything goes".
      if v != 44 && v != 10 && v != 13 {
        return "err:trailing@" + i.to_string()
      }
      closed = false
    }
    if in_quotes {
      if v == 34 {
        if i + 1 < n && data_at(input, i + 1) == 34 {
          field = field + 1
          i = i + 2
        } else {
          in_quotes = false
          closed = true
          i = i + 1
        }
      } else {
        field = field + 1
        i = i + 1
      }
    } else if v == 34 {
      if field > 0 {
        return "err:quote@" + i.to_string()
      }
      in_quotes = true
      i = i + 1
    } else if v == 44 {
      cols_here = cols_here + 1
      max_field = max_of(max_field, field)
      field = 0
      i = i + 1
    } else if v == 10 {
      rows = rows + 1
      cols_here = cols_here + 1
      max_cols = max_of(max_cols, cols_here)
      max_field = max_of(max_field, field)
      cols_here = 0
      field = 0
      i = i + 1
    } else if v == 13 {
      i = i + 1
    } else {
      field = field + 1
      i = i + 1
    }
  }
  if in_quotes {
    return "err:unterminated@" + i.to_string()
  }
  if any {
    if cols_here > 0 || field > 0 {
      rows = rows + 1
      cols_here = cols_here + 1
      max_cols = max_of(max_cols, cols_here)
      max_field = max_of(max_field, field)
    }
  }
  "rows=" +
  rows.to_string() +
  ";cols=" +
  max_cols.to_string() +
  ";max=" +
  max_field.to_string()
}

///|
fn data_at(data : Bytes, i : Int32) -> Int32 {
  data[i].to_int()
}

///|
fn max_of(a : Int32, b : Int32) -> Int32 {
  if a > b {
    a
  } else {
    b
  }
}
